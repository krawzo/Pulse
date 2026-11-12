import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:crypto/crypto.dart';
import '../data/app_data_directory.dart';
import '../data/embedded_lyrics_reader.dart';
import '../data/jellyfin_client.dart';
import '../data/music_server_client.dart';
import '../data/navidrome_client.dart';
import '../data/remote_artwork_cache.dart';
import '../data/jellyfin_offline_store.dart';
import '../data/mobile_secure_session_store.dart';
import '../data/secure_session_store.dart';
import '../data/windows_secure_session_store.dart';
import '../domain/audio_track.dart';
import '../domain/pulse_lyrics.dart';

enum MusicServerKind { jellyfin, navidrome }

class JellyfinController extends ChangeNotifier {
  JellyfinController({
    SecureSessionStore? secureStorage,
    SecureSessionStore? navidromeStorage,
    SecureSessionStore? activeProviderStorage,
  })  : _storage = secureStorage ??
            (Platform.isWindows
                ? WindowsSecureSessionStore()
                : MobileSecureSessionStore()),
        _navidromeStorage = navidromeStorage ??
            (Platform.isWindows
                ? WindowsSecureSessionStore(fileName: 'navidrome-session.dpapi')
                : MobileSecureSessionStore(key: 'navidrome-session')),
        _activeProviderStorage = activeProviderStorage ??
            (Platform.isWindows
                ? WindowsSecureSessionStore(
                    fileName: 'music-provider-active.dpapi')
                : MobileSecureSessionStore(key: 'music-provider-active'));

  static const defaultServer = 'https://media.discovery.dev.br';
  final SecureSessionStore _storage;
  final SecureSessionStore _navidromeStorage;
  final SecureSessionStore _activeProviderStorage;
  final JellyfinOfflineStore _offline = JellyfinOfflineStore();
  MusicServerClient? _client;
  MusicServerKind _serverKind = MusicServerKind.jellyfin;
  HttpServer? _proxy;
  String? _proxyNonce;
  String? _userId;
  String? _username;
  String? _profileImageTag;
  String _server = defaultServer;
  List<AudioTrack> _tracks = const [];
  List<AudioTrack>? _readOnlyTracks;
  List<AudioTrack>? _readOnlyTracksSource;
  List<Map<String, dynamic>> _artists = const [];
  List<Map<String, dynamic>> _playlists = const [];
  final Set<String> _favoriteIds = {};
  final Set<String> _downloadingIds = {};
  final Set<String> _newTrackIds = {};
  DateTime? _catalogUpdatedAt;
  bool _hasCatalogBaseline = false;
  bool _loading = false;
  bool _sessionExpired = false;
  String? _error;
  String? _streamError;
  static const _catalogRefreshInterval = Duration(minutes: 15);
  DateTime? _lastNavidromeQueueSave;
  String? _lastNavidromeQueueSignature;
  Future<void> _queueWrite = Future<void>.value();
  DateTime? _lastConnectionWarmup;
  Future<void>? _connectionWarmup;

  bool get connected =>
      _client?.token != null && _userId != null && !_sessionExpired;
  bool get sessionExpired => _sessionExpired;
  bool get loading => _loading;
  String get server => _server;
  MusicServerKind get serverKind => _serverKind;
  String get serverName =>
      _serverKind == MusicServerKind.navidrome ? 'Navidrome' : 'Jellyfin';
  String? get username => _username;
  String? get userId => _userId;
  String? get accountFingerprint => _client?.token == null || _userId == null
      ? null
      : sha256
          .convert(utf8.encode(
              '${_serverKind == MusicServerKind.navidrome ? 'navidrome|' : ''}${JellyfinClient.validateServer(_server).toString().toLowerCase()}|$_userId'))
          .toString();
  String? get profileImageUrl => _profileImageTag == null || _proxy == null
      ? null
      : 'http://127.0.0.1:${_proxy!.port}/$_proxyNonce/user-image/$_userId';
  String? get error => _error;
  String? get streamError => _streamError;
  List<AudioTrack> get tracks {
    if (!identical(_tracks, _readOnlyTracksSource)) {
      _readOnlyTracksSource = _tracks;
      _readOnlyTracks = List.unmodifiable(_tracks);
    }
    return _readOnlyTracks!;
  }

  List<AudioTrack> get newTracks => List.unmodifiable(_tracks.where((track) =>
      track.source == AudioSource.jellyfin &&
      _newTrackIds.contains(track.path)));
  DateTime? get catalogUpdatedAt => _catalogUpdatedAt;
  List<Map<String, dynamic>> get artists => List.unmodifiable(_artists);
  List<Map<String, dynamic>> get playlists => List.unmodifiable(_playlists);
  Set<String> get favoriteIds => Set.unmodifiable(_favoriteIds);
  bool isDownloaded(AudioTrack track) =>
      track.source == AudioSource.jellyfin && _offline.contains(track.path);
  bool isDownloading(AudioTrack track) => _downloadingIds.contains(track.path);

