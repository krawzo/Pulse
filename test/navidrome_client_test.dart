import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_flutter/data/navidrome_client.dart';

void main() {
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
