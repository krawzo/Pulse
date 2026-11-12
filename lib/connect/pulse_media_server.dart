import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../domain/audio_track.dart';

/// Serves only registered tracks to one receiver during a device session.
///
/// Advertise a private IPv4 address selected for the receiver's LAN.
/// A successful bind means that the server is listening; it does not prove that
/// Windows Firewall permits the receiver to reach it. Wait for
/// [PulseMediaServerStatus.receiverContacted] and the receiver's playback
/// status before reporting that handoff succeeded.
class PulseMediaServer extends ChangeNotifier {
  PulseMediaServer({
    required Future<Uri> Function(AudioTrack track) jellyfinStreamUrl,
  }) : _jellyfinStreamUrl = jellyfinStreamUrl;

  final Future<Uri> Function(AudioTrack track) _jellyfinStreamUrl;
  final Map<String, AudioTrack> _registeredTracks = {};

  HttpServer? _server;
  InternetAddress? _advertisedAddress;
  HttpClient? _upstreamClient;
  InternetAddress? _receiverAddress;
  String? _sessionSecret;
  String? _lastError;
  DateTime? _lastReceiverRequestAt;
  PulseMediaServerStatus _status = PulseMediaServerStatus.stopped;
  bool _disposed = false;

  PulseMediaServerStatus get status => _status;
  String? get lastError => _lastError;
  DateTime? get lastReceiverRequestAt => _lastReceiverRequestAt;
  InternetAddress? get boundAddress => _advertisedAddress;
  int? get port => _server?.port;
  bool get isListening => _server != null;

  /// Finds a local LAN address for receivers without a pairing handshake,
  /// such as Cast devices. Socket.address names the *destination* of an
  /// outbound Dart socket, so choose from the machine's actual interfaces.
  static Future<InternetAddress> findBindAddressForReceiver({
    required InternetAddress receiverAddress,
    required int receiverPort,
    Duration timeout = const Duration(seconds: 3),
  }) async {
    if (!_isPrivateIpv4(receiverAddress) ||
        receiverPort <= 0 ||
        receiverPort > 65535) {
      throw ArgumentError('Endereço ou porta do receptor inválidos.');
    }
    final socket = await Socket.connect(
      receiverAddress,
      receiverPort,
      timeout: timeout,
    );
    socket.destroy();
    final addresses = await _localPrivateAddresses();
    if (addresses.isEmpty) {
      throw StateError('Nenhuma interface IPv4 privada está disponível.');
    }
    addresses.sort((a, b) => _commonPrefixLength(b, receiverAddress)
        .compareTo(_commonPrefixLength(a, receiverAddress)));
    return addresses.first;
  }