  /// Refreshes an idle server connection in the background when the app returns.
  /// Playback does not wait for this request.
  Future<void> warmConnection() {
    final client = _client;
    if (!connected || client == null) return Future.value();
    if (_connectionWarmup case final pending?) return pending;
    final now = DateTime.now();
    if (_lastConnectionWarmup case final previous?) {
      if (now.difference(previous) < const Duration(minutes: 2)) {
        return Future.value();
      }
    }
    _lastConnectionWarmup = now;
    final pending = client
        .currentUser()
        .timeout(const Duration(seconds: 8))
        .then<void>((_) {}, onError: (Object _) {});
    _connectionWarmup = pending.whenComplete(() => _connectionWarmup = null);
    return _connectionWarmup!;
  }

  Future<void> saveNavidromeQueue(
      String trackId, int positionMillis, List<String> queueIds) async {
    final client = _client;
    if (_serverKind != MusicServerKind.navidrome ||
        client is! NavidromeClient ||
        !connected ||
        !trackId.startsWith('navidrome:') ||
        queueIds.isEmpty ||
        queueIds.any((id) => !id.startsWith('navidrome:'))) {
      return;
    }
    final signature = '$trackId|${queueIds.join(',')}';
    final now = DateTime.now();
    if (signature == _lastNavidromeQueueSignature &&
        _lastNavidromeQueueSave != null &&
        now.difference(_lastNavidromeQueueSave!) <
            const Duration(seconds: 30)) {
      return;
    }
    _lastNavidromeQueueSignature = signature;
    _lastNavidromeQueueSave = now;
    final current = trackId.substring('navidrome:'.length);
    final ids = queueIds
        .map((id) => id.substring('navidrome:'.length))
        .toList(growable: false);
    _queueWrite = _queueWrite.catchError((Object _) {}).then((_) async {
      if (!identical(_client, client)) return;
      try {
        await client.savePlayQueue(ids, current, positionMillis);
      } on Object {
        // Local playback and its checkpoint remain usable without the server.
      }
    });
    await _queueWrite;
  }

  Future<({String trackId, int positionMillis, List<String> queueIds})?>
      savedNavidromeQueue() async {
    final client = _client;
    if (_serverKind != MusicServerKind.navidrome ||
        client is! NavidromeClient ||
        !connected) {
      return null;
    }
    final queue = await client.getPlayQueue();
    if (queue == null) return null;
    return (
      trackId: 'navidrome:${queue.current}',
      positionMillis: queue.positionMillis,
      queueIds: queue.ids.map((id) => 'navidrome:$id').toList(growable: false),
    );
  }

  Future<void> restore() async {
    try {
      final active =
          await _activeProviderStorage.read() ?? MusicServerKind.jellyfin.name;
      if (active == 'none') return;
      final value = active == MusicServerKind.navidrome.name
          ? await _navidromeStorage.read()
          : await _storage.read();
      if (value == null) return;
      await _activateSession(value);
    } on Object {
      _error = 'Sessão $serverName indisponível. Reconecte nas Configurações.';
      notifyListeners();
    }
  }

  Future<bool> hasSavedSession(MusicServerKind kind) async {
    try {
      return await (kind == MusicServerKind.navidrome
                  ? _navidromeStorage
                  : _storage)
              .read() !=
          null;
    } on Object {
      return false;
    }
  }

  Future<void> activateSavedSession(MusicServerKind kind) async {
    final value =
        await (kind == MusicServerKind.navidrome ? _navidromeStorage : _storage)
            .read();
    if (value == null) throw StateError('Nenhuma sessão salva neste aparelho.');
    await _activeProviderStorage.write(kind.name);
    await _activateSession(value);
  }

  Future<void> _activateSession(String value) async {
    final session = jsonDecode(value) as Map;
    _client?.close();
    _lastConnectionWarmup = null;
    _server = session['server'] as String;
    _serverKind = session['provider'] == 'navidrome'
        ? MusicServerKind.navidrome
        : MusicServerKind.jellyfin;
    _username = session['username'] as String?;
    _userId = session['userId'] as String;
    _client = _serverKind == MusicServerKind.navidrome
        ? NavidromeClient(
            baseUri: NavidromeClient.validateServer(_server),
            username: _username ?? _userId!,
            password: session['token'] as String)
        : JellyfinClient(
            baseUri: JellyfinClient.validateServer(_server),
            token: session['token'] as String);
    RemoteArtworkCache.instance.setAccount(accountFingerprint);
    _sessionExpired = false;
    _tracks = const [];
    _artists = const [];
    _playlists = const [];
    _favoriteIds.clear();
    await _openOfflineLibrary();
    final cachedAt = await _loadCachedCatalog();
    notifyListeners();
    if (cachedAt == null) {
      await refresh();
    } else if (DateTime.now().difference(cachedAt) >= _catalogRefreshInterval) {
      unawaited(refresh());
    } else {
      unawaited(_checkCachedSession());
    }
  }

