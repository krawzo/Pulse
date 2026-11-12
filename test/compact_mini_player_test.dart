import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_flutter/domain/audio_track.dart';
import 'package:pulse_flutter/ui/compact_mini_player.dart';

void main() {
  testWidgets('compact mini-player fits 360dp and opens Now Playing', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var openedNowPlaying = false;
    var playTapped = false;
    Duration? soughtTo;
    const track = AudioTrack(
      id: 'compact-track',
      path: r'C:\Music\song.mp3',
      title: 'A very long song title that should truncate in compact layout',
      artist: 'A very long artist name that should truncate too',
      album: 'Album',
      sizeBytes: 1,
      modifiedAtMillis: 0,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox()),
              CompactMiniPlayer(
                track: track,
                isPlaying: false,
                position: const Duration(minutes: 1),
                duration: const Duration(minutes: 3),
                onToggle: () => playTapped = true,
                onSeek: (value) => soughtTo = value,
                onOpenNowPlaying: () => openedNowPlaying = true,
              ),
            ],
          ),
          bottomNavigationBar: NavigationBar(
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                label: 'Biblioteca',
              ),
              NavigationDestination(
                icon: Icon(Icons.favorite_border_rounded),
                label: 'Favoritos',
              ),
              NavigationDestination(
                icon: Icon(Icons.queue_music_rounded),
                label: 'Playlists',
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.byType(CompactMiniPlayer)).height,
        lessThanOrEqualTo(100));
    expect(find.text('01:00'), findsOneWidget);
    expect(find.text('03:00'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);
    await tester.tap(find.byTooltip('Reproduzir'));
    expect(playTapped, isTrue);
    await tester.drag(find.byType(Slider), const Offset(30, 0));
    expect(soughtTo, isNotNull);
    await tester.tap(find.byTooltip('Mostrar a tela Tocando agora'));
    expect(openedNowPlaying, isTrue);
  });
}
