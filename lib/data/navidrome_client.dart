import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../domain/audio_track.dart';
import 'jellyfin_client.dart';
import 'music_server_client.dart';

/// Native OpenSubsonic adapter. Keeps Navidrome's protocol out of the player UI.
/// Credentials stay in secure storage; media URLs are exposed only by Pulse's
/// loopback proxy. OpenSubsonic requires auth parameters on upstream URLs.
class NavidromeClient implements MusicServerClient {
  NavidromeClient(
      {required this.baseUri,
      required this.username,
      String? password,
      HttpClient? httpClient})
      : token = password,
        _http = httpClient ?? HttpClient();

  final Uri baseUri;
  final String username;
  final HttpClient _http;
  @override
  String? token;
  @override
  final Set<String> favoriteIds = {};
  final Map<String, (String, String)> _songNames = {};
  final Random _random = Random.secure();
  bool _supportsFormPost = false;
  bool _checkedExtensions = false;

  Future<void> _detectExtensions() async {
    if (_checkedExtensions) return;
    _checkedExtensions = true;
    try {
      final extensions = await _json('getOpenSubsonicExtensions');
      final entries = (extensions['openSubsonicExtensions']
              as Map?)?['openSubsonicExtension'] as List? ??
          const [];
      _supportsFormPost = entries
          .whereType<Map>()
          .any((extension) => extension['name'] == 'formPost');
    } on Object {
      // Standard GET requests remain available on older servers.
    }
  }

  static Uri validateServer(String input) {
    final uri = JellyfinClient.validateServer(input);
    if (uri.pathSegments.contains('jellyfin') ||
        uri.pathSegments.contains('rest')) {
      throw const FormatException('Informe a raiz HTTPS do Navidrome.');
    }
    return uri;
  }

  Uri _endpoint(String action, Map<String, List<String>> params) {
    final password = token;
    if (password == null || password.isEmpty || username.trim().isEmpty) {
      throw StateError('Conta Navidrome não autenticada.');
    }
    final salt =
        List.generate(16, (_) => _random.nextInt(16).toRadixString(16)).join();
    final digest = md5.convert(utf8.encode('$password$salt')).toString();
    return baseUri.replace(
      path: '${baseUri.path}/rest/$action.view'.replaceAll(RegExp(r'//+'), '/'),
      queryParameters: {
        'u': [username.trim()],
        't': [digest],
        's': [salt],
        'v': ['1.16.1'],
        'c': ['Pulse'],
        'f': ['json'],
        ...params,
      },
    );
  }