  Future<void> connectWithPassword(String server, String user, String password,
      {MusicServerKind kind = MusicServerKind.jellyfin}) async {
    _loading = true;
    _error = null;
    notifyListeners();
    MusicServerClient? candidate;
    try {
      candidate = kind == MusicServerKind.navidrome
          ? NavidromeClient(
              baseUri: NavidromeClient.validateServer(server),
              username: user.trim())
          : JellyfinClient(baseUri: JellyfinClient.validateServer(server));
      final auth = await candidate.authenticate(user.trim(), password);
      await _acceptAuth(candidate, server, auth, kind: kind);
    } on Object {
      candidate?.close();
      _error = 'Falha ao conectar. Verifique servidor, usuário e senha.';
      rethrow;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<({String code, String secret})> beginQuickConnect(
      String server) async {
    final candidate =
        JellyfinClient(baseUri: JellyfinClient.validateServer(server));
    try {
      final data = await candidate.initiateQuickConnect();
      return (code: data['Code'].toString(), secret: data['Secret'].toString());
    } finally {
      candidate.close();
    }
  }

  Future<bool> finishQuickConnect(String server, String secret) async {
    final candidate =
        JellyfinClient(baseUri: JellyfinClient.validateServer(server));
    try {
      if (!await candidate.quickConnectAuthorized(secret)) return false;
      final auth = await candidate.authenticateQuickConnect(secret);
      await _acceptAuth(candidate, server, auth);
      return true;
    } on Object {
      candidate.close();
      rethrow;
    }
  }

  Future<void> _acceptAuth(
      MusicServerClient client, String server, Map<String, dynamic> auth,
      {MusicServerKind kind = MusicServerKind.jellyfin}) async {
    final token = auth['AccessToken']?.toString();
    final user = auth['User'] as Map?;
    final userId = user?['Id']?.toString();
    if (token == null || token.isEmpty || userId == null || userId.isEmpty) {
      throw const FormatException('Resposta de autenticação incompleta.');
    }
    final username = user?['Name']?.toString();
    final targetStorage =
        kind == MusicServerKind.navidrome ? _navidromeStorage : _storage;
    await targetStorage.write(jsonEncode({
      'server': server,
      'provider': kind.name,
      'username': username,
      'userId': userId,
      'token': token,
    }));
    await _activeProviderStorage.write(kind.name);
    _client?.close();
    _lastConnectionWarmup = null;
    _client = client..token = token;
    _serverKind = kind;
    _server = server;
    _username = username;
    _userId = userId;
    RemoteArtworkCache.instance.setAccount(accountFingerprint);
    _profileImageTag = user?['PrimaryImageTag']?.toString();
    _sessionExpired = false;
    _tracks = const [];
    _artists = const [];
    _playlists = const [];
    _favoriteIds.clear();
    _newTrackIds.clear();
    _catalogUpdatedAt = null;
    _hasCatalogBaseline = false;
    await _openOfflineLibrary();
    await _loadCachedCatalog();
    notifyListeners();
    await refresh();
  }

  Future<void> refresh() async {
    final client = _client;
    final userId = _userId;
    if (client == null || userId == null) return;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final user = await client.currentUser();
      _profileImageTag = user['PrimaryImageTag']?.toString();
      _username = user['Name']?.toString() ?? _username;
      final tracks = await client.audioItems(userId);
      final previousIds = _tracks
          .where((track) => track.source == AudioSource.jellyfin)
          .map((track) => track.path)
          .toSet();
      if (_hasCatalogBaseline) {
        _newTrackIds.addAll(tracks
            .map((track) => track.path)
            .where((id) => !previousIds.contains(id)));
      }
      final currentIds = tracks.map((track) => track.path).toSet();
      _newTrackIds.removeWhere((id) => !currentIds.contains(id));
      final artists = await client.artists(userId);
      final playlists = await client.playlists(userId);
      await _ensureProxy();
      _tracks = _combineCatalogTracks(tracks);
      _favoriteIds
        ..clear()
        ..addAll(client.favoriteIds);
      _artists = artists;
      _playlists = playlists;
      _sessionExpired = false;
      _catalogUpdatedAt = DateTime.now();
      _hasCatalogBaseline = true;
      await _saveCachedCatalog(tracks);
    } on JellyfinException catch (error) {
      if (error.statusCode == HttpStatus.unauthorized) {
        _sessionExpired = true;
        _error = 'A sessão $serverName expirou. Entre novamente na sua conta.';
      } else {
        _error =
            'Não foi possível atualizar o catálogo $serverName (HTTP ${error.statusCode}).';
      }
    } on Object {
      _error = 'Não foi possível atualizar o catálogo $serverName.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _checkCachedSession() async {
    try {
      await _client?.currentUser();
    } on JellyfinException catch (error) {
      if (error.statusCode == HttpStatus.unauthorized) {
        _sessionExpired = true;
        _error = 'A sessão $serverName expirou. Entre novamente na sua conta.';
        notifyListeners();
      }
    } on Object {
      // Sem rede, a biblioteca salva continua disponível para navegação.
    }
  }

  Future<List<AudioTrack>> playlistTracks(String playlistId) async {
    final client = _client;
    final userId = _userId;
    if (client == null || userId == null) return const [];
    final ids = await client.playlistItemIds(playlistId, userId);
    final byId = {for (final track in _tracks) track.path: track};
    return [
      for (final id in ids)
        if (byId[id] case final track?) track
    ];
  }

  Future<void> refreshPlaylists() async {
    final client = _client;
    final userId = _userId;
    if (client == null || userId == null) return;
    _playlists = await client.playlists(userId);
    notifyListeners();
  }

  Future<String> createPlaylist(
      String name, Iterable<AudioTrack> tracks) async {
    final client = _client;
    final userId = _userId;
    if (client == null || userId == null) {
      throw StateError(
          'Conecte sua conta $serverName para sincronizar playlists.');
    }
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('Informe o nome da playlist.');
    final items = tracks.toList(growable: false);
    if (items.any((track) => track.source != AudioSource.jellyfin)) {
      throw ArgumentError(
          'A playlist sincronizada aceita apenas músicas do servidor.');
    }
    final id = await client.createPlaylist(
      cleanName,
      userId,
      items.map((track) => track.path).toList(growable: false),
    );
    await refreshPlaylists();
    return id;
  }

  MusicServerClient _playlistClient(String playlistId) {
    final client = _client;
    if (client == null || _userId == null) {
      throw StateError('Entre na conta $serverName para editar a playlist.');
    }
    if (!_playlists
        .any((playlist) => playlist['Id']?.toString() == playlistId)) {
      throw StateError('Esta playlist não está disponível na conta atual.');
    }
    return client;
  }

  Future<List<String>> playlistItemIds(String playlistId) =>
      _playlistClient(playlistId).playlistItemIds(playlistId, _userId!);

  Future<void> renamePlaylist(String playlistId, String name) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw ArgumentError('Informe o nome da playlist.');
    await _playlistClient(playlistId)
        .updatePlaylist(playlistId, name: cleanName);
    await refreshPlaylists();
  }

  Future<void> replacePlaylistItems(
      String playlistId, List<String> itemIds) async {
    await _playlistClient(playlistId).updatePlaylist(
      playlistId,
      itemIds: itemIds,
    );
    await refreshPlaylists();
  }

  Future<void> deletePlaylist(String playlistId) async {
    await _playlistClient(playlistId).deletePlaylist(playlistId);
    await refreshPlaylists();
  }

  Future<void> addTracksToPlaylist(
      String playlistId, Iterable<AudioTrack> tracks) async {
    final client = _client;
    final userId = _userId;
    if (client == null || userId == null) {
      throw StateError('Conecte sua conta Jellyfin para editar a playlist.');
    }
    final items = tracks.toList(growable: false);
    if (items.any((track) => track.source != AudioSource.jellyfin)) {
      throw ArgumentError(
          'A playlist sincronizada aceita apenas músicas do servidor.');
    }
    final existing = (await client.playlistItemIds(playlistId, userId)).toSet();
    final additions = items
        .map((track) => track.path)
        .where((id) => !existing.contains(id))
        .toSet()
        .toList(growable: false);
    await client.addPlaylistItems(playlistId, userId, additions);
    await refreshPlaylists();
  }

  Future<void> toggleFavorite(AudioTrack track) async {
    final client = _client;
    final userId = _userId;
    if (client == null || userId == null) return;
    final next = !_favoriteIds.contains(track.id);
    await client.setFavorite(track.path, userId, next);
    if (next) {
      _favoriteIds.add(track.id);
    } else {
      _favoriteIds.remove(track.id);
    }
    notifyListeners();
  }

  Future<Uri> streamUrl(AudioTrack track) async {
    if (track.source != AudioSource.jellyfin || !connected) {
      throw StateError('Jellyfin desconectado.');
    }
    final saved = _offline.entry(track.path);
    if (saved != null) {
      final file = _offline.audioFile(saved);
      if (await file.exists()) return file.uri;
    }
    await _ensureProxy();
    return Uri.parse(
        'http://127.0.0.1:${_proxy!.port}/$_proxyNonce/audio/${track.path}');
  }

  Future<PulseLyrics?> lyricsFor(AudioTrack track) async {
    if (track.source != AudioSource.jellyfin) return null;
    final saved = _offline.entry(track.path);
    if (saved != null) {
      final lyrics = _offline.lyricsFile(saved);
      if (lyrics != null && await lyrics.exists()) {
        try {
          final parsed = PulseLyrics.fromText(await lyrics.readAsString());
          if (parsed != null) return parsed;
        } on Object {
          // Fall back to embedded or server lyrics if this file was damaged.
        }
      }
      final file = _offline.audioFile(saved);
      if (await file.exists()) {
        final embedded = await EmbeddedLyricsReader.fromFile(file);
        if (embedded != null) return embedded;
      }
    }
    final client = _client;
    if (client == null) return null;
    try {
      final result = await client.request('GET', 'Audio/${track.path}/Lyrics');
      final parsed = _lyricsFromJellyfin(result);
      if (parsed != null) return parsed;
    } on Object {
      // Older Jellyfin servers can return 404 when no sidecar lyrics exist.
    }
    try {
      final response = await client.openAudio(
          track.path, 'bytes=0-${EmbeddedLyricsReader.maxTagBytes - 1}',
          userId: _userId);
      final buffer = BytesBuilder(copy: false);
      int? needed;
      await for (final chunk in response) {
        buffer.add(chunk);
        if (buffer.length >= 10 && needed == null) {
          needed = EmbeddedLyricsReader.tagLength(buffer.toBytes());
          if (needed == null) break;
        }
        if (needed != null && buffer.length >= needed) break;
        if (buffer.length >= EmbeddedLyricsReader.maxTagBytes) break;
      }
      return EmbeddedLyricsReader.fromBytes(buffer.toBytes());
    } on Object {
      return null;
    }
  }

  PulseLyrics? _lyricsFromJellyfin(dynamic value) {
    if (value is! Map) return null;
    final tracks = value['Tracks'];
    if (tracks is List) {
      for (final item in tracks) {
        final parsed = _lyricsFromJellyfin(item);
        if (parsed != null) return parsed;
      }
    }
    final raw = value['Lyrics'];
    if (raw is! List) return null;
    final lines = <PulseLyricLine>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final text = item['Text']?.toString().trim() ?? '';
      if (text.isEmpty) continue;
      final ticks = item['Start'];
      final start =
          ticks is num ? Duration(microseconds: (ticks / 10).round()) : null;
      lines.add(PulseLyricLine(text, start));
    }
    if (lines.isEmpty) return null;
    if (lines.every((line) => line.start != null)) {
      lines.sort((a, b) => a.start!.compareTo(b.start!));
    }
    return PulseLyrics(lines);
  }

