import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../state/pulse_peer_discovery.dart';
import 'pulse_peer_trust.dart';
import 'pulse_output.dart';

/// Controls an approved Pulse on the same private LAN. The sender remains the
/// queue owner and serves each selected track through PulseMediaServer.
class PulsePeerOutput implements PulseOutput {
  PulsePeerOutput._(this.peer, this._token, this.senderAddress)
      : _client = HttpClient()..connectionTimeout = const Duration(seconds: 5),
        _state = PulseOutputState(
          outputId: 'pulse:${peer.id}',
          revision: 0,
          phase: PulseOutputPhase.ready,
        ) {
    _pollTimer = Timer.periodic(
        const Duration(milliseconds: 750), (_) => unawaited(_poll()));
  }

  final PulsePeer peer;
  final String _token;

  /// The sender address observed by the receiver during pairing.
  final InternetAddress? senderAddress;
  final HttpClient _client;
  final StreamController<PulseOutputState> _states =
      StreamController<PulseOutputState>.broadcast();
  late final Timer _pollTimer;
  PulseOutputState _state;
  PulseOutputSession? _session;
  bool _disposed = false;
  bool _polling = false;
  int _revision = 0;

  static Future<PulsePeerOutput> pair(PulsePeer peer,
      {required PulsePeerTrust trust, required String account}) async {
    if (peer.controlPort == null) {
      throw StateError('Atualize o Pulse no outro aparelho para conectar.');
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 5);
    try {
      final request = await client.postUrl(Uri(
        scheme: 'http',
        host: peer.address.address,
        port: peer.controlPort,
        path: '/pair',
      ));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode({
        'name': Platform.isAndroid ? 'celular Android' : Platform.localHostname,
        'deviceId': trust.deviceId,
        'account': account,
        'ticket': trust.ticket(account, peer.id),
      }));
      final response =
          await request.close().timeout(const Duration(seconds: 70));
      final data = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
      if (response.statusCode != HttpStatus.ok || data['token'] is! String) {
        throw StateError(data['error']?.toString() ?? 'Conexão recusada.');
      }
      final senderAddress = data['senderAddress'] is String
          ? InternetAddress.tryParse(data['senderAddress'] as String)
          : null;
      if (data['ticket'] is String) {
        await trust.trust(account, peer.id, data['ticket'] as String);
      }
      return PulsePeerOutput._(peer, data['token'] as String, senderAddress);
    } finally {
      client.close(force: true);
    }
  }

  @override
  String get id => 'pulse:${peer.id}';
  @override
  PulseOutputKind get kind => PulseOutputKind.pulse;
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
    if (session.startIndex < 0 || session.startIndex >= session.queue.length) {
      throw ArgumentError('Faixa inicial inválida.');
    }
    final media = session.queue[session.startIndex];
    _session = session;
    await _send('/prepare', {
      'sessionId': session.id,
      'trackId': media.trackId,
      'uri': media.uri.toString(),
      'title': media.title,
      'artist': media.artist,
      'album': media.album,
      'contentType': media.contentType,
      'positionMillis': session.startPosition.inMilliseconds,
      'durationMillis': media.duration?.inMilliseconds,
      'jellyfinItemId': media.jellyfinItemId,
    });
  }

  @override
  Future<void> start() async => _send('/start');
  @override
  Future<void> play() async => _send('/play');
  @override
  Future<void> pause() async => _send('/pause');
  @override
  Future<void> seek(Duration position) async =>
      _send('/seek', {'positionMillis': max(0, position.inMilliseconds)});
  @override
  Future<void> setVolume(double value) async =>
      _send('/volume', {'value': value.clamp(0.0, 1.0)});

  /// Gives the receiver its own Jellyfin queue, independent of this sender.
  Future<void> handOffQueue(List<String> itemIds, int index, Duration position,
          bool wasPlaying) =>
      _send('/takeover', {
        'itemIds': itemIds,
        'index': index,
        'positionMillis': position.inMilliseconds,
        'wasPlaying': wasPlaying,
      });
  @override
  Future<void> next() async =>
      throw UnsupportedError('A fila é controlada pelo Pulse de origem.');
  @override
  Future<void> previous() async =>
      throw UnsupportedError('A fila é controlada pelo Pulse de origem.');

  @override
  Future<void> stop() async {
    if (_disposed) return;
    await _send('/stop');
    _session = null;
  }

  Future<void> _send(String path,
      [Map<String, Object?> body = const {}]) async {
    _checkActive();
    final request = await _client.postUrl(_uri(path));
    request.headers.contentType = ContentType.json;
    request.headers.set('X-Pulse-Session', _token);
    request.write(jsonEncode(body));
    final response = await request
        .close()
        .timeout(Duration(seconds: path == '/takeover' ? 40 : 20));
    final data = await _readResponse(response);
    if (response.statusCode != HttpStatus.ok) {
      throw StateError(
          data['error']?.toString() ?? 'Comando recusado pelo aparelho.');
    }
    _accept(data);
  }

  Future<void> _poll() async {
    if (_polling || _disposed || _session == null) return;
    _polling = true;
    try {
      final request = await _client.getUrl(_uri('/state'));
      request.headers.set('X-Pulse-Session', _token);
      final response =
          await request.close().timeout(const Duration(seconds: 5));
      final data = await _readResponse(response);
      if (response.statusCode != HttpStatus.ok) {
        throw StateError('O aparelho recusou a sessão.');
      }
      _accept(data);
    } on Object {
      _emitDisconnected();
    } finally {
      _polling = false;
    }
  }

  Uri _uri(String path) => Uri(
        scheme: 'http',
        host: peer.address.address,
        port: peer.controlPort,
        path: path,
      );

  Future<Map<String, dynamic>> _readResponse(
      HttpClientResponse response) async {
    final bytes = <int>[];
    await for (final chunk in response) {
      bytes.addAll(chunk);
      if (bytes.length > 16384) throw StateError('Resposta muito grande.');
    }
    final data = jsonDecode(utf8.decode(bytes));
    if (data is! Map<String, dynamic>) throw StateError('Resposta inválida.');
    return data;
  }

  void _accept(Map<String, dynamic> data) {
    if (_disposed) return;
    final phase = switch (data['phase']) {
      'ready' => PulseOutputPhase.ready,
      'playing' => PulseOutputPhase.playing,
      'paused' => PulseOutputPhase.paused,
      'idle' => PulseOutputPhase.idle,
      'error' => PulseOutputPhase.error,
      'disconnected' => PulseOutputPhase.disconnected,
      _ => PulseOutputPhase.error,
    };
    final remoteRevision =
        data['revision'] is int ? data['revision'] as int : 0;
    _revision = max(_revision + 1, remoteRevision);
    _state = PulseOutputState(
      outputId: id,
      revision: _revision,
      phase: phase,
      sessionId: data['sessionId'] as String? ?? _session?.id,
      trackId: data['trackId'] as String?,
      queueIndex: 0,
      position: Duration(
          milliseconds: data['positionMillis'] is int
              ? data['positionMillis'] as int
              : 0),
      duration: Duration(
          milliseconds: data['durationMillis'] is int
              ? data['durationMillis'] as int
              : 0),
      volume: data['volume'] is num ? (data['volume'] as num).toDouble() : 1,
      completed: data['completed'] == true,
      error: data['error'] is String
          ? PulseOutputError(
              code: 'peer_error', message: data['error'] as String)
          : null,
    );
    _states.add(_state);
  }

  void _emitDisconnected() {
    if (_disposed || _state.phase == PulseOutputPhase.disconnected) return;
    _state = PulseOutputState(
      outputId: id,
      revision: ++_revision,
      phase: PulseOutputPhase.disconnected,
      sessionId: _session?.id,
      error: const PulseOutputError(
        code: 'peer_lost',
        message: 'A conexão com o outro Pulse foi perdida.',
        retryable: true,
      ),
    );
    _states.add(_state);
  }

  void _checkActive() {
    if (_disposed) throw StateError('Conexão Pulse encerrada.');
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _pollTimer.cancel();
    _client.close(force: true);
    await _states.close();
  }
}
