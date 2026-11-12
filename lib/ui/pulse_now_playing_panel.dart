import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../domain/audio_track.dart';
import '../state/playback_controller.dart';
import 'pulse_track_artwork.dart';
import 'pulse_artist_link.dart';

class PulseNowPlayingPanel extends StatefulWidget {
  const PulseNowPlayingPanel({
    super.key,
    required this.playback,
    required this.onShowLyrics,
    required this.width,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onShowQueue,
    required this.onExpandPlayer,
    required this.onHidePanel,
    required this.playlists,
    required this.onAddToPlaylist,
    required this.onOpenArtist,
  });

  final PlaybackController playback;
  final VoidCallback onShowLyrics;
  final double width;
  final bool isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onShowQueue;
  final VoidCallback onExpandPlayer;
  final VoidCallback onHidePanel;
  final List<PulsePlaylist> playlists;
  final ValueChanged<String> onAddToPlaylist;
  final ValueChanged<String> onOpenArtist;

  @override
  State<PulseNowPlayingPanel> createState() => _PulseNowPlayingPanelState();
}

class _PulseNowPlayingPanelState extends State<PulseNowPlayingPanel> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final playback = widget.playback;
    final width = widget.width;
    final isFavorite = widget.isFavorite;
    final onToggleFavorite = widget.onToggleFavorite;
    final onShowQueue = widget.onShowQueue;

    final track = playback.currentTrack;
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = math.max(0.0, constraints.maxHeight - 240);
        final artworkSize =
            math.min(math.min(width - 40, 420.0), availableHeight);
        return Container(
          width: width,
          decoration: BoxDecoration(
            color: colors.surface,
          ),
          child: Column(
            children: [
              MouseRegion(
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() => _hovered = false),
                child: Focus(
                  onFocusChange: (focused) =>
                      setState(() => _focused = focused),
                  child: Padding(
                    key: const ValueKey('now-playing-header'),
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Row(
                      children: [
                        _headerSlot(
                          visible: _hovered || _focused,
                          child: IconButton(
                            tooltip: 'Ocultar a tela Tocando agora',
                            onPressed: widget.onHidePanel,
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                        ),
                        Expanded(
                          child: Text(
                            track?.title ?? 'Tocando agora',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                        _headerSlot(
                          visible: _hovered || _focused,
                          child: PopupMenuButton<String>(
                            tooltip: 'Mais opções',
                            icon: const Icon(Icons.more_horiz_rounded),
                            onSelected: widget.onAddToPlaylist,
                            itemBuilder: (context) => track == null ||
                                    widget.playlists.isEmpty
                                ? [
                                    PopupMenuItem<String>(
                                      enabled: false,
                                      child: Text(track == null
                                          ? 'Nenhuma faixa selecionada'
                                          : 'Crie uma playlist primeiro'),
                                    ),
                                  ]
                                : widget.playlists
                                    .map((playlist) => PopupMenuItem<String>(
                                          value: playlist.id,
                                          child: Text(
                                              'Adicionar a ${playlist.name}'),
                                        ))
                                    .toList(growable: false),
                          ),
                        ),
                        _headerSlot(
                          visible: _hovered || _focused,
                          child: IconButton(
                            tooltip: 'Entrar na tela cheia',
                            onPressed: widget.onExpandPlayer,
                            icon: const Icon(Icons.open_in_full_rounded),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  key: const PageStorageKey<String>('now-playing-panel-scroll'),
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  child: track == null
                      ? _EmptyNowPlayingPanel(colors: colors)
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Center(
                              child: PulseTrackArtwork(
                                track: track,
                                title: track.title,
                                creator:
                                    '${track.artist ?? ''}${track.album ?? ''}',
                                size: artworkSize,
                                borderRadius: 14,
                              ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              track.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 6),
                            PulseArtistLink(
                              artist: track.artist,
                              fallback: 'Artista não informado',
                              onOpenArtist: widget.onOpenArtist,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: colors.onSurface
                                        .withValues(alpha: 0.72),
                                  ),
                            ),
                            if (track.album?.trim().isNotEmpty ?? false) ...[
                              const SizedBox(height: 4),
                              Text(
                                track.album!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: colors.onSurface.withValues(
                                        alpha: 0.62,
                                      ),
                                    ),
                              ),
                            ],
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton.icon(
                                  onPressed: onToggleFavorite,
                                  icon: Icon(
                                    isFavorite
                                        ? Icons.favorite_rounded
                                        : Icons.favorite_border_rounded,
                                  ),
                                  label: Text(
                                    isFavorite ? 'Favoritada' : 'Favoritar',
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed: onShowQueue,
                                  icon: const Icon(Icons.queue_music_rounded),
                                  label: const Text('Fila'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: widget.onShowLyrics,
                                  icon: const Icon(Icons.lyrics_outlined),
                                  label: const Text('Letras'),
                                ),
                              ],
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _headerSlot({required bool visible, required Widget child}) {
    return SizedBox(
      width: 48,
      height: 48,
      child: visible ? child : null,
    );
  }
}

class _EmptyNowPlayingPanel extends StatelessWidget {
  const _EmptyNowPlayingPanel({required this.colors});

  final ColorScheme colors;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.music_note_rounded,
                size: 32,
                color: colors.onSurface.withValues(alpha: 0.48),
              ),
              const SizedBox(height: 12),
              Text(
                'Nenhuma faixa selecionada',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                'Escolha uma faixa da biblioteca para começar.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.onSurface.withValues(alpha: 0.64),
                    ),
              ),
            ],
          ),
        ),
      );
}