  Future<void> _openOfflineLibrary() async {
    final account = accountFingerprint;
    if (account == null) return;
    await _offline.open(account,
        idPrefix: _serverKind == MusicServerKind.navidrome
            ? 'navidrome'
            : 'jellyfin');
    _tracks = _offline.entries.map(_offline.asTrack).toList(growable: false);
  }

  List<AudioTrack> _combineCatalogTracks(List<AudioTrack> catalog) {
    final online = [
      for (final track in catalog)
        AudioTrack(
          id: track.id,
          path: track.path,
          title: track.title,
          artist: track.artist,
          album: track.album,
          genre: track.genre,
          sizeBytes: 0,
          modifiedAtMillis: 0,
          durationMillis: track.durationMillis,
          source: AudioSource.jellyfin,
          artworkUrl: _artworkForTrack(track),
        ),
    ];
    final onlineIds = online.map((track) => track.path).toSet();
    return [
      ...online,
      for (final saved in _offline.entries)
        if (!onlineIds.contains(saved.itemId)) _offline.asTrack(saved),
    ];
  }

  String? _proxiedArtwork(String? imageId) => imageId == null || _proxy == null
      ? null
      : 'http://127.0.0.1:${_proxy!.port}/$_proxyNonce/image/$imageId';

  String? _artworkForTrack(AudioTrack track) {
    final saved = _offline.entry(track.path);
    return (saved == null ? null : _offline.asTrack(saved).artworkUrl) ??
        _proxiedArtwork(track.artworkUrl);
  }

