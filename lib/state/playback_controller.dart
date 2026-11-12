import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:media_kit/media_kit.dart' hide AudioTrack;

import '../connect/pulse_output.dart';
import '../connect/pulse_remote_playback.dart';
import '../domain/audio_track.dart';
import '../domain/pulse_preferences.dart';

enum PulseRepeatMode { off, queue, track }

class PlaybackController extends ChangeNotifier {
  PlaybackController({
    Player? player,
    this.onCheckpoint,
    this.onPlayTrack,
    this.remoteStreamUrl,
    this.activateLocalAudio,
    Random? random,
  })  : _player = player,
        _random = random ?? Random() {
    _bindPlayerStreams(player);
  }

  Player? _player;
  Player? _crossfadePlayer;
  PulseRemotePlayback? _remoteOutput;
  StreamSubscription<PulseOutputState>? _remoteStateSubscription;
  int _lastRemoteRevision = -1;
  String? _completedRemoteSessionId;
  final Random _random;
  final ValueChanged<
          ({String trackId, int positionMillis, List<String> queueIds})>?
      onCheckpoint;
  @visibleForTesting
  final Future<void> Function(AudioTrack track, Duration position)? onPlayTrack;
  final Future<Uri> Function(AudioTrack track)? remoteStreamUrl;
  final Future<bool> Function()? activateLocalAudio;
  StreamSubscription<bool>? _stateSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  StreamSubscription<Duration>? _durationSubscription;
  StreamSubscription<bool>? _completionSubscription;
  StreamSubscription<String>? _errorSubscription;
  Timer? _crossfadeTimer;
  Timer? _sleepTimer;
  String? _stopAfterTrackId;
  bool _preparingCrossfade = false;
  bool _crossfading = false;
  double _crossfadeProgress = 0;
  List<AudioTrack> _queue = const [];
  List<AudioTrack>? _queueBeforeShuffle;
  int _currentIndex = -1;
  int _lastCheckpointBucket = -1;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  bool _explicitlyPaused = false;
  bool _opening = false;
  double _volume = 1;
  bool _normalizeVolume = false;
  bool _monoAudio = false;
  PulseVolumeLevel _volumeLevel = PulseVolumeLevel.normal;
  bool autoPlayNext = true;
  bool crossfadeEnabled = false;
  int crossfadeSeconds = 5;
  bool automixEnabled = false;
  bool shuffleEnabled = false;
  PulseRepeatMode repeatMode = PulseRepeatMode.off;
  Duration _restoredPosition = Duration.zero;
  String? _errorMessage;

  // Every queue mutation replaces this immutable list. Consumers can use its
  // identity to detect reorder/removal without scanning it on position ticks.
  List<AudioTrack> get queue => _queue;
  int get currentIndex => _currentIndex;
  AudioTrack? get currentTrack =>
      _currentIndex >= 0 && _currentIndex < _queue.length
          ? _queue[_currentIndex]
          : null;
  Duration get position => _position;
  Duration get duration => _duration;
  bool get isPlaying => _isPlaying;
  double get volume => _volume;
  bool get isRemoteOutput => _remoteOutput != null;
  PulseRemotePlayback? get remoteOutput => _remoteOutput;
  String? get errorMessage => _errorMessage;
  bool get hasSleepTimer => _sleepTimer != null || _stopAfterTrackId != null;
  bool get stopsAfterTrack => _stopAfterTrackId != null;

  void configureCrossfade({required bool enabled, required int seconds}) {
    crossfadeEnabled = enabled;
    crossfadeSeconds = seconds.clamp(0, 12);
    if (!enabled) {
      unawaited(_cancelCrossfade());
    } else {
      _maybePrepareCrossfade();
    }
  }

