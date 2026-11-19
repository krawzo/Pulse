import 'dart:async';
import 'dart:io';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import '../data/windows_library_store.dart';
import '../data/pulse_preferences_store.dart';
import '../domain/audio_track.dart';
import '../domain/pulse_preferences.dart';
import '../state/library_controller.dart';
import '../state/jellyfin_controller.dart';
import '../state/playback_controller.dart';
import '../state/pulse_connect_controller.dart';
import '../ui/pulse_home_page.dart';
import 'pulse_theme.dart';
import 'pulse_audio_handler.dart';
import 'pulse_windows_accessibility_boundary.dart';

class PulseApp extends StatefulWidget {
  const PulseApp({
    super.key,
    this.enableWindowsAccessibility = false,
    this.customTitleBar = false,
    this.audioHandler,
  });

  final bool enableWindowsAccessibility;
  final bool customTitleBar;
  final PulseAudioHandler? audioHandler;

  @override
  State<PulseApp> createState() => _PulseAppState();
}

class _PulseAppState extends State<PulseApp>
    with WidgetsBindingObserver, WindowListener {
  static const _windowChannel = MethodChannel('pulse/window');
  late final LibraryController _library;
  late final PlaybackController _playback;
  late final PulseConnectController _connect;
  late final JellyfinController _jellyfin;
  late final Future<void> _jellyfinRestore;
  late final PulsePreferencesStore _preferencesStore;
  PulsePreferences _preferences = const PulsePreferences();
  String? _resumeNotice;
  Future<AudioSession>? _mobileAudioSession;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSubscription;
  StreamSubscription<void>? _noisySubscription;
  bool _wasPlayingLocally = false;
  Future<void> _focusOperation = Future<void>.value();
  Timer? _windowsOutputTimer;
  String? _windowsOutputName;
  bool _windowsOutputInitialized = false;
  bool _checkingWindowsOutput = false;
  String? _lastTaskbarPlaybackState;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (Platform.isWindows) windowManager.addListener(this);
    _library = LibraryController(WindowsLibraryStore());
    _jellyfin = JellyfinController();
    _preferencesStore = PulsePreferencesStore();
    if (Platform.isAndroid) {
      _mobileAudioSession = _setupMobileAudio();
    }
    _playback = PlaybackController(
        player: Player(),
        remoteStreamUrl: _jellyfin.streamUrl,
        activateLocalAudio: Platform.isAndroid ? _activateMobileAudio : null,
        onCheckpoint: (checkpoint) {
          unawaited(_jellyfin.saveNavidromeQueue(checkpoint.trackId,
              checkpoint.positionMillis, checkpoint.queueIds,
              force: checkpoint.force));
          if (!_preferences.continuePlayback) return;
          _preferences = _preferences.copyWith(
              lastTrackId: checkpoint.trackId,
              lastAccountFingerprint: _jellyfin.accountFingerprint ?? '',
              lastPositionMillis: checkpoint.positionMillis,
              lastQueueIds: checkpoint.queueIds);
          unawaited(
              _preferencesStore.save(_preferences).catchError((Object _) {}));
        });
    if (Platform.isAndroid) _playback.addListener(_syncMobileAudioFocus);
    if (Platform.isWindows) {
      _windowChannel.setMethodCallHandler(_handleWindowsTaskbarAction);
      _playback.addListener(_syncWindowsTaskbarPlayback);
      _library.addListener(_syncWindowsTaskbarPlayback);
      _jellyfin.addListener(_syncWindowsTaskbarPlayback);
      _syncWindowsTaskbarPlayback();
      unawaited(_checkWindowsAudioOutput());
      _windowsOutputTimer = Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => unawaited(_checkWindowsAudioOutput()),
      );
    }
    widget.audioHandler?.bind(_playback);
    _connect = PulseConnectController(playback: _playback, jellyfin: _jellyfin);
    _jellyfinRestore = _jellyfin.restore();
    if (Platform.isAndroid) unawaited(_retryJellyfinCatalogAfterRestore());
    unawaited(_initialize());
  }

  Future<void> _handleWindowsTaskbarAction(MethodCall call) async {
    if (call.method != 'taskbarAction' || !mounted) return;
    final track = _playback.currentTrack;
    if (track == null) return;
    switch (call.arguments) {
      case 'favorite':
        if (track.source == AudioSource.jellyfin) {
          await _jellyfin.toggleFavorite(track);
        } else {
          await _library.toggleFavorite(track);
        }
      case 'previous':
        await _playback.skipPrevious();
      case 'playPause':
        await _playback.togglePlayback();
      case 'next':
        await _playback.skipNext();
    }
  }

  void _syncWindowsTaskbarPlayback() {
    final track = _playback.currentTrack;
    final favorite = track != null &&
        (track.source == AudioSource.jellyfin
            ? _jellyfin.favoriteIds.contains(track.id)
            : _library.snapshot.favoriteIds.contains(track.id));
    final signature = '${track?.id}|${_playback.isPlaying}|$favorite';
    if (_lastTaskbarPlaybackState == signature) return;
    _lastTaskbarPlaybackState = signature;
    unawaited(_sendWindowsTaskbarPlayback(track != null, favorite));
  }

  Future<void> _sendWindowsTaskbarPlayback(
      bool hasTrack, bool isFavorite) async {
    try {
      await _windowChannel.invokeMethod<void>('setTaskbarPlayback', {
        'hasTrack': hasTrack,
        'isPlaying': _playback.isPlaying,
        'isFavorite': isFavorite,
      });
    } on Object {
      // The Flutter player remains usable if the shell preview is unavailable.
    }
  }

  Future<void> _retryJellyfinCatalogAfterRestore() async {
    await _jellyfinRestore;
    for (final delay in [2, 5, 12]) {
      if (!mounted || !_jellyfin.connected || _jellyfin.tracks.isNotEmpty) {
        return;
      }
      await Future<void>.delayed(Duration(seconds: delay));
      if (!mounted || !_jellyfin.connected || _jellyfin.tracks.isNotEmpty) {
        return;
      }
      if (!_jellyfin.loading) await _jellyfin.refresh();
    }
  }

  Future<AudioSession> _setupMobileAudio() async {
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _interruptionSubscription = session.interruptionEventStream.listen((event) {
      if (event.begin && _playback.isPlaying && !_playback.isRemoteOutput) {
        unawaited(_playback.pause());
      }
    });
    _noisySubscription = session.becomingNoisyEventStream.listen((_) {
      if (_playback.isPlaying && !_playback.isRemoteOutput) {
        unawaited(_playback.pause());
      }
    });
    return session;
  }

  Future<void> _checkWindowsAudioOutput() async {
    if (_checkingWindowsOutput) return;
    _checkingWindowsOutput = true;
    try {
      final name = await const MethodChannel('pulse/window')
          .invokeMethod<String>('getAudioOutput');
      if (!mounted) return;
      final next = name?.trim();
      if (_windowsOutputInitialized &&
          _windowsOutputName != null &&
          _windowsOutputName != next &&
          _playback.isPlaying &&
          !_playback.isRemoteOutput) {
        await _playback.pause();
      }
      _windowsOutputName = next;
      _windowsOutputInitialized = true;
    } on PlatformException {
      // Keep playback working if Windows cannot report its audio endpoint.
    } on MissingPluginException {
      // Older runners do not expose the audio endpoint channel.
    } finally {
      _checkingWindowsOutput = false;
    }
  }

  Future<bool> _activateMobileAudio() async {
    final session = _mobileAudioSession;
    if (session == null) return false;
    final operation = _focusOperation.then((_) async {
      try {
        return await (await session).setActive(true);
      } on Object {
        return false;
      }
    });
    _focusOperation = operation.then((_) {});
    return operation;
  }

  void _deactivateMobileAudio() {
    final session = _mobileAudioSession;
    if (session == null) return;
    _focusOperation = _focusOperation.then((_) async {
      try {
        await (await session).setActive(false);
      } on Object {
        // A failed release must not prevent the next playback attempt.
      }
    });
  }

  void _syncMobileAudioFocus() {
    final playingLocally = _playback.isPlaying && !_playback.isRemoteOutput;
    if (_wasPlayingLocally && !playingLocally) _deactivateMobileAudio();
    _wasPlayingLocally = playingLocally;
  }

  Future<void> _initialize() async {
    final results =
        await Future.wait([_library.load(), _preferencesStore.load()]);
    if (!mounted) return;
    final savedPreferences = results[1] as PulsePreferences;
    final mobileOnlyPalette = !Platform.isWindows &&
        (savedPreferences.palette == PulsePalette.purpleDeepBlue ||
            savedPreferences.palette == PulsePalette.desktopSmoke);
    final activePreferences = mobileOnlyPalette
        ? savedPreferences.copyWith(palette: PulsePalette.navyGreen)
        : savedPreferences;
    setState(() {
      _preferences = activePreferences;
      _playback.autoPlayNext = _preferences.autoPlayNext;
      _playback.configureCrossfade(
          enabled: _preferences.crossfadeEnabled,
          seconds: _preferences.crossfadeSeconds);
      _playback.automixEnabled = _preferences.automixEnabled;
      unawaited(_configurePlayback(_preferences));
      if (_preferences.continuePlayback && _preferences.lastTrackId != null) {
        if (_preferences.lastTrackId!.startsWith('jellyfin:') ||
            _preferences.lastTrackId!.startsWith('navidrome:')) {
          unawaited(_restoreRemoteCheckpoint());
          return;
        }
        final restored = _playback.restoreCheckpoint(
            _library.snapshot.tracks,
            _preferences.lastTrackId!,
            _preferences.lastPositionMillis,
            _preferences.lastQueueIds);
        if (!restored) {
          _resumeNotice = _library.snapshot.tracks
                  .any((track) => track.id == _preferences.lastTrackId)
              ? 'A fila anterior mudou. As faixas ainda disponíveis foram mantidas.'
              : 'A última faixa não está mais na biblioteca. Escolha uma faixa para continuar.';
        }
      }
      if (_preferences.continuePlayback && _preferences.lastTrackId == null) {
        unawaited(_restoreNavidromeQueue());
      }
    });
    if (mobileOnlyPalette) {
      unawaited(_preferencesStore.save(activePreferences));
    }
    await _syncWindowsBackdrop(activePreferences);
    try {
      await const MethodChannel('pulse/window').invokeMethod<void>(
          'setCloseToMinimize', _preferences.closeToMinimize);
    } on MissingPluginException {
      // Other platforms do not expose the Windows title-bar behavior.
    } on PlatformException {
      // Keep the app usable if the native window bridge is unavailable.
    }
  }

  Future<void> _restoreRemoteCheckpoint() async {
    await _jellyfinRestore;
    if (_jellyfin.serverKind == MusicServerKind.navidrome) {
      await _restoreNavidromeQueue();
      if (_playback.currentTrack != null ||
          _preferences.lastAccountFingerprint != _jellyfin.accountFingerprint) {
        return;
      }
    }
    if (!mounted ||
        !_preferences.continuePlayback ||
        _playback.currentTrack != null ||
        !_preferences.continuePlayback ||
        _preferences.lastTrackId == null) {
      return;
    }
    final tracks = [..._library.snapshot.tracks, ..._jellyfin.tracks];
    final restored = _playback.restoreCheckpoint(
      tracks,
      _preferences.lastTrackId!,
      _preferences.lastPositionMillis,
      _preferences.lastQueueIds,
    );
    if (!restored) {
      setState(() => _resumeNotice = _jellyfin.connected
          ? 'A fila anterior mudou. As faixas ainda disponíveis foram mantidas.'
          : 'A faixa Jellyfin anterior está indisponível. Conecte o servidor para continuar.');
    }
  }

  Future<void> _restoreNavidromeQueue() async {
    await _jellyfinRestore;
    if (!mounted ||
        _playback.currentTrack != null ||
        _jellyfin.serverKind != MusicServerKind.navidrome) {
      return;
    }
    try {
      final saved = await _jellyfin.savedNavidromeQueue();
      if (!mounted || saved == null || _playback.currentTrack != null) return;
      _playback.restoreCheckpoint(
        _jellyfin.tracks,
        saved.trackId,
        saved.positionMillis,
        saved.queueIds,
      );
    } on Object {
      // The server queue is optional; local navigation remains available.
    }
  }

  Future<void> _syncNavidromeQueueOnResume() async {
    await _jellyfinRestore;
    if (!mounted ||
        !_preferences.continuePlayback ||
        _playback.isPlaying ||
        _jellyfin.serverKind != MusicServerKind.navidrome) {
      return;
    }
    try {
      final saved = await _jellyfin.savedNavidromeQueue();
      if (!mounted || saved == null || _playback.isPlaying) return;
      _playback.restoreCheckpoint(_jellyfin.tracks, saved.trackId,
          saved.positionMillis, saved.queueIds);
    } on Object {
      // Keep the paused local view when the server is unreachable.
    }
  }

  Future<void> _updatePreferences(PulsePreferences preferences) async {
    final previous = _preferences;
    setState(() => _preferences = preferences);
    await _syncWindowsBackdrop(preferences);
    _playback.autoPlayNext = preferences.autoPlayNext;
    _playback.configureCrossfade(
        enabled: preferences.crossfadeEnabled,
        seconds: preferences.crossfadeSeconds);
    _playback.automixEnabled = preferences.automixEnabled;
    await _configurePlayback(preferences);
    try {
      await const MethodChannel('pulse/window').invokeMethod<void>(
          'setCloseToMinimize', preferences.closeToMinimize);
    } on MissingPluginException {
      // Other platforms do not expose the Windows title-bar behavior.
    } on PlatformException {
      // Saving the rest of the preferences should still be possible.
    }
    try {
      await _preferencesStore.save(preferences);
    } on Object {
      if (!mounted) rethrow;
      setState(() => _preferences = previous);
      await _syncWindowsBackdrop(previous);
      _playback.autoPlayNext = previous.autoPlayNext;
      try {
        await const MethodChannel('pulse/window')
            .invokeMethod<void>('setCloseToMinimize', previous.closeToMinimize);
      } on Object {
        // The persisted value remains the source of truth after restart.
      }
      rethrow;
    }
  }

  Future<void> _syncWindowsBackdrop(PulsePreferences preferences) async {
    if (!Platform.isWindows) return;
    final glass = preferences.appearance != PulseAppearance.light;
    try {
      await acrylic.Window.setEffect(
        effect: glass
            ? acrylic.WindowEffect.transparent
            : acrylic.WindowEffect.disabled,
        color: Colors.transparent,
        dark: true,
      );
      await const MethodChannel('pulse/window')
          .invokeMethod<void>('setGlassBackdrop', glass);
    } on Object {
      if (glass) {
        try {
          await acrylic.Window.setEffect(
            effect: acrylic.WindowEffect.acrylic,
            color: const Color(0x38262C30),
            dark: true,
          );
        } on Object {
          // Keep the window usable if this Windows version cannot show acrylic.
        }
      }
    }
  }

  Future<void> _configurePlayback(PulsePreferences preferences) =>
      _playback.configureAudio(
        normalize: preferences.normalizeVolume,
        volumeLevel: preferences.volumeLevel,
        mono: preferences.monoAudio,
      );

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (Platform.isWindows) {
      windowManager.removeListener(this);
      _windowChannel.setMethodCallHandler(null);
      _playback.removeListener(_syncWindowsTaskbarPlayback);
      _library.removeListener(_syncWindowsTaskbarPlayback);
      _jellyfin.removeListener(_syncWindowsTaskbarPlayback);
    }
    _windowsOutputTimer?.cancel();
    _playback.persistCheckpoint();
    if (Platform.isAndroid) _playback.removeListener(_syncMobileAudioFocus);
    unawaited(_interruptionSubscription?.cancel());
    unawaited(_noisySubscription?.cancel());
    widget.audioHandler?.unbind();
    _connect.dispose();
    _library.dispose();
    _jellyfin.dispose();
    _playback.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncNavidromeQueueOnResume());
    }
    if (Platform.isAndroid &&
        (state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden)) {
      _playback.persistCheckpoint();
    }
  }

  @override
  void onWindowFocus() {
    unawaited(_jellyfin.warmConnection());
    unawaited(_syncNavidromeQueueOnResume());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pulse',
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        final content = PulseWindowsAccessibilityBoundary(
          enabled: widget.enableWindowsAccessibility,
          child: child ?? const SizedBox.shrink(),
        );
        return widget.customTitleBar
            ? VirtualWindowFrame(child: content)
            : content;
      },
      theme: buildPulseTheme(
          light: _preferences.appearance == PulseAppearance.light,
          palette: _preferences.palette,
          density: switch (_preferences.density) {
            PulseDensity.compact => VisualDensity.compact,
            PulseDensity.standard => VisualDensity.standard,
            PulseDensity.comfortable =>
              const VisualDensity(horizontal: 1, vertical: 1),
          }),
      home: PulseHomePage(
          library: _library,
          jellyfin: _jellyfin,
          playback: _playback,
          connect: _connect,
          preferences: _preferences,
          customTitleBar: widget.customTitleBar,
          onPreferencesChanged: _updatePreferences,
          startupNotice: _resumeNotice),
    );
  }
}
