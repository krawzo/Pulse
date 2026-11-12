// Local review surface. Run with `flutter run -t tool/mobile_layout_preview.dart`.
// It uses sample data and is not part of the production application.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pulse_flutter/domain/audio_track.dart';
import 'package:pulse_flutter/state/jellyfin_controller.dart';
import 'package:pulse_flutter/state/playback_controller.dart';
import 'package:pulse_flutter/ui/compact_mini_player.dart';
import 'package:pulse_flutter/ui/pulse_mobile_navigation.dart';
import 'package:pulse_flutter/ui/pulse_mobile_now_playing.dart';
import 'package:pulse_flutter/ui/pulse_mobile_playlist_page.dart';
import 'package:pulse_flutter/ui/pulse_track_artwork.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final support = await getApplicationSupportDirectory();
  final sample = File('${support.path}/pulse_preview.mp3');
  await File('${support.path}/pulse_preview.lrc').writeAsString('''
[00:00.00]E o telefone para contato é 75 9108-9362
[00:07.00]É paixão!
[00:13.00]Vem comigo
[00:20.00]Eu poderia te enganar, mentir
[00:27.00]Fingir que esqueci
[00:35.00]Mas a verdade é que eu vivo a sonhar
[00:44.00]Trecho de exemplo sete
[00:51.00]Trecho de exemplo oito
[00:58.00]Trecho de exemplo nove
[01:05.00]Trecho de exemplo dez
[01:12.00]Trecho de exemplo onze
[01:19.00]Trecho de exemplo doze
[01:26.00]Trecho de exemplo treze
[01:33.00]Trecho de exemplo catorze
''');
  final tracks = List<AudioTrack>.generate(28, (index) {
    const titles = [
      'Volta Vida',
      'Bum Bum Tam Tam',
      'Malandramente',
      'Agora Vai Sentar',
      'Vai Embrazando',
      'Rabetão',
      'Ela me Falou Que Quer Rave',
      'Taça a Xereca pra Mim',
      'Forever',
      'Flor de Tangerina',
    ];
    const artists = [
      'Raquel dos Teclados',
      'MC Fioti',
      'DENNIS',
      'MCs Jhowzinho & Kadinho',
      'ZAAC e MC Vigary',
      'MC Lan',
      'MC Levin',
      'MC Kaique da VP',
      'Labrinth',
      'Alceu Valença',
    ];
    final i = index % titles.length;
    return AudioTrack(
      id: 'preview-$index',
      path: index == 0 ? sample.path : '${support.path}/track_$index.mp3',
      title: titles[i],
      artist: artists[i],
      album: 'Músicas para ouvir',
      sizeBytes: 0,
      modifiedAtMillis: 0,
      durationMillis: 238000,
    );
  });
  final playback = PlaybackController(onPlayTrack: (_, __) async {});
  await playback.playPlaylistQueue(tracks, 0);
  await playback.seek(const Duration(seconds: 7));
  final jellyfin = JellyfinController();
  runApp(_PreviewApp(tracks: tracks, playback: playback, jellyfin: jellyfin));
}

class _PreviewApp extends StatefulWidget {
  const _PreviewApp(
      {required this.tracks, required this.playback, required this.jellyfin});
  final List<AudioTrack> tracks;
  final PlaybackController playback;
  final JellyfinController jellyfin;

  @override
  State<_PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<_PreviewApp> {
  final _search = TextEditingController();
  String _query = '';
  bool _playerOpen = false;

  @override
  void dispose() {
    _search.dispose();
    widget.playback.dispose();
    widget.jellyfin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData.dark().copyWith(
          colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFFB32D8F), brightness: Brightness.dark),
        ),
        home: Scaffold(
          backgroundColor: const Color(0xFFC83A92),
          body: _playerOpen
              ? PulseMobileNowPlaying(
                  playback: widget.playback,
                  jellyfin: widget.jellyfin,
                  onlineLookupEnabled: false,
                  onClose: () => setState(() => _playerOpen = false),
                  onShowQueue: () {},
                  onShowDevices: () {},
                  onShowTimer: () {},
                  onShare: () {},
                  onToggleFavorite: () {},
                  onMore: () {},
                  isFavorite: (_) => true,
                  onOpenArtist: (_) {},
                )
              : SafeArea(
                  bottom: false,
                  child: Stack(children: [
                    Positioned.fill(
                        child: PulseMobilePlaylistPage(
                      title: 'Minha playlist #23',
                      owner: 'Krawzo',
                      durationLabel: '1h 51min',
                      tracks: widget.tracks,
                      searchController: _search,
                      onSearchChanged: (value) =>
                          setState(() => _query = value),
                      onBack: () {},
                      onPlay: () => setState(() => _playerOpen = true),
                      onShuffle: widget.playback.toggleShuffle,
                      shuffleActive: widget.playback.shuffleEnabled,
                      onAdd: () {},
                      onEdit: () {},
                      onRename: () {},
                      onMore: () {},
                      onDownload: () {},
                      onShare: () {},
                      content: ListView.builder(
                        padding: const EdgeInsets.only(bottom: 180),
                        itemCount: widget.tracks
                            .where((track) => track.title
                                .toLowerCase()
                                .contains(_query.toLowerCase()))
                            .length,
                        itemBuilder: (context, index) {
                          final visible = widget.tracks
                              .where((track) => track.title
                                  .toLowerCase()
                                  .contains(_query.toLowerCase()))
                              .toList();
                          final track = visible[index];
                          return ListTile(
                            leading: PulseTrackArtwork(
                                track: track, title: track.title, size: 48),
                            title: Text(track.title),
                            subtitle: Text(track.artist ?? ''),
                            trailing: const Icon(Icons.more_vert_rounded),
                          );
                        },
                      ),
                    )),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 64 + MediaQuery.viewPaddingOf(context).bottom,
                      child: CompactMiniPlayer(
                        mobile: true,
                        track: widget.playback.currentTrack,
                        isPlaying: true,
                        position: widget.playback.position,
                        duration: widget.playback.duration,
                        onToggle: () {},
                        onSeek: (_) {},
                        onOpenNowPlaying: () =>
                            setState(() => _playerOpen = true),
                        onShowDevices: () {},
                        onToggleFavorite: () {},
                        isFavorite: true,
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: PulseMobileNavigation(
                        selected: PulseMobileTab.library,
                        onSelect: (_) {},
                      ),
                    ),
                  ]),
                ),
        ),
      );
}