  Future<File?> _catalogFile() async {
    final account = accountFingerprint;
    if (!(Platform.isAndroid || Platform.isWindows) || account == null) {
      return null;
    }
    final root = await pulseAppDataDirectory();
    final directory = Directory('${root.path}${Platform.pathSeparator}catalog');
    await directory.create(recursive: true);
    return File('${directory.path}${Platform.pathSeparator}$account.json');
  }

  Future<DateTime?> _loadCachedCatalog() async {
    try {
      final file = await _catalogFile();
      if (file == null || !await file.exists()) return null;
      final data = await compute(_decodeCatalogJson, await file.readAsString());
      if (data['version'] != 1) return null;
      final catalog = (data['tracks'] as List)
          .map((item) =>
              AudioTrack.fromJson(Map<String, Object?>.from(item as Map)))
          .where((track) => track.source == AudioSource.jellyfin)
          .toList(growable: false);
      await _ensureProxy();
      _tracks = _combineCatalogTracks(catalog);
      _artists = (data['artists'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);
      _playlists = (data['playlists'] as List)
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList(growable: false);
      _favoriteIds
        ..clear()
        ..addAll((data['favorites'] as List).map((item) => item.toString()));
      _profileImageTag = data['profileImageTag'] as String?;
      _newTrackIds
        ..clear()
        ..addAll(
            (data['newTrackIds'] as List? ?? const []).whereType<String>());
      _catalogUpdatedAt =
          DateTime.fromMillisecondsSinceEpoch(data['savedAt'] as int);
      _hasCatalogBaseline = true;
      return _catalogUpdatedAt;
    } on Object {
      return null;
    }
  }

  Future<void> _saveCachedCatalog(List<AudioTrack> catalog,
      {bool updateTimestamp = true}) async {
    try {
      final file = await _catalogFile();
      if (file == null) return;
      final temporary = File('${file.path}.tmp');
      final snapshot = {
        'version': 1,
        'savedAt': (updateTimestamp
                ? DateTime.now()
                : _catalogUpdatedAt ?? DateTime.now())
            .millisecondsSinceEpoch,
        'tracks': catalog.map((track) => track.toJson()).toList(),
        'artists': _artists,
        'playlists': _playlists,
        'favorites': _favoriteIds.toList(),
        'newTrackIds': _newTrackIds.toList(),
        'profileImageTag': _profileImageTag,
      };
      await temporary.writeAsString(await compute(_encodeCatalogJson, snapshot),
          flush: true);
      if (Platform.isWindows && await file.exists()) await file.delete();
      await temporary.rename(file.path);
    } on Object {
      // O catálogo em memória continua utilizável se o armazenamento falhar.
    }
  }

  Future<void> markNewTracksSeen() async {
    if (_newTrackIds.isEmpty) return;
    _newTrackIds.clear();
    notifyListeners();
    await _saveCachedCatalog(
        _tracks
            .where((track) => track.source == AudioSource.jellyfin)
            .toList(growable: false),
        updateTimestamp: false);
  }

  Future<void> downloadTrack(AudioTrack track) async {
    final client = _client;
    final userId = _userId;
    if (track.source != AudioSource.jellyfin ||
        client == null ||
        userId == null) {
      throw StateError('Entre no Jellyfin para baixar esta faixa.');
    }
    if (isDownloaded(track) || !_downloadingIds.add(track.path)) return;
    notifyListeners();
    File? temporary;
    File? completedFile;
    File? artFile;
    File? artTemporary;
    File? lyricsFile;
    File? lyricsTemporary;
    bool committed = false;
    try {
      final response = await client.openDownload(track.path, userId: userId);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        throw StateError('O Jellyfin não enviou a faixa completa.');
      }
      final mime = response.headers.contentType?.mimeType.toLowerCase();
      final extension = switch (mime) {
        'audio/mpeg' || 'audio/mp3' => '.mp3',
        'audio/mp4' || 'audio/m4a' || 'audio/x-m4a' => '.m4a',
        'audio/aac' || 'audio/aacp' => '.aac',
        'audio/flac' || 'audio/x-flac' => '.flac',
        'audio/ogg' || 'application/ogg' => '.ogg',
        'audio/wav' || 'audio/x-wav' => '.wav',
        'audio/opus' => '.opus',
        'application/octet-stream' => '.bin',
        _ => throw StateError('Formato de áudio não suportado para download.'),
      };
      final file = _offline.target(track.path, extension);
      temporary = File('${file.path}.part');
      await response.pipe(temporary.openWrite());
      final downloadedBytes = await temporary.length();
      if (downloadedBytes == 0 ||
          response.contentLength >= 0 &&
              downloadedBytes != response.contentLength) {
        throw StateError('O download da faixa ficou incompleto.');
      }
      if (await file.exists()) await file.delete();
      await temporary.rename(file.path);
      temporary = null;
      completedFile = file;

      final imageId =
          Uri.tryParse(track.artworkUrl ?? '')?.pathSegments.lastOrNull;
      if (imageId != null && imageId.isNotEmpty) {
        try {
          final image = await client.openImage(imageId);
          if (image.statusCode == HttpStatus.ok &&
              image.headers.contentType?.mimeType.startsWith('image/') ==
                  true) {
            final target = _offline.target(track.path, '.jpg');
            artTemporary = File('${target.path}.part');
            await image.pipe(artTemporary.openWrite());
            if (await artTemporary.length() > 0) {
              if (await target.exists()) await target.delete();
              await artTemporary.rename(target.path);
              artTemporary = null;
              artFile = target;
            } else {
              await artTemporary.delete();
              artTemporary = null;
            }
          } else {
            await image.drain<void>();
          }
        } on Object {
          // Cover art is optional; keep the completed audio download.
        }
      }
      try {
        PulseLyrics? embedded;
        try {
          embedded = await EmbeddedLyricsReader.fromFile(completedFile);
        } on Object {
          // An unsupported tag format can still have lyrics on the server.
        }
        if (embedded == null) {
          final lyrics = await lyricsFor(track);
          if (lyrics != null) {
            final target = _offline.target(track.path, '.lrc');
            lyricsTemporary = File('${target.path}.part');
            await lyricsTemporary.writeAsString(_lyricsText(lyrics),
                flush: true);
            if (await target.exists()) await target.delete();
            await lyricsTemporary.rename(target.path);
            lyricsTemporary = null;
            lyricsFile = target;
          }
        }
      } on Object {
        // A failed lyric lookup must not discard downloaded audio.
      }
      final saved = JellyfinOfflineEntry(
        itemId: track.path,
        fileName: file.uri.pathSegments.last,
        title: track.title,
        artist: track.artist,
        album: track.album,
        durationMillis: track.durationMillis,
        artworkFileName: artFile?.uri.pathSegments.last,
        lyricsFileName: lyricsFile?.uri.pathSegments.last,
      );
      await _offline.put(saved);
      committed = true;
      final offlineTrack = _offline.asTrack(saved);
      _tracks = [
        for (final item in _tracks)
          if (item.path == track.path)
            AudioTrack(
              id: offlineTrack.id,
              path: offlineTrack.path,
              title: offlineTrack.title,
              artist: offlineTrack.artist,
              album: offlineTrack.album,
              genre: item.genre,
              sizeBytes: offlineTrack.sizeBytes,
              modifiedAtMillis: offlineTrack.modifiedAtMillis,
              durationMillis: offlineTrack.durationMillis,
              source: offlineTrack.source,
              artworkUrl: offlineTrack.artworkUrl,
            )
          else
            item,
      ];
    } finally {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
      if (artTemporary != null && await artTemporary.exists()) {
        await artTemporary.delete();
      }
      if (lyricsTemporary != null && await lyricsTemporary.exists()) {
        await lyricsTemporary.delete();
      }
      if (!committed) {
        if (completedFile != null && await completedFile.exists()) {
          await completedFile.delete();
        }
        if (artFile != null && await artFile.exists()) await artFile.delete();
        if (lyricsFile != null && await lyricsFile.exists()) {
          await lyricsFile.delete();
        }
      }
      _downloadingIds.remove(track.path);
      notifyListeners();
    }
  }

