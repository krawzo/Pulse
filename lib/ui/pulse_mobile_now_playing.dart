import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/local_artwork_cache.dart';
import '../data/remote_artwork_cache.dart';
import '../domain/audio_track.dart';
import '../state/jellyfin_controller.dart';
import '../state/mobile_audio_output.dart';
import '../state/playback_controller.dart';
import '../state/pulse_connect_controller.dart';
import 'pulse_lyrics_sheet.dart';
import 'pulse_track_artwork.dart';
import 'pulse_artist_link.dart';

class PulseMobileNowPlaying extends StatefulWidget {
  const PulseMobileNowPlaying({
    super.key,
    required this.playback,
    this.connect,
    required this.jellyfin,
    required this.onlineLookupEnabled,
    required this.onClose,
    required this.onShowQueue,
    required this.onShowDevices,
    required this.onShowTimer,
    required this.onShare,
    required this.onToggleFavorite,
    required this.onMore,
    required this.isFavorite,
    required this.onOpenArtist,
  });

  final PlaybackController playback;
  final PulseConnectController? connect;
  final JellyfinController jellyfin;
  final bool onlineLookupEnabled;
  final VoidCallback onClose;
  final VoidCallback onShowQueue;
  final VoidCallback onShowDevices;
  final VoidCallback onShowTimer;
  final VoidCallback onShare;
  final VoidCallback onToggleFavorite;
  final VoidCallback onMore;
  final bool Function(AudioTrack?) isFavorite;
  final ValueChanged<String> onOpenArtist;

  @override
  State<PulseMobileNowPlaying> createState() => _PulseMobileNowPlayingState();
}

class _PulseMobileNowPlayingState extends State<PulseMobileNowPlaying> {
  Future<Color?>? _coverColor;
  String? _artworkSignature;
  double? _draggingPosition;
  String? _favoriteOverrideTrackId;
  bool? _favoriteOverride;
  String? _inlineLyric;
  String? _inlineLyricTrackId;

