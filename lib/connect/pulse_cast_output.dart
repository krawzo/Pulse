import 'dart:async';

import 'package:dart_cast/dart_cast.dart' show CastDevice;

import 'pulse_cast_sender.dart';
import 'pulse_output.dart';

/// Adapts a Google Cast receiver to the Pulse output contract.
///
/// The caller starts a scoped LAN media server before preparing this output.
/// Only URLs from that server should be placed in [PulseOutputMedia].
class PulseCastOutput implements PulseOutput {
  PulseCastOutput(this.device, {PulseCastSender? sender})
      : _sender = sender ?? PulseCastSender(),
        _state = PulseOutputState(
          outputId: 'cast:${device.id}',
          revision: 0,
          phase: PulseOutputPhase.disconnected,
        ) {
    _sender.addListener(_onSenderChanged);
  }

  final CastDevice device;
  final PulseCastSender _sender;
  final StreamController<PulseOutputState> _states =
      StreamController<PulseOutputState>.broadcast();
  PulseOutputState _state;
  PulseOutputSession? _session;
  int _revision = 0;
  bool _disposed = false;

  @override
  String get id => 'cast:${device.id}';

  @override
  PulseOutputKind get kind => PulseOutputKind.cast;

  @override
  Set<PulseOutputCapability> get capabilities => const {
        PulseOutputCapability.seek,
        PulseOutputCapability.volume,
      };

  @override
  PulseOutputState get state => _state;

  @override
  Stream<PulseOutputState> get states => _states.stream;

  @override
  Future<void> prepare(PulseOutputSession session) async {
    _checkDisposed();
    if (session.startIndex < 0 || session.startIndex >= session.queue.length) {
      throw ArgumentError('Faixa inicial fora da fila.');
    }
    final media = session.queue[session.startIndex];
    if (!media.uri.hasScheme ||
        !{'http', 'https'}.contains(media.uri.scheme) ||
        !media.contentType.startsWith('audio/')) {
      throw ArgumentError('A TV requer uma URL HTTP e um formato de áudio.');
    }
    _session = session;
    _emit(PulseOutputPhase.preparing);
    try {
      if (!_sender.isConnected) await _sender.connect(device);
      _emit(PulseOutputPhase.ready);
    } on Object catch (error) {
      _emit(PulseOutputPhase.error,
          error: PulseOutputError(
            code: 'cast_connect_failed',
            message: 'Não foi possível preparar a TV: $error',
            retryable: true,
          ));
      rethrow;
    }
  }

  @override
  Future<void> start() async {
    _checkDisposed();
    final session = _session;
    if (session == null) throw StateError('Prepare uma faixa antes de tocar.');
    final media = session.queue[session.startIndex];
    final contentType = media.contentType;
    try {
      await _sender.loadAudio(
        url: media.uri,
        mimeType: contentType,
        title: media.title,
        artist: media.artist,
        album: media.album,
        startPosition: session.startPosition,
      );
      _onSenderChanged();
    } on Object catch (error) {
      _emit(PulseOutputPhase.error,
          error: PulseOutputError(
            code: 'cast_load_failed',
            message: 'A TV não conseguiu tocar esta faixa: $error',
            retryable: true,
          ));
      rethrow;
    }
  }

  @override
  Future<void> play() => _sender.play();

  @override
  Future<void> pause() => _sender.pause();

  @override
  Future<void> seek(Duration position) => _sender.seek(position);

  @override
  Future<void> next() async =>
      throw UnsupportedError('A fila é controlada pelo Pulse de origem.');

  @override
  Future<void> previous() async =>
      throw UnsupportedError('A fila é controlada pelo Pulse de origem.');

  @override
  Future<void> setVolume(double value) => _sender.setVolume(value);

  @override
  Future<void> stop() async {
    _checkDisposed();
    if (_sender.isConnected) await _sender.disconnect(stopPlayback: true);
    _session = null;
    _emit(PulseOutputPhase.stopped);
  }

  void _onSenderChanged() {
    if (_disposed) return;
    final phase = switch (_sender.state) {
      PulseCastState.disconnected => PulseOutputPhase.disconnected,
      PulseCastState.connecting => PulseOutputPhase.preparing,
      PulseCastState.ready => PulseOutputPhase.ready,
      PulseCastState.loading => PulseOutputPhase.buffering,
      PulseCastState.buffering => PulseOutputPhase.buffering,
      PulseCastState.playing => PulseOutputPhase.playing,
      PulseCastState.paused => PulseOutputPhase.paused,
      PulseCastState.idle => PulseOutputPhase.idle,
      PulseCastState.error => PulseOutputPhase.error,
    };
    _emit(
      phase,
      error: _sender.errorMessage == null
          ? null
          : PulseOutputError(
              code: 'cast_error',
              message: _sender.errorMessage!,
              retryable: true,
            ),
    );
  }

  void _emit(PulseOutputPhase phase, {PulseOutputError? error}) {
    if (_disposed) return;
    final session = _session;
    final media = session == null ? null : session.queue[session.startIndex];
    _state = PulseOutputState(
      outputId: id,
      revision: ++_revision,
      phase: phase,
      sessionId: session?.id,
      trackId: media?.trackId,
      queueIndex: session?.startIndex,
      position: _sender.position,
      duration: _sender.duration,
      volume: _sender.volume ?? 1,
      completed: _sender.completed,
      error: error,
    );
    _states.add(_state);
  }

  void _checkDisposed() {
    if (_disposed) throw StateError('A saída Cast foi encerrada.');
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _sender.removeListener(_onSenderChanged);
    _sender.dispose();
    await _states.close();
  }
}