  void _bindPlayerStreams(Player? active) {
    unawaited(_stateSubscription?.cancel());
    unawaited(_positionSubscription?.cancel());
    unawaited(_durationSubscription?.cancel());
    unawaited(_completionSubscription?.cancel());
    unawaited(_errorSubscription?.cancel());
    if (active == null) return;
    _stateSubscription = active.stream.playing.listen((value) {
      if (_remoteOutput != null || !identical(active, _player)) return;
      if (_crossfading) return;
      if (value && _explicitlyPaused) {
        unawaited(active.pause());
        return;
      }
      _isPlaying = value;
      notifyListeners();
    });
    _positionSubscription = active.stream.position.listen((value) {
      if (_remoteOutput != null || !identical(active, _player)) return;
      _position = value;
      final bucket = value.inSeconds ~/ 8;
      if (bucket != _lastCheckpointBucket) {
        _lastCheckpointBucket = bucket;
        _saveCheckpoint();
      }
      _maybePrepareCrossfade();
      _maybeStartCrossfade();
      notifyListeners();
    });
    _durationSubscription = active.stream.duration.listen((value) {
      if (_remoteOutput != null || !identical(active, _player)) return;
      _duration = value > Duration.zero
          ? value
          : Duration(milliseconds: currentTrack?.durationMillis ?? 0);
      _maybePrepareCrossfade();
      notifyListeners();
    });
    _completionSubscription = active.stream.completed.listen((value) {
      if (_remoteOutput != null || !identical(active, _player)) return;
      if (value && !_crossfading) _handleTrackComplete();
    });
    _errorSubscription = active.stream.error.listen((error) {
      if (_remoteOutput == null && identical(active, _player)) _setError(error);
    });
  }

  Future<void> configureAudio({
    required bool normalize,
    required PulseVolumeLevel volumeLevel,
    required bool mono,
  }) async {
    _normalizeVolume = normalize;
    _volumeLevel = volumeLevel;
    _monoAudio = mono;
    for (final player in [_player, _crossfadePlayer]) {
      if (player != null) await _applyAudioConfig(player);
    }
    notifyListeners();
  }

  Future<void> _applyAudioConfig(Player player) async {
    final platform = player.platform;
    if (platform != null &&
        platform.runtimeType.toString().contains('NativePlayer')) {
      try {
        await (platform as dynamic)
            .setProperty('audio-channels', _monoAudio ? 'mono' : 'auto-safe');
        // The bundled libmpv cannot initialize the loudnorm audio filter for
        // every source. ReplayGain uses stored track gain without a filter and
        // leaves untagged tracks at their original level.
        await (platform as dynamic)
            .setProperty('replaygain', _normalizeVolume ? 'track' : 'no');
        await (platform as dynamic).setProperty('replaygain-preamp',
            _normalizeVolume ? _replayGainPreamp(_volumeLevel) : '0');
        await (platform as dynamic).setProperty('replaygain-fallback', '0');
      } on Object catch (error) {
        _setError(error);
      }
    }
  }

  String _replayGainPreamp(PulseVolumeLevel level) => switch (level) {
        PulseVolumeLevel.quiet => '-5',
        PulseVolumeLevel.normal => '0',
        PulseVolumeLevel.loud => '3',
      };

  Future<void> setVolume(double value) async {
    final next = value.clamp(0.0, 1.0);
    _volume = next;
    notifyListeners();
    final currentMix = _crossfadeProgress;
    await Future.wait([
      if (_player != null) _player!.setVolume(next * (1 - currentMix) * 100),
      if (_crossfadePlayer != null)
        _crossfadePlayer!.setVolume(next * currentMix * 100),
      if (_remoteOutput != null) _remoteOutput!.setVolume(next),
    ]);
  }

  int? _nextCrossfadeIndex() {
    if (_queue.isEmpty || !_playerCrossfadeAllowed) return null;
    if (_currentIndex + 1 < _queue.length) return _currentIndex + 1;
    if (repeatMode == PulseRepeatMode.queue) return 0;
    return null;
  }

  bool get _playerCrossfadeAllowed =>
      _remoteOutput == null &&
      _isPlaying &&
      crossfadeEnabled &&
      crossfadeSeconds > 0 &&
      autoPlayNext &&
      repeatMode != PulseRepeatMode.track &&
      _stopAfterTrackId != currentTrack?.id;

  void setSleepTimer(Duration duration) {
    _clearSleepTimer();
    if (duration <= Duration.zero) return;
    _sleepTimer = Timer(duration, () => unawaited(_finishSleepTimer()));
    notifyListeners();
  }

  void stopAfterCurrentTrack() {
    final track = currentTrack;
    if (track == null) return;
    _clearSleepTimer();
    _stopAfterTrackId = track.id;
    if (_crossfading || _preparingCrossfade || _crossfadePlayer != null) {
      unawaited(_cancelCrossfade());
    }
    notifyListeners();
  }

