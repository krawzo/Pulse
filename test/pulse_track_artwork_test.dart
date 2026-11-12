import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_flutter/data/local_artwork_cache.dart';
import 'package:pulse_flutter/domain/audio_track.dart';
import 'package:pulse_flutter/ui/pulse_track_artwork.dart';

void main() {
  late Directory temporaryDirectory;
  late Map<String, AudioTrack> tracks;

  setUpAll(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('pulse-art-ui-');
    tracks = {};
    for (final scenario in [
      (name: 'embedded cover', image: true, valid: true),
      (name: 'missing cover fallback', image: false, valid: true),
      (name: 'corrupt cover fallback', image: true, valid: false),
    ]) {
      final bytes = scenario.image
          ? _id3WithImage(scenario.valid ? await _tinyPng() : [1, 2, 3])
          : _id3WithoutImage();
      final file = File('${temporaryDirectory.path}/${scenario.name}.mp3');
      await file.writeAsBytes(bytes);
      final stat = await file.stat();
      final track = AudioTrack(
        id: scenario.name,
        path: file.path,
        title: 'Faixa de revisão',
        artist: 'Artista local',
        album: 'Álbum local',
        sizeBytes: stat.size,
        modifiedAtMillis: stat.modified.millisecondsSinceEpoch,
      );
      tracks[scenario.name] = track;
      await LocalArtworkCache.instance.imageFor(
        track.path,
        track.sizeBytes,
        track.modifiedAtMillis,
      );
    }
  });

  tearDownAll(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  for (final scenario in [
    (name: 'embedded cover', image: true, valid: true),
    (name: 'missing cover fallback', image: false, valid: true),
    (name: 'corrupt cover fallback', image: true, valid: false),
  ]) {
    testWidgets('artwork shows ${scenario.name}', (tester) async {
      tester.view.physicalSize = const Size(160, 160);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final track = tracks[scenario.name]!;
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            backgroundColor: const Color(0xFF101318),
            body: Center(
              child: PulseTrackArtwork(
                track: track,
                title: track.title,
                creator: '${track.artist}${track.album}',
                size: 120,
                borderRadius: 16,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pumpAndSettle();
      expect(
        tester.getSize(find.byType(PulseTrackArtwork)),
        const Size(120, 120),
      );
      expect(
        find.descendant(
          of: find.byType(PulseTrackArtwork),
          matching: find.text('F'),
        ),
        scenario.valid && scenario.image ? findsNothing : findsOneWidget,
      );
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
            'goldens/pulse_track_artwork_${scenario.name.replaceAll(' ', '_')}_120x120.png'),
      );
    });
  }
}

Future<Uint8List> _tinyPng() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 320, 180),
    ui.Paint()..color = const ui.Color(0xFF343A78),
  );
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 96, 180),
    ui.Paint()..color = const ui.Color(0xFF288F83),
  );
  canvas.drawCircle(
    const ui.Offset(160, 90),
    62,
    ui.Paint()..color = const ui.Color(0xFFE8894A),
  );
  canvas.drawRect(
    const ui.Rect.fromLTWH(220, 0, 100, 180),
    ui.Paint()..color = const ui.Color(0xFFB84D69),
  );
  final image = await recorder.endRecording().toImage(320, 180);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image.dispose();
  }
}

Uint8List _id3WithoutImage() => Uint8List.fromList([
      ...ascii.encode('ID3'),
      4,
      0,
      0,
      0,
      0,
      0,
      0,
    ]);

Uint8List _id3WithImage(List<int> image) {
  final payload = <int>[
    0,
    ...ascii.encode('image/png'),
    0,
    3,
    0,
    ...image,
  ];
  final frame = <int>[
    ...ascii.encode('APIC'),
    ..._syncSafe(payload.length),
    0,
    0,
    ...payload,
  ];
  return Uint8List.fromList([
    ...ascii.encode('ID3'),
    4,
    0,
    0,
    ..._syncSafe(frame.length),
    ...frame,
  ]);
}

List<int> _syncSafe(int value) => [
      (value >> 21) & 0x7F,
      (value >> 14) & 0x7F,
      (value >> 7) & 0x7F,
      value & 0x7F,
    ];