  void _openLyrics() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PulseLyricsSheet(
        playback: widget.playback,
        jellyfin: widget.jellyfin,
        onlineLookupEnabled: widget.onlineLookupEnabled,
        fullScreenMobile: true,
        onShare: widget.onShare,
        onMore: widget.onMore,
      ),
    ));
  }

  Widget _transportButton(String label, IconData icon, VoidCallback? onTap,
      {Color color = Colors.white70, double size = 26}) {
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        enabled: onTap != null,
        label: label,
        child: InkResponse(
          onTap: onTap,
          radius: 24,
          child: SizedBox(
            width: 34,
            height: 52,
            child: Icon(icon,
                size: size, color: onTap == null ? Colors.white38 : color),
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadColor();
    MobileAudioOutput.instance.start();
  }

  @override
  void didUpdateWidget(covariant PulseMobileNowPlaying oldWidget) {
    super.didUpdateWidget(oldWidget);
    final track = widget.playback.currentTrack;
    final nextSignature = track == null
        ? null
        : '${track.id}\u0000${track.path}\u0000${track.modifiedAtMillis}\u0000${track.artworkUrl ?? ''}';
    if (_artworkSignature != nextSignature) _loadColor();
  }

  void _loadColor() {
    final track = widget.playback.currentTrack;
    _artworkSignature = track == null
        ? null
        : '${track.id}\u0000${track.path}\u0000${track.modifiedAtMillis}\u0000${track.artworkUrl ?? ''}';
    _coverColor = track == null ? Future.value(null) : _extractColor(track);
  }

  Future<Color?> _extractColor(AudioTrack track) async {
    try {
      ImageProvider? provider;
      if (track.source == AudioSource.jellyfin && track.artworkUrl != null) {
        final cached = await RemoteArtworkCache.instance.imageFor(track);
        provider = cached == null
            ? NetworkImage(track.artworkUrl!)
            : FileImage(cached);
      } else if (track.source == AudioSource.local) {
        final Uint8List? bytes =
            await LocalArtworkCache.instance.imageForTracks([
          (
            path: track.path,
            size: track.sizeBytes,
            modifiedAtMillis: track.modifiedAtMillis,
          ),
        ]);
        if (bytes != null) provider = MemoryImage(bytes);
      }
      if (provider == null) return null;
      final scheme = await ColorScheme.fromImageProvider(
          provider: provider, brightness: Brightness.dark);
      return scheme.primary;
    } on Object {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: Listenable.merge([
          widget.playback,
          if (widget.connect case final connect?) connect,
          MobileAudioOutput.instance,
        ]),
        builder: (context, _) {
          final playback = widget.playback;
          final track = playback.currentTrack;
          final remoteName = widget.connect?.connected == true
              ? widget.connect?.deviceName?.trim()
              : null;
          final deviceName = remoteName?.isNotEmpty == true
              ? remoteName
              : MobileAudioOutput.instance.deviceName;
          final namedDevice = deviceName?.isNotEmpty == true;
          final favorite = track?.id == _favoriteOverrideTrackId
              ? _favoriteOverride ?? widget.isFavorite(track)
              : widget.isFavorite(track);
          final screen = MediaQuery.sizeOf(context);
          final insets = MediaQuery.viewPaddingOf(context);
          // Modal routes can remove MediaQuery's top padding even though the
          // system status bar and camera cutout are still present.
          final view = View.of(context);
          final systemTop = math.max(
              insets.top, view.viewPadding.top / view.devicePixelRatio);
          final usableHeight = screen.height - systemTop - insets.bottom;
          final shortScreen = usableHeight < 780;
          if (_inlineLyricTrackId != track?.id) {
            _inlineLyricTrackId = track?.id;
            _inlineLyric = null;
          }
          final showInlineLyricSpace = usableHeight >= 700;
          final hasInlineLyric = _inlineLyric?.trim().isNotEmpty == true;
          final artworkSize = math.max(
              120.0,
              math.min(
                  screen.width - 56,
                  math.min(
                      usableHeight * (usableHeight < 700 ? .22 : .42), 440.0)));
          final effectiveDuration = playback.duration > Duration.zero
              ? playback.duration
              : Duration(milliseconds: track?.durationMillis ?? 0);
          final maxMs = effectiveDuration.inMilliseconds;
          final positionMs = playback.position.inMilliseconds.clamp(
            0,
            maxMs > 0 ? maxMs : 1,
          );
          final sliderValue = (_draggingPosition ?? positionMs.toDouble())
              .clamp(0, maxMs > 0 ? maxMs.toDouble() : 1)
              .toDouble();
          return FutureBuilder<Color?>(
            future: _coverColor,
            builder: (context, snapshot) {
              final raw = snapshot.data ?? const Color(0xFF327F70);
              final hsv = HSVColor.fromColor(raw);
              final source = hsv
                  .withSaturation(math.max(hsv.saturation, .68))
                  .withValue(math.max(hsv.value, .60))
                  .toColor();
              final topLeft = Color.lerp(source, Colors.black, .08)!;
              final middle = Color.lerp(source, Colors.black, .37)!;
              final bottomRight = Color.lerp(source, Colors.black, .73)!;
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: const SystemUiOverlayStyle(
                  statusBarColor: Colors.transparent,
                  statusBarIconBrightness: Brightness.light,
                  systemNavigationBarColor: Colors.transparent,
                  systemNavigationBarIconBrightness: Brightness.light,
                  systemNavigationBarContrastEnforced: false,
                ),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 350),
                  decoration: BoxDecoration(
                      gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [topLeft, middle, bottomRight],
                    stops: const [0, .52, 1],
                  )),
                  child: SafeArea(
                    top: false,
                    bottom: false,
                    child: Padding(
                      // Full-screen bottom sheets remove MediaQuery's top padding.
                      // viewPadding still carries the camera/status-bar inset.
                      padding: EdgeInsets.only(top: systemTop + 14),
                      child: ListView(
                        padding:
                            EdgeInsets.fromLTRB(24, 6, 24, insets.bottom + 24),
                        children: [
                          Row(children: [
                            IconButton(
                              tooltip: 'Voltar',
                              onPressed: widget.onClose,
                              icon: const Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: Colors.white,
                                  size: 30),
                            ),
                            Expanded(
                              child: Column(children: [
                                const Text('TOCANDO AGORA',
                                    style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 10,
                                        letterSpacing: 1.4,
                                        fontWeight: FontWeight.w700)),
                                Text(track?.album ?? 'Pulse',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700)),
                              ]),
                            ),
                            IconButton(
                              tooltip: 'Mais opções',
                              onPressed: track == null ? null : widget.onMore,
                              icon: const Icon(Icons.more_vert_rounded,
                                  color: Colors.white),
                            ),
                          ]),
                          SizedBox(
                              height: shortScreen
                                  ? 8
                                  : math.max(12, screen.height * .019)),
                          Center(
                            child: PulseTrackArtwork(
                              track: track,
                              title: track?.title ?? 'Pulse',
                              creator: track?.artist ?? '',
                              size: artworkSize,
                              borderRadius: 8,
                            ),
                          ),
                          SizedBox(
                              height: usableHeight >= 700 && usableHeight < 840
                                  ? 52
                                  : shortScreen
                                      ? 14
                                      : (showInlineLyricSpace ? 14 : 22)),
                          if (showInlineLyricSpace) ...[
                            SizedBox(
                              height: shortScreen ? 32 : 48,
                              child: hasInlineLyric
                                  ? Center(
                                      child: Text(
                                        _inlineLyric!,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 12),
                          ],
                          Row(children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      track?.title ??
                                          'Nenhuma faixa selecionada',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: Colors.white,
                                          fontSize:
                                              screen.width < 400 ? 20 : 23,
                                          fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 4),
                                  PulseArtistLink(
                                      artist: track?.artist,
                                      fallback: 'Artista não informado',
                                      onOpenArtist: widget.onOpenArtist,
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 16)),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: favorite
                                  ? 'Remover de músicas curtidas'
                                  : 'Adicionar a músicas curtidas',
                              onPressed: track == null
                                  ? null
                                  : () {
                                      setState(() {
                                        _favoriteOverrideTrackId = track.id;
                                        _favoriteOverride = !favorite;
                                      });
                                      widget.onToggleFavorite();
                                    },
                              icon: Icon(favorite
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded),
                              color: favorite
                                  ? const Color(0xFF1ED760)
                                  : Colors.white,
                            ),
                            IconButton(
                              tooltip: switch (playback.repeatMode) {
                                PulseRepeatMode.off =>
                                  'Repetição desligada. Toque para repetir a fila',
                                PulseRepeatMode.queue =>
                                  'Repetir fila. Toque para repetir esta faixa',
                                PulseRepeatMode.track =>
                                  'Repetir faixa. Toque para desligar',
                              },
                              onPressed: track == null
                                  ? null
                                  : playback.cycleRepeatMode,
                              icon: Icon(
                                playback.repeatMode == PulseRepeatMode.track
                                    ? Icons.repeat_one_rounded
                                    : Icons.repeat_rounded,
                                size: 24,
                              ),
                              color: playback.repeatMode == PulseRepeatMode.off
                                  ? Colors.white70
                                  : const Color(0xFF1ED760),
                            ),
                          ]),
                          SizedBox(
                              height: usableHeight >= 700 && usableHeight < 840
                                  ? 0
                                  : 10),
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 5),
                              activeTrackColor: Colors.white,
                              inactiveTrackColor: Colors.white38,
                              thumbColor: Colors.white,
                            ),
                            child: Slider(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 8),
                              min: 0,
                              max: maxMs > 0 ? maxMs.toDouble() : 1,
                              value: sliderValue,
                              onChanged: track == null || maxMs <= 0
                                  ? null
                                  : (value) =>
                                      setState(() => _draggingPosition = value),
                              onChangeEnd: track == null || maxMs <= 0
                                  ? null
                                  : (value) {
                                      setState(() => _draggingPosition = null);
                                      playback.seek(Duration(
                                          milliseconds: value.round()));
                                    },
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 9),
                            child: Row(children: [
                              Text(_time(playback.position),
                                  style:
                                      const TextStyle(color: Colors.white70)),
                              const Spacer(),
                              Text(_time(effectiveDuration),
                                  style:
                                      const TextStyle(color: Colors.white70)),
                            ]),
                          ),
                          SizedBox(height: shortScreen ? 10 : 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              _transportButton(
                                  'Aleatório',
                                  Icons.shuffle_rounded,
                                  track == null ? null : playback.toggleShuffle,
                                  color: playback.shuffleEnabled
                                      ? const Color(0xFF1ED760)
                                      : Colors.white70),
                              _transportButton(
                                  'Anterior',
                                  Icons.skip_previous_rounded,
                                  track == null ? null : playback.skipPrevious,
                                  color: Colors.white,
                                  size: 32),
                              Material(
                                color: Colors.white,
                                shape: const CircleBorder(),
                                child: InkWell(
                                  onTap: track == null
                                      ? null
                                      : playback.togglePlayback,
                                  customBorder: const CircleBorder(),
                                  child: SizedBox.square(
                                    dimension: 64,
                                    child: Icon(
                                      playback.isPlaying
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                      size: 38,
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                              ),
                              _transportButton(
                                  'Próxima',
                                  Icons.skip_next_rounded,
                                  track == null ? null : playback.skipNext,
                                  color: Colors.white,
                                  size: 32),
                              _transportButton(
                                  playback.hasSleepTimer
                                      ? 'Alterar temporizador'
                                      : 'Temporizador',
                                  Icons.timer_outlined,
                                  track == null ? null : widget.onShowTimer,
                                  color: playback.hasSleepTimer
                                      ? const Color(0xFF1ED760)
                                      : Colors.white70),
                            ],
                          ),
                          SizedBox(
                              height: usableHeight < 700
                                  ? 6
                                  : shortScreen
                                      ? 16
                                      : 20),
                          Row(
                            children: [
                              Expanded(
                                child: Tooltip(
                                  message: namedDevice
                                      ? 'Conectado a $deviceName'
                                      : 'Conectar a um dispositivo',
                                  child: InkWell(
                                    onTap: widget.onShowDevices,
                                    borderRadius: BorderRadius.circular(8),
                                    child: SizedBox(
                                      height: 48,
                                      child: Row(children: [
                                        Icon(
                                          remoteName?.isNotEmpty == true
                                              ? Icons.devices_rounded
                                              : namedDevice
                                                  ? Icons.headphones_rounded
                                                  : Icons.devices_rounded,
                                          color: namedDevice
                                              ? const Color(0xFF1ED760)
                                              : Colors.white,
                                          size: 24,
                                        ),
                                        if (namedDevice) ...[
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              deviceName!,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Color(0xFF1ED760),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ]),
                                    ),
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Compartilhar faixa',
                                onPressed:
                                    track == null ? null : widget.onShare,
                                icon: const Icon(Icons.share_outlined),
                                color: Colors.white,
                              ),
                              IconButton(
                                tooltip: 'Fila de reprodução',
                                onPressed: widget.onShowQueue,
                                icon: const Icon(Icons.queue_music_rounded),
                                color: Colors.white,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Container(
                            key: const ValueKey('mobile-lyrics-preview-card'),
                            height: 355,
                            decoration: BoxDecoration(
                              color: Color.lerp(source, Colors.black, .13),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: Colors.white24),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: PulseLyricsSheet(
                              playback: playback,
                              jellyfin: widget.jellyfin,
                              onlineLookupEnabled: widget.onlineLookupEnabled,
                              previewOnly: true,
                              onShowFullLyrics: _openLyrics,
                              onActiveLineChanged: (line) {
                                if (!mounted ||
                                    widget.playback.currentTrack?.id !=
                                        track?.id ||
                                    _inlineLyric == line) {
                                  return;
                                }
                                setState(() => _inlineLyric = line);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      );

  String _time(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}