  String _lyricsText(PulseLyrics lyrics) => lyrics.lines.map((line) {
        final start = line.start;
        if (start == null) return line.text;
        final minutes = start.inMinutes.toString().padLeft(2, '0');
        final seconds = (start.inSeconds % 60).toString().padLeft(2, '0');
        final millis = (start.inMilliseconds % 1000).toString().padLeft(3, '0');
        return '[$minutes:$seconds.$millis]${line.text}';
      }).join('\n');

  Future<void> removeDownload(AudioTrack track) async {
    if (!isDownloaded(track)) return;
    await _offline.remove(track.path);
    _tracks = [
      for (final item in _tracks)
        if (item.path == track.path)
          AudioTrack(
            id: item.id,
            path: item.path,
            title: item.title,
            artist: item.artist,
            album: item.album,
            genre: item.genre,
            sizeBytes: 0,
            modifiedAtMillis: 0,
            durationMillis: item.durationMillis,
            source: AudioSource.jellyfin,
          )
        else
          item,
    ];
    notifyListeners();
  }

  Future<File> prepareTrackForSharing(AudioTrack track) async {
    final saved = _offline.entry(track.path);
    if (saved != null) {
      final file = _offline.audioFile(saved);
      if (await file.exists()) return file;
    }
    final client = _client;
    final userId = _userId;
    if (track.source != AudioSource.jellyfin ||
        client == null ||
        userId == null) {
      throw StateError('A faixa do Jellyfin não está disponível.');
    }

    final response = await client.openDownload(track.path, userId: userId);
    final mimeType = response.headers.contentType?.mimeType.toLowerCase();
    final extension = switch (mimeType) {
      'audio/mpeg' || 'audio/mp3' => '.mp3',
      'audio/mp4' || 'audio/m4a' || 'audio/x-m4a' => '.m4a',
      'audio/aac' || 'audio/aacp' => '.aac',
      'audio/flac' || 'audio/x-flac' => '.flac',
      'audio/ogg' || 'application/ogg' => '.ogg',
      'audio/wav' || 'audio/x-wav' => '.wav',
      'audio/opus' => '.opus',
      _ => '.audio',
    };
    final directory = Directory('${Directory.systemTemp.path}\\Pulse\\Share');
    await directory.create(recursive: true);
    final safeTitle =
        track.title.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
    final file = File(
      '${directory.path}\\${safeTitle.isEmpty ? 'faixa' : safeTitle}_'
      '${DateTime.now().microsecondsSinceEpoch}$extension',
    );
    try {
      await response.pipe(file.openWrite());
      return file;
    } on Object {
      if (await file.exists()) await file.delete();
      rethrow;
    }
  }

