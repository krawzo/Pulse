import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_flutter/data/navidrome_client.dart';

void main() {
  test('saved play queue keeps the current song and millisecond position',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final queues = <String, Map<String, dynamic>>{};
    server.listen((request) async {
      final user = request.uri.queryParameters['u']!;
      if (request.uri.path == '/rest/savePlayQueue.view') {
        queues[user] = {
          'entry': request.uri.queryParametersAll['id']!
              .map((id) => {'id': id})
              .toList(),
          'current': request.uri.queryParameters['current'],
          'position': int.parse(request.uri.queryParameters['position']!),
        };
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'subsonic-response': {
          'status': 'ok',
          if (request.uri.path == '/rest/getPlayQueue.view')
            'playQueue': queues[user],
        }
      }));
      await request.response.close();
    });
    final baseUri = Uri.parse('http://127.0.0.1:${server.port}');
    final pc = NavidromeClient(
        baseUri: baseUri, username: 'alice', password: 'password');
    final phone = NavidromeClient(
        baseUri: baseUri, username: 'alice', password: 'password');
    final other = NavidromeClient(
        baseUri: baseUri, username: 'bob', password: 'password');
    try {
      await pc.savePlayQueue(['song-1', 'song-2'], 'song-2', 74231);
      final resumed = await phone.getPlayQueue();
      expect(resumed?.ids, ['song-1', 'song-2']);
      expect(resumed?.current, 'song-2');
      expect(resumed?.positionMillis, 74231);
      expect(await other.getPlayQueue(), isNull);
    } finally {
      pc.close();
      phone.close();
      other.close();
      await server.close(force: true);
    }
  });

  test('audio probe uses HEAD without downloading the track', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final methods = <String>[];
    server.listen((request) async {
      methods.add(request.method);
      expect(request.uri.path, '/rest/stream.view');
      expect(request.uri.queryParameters['id'], 'song-1');
      request.response.headers.contentType = ContentType('audio', 'mpeg');
      request.response.headers.contentLength = 4096;
      await request.response.close();
    });
    final client = NavidromeClient(
      baseUri: Uri.parse('http://127.0.0.1:${server.port}'),
      username: 'alice',
      password: 'example-password',
    );
    try {
      final response = await client.openAudio('song-1', null, method: 'HEAD');
      await response.drain<void>();
      expect(response.statusCode, HttpStatus.ok);
      expect(methods, ['HEAD']);
    } finally {
      client.close();
      await server.close(force: true);
    }
  });
}
