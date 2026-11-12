import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app/pulse_theme.dart';
import '../data/local_artwork_cache.dart';
import '../data/remote_artwork_cache.dart';
import '../domain/audio_track.dart';
import '../state/playback_controller.dart';
import 'pulse_track_artwork.dart';
import 'pulse_artist_link.dart';

class PulseExpandedPlayerView extends StatefulWidget {
  const PulseExpandedPlayerView({
    super.key,
    required this.playback,
    required this.onOpenArtist,
  });

  final PlaybackController playback;
  final ValueChanged<String> onOpenArtist;

  @override
  State<PulseExpandedPlayerView> createState() =>
      _PulseExpandedPlayerViewState();
}

class _PulseExpandedPlayerViewState extends State<PulseExpandedPlayerView> {
  Future<Color?>? _coverColor;
  String? _loadedArtworkSignature;

  @override
  void initState() {
    super.initState();
    _loadColor();
  }

  @override
  void didUpdateWidget(covariant PulseExpandedPlayerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_artworkSignature(widget.playback.currentTrack) !=
        _loadedArtworkSignature) {
      _loadColor();
    }
  }

  String? _artworkSignature(AudioTrack? track) => track == null
      ? null
      : '${track.id}\u0000${track.path}\u0000${track.modifiedAtMillis}\u0000${track.artworkUrl ?? ''}';

  void _loadColor() {
    final track = widget.playback.currentTrack;
    _loadedArtworkSignature = _artworkSignature(track);
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
        provider: provider,
        brightness: Brightness.dark,
      );
      return scheme.primary;
    } on Object {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.playback.currentTrack;
    return FutureBuilder<Color?>(
      future: _coverColor,
      builder: (context, snapshot) {
        final frosted = PulsePaletteTheme.of(context).isFrosted;
        final base = snapshot.data ?? const Color(0xFF454F4B);
        final top = Color.lerp(base, Colors.black, .24)!;
        final bottom = Color.lerp(base, Colors.black, .66)!;
        return Padding(
          padding: const EdgeInsets.all(8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 350),
              decoration: BoxDecoration(
                border: frosted
                    ? Border.all(color: Colors.white.withValues(alpha: 0.16))
                    : null,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: frosted
                      ? const [Color(0x702B3338), Color(0x6020272C)]
                      : [top, bottom],
                ),
              ),
              child: Material(
                type: MaterialType.transparency,
                child: _buildContent(context, track),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent(BuildContext context, AudioTrack? track) => Column(
        children: [
          SizedBox(
            height: 64,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      track?.title ?? 'Tocando agora',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final artSize = math.min(
                  math.min(constraints.maxWidth * 0.70,
                      constraints.maxHeight * 0.74),
                  640.0,
                );
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (track != null)
                          PulseTrackArtwork(
                            track: track,
                            title: track.title,
                            creator:
                                '${track.artist ?? ''}${track.album ?? ''}',
                            size: artSize,
                            borderRadius: 18,
                          )
                        else
                          SizedBox.square(dimension: artSize),
                        const SizedBox(height: 24),
                        Text(
                          track?.title ?? 'Nenhuma faixa selecionada',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        PulseArtistLink(
                          artist: track?.artist,
                          fallback: 'Escolha uma faixa na biblioteca',
                          onOpenArtist: widget.onOpenArtist,
                          textAlign: TextAlign.center,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.76),
                                  ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
}
