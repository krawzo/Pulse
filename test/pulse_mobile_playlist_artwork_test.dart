import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_flutter/ui/pulse_mobile_browse.dart';
import 'package:pulse_flutter/ui/pulse_mobile_navigation.dart';
import 'package:pulse_flutter/ui/pulse_track_artwork.dart';

void main() {
  testWidgets('mobile library uses account and server playlist artwork',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final search = TextEditingController();
    addTearDown(search.dispose);
    const cover = 'file:///C:/missing-playlist-cover.jpg';

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PulseMobileBrowse(
          tab: PulseMobileTab.library,
          tracks: const [],
          newTracks: const [],
          onOpenInsights: () {},
          onMarkNewSeen: () {},
          playlists: const [],
          remotePlaylists: const [
            {'Id': 'playlist-1', 'Name': 'Adoração', 'CoverArt': 'cover-1'},
          ],
          remotePlaylistCoverUrl: (_) => cover,
          favoriteIds: const {},
          currentTrackId: null,
          query: '',
          searchController: search,
          onQueryChanged: (_) {},
          onClearQuery: () {},
          onOpenSettings: () {},
          onOpenAccount: () {},
          accountName: 'Marlus',
          onOpenFavorites: () {},
          onOpenPlaylist: (_) {},
          onOpenRemotePlaylist: (_) {},
          onPlaylistMore: (_) {},
          onOpenAlbum: (_) {},
          onOpenArtist: (_) {},
          onImportMusic: () {},
          onCreatePlaylist: () {},
          onPlayTrack: (_) {},
          onPlayNext: (_) {},
          onTrackMore: (_) {},
          onSelectTab: (_) {},
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('Músicas curtidas'), findsOneWidget);
    expect(find.text('Marlus'), findsOneWidget);
    expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
    expect(find.text('Adoração'), findsOneWidget);
    expect(
      find.byWidgetPredicate((widget) =>
          widget is PulseTrackArtwork && widget.artworkUrl == cover),
      findsOneWidget,
    );
  });
}
