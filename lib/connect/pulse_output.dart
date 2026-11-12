import 'dart:async';

/// The playback destination. Cast and another Pulse are separate transports.
enum PulseOutputKind { local, cast, pulse }

/// Features that a destination can perform without falling back to this PC.
enum PulseOutputCapability { seek, skip, volume, queue, crossfade }

/// A media item already resolved for the selected destination.
///
/// [uri] must be playable by that destination. A local file URI or the
/// Jellyfin loopback proxy URL cannot be sent unchanged to another device.
class PulseOutputMedia {
  const PulseOutputMedia({
    required this.trackId,
    required this.uri,
    required this.title,
    required this.contentType,
    this.artist,
    this.album,
    this.duration,
    this.jellyfinItemId,
  });

  final String trackId;
  final Uri uri;
  final String title;
  final String? artist;
  final String? album;
  final String contentType;
  final Duration? duration;
  final String? jellyfinItemId;
}

/// One queue handoff. A new ID distinguishes it from an earlier transfer.
class PulseOutputSession {
  PulseOutputSession({
    required this.id,
    required Iterable<PulseOutputMedia> queue,
    required this.startIndex,
    this.startPosition = Duration.zero,
  }) : queue = List<PulseOutputMedia>.unmodifiable(queue);

  final String id;
  final List<PulseOutputMedia> queue;
  final int startIndex;
  final Duration startPosition;
}

enum PulseOutputPhase {
  disconnected,
  idle,
  preparing,
  ready,
  buffering,
  playing,
  paused,
  stopped,
  error,
}

/// An error suitable for display, without credentials or playable URLs.
class PulseOutputError {
  const PulseOutputError({
    required this.code,
    required this.message,
    this.retryable = false,
  });

  final String code;
  final String message;
  final bool retryable;
}

/// Authoritative state reported by the destination, not an optimistic command.
///
/// [schemaVersion] describes the wire/state shape. [revision] increases for
/// every new state from one output; callers discard older revisions. A new
/// [sessionId] supersedes reports from any earlier transfer.
class PulseOutputState {
  const PulseOutputState({
    required this.outputId,
    required this.revision,
    required this.phase,
    this.schemaVersion = currentSchemaVersion,
    this.sessionId,
    this.trackId,
    this.queueIndex,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.volume = 1,
    this.completed = false,
    this.error,
  });

  static const int currentSchemaVersion = 1;

  final int schemaVersion;
  final int revision;
  final String outputId;
  final String? sessionId;
  final PulseOutputPhase phase;
  final String? trackId;
  final int? queueIndex;
  final Duration position;
  final Duration duration;
  final double volume;
  final bool completed;
  final PulseOutputError? error;

  bool get isPlaying => phase == PulseOutputPhase.playing;
}

/// A local player, Cast receiver, or another Pulse seen as one destination.
///
/// Command futures acknowledge that a command was handled. Consumers use
/// [states] to confirm what actually happened before changing the active
/// destination. [states] must be a broadcast stream so a handoff and the UI
/// can observe the same transition. Unsupported optional operations throw
/// [UnsupportedError].
abstract interface class PulseOutput {
  String get id;
  PulseOutputKind get kind;
  Set<PulseOutputCapability> get capabilities;
  PulseOutputState get state;
  Stream<PulseOutputState> get states;

  /// Accept a queue and seek position without beginning audible playback.
  Future<void> prepare(PulseOutputSession session);

  /// Begin the prepared session at its requested track and position.
  Future<void> start();

  /// Resume after pause, preserving the current queue and position.
  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);
  Future<void> next();
  Future<void> previous();

  /// Volume is normalized to the inclusive range 0.0–1.0.
  Future<void> setVolume(double value);

  /// Halt playback and release the prepared session.
  Future<void> stop();
  Future<void> dispose();
}
