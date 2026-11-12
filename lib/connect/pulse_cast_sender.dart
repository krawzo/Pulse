import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dart_cast/dart_cast.dart'
    show CastDevice, ChromecastDiscoveryProvider;
// dart_cast 0.7.4 exposes no public raw LOAD API. Keep this import isolated here.
// ignore: implementation_imports
import 'package:dart_cast/src/protocols/chromecast/castv2_channel.dart';
import 'package:flutter/foundation.dart';

/// The state reported by the Chromecast, separate from local Pulse playback.
enum PulseCastState {
  disconnected,
  connecting,
  ready,
  loading,
  buffering,
  playing,
  paused,
  idle,
  error,
}

class PulseCastException implements Exception {
  const PulseCastException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// Sends audio to the Chromecast Default Media Receiver over Cast V2.
///
/// The receiver downloads [loadAudio]'s URL itself. Callers must provide a URL
/// reachable from the Chromecast on the LAN; `file:` and localhost URLs cannot
/// work. This class intentionally does not expose the computer's local files or
/// the Jellyfin loopback proxy. Those need a separate, scoped LAN media server.
class PulseCastSender extends ChangeNotifier {
  PulseCastSender();

  static const _receiverAppId = 'CC1AD845';
  static const _receiverId = 'receiver-0';
  static const _connectionNamespace =
      'urn:x-cast:com.google.cast.tp.connection';
  static const _heartbeatNamespace = 'urn:x-cast:com.google.cast.tp.heartbeat';
  static const _receiverNamespace = 'urn:x-cast:com.google.cast.receiver';
  static const _mediaNamespace = 'urn:x-cast:com.google.cast.media';

  final ChromecastDiscoveryProvider _discovery = ChromecastDiscoveryProvider();
  final String _senderId = 'sender-${Random.secure().nextInt(0x7fffffff)}';
  final List<CastDevice> _devices = [];

  StreamSubscription<List<CastDevice>>? _discoverySubscription;
  Completer<List<CastDevice>>? _discoveryResult;
  StreamSubscription<dynamic>? _messageSubscription;
  CastV2Channel? _channel;
  Timer? _heartbeatTimer;
  Timer? _statusTimer;
  Completer<void>? _readyCompleter;
  Completer<void>? _loadCompleter;
  int? _loadRequestId;
  int? _previousMediaSessionId;
  int? _loadMediaSessionId;
  String? _loadContentId;
  int _requestId = Random.secure().nextInt(0x3fffffff) + 1;
  int _generation = 0;
  String? _transportId;
  int? _mediaSessionId;
  bool _isDiscovering = false;
  bool _completed = false;
  bool _disposed = false;
  CastDevice? _device;
  PulseCastState _state = PulseCastState.disconnected;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double? _volume;
  bool? _isMuted;
  String? _errorMessage;

  List<CastDevice> get devices => List.unmodifiable(_devices);
  CastDevice? get device => _device;
  PulseCastState get state => _state;
  Duration get position => _position;
  Duration get duration => _duration;

  /// Volume confirmed by the receiver, rather than an optimistic slider value.
  double? get volume => _volume;
  bool? get isMuted => _isMuted;
  String? get errorMessage => _errorMessage;
  bool get isDiscovering => _isDiscovering;

  /// True only when the receiver says the current media ended naturally.
  bool get completed => _completed;
  bool get isConnected => _channel != null && _transportId != null;