  /// Opens a new session and advertises the selected private LAN address.
  ///
  /// Throws when binding fails. A firewall block may only become apparent
  /// later, when the receiver never requests a registered media URL.
  Future<void> start({
    required InternetAddress bindAddress,
    required InternetAddress receiverAddress,
  }) async {
    if (_disposed) throw StateError('O servidor de mídia foi encerrado.');
    if (_server != null || _status == PulseMediaServerStatus.starting) {
      throw StateError('Já existe uma sessão de mídia ativa.');
    }
    if (!_isPrivateIpv4(bindAddress) || !_isPrivateIpv4(receiverAddress)) {
      throw ArgumentError(
          'Selecione endereços IPv4 privados do computador e do receptor.');
    }
    final addresses = await _localPrivateAddresses();
    if (!addresses.any((address) => address.address == bindAddress.address)) {
      throw StateError(
        'O endereço usado para enviar áudio não pertence mais a este aparelho. '
        'Confira a conexão de rede e tente novamente.',
      );
    }

    _status = PulseMediaServerStatus.starting;
    _lastError = null;
    _lastReceiverRequestAt = null;
    _notify();
    HttpServer? openedServer;
    try {
      // Listen on IPv4 interfaces while publishing only the routed LAN address.
      // A per-interface bind can fail with Windows error 10049 if the adapter
      // changes between route selection and server startup.
      final server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        0,
        shared: false,
      );
      openedServer = server;
      if (_status != PulseMediaServerStatus.starting || _disposed) {
        await server.close(force: true);
        throw StateError('A sessão de mídia foi cancelada.');
      }
      _server = server;
      _advertisedAddress = bindAddress;
      _receiverAddress = receiverAddress;
      _sessionSecret = _newSecret(24);
      _upstreamClient = HttpClient();
      _registeredTracks.clear();
      server.listen(
        (request) => unawaited(_handleRequest(request)),
        onError: (Object error) {
          _lastError = 'Falha de rede no servidor de mídia: $error';
          _notify();
        },
      );
      _status = PulseMediaServerStatus.listening;
      _notify();
    } on Object catch (error) {
      if (openedServer != null && identical(_server, openedServer)) {
        _server = null;
        _advertisedAddress = null;
        _receiverAddress = null;
        _sessionSecret = null;
        _registeredTracks.clear();
        _upstreamClient?.close(force: true);
        _upstreamClient = null;
        await openedServer.close(force: true);
      }
      if (_status != PulseMediaServerStatus.stopped) {
        _status = PulseMediaServerStatus.failed;
        _lastError = 'Não foi possível iniciar o servidor de mídia: $error';
        _notify();
      }
      rethrow;
    }
  }

  /// Registers a library track and returns a short-lived, unguessable URL.
  ///
  /// The path contains neither a local filename nor Jellyfin credentials.
  /// Stop the server when disconnecting from the receiver to revoke all URLs.
  Uri mediaUriFor(AudioTrack track) {
    final server = _server;
    final advertisedAddress = _advertisedAddress;
    final secret = _sessionSecret;
    if (server == null || advertisedAddress == null || secret == null) {
      throw StateError('Inicie a sessão antes de compartilhar uma faixa.');
    }
    String mediaKey;
    do {
      mediaKey = _newSecret(16);
    } while (_registeredTracks.containsKey(mediaKey));
    _registeredTracks[mediaKey] = track;
    return Uri(
      scheme: 'http',
      host: advertisedAddress.address,
      port: server.port,
      pathSegments: ['pulse', secret, mediaKey],
    );
  }

  /// Returns the audio MIME type to use in a Cast LOAD request.
  ///
  /// Jellyfin is queried through its existing loopback proxy, so the receiver
  /// never receives a Jellyfin access token or a server URL.
  Future<String> mimeTypeFor(AudioTrack track) async {
    if (_server == null) {
      throw StateError('Inicie a sessão antes de consultar a faixa.');
    }
    if (track.source == AudioSource.local) {
      final stat = await File(track.path).stat();
      if (stat.type != FileSystemEntityType.file) {
        throw StateError('O arquivo local desta faixa não está disponível.');
      }
      final mimeType = _mimeType(track.path);
      if (!mimeType.startsWith('audio/')) {
        throw StateError(
            'O arquivo local não tem um formato de áudio reconhecido.');
      }
      return mimeType;
    }

    final uri = await _jellyfinStreamUrl(track);
    if (uri.scheme == 'file') {
      final file = File.fromUri(uri);
      if (!await file.exists()) {
        throw StateError('Download offline não está disponível.');
      }
      return _mimeType(file.path);
    }
    if (uri.scheme != 'http' || uri.host != '127.0.0.1' || uri.port == 0) {
      throw StateError('O proxy local do Jellyfin não está disponível.');
    }
    final client = _upstreamClient;
    if (client == null) throw StateError('A sessão de mídia foi encerrada.');
    final request = await client.openUrl('HEAD', uri);
    request.followRedirects = false;
    final response = await request.close();
    try {
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StateError(
            'O Jellyfin não forneceu o formato da faixa (HTTP ${response.statusCode}).');
      }
      final mimeType = response.headers.contentType?.mimeType.toLowerCase();
      if (mimeType == null || !mimeType.startsWith('audio/')) {
        throw StateError('O Jellyfin não informou um formato de áudio válido.');
      }
      return mimeType;
    } finally {
      await response.drain<void>();
    }
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    _advertisedAddress = null;
    _receiverAddress = null;
    _sessionSecret = null;
    _registeredTracks.clear();
    _upstreamClient?.close(force: true);
    _upstreamClient = null;
    _lastReceiverRequestAt = null;
    _status = PulseMediaServerStatus.stopped;
    _notify();
    await server?.close(force: true);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final server = _server;
    final remoteAddress = request.connectionInfo?.remoteAddress;
    final parts = request.uri.pathSegments;
    final secret = _sessionSecret;
    final track = parts.length == 3 ? _registeredTracks[parts.last] : null;
    if (server == null ||
        remoteAddress?.address != _receiverAddress?.address ||
        parts.length != 3 ||
        parts.first != 'pulse' ||
        parts[1] != secret ||
        track == null ||
        request.uri.hasQuery) {
      await _respond(request.response, HttpStatus.notFound);
      return;
    }
    if (request.method != 'GET' && request.method != 'HEAD') {
      request.response.headers.set(HttpHeaders.allowHeader, 'GET, HEAD');
      await _respond(request.response, HttpStatus.methodNotAllowed);
      return;
    }

    _lastReceiverRequestAt = DateTime.now();
    _status = PulseMediaServerStatus.receiverContacted;
    _notify();
    try {
      if (track.source == AudioSource.local) {
        await _serveLocal(request, track);
      } else {
        await _serveJellyfin(request, track);
      }
    } on Object catch (error) {
      _lastError = 'Não foi possível enviar a faixa ao dispositivo: $error';
      _notify();
      await _respond(request.response, HttpStatus.badGateway);
    }
  }

  Future<void> _serveLocal(HttpRequest request, AudioTrack track,
      {File? sourceFile}) async {
    final file = sourceFile ?? File(track.path);
    final stat = await file.stat();
    if (stat.type != FileSystemEntityType.file) {
      await _respond(request.response, HttpStatus.notFound);
      return;
    }
    final length = stat.size;
    final response = request.response;
    final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
    final range = rangeHeader == null ? null : _parseRange(rangeHeader, length);
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    response.headers.contentType = ContentType.parse(_mimeType(file.path));
    if (rangeHeader != null && range == null) {
      response.headers.set(HttpHeaders.contentRangeHeader, 'bytes */$length');
      await _respond(response, HttpStatus.requestedRangeNotSatisfiable);
      return;
    }

    final start = range?.start ?? 0;
    final endExclusive = range == null ? length : range.endInclusive + 1;
    response.statusCode =
        range == null ? HttpStatus.ok : HttpStatus.partialContent;
    response.contentLength = endExclusive - start;
    if (range != null) {
      response.headers.set(HttpHeaders.contentRangeHeader,
          'bytes ${range.start}-${range.endInclusive}/$length');
    }
    if (request.method == 'GET') {
      await response.addStream(file.openRead(start, endExclusive));
    }
    await response.close();
  }

  Future<void> _serveJellyfin(HttpRequest request, AudioTrack track) async {
    final uri = await _jellyfinStreamUrl(track);
    if (uri.scheme == 'file') {
      await _serveLocal(request, track, sourceFile: File.fromUri(uri));
      return;
    }
    // The authenticated Jellyfin controller owns this loopback proxy. Never
    // turn this server into an arbitrary LAN-to-Internet HTTP forwarder.
    if (uri.scheme != 'http' || uri.host != '127.0.0.1' || uri.port == 0) {
      throw StateError('O proxy local do Jellyfin não está disponível.');
    }
    final client = _upstreamClient;
    if (client == null) throw StateError('A sessão de mídia foi encerrada.');
    final upstreamRequest = await client.openUrl(request.method, uri);
    final requestedRange = request.headers.value(HttpHeaders.rangeHeader);
    if (requestedRange != null) {
      upstreamRequest.headers.set(HttpHeaders.rangeHeader, requestedRange);
    }
    final upstream = await upstreamRequest.close();
    final response = request.response;
    if (upstream.statusCode != HttpStatus.ok &&
        upstream.statusCode != HttpStatus.partialContent &&
        upstream.statusCode != HttpStatus.requestedRangeNotSatisfiable) {
      await upstream.drain<void>();
      await _respond(response, HttpStatus.badGateway);
      return;
    }
    response.statusCode = upstream.statusCode;
    response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    for (final header in [
      HttpHeaders.contentTypeHeader,
      HttpHeaders.contentLengthHeader,
      HttpHeaders.contentRangeHeader,
      HttpHeaders.acceptRangesHeader,
    ]) {
      final value = upstream.headers.value(header);
      if (value != null) response.headers.set(header, value);
    }
    if (request.method == 'HEAD') {
      await upstream.drain<void>();
    } else {
      await response.addStream(upstream);
    }
    await response.close();
  }

  Future<void> _respond(HttpResponse response, int statusCode) async {
    try {
      response.statusCode = statusCode;
      response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      response.contentLength = 0;
      await response.close();
    } on Object {
      // A failed stream may already have committed headers or closed the socket.
      try {
        await response.close();
      } on Object {
        // The receiver has disconnected.
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(stop());
    super.dispose();
  }

  static bool _isPrivateIpv4(InternetAddress address) {
    if (address.type != InternetAddressType.IPv4) return false;
    final bytes = address.rawAddress;
    return bytes[0] == 10 ||
        (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
        (bytes[0] == 192 && bytes[1] == 168);
  }

  static Future<List<InternetAddress>> _localPrivateAddresses() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    return [
      for (final interface in interfaces)
        for (final address in interface.addresses)
          if (_isPrivateIpv4(address)) address,
    ];
  }

  static int _commonPrefixLength(InternetAddress a, InternetAddress b) {
    final left = a.rawAddress;
    final right = b.rawAddress;
    var bits = 0;
    for (var i = 0; i < 4; i++) {
      final difference = left[i] ^ right[i];
      if (difference == 0) {
        bits += 8;
        continue;
      }
      for (var shift = 7; shift >= 0; shift--) {
        if (difference & (1 << shift) != 0) return bits;
        bits++;
      }
    }
    return bits;
  }

  static String _newSecret(int byteCount) {
    final random = Random.secure();
    return List.generate(byteCount,
        (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
  }

  static ({int start, int endInclusive})? _parseRange(
      String header, int length) {
    if (length <= 0) return null;
    final match = RegExp(r'^bytes=(\d*)-(\d*)$').firstMatch(header.trim());
    if (match == null) return null;
    final first = match.group(1)!;
    final last = match.group(2)!;
    if (first.isEmpty && last.isEmpty) return null;
    if (first.isEmpty) {
      final suffixLength = int.tryParse(last);
      if (suffixLength == null || suffixLength <= 0) return null;
      return (start: max(0, length - suffixLength), endInclusive: length - 1);
    }
    final start = int.tryParse(first);
    final end = last.isEmpty ? length - 1 : int.tryParse(last);
    if (start == null || end == null || start >= length || end < start) {
      return null;
    }
    return (start: start, endInclusive: min(end, length - 1));
  }

  static String _mimeType(String path) {
    final extension = path.toLowerCase().split('.').last;
    return switch (extension) {
      'mp3' => 'audio/mpeg',
      'm4a' || 'mp4' => 'audio/mp4',
      'aac' => 'audio/aac',
      'flac' => 'audio/flac',
      'ogg' || 'opus' => 'audio/ogg',
      'wav' => 'audio/wav',
      'wma' => 'audio/x-ms-wma',
      _ => 'application/octet-stream',
    };
  }
}

enum PulseMediaServerStatus {
  stopped,
  starting,
  listening,
  receiverContacted,
  failed,
}
