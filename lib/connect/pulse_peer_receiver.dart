import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../domain/audio_track.dart';
import '../state/playback_controller.dart';
import '../state/jellyfin_controller.dart';
import 'pulse_peer_trust.dart';

typedef PulsePeerApproval = Future<bool> Function(String name, String address);

/// Small LAN-only receiver. A person must approve each new sender on this
/// device. The approved sender gets a random token scoped to its IP address.
class PulsePeerReceiver {
  PulsePeerReceiver(
      {required PlaybackController playback,
      required JellyfinController jellyfin,
      required PulsePeerTrust trust})
      : _playback = playback,
        _jellyfin = jellyfin,
        _trust = trust;

  final PlaybackController _playback;
  final JellyfinController _jellyfin;
  final PulsePeerTrust _trust;
  Future<bool> Function(String peerId)? onReverseRequested;
  HttpServer? _server;
  PulsePeerApproval? onApprovalRequested;
  String? _token;
  String? _pairedAddress;
  String? _pairedAccount;
  String? _sessionId;
  String? _trackId;
  String? _incomingTrackId;
  Uri? _mediaUri;
  AudioTrack? _jellyfinTrack;
  String? _title;
  String? _artist;
  String? _album;
  int? _durationMillis;
  Duration _startPosition = Duration.zero;
  bool _started = false;
  bool _pairing = false;
  int _revision = 0;
  bool? _previousAutoPlayNext;
  bool _disposed = false;

  Future<int?> start() async {
    if (_disposed) return null;
    try {
      final server = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      if (_disposed) {
        await server.close(force: true);
        return null;
      }
      _server = server;
      _playback.addListener(_onPlaybackChanged);
      server.listen((request) => unawaited(_handle(request)));
      return server.port;
    } on Object {
      return null;
    }
  }

  void _onPlaybackChanged() => _revision++;

  Future<void> _handle(HttpRequest request) async {
    try {
      final address = request.connectionInfo?.remoteAddress;
      if (address == null || !_isPrivateIpv4(address)) {
        await _reply(
            request, HttpStatus.forbidden, {'error': 'Rede inválida.'});
        return;
      }
      if (request.method == 'POST' && request.uri.path == '/pair') {
        await _pair(request, address);
        return;
      }
      if (_token == null ||
          _pairedAddress != address.address ||
          _pairedAccount != _jellyfin.accountFingerprint ||
          request.headers.value('X-Pulse-Session') != _token) {
        await _reply(request, HttpStatus.unauthorized,
            {'error': 'Conexão não autorizada.'});
        return;
      }
      if (request.method == 'GET' && request.uri.path == '/state') {
        await _reply(request, HttpStatus.ok, _state());
        return;
      }
      if (request.method != 'POST') {
        await _reply(request, HttpStatus.methodNotAllowed,
            {'error': 'Comando não permitido.'});
        return;
      }
      switch (request.uri.path) {
        case '/takeover':
          await _takeOver(request);
        case '/prepare':
          await _prepare(request, address);
        case '/start':
          await _startPlayback(request);
        case '/play':
          await _playback.togglePlaybackIfPaused();
          await _reply(request, HttpStatus.ok, _state());
        case '/pause':
          await _playback.pauseIfPlaying();
          await _reply(request, HttpStatus.ok, _state());
        case '/seek':
          final body = await _body(request);
          final value = body['positionMillis'];
          if (value is! int || value < 0 || value > 1 << 34) {
            throw const FormatException('Posição inválida.');
          }
          await _playback.seek(Duration(milliseconds: value));
          await _reply(request, HttpStatus.ok, _state());
        case '/volume':
          final body = await _body(request);
          final value = body['value'];
          if (value is! num || value < 0 || value > 1) {
            throw const FormatException('Volume inválido.');
          }
          await _playback.setVolume(value.toDouble());
          await _reply(request, HttpStatus.ok, _state());
        case '/stop':
          await _playback.pauseIfPlaying();
          _clearSession();
          await _reply(request, HttpStatus.ok, _state());
        default:
          await _reply(
              request, HttpStatus.notFound, {'error': 'Comando desconhecido.'});
      }
    } on FormatException catch (error) {
      await _reply(request, HttpStatus.badRequest, {'error': error.message});
    } on Object {
      await _reply(request, HttpStatus.internalServerError,
          {'error': 'Não foi possível executar o comando.'});
    }
  }

