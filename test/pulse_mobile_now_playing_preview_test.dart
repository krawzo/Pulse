import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_flutter/domain/audio_track.dart';
import 'package:pulse_flutter/domain/pulse_lyrics.dart';
import 'package:pulse_flutter/state/jellyfin_controller.dart';
import 'package:pulse_flutter/state/playback_controller.dart';
import 'package:pulse_flutter/ui/pulse_mobile_now_playing.dart';

class _PreviewPlayback extends PlaybackController {
  static const song = AudioTrack(
    id: 'visual-preview',
    path: 'visual-preview',
    title: 'Canarinho Prisioneiro',
    artist: 'Chico Rey & Paraná',
    album: 'Acústico',
    source: AudioSource.jellyfin,
    sizeBytes: 0,
    modifiedAtMillis: 0,
    durationMillis: 204000,
  );

  @override
  AudioTrack? get currentTrack => song;
  @override
  Duration get position => const Duration(seconds: 16);
  @override
  Duration get duration => const Duration(minutes: 3, seconds: 24);
  @override
  bool get isPlaying => true;
}

class _PreviewLyrics extends JellyfinController {
  @override
  Future<PulseLyrics?> lyricsFor(AudioTrack track) async => const PulseLyrics([
        PulseLyricLine('Primeira linha da letra', Duration.zero),
        PulseLyricLine('A música continua aqui', Duration(seconds: 15)),
        PulseLyricLine('Próxima linha da letra', Duration(seconds: 30)),
      ]);
}

void main() {
  setUpAll(() async {
    final textFont = FontLoader('Roboto')
      ..addFont(Future.value(ByteData.sublistView(
          File(r'C:\Windows\Fonts\segoeui.ttf').readAsBytesSync())));
    final icons = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(File(
              'tools/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf')
          .readAsBytesSync())));
    await textFont.load();
    await icons.load();
  });
  for (final size in [
    const Size(393, 873),
    const Size(360, 800),
    const Size(320, 640),
  ]) {
    testWidgets('prévia visível em ${size.width}x${size.height}',
        (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final playback = _PreviewPlayback();
      final lyrics = _PreviewLyrics();
      addTearDown(playback.dispose);
      addTearDown(lyrics.dispose);

      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            viewPadding: const EdgeInsets.only(top: 24, bottom: 24),
          ),
          child: Scaffold(
            body: PulseMobileNowPlaying(
              playback: playback,
              jellyfin: lyrics,
              onlineLookupEnabled: false,
              onClose: () {},
              onShowQueue: () {},
              onShowDevices: () {},
              onShowTimer: () {},
              onShare: () {},
              onToggleFavorite: () {},
              onMore: () {},
              isFavorite: (_) => false,
              onOpenArtist: (_) {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Prévia da letra'), findsOneWidget);
      expect(find.text('Mostrar letra'), findsOneWidget);
      final card = find.byKey(const ValueKey('mobile-lyrics-preview-card'));
      expect(tester.getRect(card).top, lessThan(size.height - 24));
      expect(tester.getRect(card).bottom, greaterThan(size.height));
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile(
            'goldens/mobile_player_preview_${size.width.toInt()}x${size.height.toInt()}.png'),
      );

      await tester.drag(find.byType(ListView).first, const Offset(0, -500));
      await tester.pumpAndSettle();
      final buttonBottom = tester.getRect(find.text('Mostrar letra')).bottom;
      expect(buttonBottom, lessThan(size.height - 24));
    });
  }
}
