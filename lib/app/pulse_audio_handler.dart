import 'dart:async';

import 'package:audio_service/audio_service.dart';

import '../domain/audio_track.dart';
import '../state/playback_controller.dart';

/// Bridges Android's media session to the existing Pulse playback controller.
/// The controller remains the sole owner of the audio players and queue.
class PulseAudioHandler extends BaseAudioHandler {
  PlaybackController? _playback;
  String? _lastTrackId;
  List<AudioTrack>? _lastQueue;
  int _lastQueueIndex = -1;
  int _lastQueueLength = -1;
  int _lastPositionSecond = -1;
  bool? _lastPlaying;
  Duration? _lastDuration;
  bool _sessionStopped = false;

  void bind(PlaybackController playback) {
    if (identical(_playback, playback)) return;
    unbind();
    _playback = playback;
    _sessionStopped = false;
    playback.addListener(_sync);
    _sync();
  }

  void unbind() {
    _playback?.removeListener(_sync);
    _playback = null;
    _sessionStopped = true;
    _lastTrackId = null;
    _lastQueue = null;
    _lastQueueIndex = -1;
    _lastQueueLength = -1;
    _lastPositionSecond = -1;
    _lastPlaying = null;
    _lastDuration = null;
    mediaItem.add(null);
    queue.add(const []);
    playbackState
        .add(PlaybackState(processingState: AudioProcessingState.idle));
  }

  void _sync() {
    final playback = _playback;
    if (playback == null) return;
    if (_sessionStopped) {
      if (!playback.isPlaying) return;
      // A new play started from the app itself after a stopped session.
      _sessionStopped = false;
      _lastTrackId = null;
      _lastQueue = null;
      _lastPlaying = null;
      _lastPositionSecond = -1;
    }
    final track = playback.currentTrack;
    final duration = playback.duration > Duration.zero
        ? playback.duration
        : Duration(milliseconds: track?.durationMillis ?? 0);
    final queueChanged = !identical(playback.queue, _lastQueue) ||
        playback.currentIndex != _lastQueueIndex ||
        playback.queue.length != _lastQueueLength ||
        track?.id != _lastTrackId;
    if (queueChanged) {
      _lastQueue = playback.queue;
      _lastQueueIndex = playback.currentIndex;
      _lastQueueLength = playback.queue.length;
      _lastTrackId = track?.id;
      queue.add(playback.queue.map(_mediaItemFor).toList(growable: false));
    }
    if (queueChanged || duration != _lastDuration) {
      _lastDuration = duration;
      mediaItem.add(track == null ? null : _mediaItemFor(track, duration));
    }

    // The Android session projects the position between updates. Avoid
    // sending a platform message for every media_kit position callback.
    final second = playback.position.inSeconds;
    if (!queueChanged &&
        _lastPlaying == playback.isPlaying &&
        _lastPositionSecond >= 0 &&
        (second - _lastPositionSecond).abs() < 2) {
      return;
    }
    _lastPlaying = playback.isPlaying;
    _lastPositionSecond = second;
    playbackState.add(PlaybackState(
      controls: track == null
          ? const []
          : [
              MediaControl.skipToPrevious,
              playback.isPlaying ? MediaControl.pause : MediaControl.play,
              MediaControl.skipToNext,
            ],
      systemActions: track == null ? const {} : const {MediaAction.seek},
      androidCompactActionIndices: track == null ? const [] : const [0, 1, 2],
      processingState: track == null
          ? AudioProcessingState.idle
          : playback.errorMessage != null
              ? AudioProcessingState.error
              : AudioProcessingState.ready,
      playing: playback.isPlaying,
      updatePosition: playback.position,
      queueIndex: track == null ? null : playback.currentIndex,
    ));
  }

  MediaItem _mediaItemFor(AudioTrack track, [Duration? actualDuration]) {
    final art = track.artworkUrl;
    return MediaItem(
      id: track.id,
      title: track.title,
      artist: track.artist,
      album: track.album,
      duration: actualDuration ??
          (track.durationMillis == null
              ? null
              : Duration(milliseconds: track.durationMillis!)),
      artUri: art == null ? null : Uri.tryParse(art),
    );
  }

  @override
  Future<void> play() async {
    final playback = _playback;
    if (!_sessionStopped && playback != null && !playback.isPlaying) {
      await playback.togglePlayback();
    }
  }

  @override
  Future<void> pause() async {
    await _playback?.pauseIfPlaying();
  }

  @override
  Future<void> stop() async {
    await _playback?.pauseIfPlaying();
    _sessionStopped = true;
    _lastTrackId = null;
    _lastQueue = null;
    _lastPlaying = null;
    _lastPositionSecond = -1;
    mediaItem.add(null);
    queue.add(const []);
    playbackState
        .add(PlaybackState(processingState: AudioProcessingState.idle));
  }

  @override
  Future<void> onTaskRemoved() async {
    // Keep intentional background playback, but release a paused session when
    // the user removes Pulse from recent apps. Headsets cannot revive it later.
    if (_playback?.isPlaying != true) await stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await _playback?.seek(position);
    _lastPositionSecond = -1;
    _sync();
  }

  @override
  Future<void> skipToNext() async => _playback?.skipNext();

  @override
  Future<void> skipToPrevious() async => _playback?.skipPrevious();

  @override
  Future<void> skipToQueueItem(int index) async =>
      _playback?.playQueueItem(index);
}