  Future<void> _takeOver(HttpRequest request) async {
    final body = await _body(request);
    final rawIds = body['itemIds'];
    final index = body['index'];
    final position = body['positionMillis'];
    final wasPlaying = body['wasPlaying'];
    if (rawIds is! List ||
        rawIds.isEmpty ||
        rawIds.length > 500 ||
        rawIds.any((id) => id is! String || id.isEmpty || id.length > 128) ||
        index is! int ||
        index < 0 ||
        index >= rawIds.length ||
        position is! int ||
        position < 0 ||
        position > 1 << 34 ||
        wasPlaying is! bool) {
      throw const FormatException('Fila inválida.');
    }
    final catalog = {
      for (final track in _jellyfin.tracks)
        if (track.source == AudioSource.jellyfin) track.path: track,
    };
    final tracks = <AudioTrack>[];
    for (final id in rawIds) {
      final track = catalog[id];
      if (track == null) {
        throw const FormatException(
            'Uma faixa não existe neste aparelho. Atualize a biblioteca.');
      }
      tracks.add(track);
    }
    _clearSession();
    // The incoming list is already in playback order, even if it was shuffled
    // on the sender. Do not shuffle it a second time on this device.
    _playback.setShuffleEnabled(false);
    await _playback.playPlaylistQueue(tracks, index);
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!_playback.isPlaying &&
        _playback.errorMessage == null &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (_playback.currentTrack?.path != tracks[index].path ||
        !_playback.isPlaying) {
      await _reply(request, HttpStatus.badGateway, {
        'error': _playback.errorMessage ?? 'A faixa não iniciou no destino.'
      });
      return;
    }
    if (position > 0) await _playback.seek(Duration(milliseconds: position));
    if (!wasPlaying) await _playback.pauseIfPlaying();
    await _reply(request, HttpStatus.ok, _state());
  }

  Future<void> _pair(HttpRequest request, InternetAddress address) async {
    if (_pairing) {
      await _reply(request, HttpStatus.conflict,
          {'error': 'Já existe um pedido de conexão pendente.'});
      return;
    }
    final body = await _body(request);
    final rawName = body['name'];
    final peerId = body['deviceId'];
    final account = _jellyfin.accountFingerprint;
    if (rawName is! String ||
        rawName.trim().isEmpty ||
        peerId is! String ||
        !RegExp(r'^[a-f0-9]{32}$').hasMatch(peerId)) {
      throw const FormatException('Nome do dispositivo inválido.');
    }
    if (account == null || body['account'] != account) {
      await _reply(request, HttpStatus.forbidden,
          {'error': 'Entre na mesma conta Jellyfin nos dois aparelhos.'});
      return;
    }
    final existingTicket = _trust.ticket(account, peerId);
    final trusted = existingTicket != null && body['ticket'] == existingTicket;
    if (_sessionId != null && !trusted) {
      await _reply(request, HttpStatus.conflict,
          {'error': 'Este Pulse já está recebendo outra sessão.'});
      return;
    }
    _pairing = true;
    try {
      var reversed = false;
      if (_playback.isRemoteOutput) {
        reversed =
            await (onReverseRequested?.call(peerId) ?? Future.value(false));
        if (!reversed) {
          await _reply(request, HttpStatus.conflict,
              {'error': 'Este Pulse já está usando outra saída.'});
          return;
        }
      }
      final approval = onApprovalRequested;
      if (!trusted &&
          !reversed &&
          (approval == null ||
              !await approval(
                      rawName
                          .trim()
                          .substring(0, min(48, rawName.trim().length)),
                      address.address)
                  .timeout(const Duration(seconds: 60),
                      onTimeout: () => false))) {
        await _reply(request, HttpStatus.forbidden,
            {'error': 'Conexão recusada no dispositivo.'});
        return;
      }
      _clearSession();
      _pairedAddress = address.address;
      _pairedAccount = account;
      _token = _secret();
      final ticket = trusted ? existingTicket : _secret();
      if (!trusted) await _trust.trust(account, peerId, ticket);
      await _reply(request, HttpStatus.ok, {
        'token': _token,
        'ticket': ticket,
        // This is the sender's IP as seen by the receiver, and is the address
        // the receiver must use when requesting the sender's audio stream.
        'senderAddress': address.address,
      });
    } finally {
      _pairing = false;
    }
  }

  Future<void> _prepare(HttpRequest request, InternetAddress address) async {
    final body = await _body(request);
    final sessionId = body['sessionId'];
    final trackId = body['trackId'];
    final title = body['title'];
    final uriString = body['uri'];
    final contentType = body['contentType'];
    final position = body['positionMillis'];
    final duration = body['durationMillis'];
    final jellyfinItemId = body['jellyfinItemId'];
    final uri = uriString is String ? Uri.tryParse(uriString) : null;
    if (sessionId is! String ||
        sessionId.isEmpty ||
        sessionId.length > 64 ||
        trackId is! String ||
        trackId.isEmpty ||
        trackId.length > 256 ||
        title is! String ||
        title.isEmpty ||
        title.length > 200 ||
        contentType is! String ||
        !contentType.startsWith('audio/') ||
        uri == null ||
        uri.scheme != 'http' ||
        uri.host != address.address ||
        uri.port <= 0 ||
        uri.pathSegments.length != 3 ||
        uri.pathSegments.first != 'pulse' ||
        uri.hasQuery ||
        uri.hasFragment ||
        position is! int ||
        position < 0 ||
        position > 1 << 34 ||
        duration != null && (duration is! int || duration < 0)) {
      throw const FormatException('Faixa remota inválida.');
    }
    final localJellyfinTrack = jellyfinItemId is String
        ? _jellyfin.tracks
            .where((track) => track.path == jellyfinItemId)
            .firstOrNull
        : null;
    if (jellyfinItemId != null && localJellyfinTrack == null) {
      throw const FormatException(
          'Faixa Jellyfin indisponível neste aparelho.');
    }
    _sessionId = sessionId;
    _trackId = trackId;
    _incomingTrackId = 'pulse-incoming:$sessionId:$trackId';
    _mediaUri = uri;
    _jellyfinTrack = localJellyfinTrack;
    _title = title;
    _artist = body['artist'] is String ? body['artist'] as String : null;
    _album = body['album'] is String ? body['album'] as String : null;
    _durationMillis = duration as int?;
    _startPosition = Duration(milliseconds: position);
    _started = false;
    _revision++;
    await _reply(request, HttpStatus.ok, _state());
  }