  Future<void> _ensureProxy() async {
    if (_proxy != null) return;
    _proxy = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final random = Random.secure();
    _proxyNonce =
        List.generate(24, (_) => random.nextInt(16).toRadixString(16)).join();
    _proxy!.listen(_serveAudio);
  }

  Future<void> _serveAudio(HttpRequest incoming) async {
    final parts = incoming.uri.pathSegments;
    if ((incoming.method != 'GET' && incoming.method != 'HEAD') ||
        parts.length != 3 ||
        parts.first != _proxyNonce ||
        !(parts[1] == 'user-image' &&
                parts.last == _userId &&
                _profileImageTag != null ||
            parts[1] == 'audio' &&
                _tracks.any((track) => track.path == parts.last) ||
            parts[1] == 'image' &&
                _tracks.any((track) =>
                    track.artworkUrl?.endsWith('/${parts.last}') == true))) {
      incoming.response.statusCode = HttpStatus.notFound;
      await incoming.response.close();
      return;
    }
    try {
      final upstream = parts[1] == 'user-image'
          ? await _client!.openUserImage(parts.last)
          : parts[1] == 'image'
              ? await _client!.openImage(parts.last)
              : await _client!.openAudio(
                  parts.last,
                  incoming.headers.value(HttpHeaders.rangeHeader),
                  method: incoming.method,
                  userId: _userId!,
                );
      debugPrint('Jellyfin audio proxy: HTTP ${upstream.statusCode}, '
          'type=${upstream.headers.contentType}, '
          'length=${upstream.contentLength}');
      if (parts[1] == 'audio') _streamError = null;
      incoming.response.statusCode = upstream.statusCode;
      for (final header in [
        HttpHeaders.contentTypeHeader,
        HttpHeaders.contentLengthHeader,
        HttpHeaders.contentRangeHeader,
        HttpHeaders.acceptRangesHeader,
      ]) {
        final value = upstream.headers.value(header);
        if (value != null) incoming.response.headers.set(header, value);
      }
      if (incoming.method == 'HEAD') {
        await upstream.drain<void>();
      } else {
        await incoming.response.addStream(upstream);
      }
    } on Object catch (error) {
      debugPrint('Jellyfin audio proxy failed: $error');
      if (parts.length == 3 && parts[1] == 'audio') {
        _streamError = error.toString();
        notifyListeners();
      }
      incoming.response.statusCode = HttpStatus.badGateway;
    } finally {
      await incoming.response.close();
    }
  }

  Future<void> disconnect({bool keepSavedSession = false}) async {
    _newTrackIds.clear();
    _catalogUpdatedAt = null;
    _hasCatalogBaseline = false;
    if (!keepSavedSession) {
      await (_serverKind == MusicServerKind.navidrome
              ? _navidromeStorage
              : _storage)
          .delete();
    }
    await _activeProviderStorage.write('none');
    _client?.close();
    _lastConnectionWarmup = null;
    _client = null;
    _userId = null;
    RemoteArtworkCache.instance.setAccount(null);
    _username = null;
    _profileImageTag = null;
    _sessionExpired = false;
    _tracks = const [];
    _artists = const [];
    _playlists = const [];
    _favoriteIds.clear();
    _tracks = const [];
    await _proxy?.close(force: true);
    _proxy = null;
    _proxyNonce = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _client?.close();
    unawaited(_proxy?.close(force: true));
    super.dispose();
  }
}

Map<String, dynamic> _decodeCatalogJson(String contents) =>
    Map<String, dynamic>.from(jsonDecode(contents) as Map);

String _encodeCatalogJson(Map<String, Object?> contents) =>
    jsonEncode(contents);