  void cancelSleepTimer() {
    if (!hasSleepTimer) return;
    _clearSleepTimer();
    notifyListeners();
  }

  void _clearSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _stopAfterTrackId = null;
  }

  Future<void> _finishSleepTimer() async {
    _clearSleepTimer();
    await _cancelCrossfade();
    if (_remoteOutput case final remote?) {
      await remote.pause();
    } else {
      await _player?.pause();
    }
    _isPlaying = false;
    _saveCheckpoint();
    notifyListeners();
  }

  void _maybePrepareCrossfade() {
    if (!_playerCrossfadeAllowed ||
        _crossfading ||
        _crossfadePlayer != null ||
        _preparingCrossfade ||
        _duration <= Duration.zero ||
        _nextCrossfadeIndex() == null) {
      return;
    }
    final remaining = _duration - _position;
    if (remaining > Duration(seconds: crossfadeSeconds + 5)) return;
    _preparingCrossfade = true;
    unawaited(_prepareCrossfade());
  }

  Future<void> _prepareCrossfade() async {
    final nextIndex = _nextCrossfadeIndex();
    if (nextIndex == null) {
      _preparingCrossfade = false;
      return;
    }
    final nextTrack = _queue[nextIndex];
    final standby = Player();
    try {
      await _applyAudioConfig(standby);
      await standby.setVolume(0);
      await standby.open(Media(await _uriFor(nextTrack)), play: false);
      if (!_playerCrossfadeAllowed || _nextCrossfadeIndex() != nextIndex) {
        await standby.dispose();
        _preparingCrossfade = false;
        return;
      }
      _crossfadePlayer = standby;
      _preparingCrossfade = false;
      _maybeStartCrossfade();
    } on Object catch (error) {
      await standby.dispose();
      _preparingCrossfade = false;
      _setError('Falha ao preparar a próxima faixa para a transição: $error');
    }
  }

  void _maybeStartCrossfade() {
    final standby = _crossfadePlayer;
    if (!_playerCrossfadeAllowed || _crossfading || standby == null) return;
    final remaining = _duration - _position;
    if (remaining > Duration(seconds: crossfadeSeconds)) return;
    final duration = remaining > Duration.zero
        ? remaining
        : Duration(seconds: crossfadeSeconds);
    unawaited(_runCrossfade(standby, duration));
  }

  Future<void> _runCrossfade(Player standby, Duration duration) async {
    if (_crossfading || !identical(standby, _crossfadePlayer)) return;
    final current = _player;
    final nextIndex = _nextCrossfadeIndex();
    if (current == null || nextIndex == null) return;
    _crossfading = true;
    _crossfadeProgress = 0;
    try {
      await standby.play();
      final started = DateTime.now();
      final totalMs = max(250, duration.inMilliseconds);
      final completer = Completer<void>();
      _crossfadeTimer =
          Timer.periodic(const Duration(milliseconds: 100), (timer) {
        final progress =
            ((DateTime.now().difference(started).inMilliseconds) / totalMs)
                .clamp(0.0, 1.0);
        _crossfadeProgress = progress;
        Future.wait([
          current.setVolume(_volume * (1 - progress) * 100),
          standby.setVolume(_volume * progress * 100),
        ]).then((_) {
          if (progress >= 1 && !completer.isCompleted) completer.complete();
        }).catchError((Object error) {
          if (!completer.isCompleted) completer.completeError(error);
        });
        notifyListeners();
      });
      await completer.future;
      _crossfadeTimer?.cancel();
      _crossfadeTimer = null;
      _currentIndex = nextIndex;
      _restoredPosition = Duration.zero;
      _player = standby;
      _crossfadePlayer = null;
      _crossfadeProgress = 0;
      _crossfading = false;
      _position = standby.state.position;
      _duration = standby.state.duration > Duration.zero
          ? standby.state.duration
          : Duration(milliseconds: currentTrack?.durationMillis ?? 0);
      _isPlaying = standby.state.playing;
      _errorMessage = null;
      _bindPlayerStreams(standby);
      await standby.setVolume(_volume * 100);
      await current.dispose();
      _saveCheckpoint();
      notifyListeners();
    } on Object catch (error) {
      _crossfadeTimer?.cancel();
      _crossfadeTimer = null;
      _crossfadeProgress = 0;
      _crossfading = false;
      _crossfadePlayer = null;
      await current.setVolume(_volume * 100);
      await standby.dispose();
      _setError('A transição gradual falhou: $error');
    }
  }

  Future<String> _uriFor(AudioTrack track) async {
    if (track.source == AudioSource.local) {
      if (track.id.startsWith('pulse-incoming:')) {
        final uri = Uri.tryParse(track.path);
        if (uri == null || uri.scheme != 'http') {
          throw StateError('Endereço da faixa Pulse inválido.');
        }
        return uri.toString();
      }
      return Uri.file(track.path).toString();
    }
    final resolver = remoteStreamUrl;
    if (resolver == null) throw StateError('Fonte Jellyfin indisponível.');
    return (await resolver(track)).toString();
  }

  Future<void> _cancelCrossfade() async {
    _crossfadeTimer?.cancel();
    _crossfadeTimer = null;
    _crossfading = false;
    _crossfadeProgress = 0;
    final standby = _crossfadePlayer;
    _crossfadePlayer = null;
    _preparingCrossfade = false;
    if (standby != null) await standby.dispose();
    await _player?.setVolume(_volume * 100);
  }

  /// Move playback to a prepared destination. The current output keeps playing
  /// until the destination reports that it is playing the same track.
  Future<void> selectRemoteOutput(PulseRemotePlayback candidate) async {
    if (identical(candidate, _remoteOutput)) return;
    await _cancelCrossfade();
    final previous = _remoteOutput;
    final track = currentTrack;
    final position = _position;
    final shouldPlay = track != null && _isPlaying;
    if (previous == null && shouldPlay && _player == null) {
      throw StateError('Reprodutor local indisponível para transferência.');
    }
    try {
      if (track != null) {
        await candidate.load(track, position);
        if (shouldPlay) {
          await candidate.play();
          await candidate.waitUntilPlaying();
        }
      }
      if (previous != null) {
        await previous.stop();
      } else if (shouldPlay) {
        await _pauseLocalAndConfirm(_player!);
      }
      await _remoteStateSubscription?.cancel();
      _remoteOutput = candidate;
      _lastRemoteRevision = -1;
      _completedRemoteSessionId = null;
      _remoteStateSubscription = candidate.states.listen(
        (state) => _applyRemoteState(candidate, state),
        onError: (Object error) => _setError(error),
      );
      _applyRemoteState(candidate, candidate.state);
      _restoredPosition = Duration.zero;
      if (!shouldPlay) {
        _position = position;
        _isPlaying = false;
        _saveCheckpoint();
        notifyListeners();
      }
    } on Object catch (error) {
      try {
        await candidate.stop();
      } on Object {
        // Keep the original output selected when the handoff fails.
      }
      if (previous == null && shouldPlay) {
        try {
          await _player?.play();
        } on Object {
          // Surface the original transfer failure below.
        }
      }
      _setError(error);
      rethrow;
    }
  }

  /// Pull the same track and position back to this computer before stopping
  /// the remote destination. A failed local start leaves remote selected.
  Future<void> returnToLocalOutput() async {
    final remote = _remoteOutput;
    if (remote == null) return;
    final track = currentTrack;
    final player = _player;
    final remoteState = remote.state;
    final position = remote.pendingStartPosition ??
        (remoteState.sessionId == remote.sessionId
            ? remoteState.position
            : _position);
    final shouldPlay = track != null && remoteState.isPlaying;
    if (track != null && player == null) {
      throw StateError('Reprodutor local indisponível.');
    }
    var localStarted = false;
    try {
      if (track != null && player != null) {
        final uri = await _uriFor(track);
        await player.open(
          Media(uri, start: position > Duration.zero ? position : null),
          play: false,
        );
        await player.setVolume(_volume * 100);
        if (shouldPlay) {
          await _startLocalAndConfirm(player);
          localStarted = true;
        }
      }
      try {
        await remote.stop();
      } on Object {
        if (remoteState.phase != PulseOutputPhase.disconnected &&
            remoteState.phase != PulseOutputPhase.error) {
          rethrow;
        }
        // The receiver is already unreachable; keep the recovered local output.
      }
      await _remoteStateSubscription?.cancel();
      _remoteStateSubscription = null;
      _remoteOutput = null;
      _lastRemoteRevision = -1;
      _completedRemoteSessionId = null;
      _position = position;
      _isPlaying = shouldPlay;
      _errorMessage = null;
      _saveCheckpoint();
      notifyListeners();
    } on Object catch (error) {
      if (localStarted) {
        try {
          await player?.pause();
        } on Object {
          // The remote output remains selected if local recovery fails.
        }
      }
      _setError(error);
      rethrow;
    }
  }

  Future<void> _startLocalAndConfirm(Player player) async {
    if (activateLocalAudio case final activate?) {
      if (!await activate()) {
        throw StateError('O áudio está em uso por outro aplicativo.');
      }
    }
    final confirmed = Completer<void>();
    final subscription = player.stream.playing.listen((playing) {
      if (playing && !confirmed.isCompleted) confirmed.complete();
    });
    try {
      await player.play();
      if (player.state.playing && !confirmed.isCompleted) confirmed.complete();
      await confirmed.future.timeout(const Duration(seconds: 15));
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> _pauseLocalAndConfirm(Player player) async {
    final confirmed = Completer<void>();
    final subscription = player.stream.playing.listen((playing) {
      if (!playing && !confirmed.isCompleted) confirmed.complete();
    });
    try {
      await player.pause();
      if (!player.state.playing && !confirmed.isCompleted) confirmed.complete();
      await confirmed.future.timeout(const Duration(seconds: 5));
    } finally {
      await subscription.cancel();
    }
  }

  void _applyRemoteState(PulseRemotePlayback source, PulseOutputState state) {
    if (!identical(source, _remoteOutput) ||
        (state.sessionId != source.sessionId &&
            state.phase != PulseOutputPhase.disconnected) ||
        state.revision <= _lastRemoteRevision) {
      return;
    }
    if (state.schemaVersion != PulseOutputState.currentSchemaVersion) {
      _setError('Versão de estado do dispositivo incompatível.');
      return;
    }
    _lastRemoteRevision = state.revision;
    _position = source.pendingStartPosition ?? state.position;
    _duration = state.duration;
    _isPlaying = state.isPlaying;
    if (source.output.kind == PulseOutputKind.pulse) {
      _volume = state.volume.clamp(0.0, 1.0);
    }
    // Keep the computer's volume preference for the return handoff. A Cast
    // receiver may not report its current volume and can default to 100%.
    if (state.error case final error?) {
      _errorMessage = error.message;
    } else if (state.phase == PulseOutputPhase.disconnected) {
      _errorMessage = 'Dispositivo desconectado.';
    } else if (state.phase != PulseOutputPhase.error) {
      _errorMessage = null;
    }
    final bucket = _position.inSeconds ~/ 8;
    if (bucket != _lastCheckpointBucket) {
      _lastCheckpointBucket = bucket;
      _saveCheckpoint();
    }
    notifyListeners();
    if (state.completed &&
        state.phase == PulseOutputPhase.idle &&
        state.sessionId != null &&
        state.sessionId != _completedRemoteSessionId) {
      _completedRemoteSessionId = state.sessionId;
      _handleTrackComplete();
    }
  }

  Future<void> playQueue(List<AudioTrack> tracks, int startIndex) async {
    await _startQueue(tracks, startIndex, isPlaylist: false);
  }

  void addToQueue(AudioTrack track) {
    addTracksToQueue([track]);
  }

  void playNext(AudioTrack track) {
    if (currentTrack == null) {
      unawaited(playQueue([track], 0));
      return;
    }
    final next = List<AudioTrack>.of(_queue);
    final insertAt = (_currentIndex + 1).clamp(0, next.length);
    next.insert(insertAt, track);
    _queue = List.unmodifiable(next);
    if (shuffleEnabled) _queueBeforeShuffle = _queue;
    _saveCheckpoint();
    notifyListeners();
  }

  void addTracksToQueue(Iterable<AudioTrack> tracks) {
    final additions = tracks.toList(growable: false);
    if (additions.isEmpty) return;
    _queue = List.unmodifiable([..._queue, ...additions]);
    _queueBeforeShuffle = _queueBeforeShuffle == null
        ? null
        : List<AudioTrack>.unmodifiable(
            [..._queueBeforeShuffle!, ...additions]);
    _saveCheckpoint();
    notifyListeners();
  }

  bool removeUpcomingAt(int index) {
    if (index <= _currentIndex || index >= _queue.length) return false;
    final next = List<AudioTrack>.of(_queue)..removeAt(index);
    _queue = List.unmodifiable(next);
    if (shuffleEnabled) _queueBeforeShuffle = _queue;
    _saveCheckpoint();
    notifyListeners();
    return true;
  }

  bool moveUpcomingTrack(int fromIndex, int toIndex) {
    if (fromIndex <= _currentIndex ||
        toIndex <= _currentIndex ||
        fromIndex >= _queue.length ||
        toIndex >= _queue.length ||
        fromIndex == toIndex) {
      return false;
    }
    final next = List<AudioTrack>.of(_queue);
    final track = next.removeAt(fromIndex);
    next.insert(toIndex, track);
    _queue = List.unmodifiable(next);
    if (shuffleEnabled) _queueBeforeShuffle = _queue;
    _saveCheckpoint();
    notifyListeners();
    return true;
  }

  Future<void> playPlaylistQueue(List<AudioTrack> tracks, int startIndex) =>
      _startQueue(tracks, startIndex, isPlaylist: true);

  Future<void> _startQueue(List<AudioTrack> tracks, int startIndex,
      {required bool isPlaylist}) async {
    if (tracks.isEmpty || startIndex < 0 || startIndex >= tracks.length) return;
    _explicitlyPaused = false;
    await _cancelCrossfade();
    _queue = List.unmodifiable(tracks);
    _currentIndex = startIndex;
    _queueBeforeShuffle = shuffleEnabled ? List<AudioTrack>.of(tracks) : null;
    if (shuffleEnabled) _shuffleFromCurrent();
    _restoredPosition = Duration.zero;
    _saveCheckpoint();
    _errorMessage = null;
    await _playCurrent();
  }

  Future<void> togglePlayback() async {
    if (currentTrack == null) return;
    try {
      if (_remoteOutput case final remote?) {
        if (_isPlaying || _opening) {
          await pause();
        } else if (remote.sessionId == null) {
          _explicitlyPaused = false;
          await _playCurrent();
        } else if (_duration > Duration.zero &&
            _position >= _duration - const Duration(milliseconds: 500)) {
          _explicitlyPaused = false;
          await _playCurrent();
        } else if (_restoredPosition > Duration.zero) {
          _explicitlyPaused = false;
          await remote.load(currentTrack!, _restoredPosition);
          await remote.play();
          await remote.waitUntilPlaying();
          _restoredPosition = Duration.zero;
        } else {
          _explicitlyPaused = false;
          await remote.play();
        }
        return;
      }
      if (_isPlaying || _opening) {
        await pause();
      } else {
        _explicitlyPaused = false;
        if (_duration > Duration.zero &&
            _position >= _duration - const Duration(milliseconds: 500)) {
          await _playCurrent();
        } else if (_restoredPosition > Duration.zero) {
          await _openCurrent(position: _restoredPosition);
          _restoredPosition = Duration.zero;
        } else {
          if (activateLocalAudio case final activate?) {
            if (!await activate()) {
              throw StateError('O áudio está em uso por outro aplicativo.');
            }
          }
          await _player?.play();
          if (_crossfading) await _crossfadePlayer?.play();
          _isPlaying = true;
          notifyListeners();
        }
      }
    } on Object catch (error) {
      _setError(error);
    }
  }

  Future<void> pauseIfPlaying() async {
    if (currentTrack != null) await pause();
  }

  /// Pause is idempotent, including when a stream start is still pending.
  Future<void> pause() async {
    _explicitlyPaused = true;
    try {
      if (_remoteOutput case final remote?) {
        await remote.pause();
      } else {
        await _player?.pause();
        if (_crossfading) await _crossfadePlayer?.pause();
      }
      _isPlaying = false;
      _saveCheckpoint();
      notifyListeners();
    } on Object catch (error) {
      _setError(error);
    }
  }

  Future<void> togglePlaybackIfPaused() async {
    if (!_isPlaying && currentTrack != null) await togglePlayback();
  }

  Future<void> skipNext() async {
    _explicitlyPaused = false;
    if (_crossfadePlayer != null || _preparingCrossfade) {
      await _cancelCrossfade();
    }
    if (_currentIndex + 1 >= _queue.length) {
      if (repeatMode == PulseRepeatMode.queue && _queue.isNotEmpty) {
        if (shuffleEnabled && _queue.length > 1) {
          final current = currentTrack!;
          final remaining = List<AudioTrack>.of(_queueBeforeShuffle ?? _queue)
            ..removeWhere((track) => track.id == current.id)
            ..shuffle(_random);
          _queue = List.unmodifiable([current, ...remaining]);
          _currentIndex = 1;
        } else {
          _currentIndex = 0;
        }
        _restoredPosition = Duration.zero;
        await _playCurrent();
        return;
      }
      if (_remoteOutput case final remote?) {
        await remote.stop();
      } else {
        await _player?.stop();
      }
      _isPlaying = false;
      _position = Duration.zero;
      _errorMessage = null;
      _saveCheckpoint();
      notifyListeners();
      return;
    }
    _currentIndex++;
    _restoredPosition = Duration.zero;
    await _playCurrent();
  }

  Future<void> skipPrevious() async {
    if (currentTrack == null) return;
    _explicitlyPaused = false;
    if (_crossfadePlayer != null || _preparingCrossfade) {
      await _cancelCrossfade();
    }
    if (_position > const Duration(seconds: 3)) {
      await seek(Duration.zero);
    } else if (_currentIndex > 0) {
      _currentIndex--;
      _restoredPosition = Duration.zero;
      await _playCurrent();
    } else {
      await seek(Duration.zero);
    }
  }

  void toggleShuffle() => setShuffleEnabled(!shuffleEnabled);

  void setShuffleEnabled(bool enabled) {
    if (shuffleEnabled == enabled) return;
    if (enabled) {
      _queueBeforeShuffle = List<AudioTrack>.of(_queue);
      if (_queue.isNotEmpty) _shuffleFromCurrent();
    } else {
      final currentId = currentTrack?.id;
      final original = _queueBeforeShuffle;
      if (original != null && currentId != null) {
        _queue = List.unmodifiable(original);
        _currentIndex = _queue.indexWhere((track) => track.id == currentId);
      }
      _queueBeforeShuffle = null;
    }
    shuffleEnabled = enabled;
    _saveCheckpoint();
    notifyListeners();
  }

  void cycleRepeatMode() {
    repeatMode = switch (repeatMode) {
      PulseRepeatMode.off => PulseRepeatMode.queue,
      PulseRepeatMode.queue => PulseRepeatMode.track,
      PulseRepeatMode.track => PulseRepeatMode.off,
    };
    notifyListeners();
  }

  void _shuffleFromCurrent() {
    final current = currentTrack;
    if (current == null) return;
    final remaining = List<AudioTrack>.of(_queue)
      ..removeWhere((track) => track.id == current.id)
      ..shuffle(_random);
    _queue = List.unmodifiable([current, ...remaining]);
    _currentIndex = 0;
  }

  void _handleTrackComplete() {
    if (_explicitlyPaused) return;
    if (_stopAfterTrackId == currentTrack?.id) {
      _clearSleepTimer();
      _isPlaying = false;
      _position = _duration;
      notifyListeners();
    } else if (repeatMode == PulseRepeatMode.track) {
      _restoredPosition = Duration.zero;
      unawaited(_playCurrent());
    } else if (autoPlayNext || repeatMode == PulseRepeatMode.queue) {
      unawaited(skipNext());
    } else {
      _isPlaying = false;
      notifyListeners();
    }
  }

  Future<void> playQueueItem(int index) async {
    if (index < 0 || index >= _queue.length) return;
    _explicitlyPaused = false;
    if (_crossfadePlayer != null || _preparingCrossfade) {
      await _cancelCrossfade();
    }
    _currentIndex = index;
    _restoredPosition = Duration.zero;
    await _playCurrent();
  }

  Future<void> seek(Duration value) async {
    if (_crossfadePlayer != null || _preparingCrossfade) {
      await _cancelCrossfade();
    }
    final maximum = max(
      _duration.inMilliseconds,
      currentTrack?.durationMillis ?? 0,
    );
    final clamped = value.inMilliseconds.clamp(0, maximum).toInt();
    try {
      final position = Duration(milliseconds: clamped);
      if (_remoteOutput case final remote?) {
        await remote.seek(position);
      } else {
        await _player?.seek(position);
      }
      _position = position;
      _saveCheckpoint();
      notifyListeners();
    } on Object catch (error) {
      _setError(error);
    }
  }

  Future<void> _playCurrent() async {
    final track = currentTrack;
    if (track == null) return;
    _opening = true;
    _position = Duration.zero;
    _duration = Duration(milliseconds: track.durationMillis ?? 0);
    _errorMessage = null;
    _saveCheckpoint();
    notifyListeners();
    try {
      if (_remoteOutput case final remote?) {
        await remote.load(track, _restoredPosition);
        await remote.play();
        await remote.waitUntilPlaying();
      } else if (onPlayTrack case final callback?) {
        await callback(track, _restoredPosition);
      } else {
        await _openCurrent(position: _restoredPosition);
      }
      if (_explicitlyPaused) await pause();
      _restoredPosition = Duration.zero;
    } on Object catch (error) {
      if (_remoteOutput case final remote?) {
        try {
          await remote.stop();
        } on Object {
          // Report the original playback failure below.
        }
      }
      _isPlaying = false;
      _setError(error);
    } finally {
      _opening = false;
    }
  }

  Future<void> _openCurrent({Duration position = Duration.zero}) async {
    final track = currentTrack;
    final player = _player;
    if (track == null || player == null) return;
    if (activateLocalAudio case final activate?) {
      if (!await activate()) {
        throw StateError('O áudio está em uso por outro aplicativo.');
      }
    }
    final uri = await _uriFor(track);
    final media = Media(uri, start: position > Duration.zero ? position : null);
    await player.open(media, play: true);
  }

  void _setError(Object error) {
    _errorMessage = 'Não foi possível reproduzir esta faixa: $error';
    notifyListeners();
  }

  bool restoreCheckpoint(
      List<AudioTrack> tracks, String trackId, int positionMillis,
      [List<String> queueIds = const []]) {
    final tracksById = {for (final track in tracks) track.id: track};
    final restoredQueue = queueIds.isEmpty
        ? List<AudioTrack>.of(tracks)
        : [
            for (final id in queueIds)
              if (tracksById[id] case final track?) track
          ];
    final restoredTrack =
        tracks.where((track) => track.id == trackId).firstOrNull;
    if (restoredTrack == null) return false;
    if (!restoredQueue.any((track) => track.id == trackId)) {
      restoredQueue.insert(0, restoredTrack);
    }
    _currentIndex = restoredQueue.indexWhere((track) => track.id == trackId);
    if (_currentIndex < 0) return false;
    _queue = List.unmodifiable(restoredQueue);
    _queueBeforeShuffle = null;
    _position = Duration(milliseconds: positionMillis.clamp(0, 1 << 30));
    _restoredPosition = _position;
    notifyListeners();
    return queueIds.isEmpty ||
        (queueIds.every(tracksById.containsKey) && queueIds.contains(trackId));
  }

  void _saveCheckpoint() {
    final track = currentTrack;
    if (track != null && !track.id.startsWith('pulse-incoming:')) {
      onCheckpoint?.call((
        trackId: track.id,
        positionMillis: _position.inMilliseconds,
        queueIds: _queue.map((track) => track.id).toList(growable: false),
      ));
    }
  }

  void persistCheckpoint() => _saveCheckpoint();

  @override
  void dispose() {
    unawaited(_stateSubscription?.cancel());
    unawaited(_positionSubscription?.cancel());
    unawaited(_durationSubscription?.cancel());
    unawaited(_completionSubscription?.cancel());
    unawaited(_errorSubscription?.cancel());
    unawaited(_remoteStateSubscription?.cancel());
    if (_remoteOutput case final remote?) unawaited(_disposeRemote(remote));
    _sleepTimer?.cancel();
    _crossfadeTimer?.cancel();
    unawaited(_crossfadePlayer?.dispose());
    unawaited(_player?.dispose());
    super.dispose();
  }

  Future<void> _disposeRemote(PulseRemotePlayback remote) async {
    try {
      await remote.stop();
    } on Object {
      // Dispose still closes the output when a receiver has disappeared.
    }
    try {
      await remote.dispose();
    } on Object {
      // Disposal cannot report an error to a closed controller.
    }
  }
}