  Future<void> _startPlayback(HttpRequest request) async {
    final uri = _mediaUri;
    final incomingId = _incomingTrackId;
    if (uri == null || incomingId == null || _sessionId == null) {
      await _reply(
          request, HttpStatus.conflict, {'error': 'Nenhuma faixa preparada.'});
      return;
    }
    _previousAutoPlayNext ??= _playback.autoPlayNext;
    _playback.autoPlayNext = false;
    await _playback.playQueue([
      AudioTrack(
        id: incomingId,
        path: _jellyfinTrack?.path ?? uri.toString(),
        title: _title!,
        artist: _artist,
        album: _album,
        sizeBytes: 0,
        modifiedAtMillis: 0,
        durationMillis: _durationMillis,
        source:
            _jellyfinTrack == null ? AudioSource.local : AudioSource.jellyfin,
        artworkUrl: _jellyfinTrack?.artworkUrl,
      ),
    ], 0);
    _started = true;
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (!_playback.isPlaying &&
        _playback.errorMessage == null &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    if (!_playback.isPlaying || _playback.currentTrack?.id != incomingId) {
      await _reply(request, HttpStatus.badGateway, {
        'error': _playback.errorMessage ?? 'Áudio não iniciou no dispositivo.'
      });
      return;
    }
    if (_startPosition > Duration.zero) await _playback.seek(_startPosition);
    await _reply(request, HttpStatus.ok, _state());
  }

  Map<String, Object?> _state() {
    final sameTrack = _incomingTrackId != null &&
        _playback.currentTrack?.id == _incomingTrackId;
    final duration = sameTrack ? _playback.duration : Duration.zero;
    final position = sameTrack ? _playback.position : Duration.zero;
    final complete = sameTrack &&
        duration > Duration.zero &&
        !_playback.isPlaying &&
        position >= duration - const Duration(milliseconds: 500);
    final phase = _sessionId == null
        ? 'idle'
        : !_started
            ? 'ready'
            : !sameTrack && _mediaUri != null && _playback.currentTrack != null
                ? 'disconnected'
                : _playback.errorMessage != null && sameTrack
                    ? 'error'
                    : sameTrack
                        ? _playback.isPlaying
                            ? 'playing'
                            : complete
                                ? 'idle'
                                : 'paused'
                        : 'ready';
    return {
      'schemaVersion': 1,
      'revision': _revision,
      'sessionId': _sessionId,
      'trackId': _trackId,
      'phase': phase,
      'positionMillis': position.inMilliseconds,
      'durationMillis': duration.inMilliseconds,
      'volume': _playback.volume,
      'completed': complete,
      if (phase == 'error') 'error': _playback.errorMessage,
    };
  }

  void _clearSession() {
    _sessionId = null;
    _trackId = null;
    _incomingTrackId = null;
    _mediaUri = null;
    _jellyfinTrack = null;
    _title = null;
    _artist = null;
    _album = null;
    _durationMillis = null;
    _startPosition = Duration.zero;
    _started = false;
    if (_previousAutoPlayNext case final previous?) {
      _playback.autoPlayNext = previous;
      _previousAutoPlayNext = null;
    }
    _revision++;
  }

  Future<Map<String, dynamic>> _body(HttpRequest request) async {
    final bytes = <int>[];
    await for (final chunk in request) {
      bytes.addAll(chunk);
      if (bytes.length > (request.uri.path == '/takeover' ? 65536 : 8192)) {
        throw const FormatException('Comando muito grande.');
      }
    }
    final value = jsonDecode(utf8.decode(bytes));
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Comando inválido.');
    }
    return value;
  }

  Future<void> _reply(
      HttpRequest request, int code, Map<String, Object?> body) async {
    try {
      request.response.statusCode = code;
      request.response.headers.contentType = ContentType.json;
      request.response.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      request.response.write(jsonEncode(body));
      await request.response.close();
    } on Object {
      // The peer may have closed its socket while awaiting approval.
    }
  }

  static bool _isPrivateIpv4(InternetAddress address) {
    if (address.type != InternetAddressType.IPv4) return false;
    final bytes = address.rawAddress;
    return bytes[0] == 10 ||
        bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31 ||
        bytes[0] == 192 && bytes[1] == 168;
  }

  static String _secret() {
    final random = Random.secure();
    return List.generate(
            32, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _playback.removeListener(_onPlaybackChanged);
    _clearSession();
    await _server?.close(force: true);
  }
}
