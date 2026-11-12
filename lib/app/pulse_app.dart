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

class _PulseAppState extends State<PulseApp> with WidgetsBindingObserver {
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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
          if (Platform.isAndroid) {
            unawaited(_jellyfin.saveNavidromeQueue(checkpoint.trackId,
                checkpoint.positionMillis, checkpoint.queueIds));
          }
          if (!_preferences.continuePlayback) return;
          _preferences = _preferences.copyWith(
              lastTrackId: checkpoint.trackId,
              lastPositionMillis: checkpoint.positionMillis,
              lastQueueIds: checkpoint.queueIds);
          unawaited(
              _preferencesStore.save(_preferences).catchError((Object _) {}));
        });
    if (Platform.isAndroid) _playback.addListener(_syncMobileAudioFocus);
    widget.audioHandler?.bind(_playback);
    _connect = PulseConnectController(playback: _playback, jellyfin: _jellyfin);
    _jellyfinRestore = _jellyfin.restore();
    if (Platform.isAndroid) unawaited(_retryJellyfinCatalogAfterRestore());
    unawaited(_initialize());
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
        unawaited(_playback.togglePlayback());
      }
    });
    _noisySubscription = session.becomingNoisyEventStream.listen((_) {
      if (_playback.isPlaying && !_playback.isRemoteOutput) {
        unawaited(_playback.togglePlayback());
      }
    });
    return session;
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
      if (Platform.isAndroid &&
          _preferences.continuePlayback &&
          _preferences.lastTrackId == null) {
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
    final savedId = _preferences.lastTrackId;
    if (Platform.isAndroid &&
        _jellyfin.serverKind == MusicServerKind.navidrome &&
        savedId?.startsWith('jellyfin:') == true) {
      await _restoreNavidromeQueue();
      return;
    }
    if (!mounted ||
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
    if (Platform.isAndroid &&
        (state == AppLifecycleState.inactive ||
            state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden)) {
      _playback.persistCheckpoint();
    }
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