  /// Finds Google Cast receivers using mDNS. An empty list means none was found.
  Future<List<CastDevice>> discover({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    _checkDisposed();
    final previous = _discoveryResult;
    if (previous != null && !previous.isCompleted) previous.complete(devices);
    await _discoverySubscription?.cancel();
    _discovery.stopDiscovery();
    _devices.clear();
    _isDiscovering = true;
    _notify();

    final result = Completer<List<CastDevice>>();
    _discoveryResult = result;
    _discoverySubscription = _discovery.startDiscovery(timeout: timeout).listen(
      (found) {
        _devices
          ..clear()
          ..addAll(found);
        _notify();
      },
      onError: (Object error) {
        _isDiscovering = false;
        _errorMessage = 'Não foi possível procurar dispositivos: $error';
        _notify();
        if (!result.isCompleted) result.completeError(error);
        if (identical(_discoveryResult, result)) _discoveryResult = null;
      },
      onDone: () {
        _isDiscovering = false;
        _notify();
        if (!result.isCompleted) result.complete(devices);
        if (identical(_discoveryResult, result)) _discoveryResult = null;
      },
    );
    return result.future;
  }

  /// Launches the Default Media Receiver and waits for its transport ID.
  Future<void> connect(CastDevice device) async {
    _checkDisposed();
    await disconnect();
    final generation = ++_generation;
    _device = device;
    _errorMessage = null;
    _state = PulseCastState.connecting;
    final ready = Completer<void>();
    // The TLS connect can fail before we begin awaiting this completer.
    unawaited(ready.future.catchError((Object _) {}));
    _readyCompleter = ready;
    _notify();

    final channel = CastV2Channel();
    try {
      await channel.connect(device.address.address, port: device.port);
      if (generation != _generation || _disposed) {
        await channel.close();
        return;
      }
      _channel = channel;
      _messageSubscription = channel.messageStream.listen(
        _onMessage,
        onError: _onTransportError,
        onDone: _onTransportClosed,
      );
      _send(_connectionNamespace, _receiverId, {
        'type': 'CONNECT',
        'origin': <String, Object>{},
      });
      _startHeartbeat();
      _send(_receiverNamespace, _receiverId, {
        'type': 'LAUNCH',
        'appId': _receiverAppId,
        'requestId': _nextRequestId(),
      });
      _send(_receiverNamespace, _receiverId, {
        'type': 'GET_STATUS',
        'requestId': _nextRequestId(),
      });
      await ready.future.timeout(const Duration(seconds: 12));
      if (generation != _generation || _disposed) return;
      _state = PulseCastState.ready;
      _startPolling();
      _notify();
    } on Object catch (error) {
      if (generation == _generation && !_disposed) {
        _errorMessage = 'Não foi possível conectar a ${device.name}: $error';
        // A failed TLS handshake has not started awaiting [ready] yet.
        // Complete it before disconnect so a later error is not unhandled.
        if (!ready.isCompleted) ready.complete();
        await disconnect();
        _state = PulseCastState.error;
        _notify();
      } else {
        await channel.close();
      }
      rethrow;
    } finally {
      if (identical(_readyCompleter, ready)) _readyCompleter = null;
    }
  }

  /// Loads an audio URL which the receiver can fetch directly from the LAN.
  ///
  /// The caller supplies the real audio MIME type (for example `audio/mpeg`,
  /// `audio/mp4`, `audio/flac`). Codec support varies by Cast device. A LOAD
  /// failure is surfaced instead of silently claiming that playback started.
  /// This future completes only after the receiver reports PLAYING.
  Future<void> loadAudio({
    required Uri url,
    required String mimeType,
    required String title,
    String? artist,
    String? album,
    Uri? imageUrl,
    Duration startPosition = Duration.zero,
  }) async {
    _checkDisposed();
    _requireConnected();
    _checkReachableUrl(url);
    if (!mimeType.toLowerCase().startsWith('audio/')) {
      throw const PulseCastException('Informe um tipo de áudio válido.');
    }
    if (startPosition.isNegative) {
      throw const PulseCastException('A posição precisa ser positiva.');
    }
    if (imageUrl != null) _checkReachableUrl(imageUrl);
    if (_loadCompleter != null) {
      throw const PulseCastException('Uma faixa já está sendo enviada.');
    }

    final generation = _generation;
    final requestId = _nextRequestId();
    final load = Completer<void>();
    _loadCompleter = load;
    _loadRequestId = requestId;
    _previousMediaSessionId = _mediaSessionId;
    _loadMediaSessionId = null;
    _loadContentId = url.toString();
    _completed = false;
    _errorMessage = null;
    _state = PulseCastState.loading;
    _notify();

    final metadata = <String, Object>{
      'metadataType': 3, // MusicTrackMediaMetadata.
      'title': title,
      if (artist != null && artist.trim().isNotEmpty) 'artist': artist,
      if (album != null && album.trim().isNotEmpty) 'albumName': album,
      if (imageUrl != null)
        'images': [
          {'url': imageUrl.toString()}
        ],
    };
    try {
      _send(_mediaNamespace, _transportId!, {
        'type': 'LOAD',
        'requestId': requestId,
        'autoplay': true,
        'currentTime': startPosition.inMilliseconds / 1000,
        'media': {
          'contentId': url.toString(),
          'contentType': mimeType,
          'streamType': 'BUFFERED',
          'metadata': metadata,
        },
      });
      await load.future.timeout(const Duration(seconds: 30));
    } on Object catch (error) {
      if (generation == _generation && !_disposed) {
        _errorMessage = 'A TV não conseguiu carregar a faixa: $error';
        _state = PulseCastState.error;
        _notify();
      }
      rethrow;
    } finally {
      if (identical(_loadCompleter, load)) {
        _loadCompleter = null;
        _loadRequestId = null;
        _previousMediaSessionId = null;
        _loadMediaSessionId = null;
        _loadContentId = null;
      }
    }
  }

  Future<void> play() async => _sendMediaCommand('PLAY');
  Future<void> pause() async => _sendMediaCommand('PAUSE');
  Future<void> stop() async => _sendMediaCommand('STOP');

  Future<void> seek(Duration position) async {
    if (position.isNegative) {
      throw const PulseCastException('A posição precisa ser positiva.');
    }
    _sendMediaCommand('SEEK', {
      'currentTime': position.inMilliseconds / 1000,
    });
  }

  /// Changes the receiver device volume. The [volume] getter updates only
  /// after a RECEIVER_STATUS response confirms the value.
  Future<void> setVolume(double level) async {
    _requireConnected();
    if (!level.isFinite || level < 0 || level > 1) {
      throw const PulseCastException('Volume precisa estar entre 0 e 1.');
    }
    _send(_receiverNamespace, _receiverId, {
      'type': 'SET_VOLUME',
      'requestId': _nextRequestId(),
      'volume': {'level': level},
    });
    _send(_receiverNamespace, _receiverId, {
      'type': 'GET_STATUS',
      'requestId': _nextRequestId(),
    });
  }

  /// Requests the receiver's current playback state and position.
  Future<void> refreshStatus() async {
    _requireConnected();
    _send(_mediaNamespace, _transportId!, {
      'type': 'GET_STATUS',
      'requestId': _nextRequestId(),
    });
  }

  /// Disconnects the sender. The receiver keeps playing unless [stopPlayback]
  /// is true, as with other Cast senders.
  Future<void> disconnect({bool stopPlayback = false}) async {
    ++_generation;
    if (stopPlayback && _mediaSessionId != null && isConnected) {
      try {
        _sendMediaCommand('STOP');
      } on Object {
        // The socket may already be gone.
      }
    }
    _heartbeatTimer?.cancel();
    _statusTimer?.cancel();
    _heartbeatTimer = null;
    _statusTimer = null;
    _completePending(PulseCastException('Conexão com a TV encerrada.'));
    await _messageSubscription?.cancel();
    _messageSubscription = null;
    final channel = _channel;
    _channel = null;
    _transportId = null;
    _mediaSessionId = null;
    _completed = false;
    _device = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    _volume = null;
    _isMuted = null;
    _state = PulseCastState.disconnected;
    _notify();
    await channel?.close();
  }

  void _onMessage(dynamic message) {
    if (_disposed) return;
    final namespace = message.namespace_ as String;
    Map<String, dynamic> payload;
    try {
      payload = Map<String, dynamic>.from(
        jsonDecode(message.payloadUtf8 as String) as Map,
      );
    } on Object {
      return;
    }
    final type = payload['type'];
    if (namespace == _heartbeatNamespace) {
      if (type == 'PING') {
        _send(_heartbeatNamespace, _receiverId, {'type': 'PONG'});
      }
      return;
    }
    if (namespace == _receiverNamespace) {
      if (type == 'RECEIVER_STATUS') _onReceiverStatus(payload);
      if (type == 'LAUNCH_ERROR') {
        _completePending(const PulseCastException(
          'A TV recusou abrir o reprodutor Cast.',
        ));
      }
      return;
    }
    if (namespace != _mediaNamespace || message.sourceId != _transportId) {
      return;
    }
    if (type == 'MEDIA_STATUS') {
      _onMediaStatus(payload);
    } else if (type == 'LOAD_FAILED' ||
        type == 'LOAD_CANCELLED' ||
        type == 'INVALID_REQUEST' ||
        type == 'INVALID_PLAYER_STATE') {
      final error = PulseCastException('Comando Cast recusado: $type.');
      if (payload['requestId'] == _loadRequestId) {
        _completeLoadError(error);
      } else {
        _errorMessage = error.message;
        _notify();
      }
    }
  }

  void _onReceiverStatus(Map<String, dynamic> payload) {
    final status = payload['status'];
    if (status is! Map) return;
    final volume = status['volume'];
    if (volume is Map) {
      final level = volume['level'];
      if (level is num) _volume = level.toDouble().clamp(0, 1);
      if (volume['muted'] is bool) _isMuted = volume['muted'] as bool;
      _notify();
    }
    final applications = status['applications'];
    if (applications is! List) return;
    for (final app in applications) {
      if (app is! Map || app['appId'] != _receiverAppId) continue;
      final transportId = app['transportId'];
      if (transportId is! String || transportId.isEmpty) continue;
      if (_transportId != transportId) {
        _transportId = transportId;
        _send(_connectionNamespace, transportId, {
          'type': 'CONNECT',
          'origin': <String, Object>{},
        });
        _send(_mediaNamespace, transportId, {
          'type': 'GET_STATUS',
          'requestId': _nextRequestId(),
        });
      }
      if (_readyCompleter?.isCompleted == false) _readyCompleter!.complete();
      return;
    }
  }

  void _onMediaStatus(Map<String, dynamic> payload) {
    final statuses = payload['status'];
    if (statuses is! List || statuses.isEmpty) {
      if (_loadCompleter?.isCompleted != false) {
        _mediaSessionId = null;
        _state = PulseCastState.idle;
      }
      _notify();
      return;
    }
    final status = statuses.first;
    if (status is! Map) return;
    final sessionId = status['mediaSessionId'];
    final media = status['media'];
    final load = _loadCompleter;
    if (load != null && !load.isCompleted) {
      // A replacement LOAD can overlap late statuses from the old session.
      if (sessionId == _previousMediaSessionId) return;
      if (sessionId is int &&
          (payload['requestId'] == _loadRequestId ||
              (media is Map && media['contentId'] == _loadContentId))) {
        _loadMediaSessionId ??= sessionId;
      }
      // Do not let another sender's status finish our LOAD or interrupt the PC.
      if (sessionId is! int || sessionId != _loadMediaSessionId) return;
    }
    if (sessionId is int) _mediaSessionId = sessionId;
    final seconds = status['currentTime'];
    if (seconds is num) {
      _position = Duration(milliseconds: (seconds.toDouble() * 1000).round());
    }
    if (media is Map && media['duration'] is num) {
      _duration = Duration(
        milliseconds: ((media['duration'] as num).toDouble() * 1000).round(),
      );
    }
    final remoteState = status['playerState'];
    // An old track may finish while a replacement LOAD is still pending.
    _completed = (load == null || load.isCompleted) &&
        remoteState == 'IDLE' &&
        status['idleReason'] == 'FINISHED';
    _state = switch (remoteState) {
      'PLAYING' => PulseCastState.playing,
      'PAUSED' => PulseCastState.paused,
      'BUFFERING' => PulseCastState.buffering,
      'IDLE' => PulseCastState.idle,
      _ => _state,
    };
    if (remoteState == 'IDLE' && status['idleReason'] == 'ERROR') {
      _completeLoadError(const PulseCastException(
        'A TV não conseguiu reproduzir este formato ou URL.',
      ));
      _state = PulseCastState.error;
    } else if (load != null) {
      final newSession = sessionId is int &&
          sessionId == _loadMediaSessionId &&
          remoteState == 'PLAYING';
      if (!load.isCompleted && newSession) {
        load.complete();
      }
    }
    if (remoteState == 'IDLE') _mediaSessionId = null;
    _notify();
  }

  void _onTransportError(Object error) {
    _errorMessage = 'A ligação com a TV falhou: $error';
    _state = PulseCastState.error;
    _completePending(PulseCastException(_errorMessage!));
    _heartbeatTimer?.cancel();
    _statusTimer?.cancel();
    _transportId = null;
    _mediaSessionId = null;
    _completed = false;
    final channel = _channel;
    _channel = null;
    unawaited(_messageSubscription?.cancel());
    _messageSubscription = null;
    if (channel != null) unawaited(channel.close());
    _notify();
  }

  void _onTransportClosed() {
    _heartbeatTimer?.cancel();
    _statusTimer?.cancel();
    _channel = null;
    _transportId = null;
    _mediaSessionId = null;
    _completed = false;
    _device = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    _volume = null;
    _isMuted = null;
    _state = PulseCastState.disconnected;
    _completePending(const PulseCastException('A TV encerrou a conexão.'));
    _notify();
  }

  void _startPolling() {
    _statusTimer?.cancel();
    _startHeartbeat();
    _statusTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!isConnected) return;
      try {
        _send(_mediaNamespace, _transportId!, {
          'type': 'GET_STATUS',
          'requestId': _nextRequestId(),
        });
      } on Object catch (error) {
        _onTransportError(error);
      }
    });
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (_channel == null) return;
      try {
        _send(_heartbeatNamespace, _receiverId, {'type': 'PING'});
      } on Object catch (error) {
        _onTransportError(error);
      }
    });
  }

  void _sendMediaCommand(String type, [Map<String, Object>? extra]) {
    _requireConnected();
    if (type == 'STOP') {
      _completed = false;
      _notify();
    }
    final mediaSessionId = _mediaSessionId;
    if (mediaSessionId == null) {
      if (type == 'STOP') return;
      throw const PulseCastException('Nenhuma faixa está carregada na TV.');
    }
    _send(_mediaNamespace, _transportId!, {
      'type': type,
      'mediaSessionId': mediaSessionId,
      'requestId': _nextRequestId(),
      ...?extra,
    });
  }

  void _send(String namespace, String destination, Map<String, Object> body) {
    final channel = _channel;
    if (channel == null) {
      throw const PulseCastException('TV desconectada.');
    }
    channel.sendMessage(
      namespace: namespace,
      sourceId: _senderId,
      destinationId: destination,
      payload: jsonEncode(body),
    );
  }

  int _nextRequestId() => ++_requestId;

  void _requireConnected() {
    if (!isConnected) {
      throw const PulseCastException('Conecte a uma TV antes de reproduzir.');
    }
  }

  void _checkDisposed() {
    if (_disposed) throw StateError('PulseCastSender já foi encerrado.');
  }

  static void _checkReachableUrl(Uri url) {
    final host = url.host.toLowerCase();
    if ((url.scheme != 'http' && url.scheme != 'https') ||
        host.isEmpty ||
        host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1' ||
        host == '0.0.0.0') {
      throw const PulseCastException(
        'A TV precisa de um endereço HTTP acessível na rede local.',
      );
    }
  }

  void _completeLoadError(Object error) {
    final load = _loadCompleter;
    if (load != null && !load.isCompleted) load.completeError(error);
  }

  void _completePending(Object error) {
    final ready = _readyCompleter;
    if (ready != null && !ready.isCompleted) ready.completeError(error);
    _completeLoadError(error);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    _heartbeatTimer?.cancel();
    _statusTimer?.cancel();
    _completePending(const PulseCastException('Emissor Cast encerrado.'));
    _discovery.stopDiscovery();
    _discovery.dispose();
    final discoveryResult = _discoveryResult;
    if (discoveryResult != null && !discoveryResult.isCompleted) {
      discoveryResult.complete(devices);
    }
    unawaited(_discoverySubscription?.cancel());
    unawaited(_messageSubscription?.cancel());
    final channel = _channel;
    _channel = null;
    if (channel != null) unawaited(channel.close());
    super.dispose();
  }
}
