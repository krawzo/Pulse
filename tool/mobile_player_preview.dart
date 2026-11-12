import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pulse_flutter/domain/audio_track.dart';
import 'package:pulse_flutter/domain/pulse_lyrics.dart';
import 'package:pulse_flutter/state/jellyfin_controller.dart';
import 'package:pulse_flutter/state/playback_controller.dart';
import 'package:pulse_flutter/ui/pulse_mobile_now_playing.dart';

class PreviewPlayback extends PlaybackController {
  static const song = AudioTrack(
    id: 'preview-song',
    path: 'preview-song',
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

class PreviewLyrics extends JellyfinController {
  @override
  Future<PulseLyrics?> lyricsFor(AudioTrack track) async => const PulseLyrics([
        PulseLyricLine('Primeira linha da letra', Duration.zero),
        PulseLyricLine('A música continua aqui', Duration(seconds: 15)),
        PulseLyricLine('Próxima linha da letra', Duration(seconds: 30)),
      ]);
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const PreviewApp());
}

class PreviewApp extends StatefulWidget {
  const PreviewApp({super.key});

  @override
  State<PreviewApp> createState() => _PreviewAppState();
}

class _PreviewAppState extends State<PreviewApp> {
  final playback = PreviewPlayback();
  final lyrics = PreviewLyrics();

  @override
  void dispose() {
    playback.dispose();
    lyrics.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
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
      );
}
