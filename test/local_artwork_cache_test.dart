import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_flutter/data/local_artwork_cache.dart';

void main() {
  late Directory temporaryDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('pulse-art-');
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('extracts a thumbnail from an embedded front cover', () async {
    final file = File('${temporaryDirectory.path}/cover.mp3');
    await file.writeAsBytes(_id3WithPictures([await _tinyPng()], [3]));
    final stat = await file.stat();

    final thumbnail = await LocalArtworkCache.instance.imageFor(
      file.path,
      stat.size,
      stat.modified.millisecondsSinceEpoch,
    );

    expect(thumbnail, isNotNull);
    expect(thumbnail, isNotEmpty);
  });

  test('returns no artwork for missing or malformed embedded images', () async {
    final withoutCover = File('${temporaryDirectory.path}/empty.mp3');
    await withoutCover.writeAsBytes(_id3WithPictures([], []));
    final corruptCover = File('${temporaryDirectory.path}/corrupt.mp3');
    await corruptCover.writeAsBytes(
      _id3WithPictures([
        Uint8List.fromList([1, 2, 3])
      ], [
        3
      ]),
    );

    for (final file in [withoutCover, corruptCover]) {
      final stat = await file.stat();
      expect(
        await LocalArtworkCache.instance.imageFor(
          file.path,
          stat.size,
          stat.modified.millisecondsSinceEpoch,
        ),
        isNull,
      );
    }
  });

  test('a pending artwork read cannot repopulate the cache after clear',
      () async {
    final file = File('${temporaryDirectory.path}/pending-cover.mp3');
    await file.writeAsBytes(_id3WithPictures([await _tinyPng()], [3]));
    final stat = await file.stat();
    final cache = LocalArtworkCache.instance;
    cache.clear();

    final pending = cache.imageFor(
      file.path,
      stat.size,
      stat.modified.millisecondsSinceEpoch,
    );
    cache.clear();
    expect(await pending, isNotNull);
    expect(cache.cachedEntryCount, 0);
  });

  test('keeps artwork reads bounded by tag size, not audio length', () async {
    final oversizedTag = File('${temporaryDirectory.path}/large-tag.mp3');
    await oversizedTag.writeAsBytes([
      ...ascii.encode('ID3'),
      4,
      0,
      0,
      13,
      0,
      0,
      0,
    ]);
    final longAudio = File('${temporaryDirectory.path}/long-audio.mp3');
    final handle = await longAudio.open(mode: FileMode.write);
    await handle.writeFrom([
      ...ascii.encode('ID3'),
      4,
      0,
      0,
      0,
      0,
      0,
    ]);
    await handle.setPosition(25 * 1024 * 1024);
    await handle.writeByte(0);
    await handle.close();

    final oversizedStat = await oversizedTag.stat();
    expect(
      await LocalArtworkCache.instance.imageFor(
        oversizedTag.path,
        oversizedStat.size,
        oversizedStat.modified.millisecondsSinceEpoch,
      ),
      isNull,
    );
    final longStat = await longAudio.stat();
    expect(longStat.size, greaterThan(24 * 1024 * 1024));
    expect(
      await LocalArtworkCache.instance.imageFor(
        longAudio.path,
        longStat.size,
        longStat.modified.millisecondsSinceEpoch,
      ),
      isNull,
    );
  });
}

Future<Uint8List> _tinyPng() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 2, 2),
    ui.Paint()..color = const ui.Color(0xFFFF0000),
  );
  final image = await recorder.endRecording().toImage(2, 2);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}

Uint8List _id3WithPictures(List<Uint8List> images, List<int> types) {
  final frames = <int>[];
  for (var index = 0; index < images.length; index++) {
    final image = images[index];
    final payload = <int>[
      0,
      ...ascii.encode('image/png'),
      0,
      types[index],
      0,
      ...image,
    ];
    frames.addAll(ascii.encode('APIC'));
    frames.addAll(_syncSafe(payload.length));
    frames.addAll([0, 0]);
    frames.addAll(payload);
  }
  return Uint8List.fromList([
    ...ascii.encode('ID3'),
    4,
    0,
    0,
    ..._syncSafe(frames.length),
    ...frames,
  ]);
}

List<int> _syncSafe(int value) => [
      (value >> 21) & 0x7F,
      (value >> 14) & 0x7F,
      (value >> 7) & 0x7F,
      value & 0x7F,
    ];
