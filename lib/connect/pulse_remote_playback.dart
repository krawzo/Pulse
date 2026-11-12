import 'dart:async';
import 'dart:math';

import '../domain/audio_track.dart';
import 'pulse_output.dart';

/// Adapts a destination to the single-track operations used by the player.
///
/// The supplied URI must be reachable from [output]. This class never exposes
/// local file paths or Jellyfin credentials to the destination by itself.
class PulseRemotePlayback {
  PulseRemotePlayback({
    required this.output,
    required this.mediaUriFor,
    required this.mimeTypeFor,
    this.playingTimeout = const Duration(seconds: 15),
  });

  final PulseOutput output;
  final Future<Uri> Function(AudioTrack track) mediaUriFor;
  final Future<String> Function(AudioTrack track) mimeTypeFor;
  final Duration playingTimeout;

  bool _needsStart = false;
  String? _sessionId;
  Duration? _preparedPosition;

  String? get sessionId => _sessionId;
  Duration? get pendingStartPosition => _needsStart ? _preparedPosition : null;
  PulseOutputState get state => output.state;
  Stream<PulseOutputState> get states => output.states;

  /// Prepare the selected track, leaving the destination silent until play.
  Future<void> load(AudioTrack track, Duration position) async {
    final contentType = await mimeTypeFor(track);
    final uri = await mediaUriFor(track);
    final random = Random.secure();
    final sessionId = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final startPosition = position.isNegative ? Duration.zero : position;
    _sessionId = sessionId;
    _needsStart = false;
    _preparedPosition = startPosition;
    try {
      await output.prepare(PulseOutputSession(
        id: sessionId,
        queue: [
          PulseOutputMedia(
            trackId: track.id,
            uri: uri,
            title: track.title,
            artist: track.artist,
            album: track.album,
            contentType: contentType,
            duration: track.durationMillis == null
                ? null
                : Duration(milliseconds: track.durationMillis!),
            jellyfinItemId:
                track.source == AudioSource.jellyfin ? track.path : null,
          ),
        ],
        startIndex: 0,
        startPosition: startPosition,
      ));
      _needsStart = true;
    } on Object {
      try {
        await output.stop();
      } on Object {
        // Preserve the original prepare failure.
      }
      _sessionId = null;
      _preparedPosition = null;
      rethrow;
    }
  }

  Future<void> play() async {
    if (_needsStart) {
      await output.start();
      _needsStart = false;
      _preparedPosition = null;
    } else {
      await output.play();
    }
  }

  Future<void> pause() => output.pause();
  Future<void> seek(Duration position) => output.seek(position);
  Future<void> setVolume(double value) => output.setVolume(value);

  Future<void> stop() async {
    await output.stop();
    _needsStart = false;
    _sessionId = null;
    _preparedPosition = null;
  }

  /// Wait for the destination's state, not just a command acknowledgement.
  Future<void> waitUntilPlaying() async {
    final expectedSession = _sessionId;
    if (expectedSession == null) {
      throw StateError('Nenhuma faixa foi preparada no dispositivo.');
    }
    final completer = Completer<void>();
    void inspect(PulseOutputState value) {
      if (value.sessionId != expectedSession || completer.isCompleted) return;
      if (value.error case final error?) {
        completer.completeError(StateError(error.message));
      } else if (value.phase == PulseOutputPhase.error) {
        completer.completeError(StateError('Falha na reprodução remota.'));
      } else if (value.isPlaying) {
        completer.complete();
      }
    }

    final subscription = states.listen(
      inspect,
      onError: (Object error, StackTrace stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      },
      onDone: () {
        if (!completer.isCompleted) {
          completer.completeError(StateError('Dispositivo desconectado.'));
        }
      },
    );
    inspect(state);
    try {
      await completer.future.timeout(playingTimeout);
    } finally {
      await subscription.cancel();
    }
  }

  Future<void> dispose() => output.dispose();
}