  Future<Map<String, dynamic>> _json(String action,
      [Map<String, List<String>> params = const {}]) async {
    final uri = _endpoint(action, params);
    final request = _supportsFormPost
        ? await _http.postUrl(uri.replace(query: null))
        : await _http.getUrl(uri);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (_supportsFormPost) {
      request.headers.contentType =
          ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
      request.write(uri.query);
    }
    final response = await request.close();
    final content = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw JellyfinException(response.statusCode);
    }
    final wrapper = (jsonDecode(content) as Map)['subsonic-response'];
    if (wrapper is! Map) {
      throw const FormatException('Resposta Navidrome inválida.');
    }
    if (wrapper['status'] != 'ok') {
      final error = wrapper['error'] as Map?;
      final code = (error?['code'] as num?)?.toInt();
      throw JellyfinException(code == 40 || code == 41 ? 401 : 500);
    }
    return Map<String, dynamic>.from(wrapper);
  }

  Future<HttpClientResponse> _media(String action, String id,
      {String? range, String method = 'GET'}) async {
    final request = await _http.openUrl(
        method,
        _endpoint(action, {
          'id': [id]
        }));
    if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
    final response = await request.close();
    if (response.statusCode >= 400) {
      await response.drain<void>();
      throw JellyfinException(response.statusCode);
    }
    return response;
  }

  @override
  Future<Map<String, dynamic>> authenticate(
      String user, String password) async {
    token = password;
    await _json('ping');
    await _detectExtensions();
    final result = await _json('getUser', {
      'username': [username]
    });
    final account = result['user'] as Map?;
    final name = account?['username']?.toString() ?? user.trim();
    return {
      'AccessToken': password,
      'User': {'Id': name, 'Name': name},
    };
  }

  @override
  Future<Map<String, dynamic>> currentUser() async {
    await _detectExtensions();
    final result = await _json('getUser', {
      'username': [username]
    });
    final user = result['user'] as Map?;
    return {'Id': username, 'Name': user?['username'] ?? username};
  }

  @override
  Future<List<AudioTrack>> audioItems(String userId) async {
    final albums = <Map<String, dynamic>>[];
    for (var offset = 0;; offset += 500) {
      final result = await _json('getAlbumList2', {
        'type': ['alphabeticalByName'],
        'size': ['500'],
        'offset': ['$offset'],
      });
      final page =
          ((result['albumList2'] as Map?)?['album'] as List? ?? const [])
              .whereType<Map>()
              .map((album) => Map<String, dynamic>.from(album))
              .toList();
      albums.addAll(page);
      if (page.length < 500) break;
    }
    final songs = <Map<String, dynamic>>[];
    // Bound concurrent album requests for large collections and small servers.
    for (var offset = 0; offset < albums.length; offset += 8) {
      final chunk = albums.skip(offset).take(8);
      final results = await Future.wait(chunk.map((album) => _json('getAlbum', {
            'id': [album['id'].toString()]
          })));
      for (final result in results) {
        songs.addAll(((result['album'] as Map?)?['song'] as List? ?? const [])
            .whereType<Map>()
            .map((song) => Map<String, dynamic>.from(song)));
      }
    }
    favoriteIds.clear();
    _songNames.clear();
    return [
      for (final song in songs)
        if (song['id']?.toString().isNotEmpty == true) _asTrack(song),
    ];
  }

  AudioTrack _asTrack(Map<String, dynamic> song) {
    final id = song['id'].toString();
    final title = song['title']?.toString() ?? 'Faixa sem título';
    final artist = song['artist']?.toString();
    _songNames[id] = (artist ?? '', title);
    if (song['starred'] != null) favoriteIds.add('navidrome:$id');
    return AudioTrack(
      id: 'navidrome:$id',
      path: id,
      title: title,
      artist: artist,
      album: song['album']?.toString(),
      genre: song['genre']?.toString(),
      sizeBytes: 0,
      modifiedAtMillis: 0,
      durationMillis: ((song['duration'] as num?)?.toInt() ?? 0) * 1000,
      source: AudioSource.jellyfin,
      artworkUrl: song['coverArt']?.toString(),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> artists(String userId) async {
    final result = await _json('getArtists');
    final indexes = (result['artists'] as Map?)?['index'] as List? ?? const [];
    return [
      for (final index in indexes.whereType<Map>())
        for (final artist
            in (index['artist'] as List? ?? const []).whereType<Map>())
          {'Id': artist['id'], 'Name': artist['name']},
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> playlists(String userId) async {
    final result = await _json('getPlaylists');
    return [
      for (final item
          in ((result['playlists'] as Map?)?['playlist'] as List? ?? const [])
              .whereType<Map>())
        {'Id': item['id'], 'Name': item['name']},
    ];
  }

  @override
  Future<List<String>> playlistItemIds(String playlistId, String userId) async {
    final result = await _json('getPlaylist', {
      'id': [playlistId]
    });
    return ((result['playlist'] as Map?)?['entry'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => item['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<String> createPlaylist(
      String name, String userId, List<String> itemIds) async {
    final result = await _json('createPlaylist', {
      'name': [name],
      if (itemIds.isNotEmpty) 'songId': itemIds,
    });
    final id = (result['playlist'] as Map?)?['id']?.toString();
    if (id == null || id.isEmpty) {
      throw const FormatException('O Navidrome não confirmou a playlist.');
    }
    return id;
  }

  @override
  Future<void> addPlaylistItems(
      String playlistId, String userId, List<String> itemIds) async {
    for (var index = 0; index < itemIds.length; index += 50) {
      await _json('updatePlaylist', {
        'playlistId': [playlistId],
        'songIdToAdd': itemIds.skip(index).take(50).toList(),
      });
    }
  }

  @override
  Future<void> updatePlaylist(String playlistId,
      {String? name, List<String>? itemIds}) async {
    if (name != null) {
      await _json('updatePlaylist', {
        'playlistId': [playlistId],
        'name': [name]
      });
    }
    if (itemIds != null) {
      final previous = await playlistItemIds(playlistId, username);
      // Subsonic has indexed removals and appends, but no atomic replace.
      // Remove from the end so index shifts cannot delete the wrong song.
      for (var index = previous.length - 1; index >= 0; index--) {
        await _json('updatePlaylist', {
          'playlistId': [playlistId],
          'songIndexToRemove': ['$index'],
        });
      }
      await addPlaylistItems(playlistId, username, itemIds);
    }
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {
    await _json('deletePlaylist', {
      'id': [playlistId]
    });
  }

  @override
  Future<void> setFavorite(String itemId, String userId, bool favorite) async {
    await _json(favorite ? 'star' : 'unstar', {
      'id': [itemId]
    });
  }

  Future<void> savePlayQueue(
      List<String> ids, String current, int positionMillis) async {
    if (ids.isEmpty || !ids.contains(current)) return;
    await _json('savePlayQueue', {
      'id': ids,
      'current': [current],
      'position': ['${max(0, positionMillis)}'],
    });
  }

  Future<({List<String> ids, String current, int positionMillis})?>
      getPlayQueue() async {
    final result = await _json('getPlayQueue');
    final queue = result['playQueue'] as Map?;
    if (queue == null) return null;
    final ids = ((queue['entry'] as List?) ?? const [])
        .whereType<Map>()
        .map((entry) => entry['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    final current = queue['current']?.toString() ?? '';
    if (ids.isEmpty || !ids.contains(current)) return null;
    return (
      ids: ids,
      current: current,
      positionMillis: (queue['position'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<dynamic> request(String method, String path,
      {Map<String, String>? query, Object? body}) async {
    final lyricMatch = RegExp(r'^Audio/([^/]+)/Lyrics$').firstMatch(path);
    if (lyricMatch == null) {
      throw UnsupportedError('Rota Jellyfin indisponível no Navidrome.');
    }
    final id = lyricMatch.group(1)!;
    try {
      final result = await _json('getLyricsBySongId', {
        'id': [id]
      });
      final tracks =
          ((result['lyricsList'] as Map?)?['structuredLyrics'] as List? ??
                  const [])
              .whereType<Map>();
      final selected =
          tracks.where((item) => item['synced'] == true).firstOrNull ??
              tracks.firstOrNull;
      if (selected != null) {
        return {
          'Lyrics': [
            for (final line
                in (selected['line'] as List? ?? const []).whereType<Map>())
              {
                'Text': line['value'],
                if (line['start'] is num)
                  'Start': (line['start'] as num).toInt() * 10000
              },
          ]
        };
      }
    } on Object {
      // Older Navidrome builds may lack the OpenSubsonic songLyrics extension.
    }
    final names = _songNames[id];
    if (names == null) return null;
    final result = await _json('getLyrics', {
      'artist': [names.$1],
      'title': [names.$2],
    });
    final raw = (result['lyrics'] as Map?)?['value']?.toString();
    if (raw == null || raw.trim().isEmpty) return null;
    return {
      'Lyrics': [
        for (final line in const LineSplitter().convert(raw))
          if (line.trim().isNotEmpty) {'Text': line}
      ]
    };
  }

  @override
  Future<HttpClientResponse> openAudio(String itemId, String? range,
          {String? userId, String method = 'GET'}) =>
      _media('stream', itemId, range: range, method: method);

  @override
  Future<HttpClientResponse> openDownload(String itemId, {String? userId}) =>
      _media('download', itemId);

  @override
  Future<HttpClientResponse> openImage(String itemId) =>
      _media('getCoverArt', itemId);

  @override
  Future<HttpClientResponse> openUserImage(String userId) =>
      _media('getAvatar', username);

  @override
  Future<Map<String, dynamic>> initiateQuickConnect() =>
      throw UnsupportedError('Quick Connect não pertence à API OpenSubsonic.');

  @override
  Future<bool> quickConnectAuthorized(String secret) =>
      throw UnsupportedError('Quick Connect não pertence à API OpenSubsonic.');

  @override
  Future<Map<String, dynamic>> authenticateQuickConnect(String secret) =>
      throw UnsupportedError('Quick Connect não pertence à API OpenSubsonic.');

  @override
  void close() => _http.close(force: true);
}
