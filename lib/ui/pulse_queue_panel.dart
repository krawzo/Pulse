import 'package:flutter/material.dart';

import '../app/pulse_theme.dart';
import '../domain/audio_track.dart';
import '../state/playback_controller.dart';
import 'pulse_track_artwork.dart';

class PulseQueuePanel extends StatelessWidget {
  const PulseQueuePanel(
      {super.key, required this.playback, required this.onClose});

  final PlaybackController playback;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: playback,
        builder: (context, _) {
          final queue = playback.queue;
          final start = playback.currentIndex + 1;
          final count = (queue.length - start).clamp(0, queue.length);
          final palette = PulsePaletteTheme.of(context);
          return ColoredBox(
            color: palette.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 12, 16),
                  child: Row(children: [
                    Expanded(
                      child: Text('Fila',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    IconButton(
                      tooltip: 'Voltar para Tocando agora',
                      onPressed: onClose,
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ]),
                ),
                if (playback.currentTrack case final current?) ...[
                  _heading(context, 'Tocando agora'),
                  _tile(context, current, playback.currentIndex),
                ],
                _heading(context, 'Próximas na fila'),
                Expanded(
                  child: count == 0
                      ? Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text('Adicione uma faixa para tocar a seguir.',
                              style: Theme.of(context).textTheme.bodyMedium),
                        )
                      : ReorderableListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          buildDefaultDragHandles: false,
                          itemCount: count,
                          onReorderItem: (oldIndex, newIndex) =>
                              playback.moveUpcomingTrack(
                                  start + oldIndex, start + newIndex),
                          itemBuilder: (context, relativeIndex) {
                            final index = start + relativeIndex;
                            final track = queue[index];
                            final occurrence = queue
                                .sublist(start, index + 1)
                                .where((item) => item.id == track.id)
                                .length;
                            return _tile(context, track, index,
                                key: ValueKey('${track.id}-$occurrence'),
                                dragIndex: relativeIndex);
                          },
                        ),
                ),
              ],
            ),
          );
        },
      );

  Widget _heading(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 8, 8),
        child: Text(title,
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
      );

  Widget _tile(BuildContext context, AudioTrack track, int index,
      {Key? key, int? dragIndex}) {
    final active = index == playback.currentIndex;
    final palette = PulsePaletteTheme.of(context);
    return Material(
      key: key,
      color: Colors.transparent,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
        minTileHeight: 64,
        hoverColor: palette.hover,
        leading: PulseTrackArtwork(
            track: track,
            title: track.title,
            creator: track.artist ?? '',
            size: 48,
            borderRadius: 4),
        title: Text(track.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: active ? palette.accent : null)),
        subtitle: Text(
            track.source == AudioSource.jellyfin
                ? '${track.artist ?? 'Artista não informado'} • Jellyfin'
                : track.artist ?? 'Artista não informado',
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
        trailing: dragIndex == null
            ? null
            : ReorderableDragStartListener(
                index: dragIndex,
                child: Tooltip(
                  message: 'Arrastar para mudar a ordem',
                  child: Icon(Icons.drag_handle_rounded,
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ),
        onTap: () => playback.playQueueItem(index),
      ),
    );
  }
}
