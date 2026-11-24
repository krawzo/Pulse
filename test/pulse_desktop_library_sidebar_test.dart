import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_flutter/app/pulse_theme.dart';
import 'package:pulse_flutter/domain/audio_track.dart';
import 'package:pulse_flutter/ui/pulse_desktop_library_sidebar.dart';
import 'package:pulse_flutter/ui/pulse_navigation.dart';

void main() {
  testWidgets('Tudo starts with liked songs and playlists before albums',
      (tester) async {
    tester.view.physicalSize = const Size(400, 750);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const track = AudioTrack(
      id: 'song-1',
      path: 'song-1',
      title: 'Faixa de teste',
      artist: 'Artista de teste',
      album: 'Álbum de teste',
      sizeBytes: 0,
      modifiedAtMillis: 0,
      source: AudioSource.jellyfin,
    );
    await tester.pumpWidget(MaterialApp(
      theme: buildPulseTheme(),
      home: Scaffold(
        body: PulseDesktopLibrarySidebar(
          selected: PulseDestination.library,
          onSelect: (_) {},
          onSelectPlaylist: (_) {},
          onSelectRemotePlaylist: (_) {},
          onPlayPlaylist: (_) {},
          onPlayTrack: (_) {},
          onTrackContextMenu: (_, __) {},
          onPlaylistContextMenu: (_, __) {},
          onOpenAlbum: (_) {},
          onCreatePlaylist: () {},
          onFocusSearch: () {},
          playlists: const [
            PulsePlaylist(id: 'z', name: 'Zebra', trackIds: []),
            PulsePlaylist(id: 'p', name: 'Fixada', trackIds: [], pinned: true),
          ],
          remotePlaylists: const [
            {'Id': 'a', 'Name': 'Adoração'},
          ],
          remotePlaylistPrefix: 'navidrome',
          remotePlaylistCoverUrl: (_) => null,
          tracks: const [track],
          favoriteIds: const {'song-1'},
          accountName: 'Marlus',
          width: 340,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final labels = [
      'Músicas curtidas',
      'Fixada',
      'Adoração',
      'Zebra',
      'Álbum de teste',
      'Artista de teste',
    ];
    final y =
        labels.map((label) => tester.getTopLeft(find.text(label).first).dy);
    expect(y.toList(), orderedEquals([...y]..sort()));
    expect(find.byTooltip('Ocultar biblioteca'), findsNothing);
    expect(find.text('Marlus'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
  });
}
