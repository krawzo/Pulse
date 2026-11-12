import 'dart:convert';
import 'dart:io';

import '../domain/audio_track.dart';
import 'music_server_client.dart';

/// Small, authenticated Jellyfin API client. Secrets are never placed in URLs.
class JellyfinClient implements MusicServerClient {
  JellyfinClient({required this.baseUri, this.token, HttpClient? httpClient})
      : _http = httpClient ?? HttpClient();

  final Uri baseUri;
  final HttpClient _http;
  @override
  String? token;
  @override
  final Set<String> favoriteIds = {};

  static Uri validateServer(String input) {
    final uri = Uri.tryParse(input.trim());
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      throw const FormatException(
          'Informe um endereço HTTPS válido do Jellyfin.');
    }
    return uri.replace(path: uri.path.replaceAll(RegExp(r'/$'), ''));
  }

  Uri endpoint(String path, [Map<String, String>? query]) => baseUri.replace(
        path: '${baseUri.path}/$path'.replaceAll(RegExp(r'//+'), '/'),
        queryParameters: query,
      );

  String get _authorization {
    final isAndroid = Platform.isAndroid;
    final attributes = <String>[
      'Client="Pulse"',
      'Device="${isAndroid ? 'Android' : 'Windows'}"',
      'DeviceId="pulse-flutter-${isAndroid ? 'android' : 'windows'}"',
      'Version="0.2.0"',
      if (token != null) 'Token="$token"',
    ];
    return 'MediaBrowser ${attributes.join(', ')}';
  }

  @override
  Future<dynamic> request(String method, String path,
      {Map<String, String>? query, Object? body}) async {
    final request = await _http.openUrl(method, endpoint(path, query));
    request.headers.set(HttpHeaders.authorizationHeader, _authorization);
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }
    final response = await request.close();
    final content = await utf8.decoder.bind(response).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw JellyfinException(response.statusCode);
    }
    return content.isEmpty ? null : jsonDecode(content);
  }

  @override
  Future<Map<String, dynamic>> authenticate(
      String user, String password) async {
    final result = await request('POST', 'Users/AuthenticateByName',
        body: {'Username': user, 'Pw': password});
    return Map<String, dynamic>.from(result as Map);
  }

  @override
  Future<Map<String, dynamic>> initiateQuickConnect() async {
    final result = await request('POST', 'QuickConnect/Initiate');
    return Map<String, dynamic>.from(result as Map);
  }

  @override
  Future<bool> quickConnectAuthorized(String secret) async {
    final result =
        await request('GET', 'QuickConnect/Connect', query: {'secret': secret});
    return (result as Map)['Authenticated'] == true;
  }

  @override
  Future<Map<String, dynamic>> authenticateQuickConnect(String secret) async {
    final result = await request('POST', 'Users/AuthenticateWithQuickConnect',
        body: {'Secret': secret});
    return Map<String, dynamic>.from(result as Map);
  }

  @override
  Future<List<AudioTrack>> audioItems(String userId) async {
    final items = <dynamic>[];
    const pageSize = 500;
    while (true) {
      final result = await request('GET', 'Items', query: {
        'UserId': userId,
        'Recursive': 'true',
        'IncludeItemTypes': 'Audio',
        'Fields': 'ParentId,Path,PrimaryImageAspectRatio',
        'SortBy': 'SortName',
        'StartIndex': '${items.length}',
        'Limit': '$pageSize',
      });
      final page = (result as Map)['Items'] as List? ?? const [];
      items.addAll(page);
      if (page.length < pageSize ||
          items.length >=
              ((result['TotalRecordCount'] as num?)?.toInt() ?? 1 << 30)) {
        break;
      }
    }
    favoriteIds.clear();
    for (final item in items.whereType<Map>()) {
      if ((item['UserData'] as Map?)?['IsFavorite'] == true) {
        favoriteIds.add('jellyfin:${item['Id']}');
      }
    }
    return items
        .whereType<Map>()
        .map((item) {
          final id = item['Id']?.toString() ?? '';
          return AudioTrack(
            id: 'jellyfin:$id',
            path: id,
            title: item['Name']?.toString() ?? 'Faixa sem título',
            artist: (item['Artists'] as List?)?.firstOrNull?.toString() ??
                item['AlbumArtist']?.toString(),
            album: item['Album']?.toString(),
            genre: (item['Genres'] as List?)?.firstOrNull?.toString(),
            sizeBytes: 0,
            modifiedAtMillis: 0,
            durationMillis: ((item['RunTimeTicks'] as num?)?.toInt() ?? 0) > 0
                ? ((item['RunTimeTicks'] as num).toInt() ~/ 10000)
                : null,
            source: AudioSource.jellyfin,
            // Prefer art attached to the audio item itself. Jellyfin also
            // exposes the album's primary image on every track, so checking
            // AlbumPrimaryImageTag first masks per-track artwork.
            artworkUrl: (item['ImageTags'] as Map?)?['Primary'] != null
                ? id
                : (item['AlbumId'] != null &&
                        item['AlbumPrimaryImageTag'] != null
                    ? item['AlbumId'].toString()
                    : null),
          );
        })
        .where((track) => track.path.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> artists(String userId) async {
    final result = await request('GET', 'Artists', query: {'UserId': userId});
    return ((result as Map)['Items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  @override
  Future<List<Map<String, dynamic>>> playlists(String userId) async {
    final result = await request('GET', 'Items', query: {
      'UserId': userId,
      'Recursive': 'true',
      'IncludeItemTypes': 'Playlist',
    });
    return ((result as Map)['Items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList(growable: false);
  }

  @override
  Future<List<String>> playlistItemIds(String playlistId, String userId) async {
    final result = await request('GET', 'Playlists/$playlistId/Items',
        query: {'UserId': userId});
    return ((result as Map)['Items'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => item['Id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<String> createPlaylist(
      String name, String userId, List<String> itemIds) async {
    final result = await request('POST', 'Playlists', body: {
      'Name': name,
      'UserId': userId,
      'MediaType': 'Audio',
      'IsPublic': false,
      'Ids': itemIds,
    });
    final id = (result as Map?)?['Id']?.toString();
    if (id == null || id.isEmpty) {
      throw const FormatException('O Jellyfin não confirmou a playlist.');
    }
    return id;
  }

  @override
  Future<void> addPlaylistItems(
      String playlistId, String userId, List<String> itemIds) async {
    if (itemIds.isEmpty) return;
    await request('POST', 'Playlists/$playlistId/Items', query: {
      'UserId': userId,
      'Ids': itemIds.join(','),
    });
  }

  @override
  Future<void> updatePlaylist(String playlistId,
      {String? name, List<String>? itemIds}) async {
    await request('POST', 'Playlists/$playlistId', body: {
      if (name != null) 'Name': name,
      if (itemIds != null) 'Ids': itemIds,
    });
  }

  @override
  Future<void> deletePlaylist(String playlistId) async {
    await request('DELETE', 'Items/$playlistId');
  }

  @override
  Future<void> setFavorite(String itemId, String userId, bool favorite) async {
    await request(favorite ? 'POST' : 'DELETE', 'UserFavoriteItems/$itemId',
        query: {'userId': userId});
  }

  @override
  Future<HttpClientResponse> openAudio(String itemId, String? range,
      {String? userId, String method = 'GET'}) async {
    final request = await _http.openUrl(
      method,
      endpoint('Audio/$itemId/stream', {
        if (userId != null) 'UserId': userId,
        'DeviceId': 'pulse-flutter-windows',
        'static': 'true',
      }),
    );
    request.headers.set(HttpHeaders.authorizationHeader, _authorization);
    if (range != null) request.headers.set(HttpHeaders.rangeHeader, range);
    final response = await request.close();
    if (response.statusCode >= 400) {
      await response.drain<void>();
      throw JellyfinException(response.statusCode);
    }
    return response;
  }

  @override
  Future<HttpClientResponse> openDownload(String itemId, {String? userId}) =>
      openAudio(itemId, null, userId: userId);

  @override
  Future<HttpClientResponse> openImage(String itemId) async {
    final request =
        await _http.getUrl(endpoint('Items/$itemId/Images/Primary'));
    request.headers.set(HttpHeaders.authorizationHeader, _authorization);
    return request.close();
  }

  @override
  Future<Map<String, dynamic>> currentUser() async =>
      Map<String, dynamic>.from(await request('GET', 'Users/Me') as Map);

  @override
  Future<HttpClientResponse> openUserImage(String userId) async {
    final request =
        await _http.getUrl(endpoint('Users/$userId/Images/Primary'));
    request.headers.set(HttpHeaders.authorizationHeader, _authorization);
    return request.close();
  }

  @override
  void close() => _http.close(force: true);
}

class JellyfinException implements Exception {
  const JellyfinException(this.statusCode);
  final int statusCode;
  @override
  String toString() => 'Jellyfin respondeu com HTTP $statusCode.';
}
