import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_flutter/data/jellyfin_client.dart';
import 'package:pulse_flutter/data/windows_secure_session_store.dart';
import 'package:pulse_flutter/domain/audio_track.dart';

void main() {
  test('server entry requires HTTPS and excludes URL credentials', () {
    expect(JellyfinClient.validateServer('https://media.example.test').host,
        'media.example.test');
    expect(() => JellyfinClient.validateServer('http://media.example.test'),
        throwsFormatException);
    expect(
        () => JellyfinClient.validateServer('https://u:p@media.example.test'),
        throwsFormatException);
  });

  test('authentication, catalog, favorites and audio use headers', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final observed = <String>[];
    server.listen((request) async {
      observed.add('${request.method} ${request.uri}');
      expect(request.uri.queryParameters.containsKey('api_key'), isFalse);
      expect(request.uri.queryParameters.containsKey('token'), isFalse);
      expect(request.headers.value(HttpHeaders.authorizationHeader),
          startsWith('MediaBrowser '));
      if (request.uri.path == '/Users/AuthenticateByName') {
        final body = jsonDecode(await utf8.decoder.bind(request).join()) as Map;
        expect(body, {'Username': 'alice', 'Pw': 'example-password'});
        request.response.write(jsonEncode({
          'AccessToken': 'example-token',
          'User': {'Id': 'user-1', 'Name': 'alice'}
        }));
      } else if (request.uri.path == '/Items' &&
          request.uri.queryParameters['IncludeItemTypes'] == 'Audio') {
        expect(request.headers.value(HttpHeaders.authorizationHeader),
            contains('Token="example-token"'));
        request.response.write(jsonEncode({
          'Items': [
            {
              'Id': 'song-1',
              'Name': 'Song',
              'Artists': ['Artist'],
              'Album': 'Album',
              'UserData': {'IsFavorite': true}
            }
          ]
        }));
      } else if (request.uri.path == '/Audio/song-1/universal') {
        expect(request.headers.value(HttpHeaders.rangeHeader), 'bytes=0-3');
        request.response.statusCode = HttpStatus.partialContent;
        request.response.add([1, 2, 3, 4]);
      } else {
        request.response.statusCode = HttpStatus.noContent;
      }
      await request.response.close();
    });
    final client =
        JellyfinClient(baseUri: Uri.parse('http://127.0.0.1:${server.port}'));
    try {
      final auth = await client.authenticate('alice', 'example-password');
      client.token = auth['AccessToken'] as String;
      final tracks = await client.audioItems('user-1');
      expect(tracks.single.source, AudioSource.jellyfin);
      expect(tracks.single.id, 'jellyfin:song-1');
      expect(client.favoriteIds, contains('jellyfin:song-1'));
      await client.setFavorite('song-1', 'user-1', false);
      final audio = await client.openAudio('song-1', 'bytes=0-3');
      expect(
          await audio
              .fold<List<int>>([], (bytes, chunk) => bytes..addAll(chunk)),
          [1, 2, 3, 4]);
      expect(
          observed, contains('DELETE /UserFavoriteItems/song-1?userId=user-1'));
    } finally {
      client.close();
      await server.close(force: true);
    }
  });

  test('Windows session file is DPAPI encrypted and can be removed', () async {
    if (!Platform.isWindows) return;
    final directory =
        await Directory.systemTemp.createTemp('pulse-dpapi-test-');
    final store = WindowsSecureSessionStore(storageDirectory: directory);
    try {
      await store.write('{"token":"super-secret"}');
      final file = File(
          '${directory.path}${Platform.pathSeparator}jellyfin-session.dpapi');
      expect(await file.exists(), isTrue);
      expect(await file.readAsString(encoding: latin1),
          isNot(contains('super-secret')));
      expect(await store.read(), '{"token":"super-secret"}');
      await store.delete();
      expect(await store.read(), isNull);
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
