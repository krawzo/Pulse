import 'package:flutter/material.dart';

import '../state/playback_controller.dart';
import 'pulse_track_artwork.dart';

class PulseMobileQueue extends StatelessWidget {
  const PulseMobileQueue({
    super.key,
    required this.playback,
    required this.onClose,
    required this.onSetTimer,
  });

  final PlaybackController playback;
  final VoidCallback onClose;
  final ValueChanged<Duration?> onSetTimer;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: playback,
        builder: (context, _) {
          final track = playback.currentTrack;
          final upcomingStart = playback.currentIndex + 1;
          final upcomingCount =
              (playback.queue.length - upcomingStart).clamp(0, 1000000);
          return Scaffold(
            backgroundColor: const Color(0xFF121212),
            body: SafeArea(
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 16, 12),
                  child: Row(children: [
                    IconButton(
                      tooltip: 'Voltar',
                      onPressed: onClose,
                      icon: const Icon(Icons.arrow_back_rounded,
                          color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text('Fila de reprodução',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 21,
                              fontWeight: FontWeight.w800)),
                    ),
                  ]),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 8, 20, 6),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text('Tocando agora',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.w800)),
                  ),
                ),
                if (track == null)
                  const ListTile(
                    title: Text('Nenhuma faixa em reprodução',
                        style: TextStyle(color: Colors.white70)),
                  )
                else
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                    leading: PulseTrackArtwork(
                        track: track,
                        title: track.title,
                        creator: track.artist ?? '',
                        size: 52,
                        borderRadius: 5),
                    title: Text(track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Color(0xFF1ED760),
                            fontWeight: FontWeight.w700)),
                    subtitle: Text(track.artist ?? 'Artista não informado',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white60)),
                    trailing: IconButton(
                      tooltip: playback.isPlaying ? 'Pausar' : 'Reproduzir',
                      onPressed: playback.togglePlayback,
                      icon: Icon(playback.isPlaying
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded),
                      color: Colors.white,
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                  child: Row(children: [
                    _queueAction(
                      tooltip: 'Aleatório',
                      icon: Icons.shuffle_rounded,
                      active: playback.shuffleEnabled,
                      onPressed: track == null ? null : playback.toggleShuffle,
                    ),
                    _queueAction(
                      tooltip: 'Repetir',
                      icon: playback.repeatMode == PulseRepeatMode.track
                          ? Icons.repeat_one_rounded
                          : Icons.repeat_rounded,
                      active: playback.repeatMode != PulseRepeatMode.off,
                      onPressed:
                          track == null ? null : playback.cycleRepeatMode,
                    ),
                    _queueAction(
                      tooltip: 'Timer',
                      icon: Icons.timer_outlined,
                      active: playback.hasSleepTimer,
                      onPressed: track == null
                          ? null
                          : () => _showTimerChoices(context),
                    ),
                  ]),
                ),
                const Divider(height: 1, color: Color(0xFF303030)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
                  child: Row(children: [
                    const Expanded(
                        child: Text('A seguir',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800))),
                    Text('$upcomingCount faixas',
                        style: const TextStyle(color: Colors.white60)),
                  ]),
                ),
                Expanded(
                  child: upcomingCount == 0
                      ? const Center(
                          child: Text('Não há mais faixas na fila.',
                              style: TextStyle(color: Colors.white60)))
                      : ReorderableListView.builder(
                          buildDefaultDragHandles: false,
                          itemCount: upcomingCount,
                          onReorderItem: (oldIndex, newIndex) {
                            playback.moveUpcomingTrack(
                              upcomingStart + oldIndex,
                              upcomingStart + newIndex,
                            );
                          },
                          itemBuilder: (context, relativeIndex) {
                            final index = upcomingStart + relativeIndex;
                            final item = playback.queue[index];
                            final occurrence = playback.queue
                                .sublist(upcomingStart, index + 1)
                                .where((track) => track.id == item.id)
                                .length;
                            return ListTile(
                              key: ValueKey('${item.id}-$occurrence'),
                              contentPadding:
                                  const EdgeInsets.fromLTRB(20, 2, 8, 2),
                              onTap: () => playback.playQueueItem(index),
                              leading: PulseTrackArtwork(
                                track: item,
                                title: item.title,
                                creator: item.artist ?? '',
                                size: 48,
                                borderRadius: 5,
                              ),
                              title: Text(item.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                  item.artist ?? 'Artista não informado',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      const TextStyle(color: Colors.white60)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ReorderableDragStartListener(
                                    index: relativeIndex,
                                    child: const Padding(
                                      padding: EdgeInsets.all(8),
                                      child: Icon(Icons.drag_handle_rounded,
                                          color: Colors.white54),
                                    ),
                                  ),
                                  PopupMenuButton<String>(
                                    tooltip: 'Opções para ${item.title}',
                                    color: const Color(0xFF282828),
                                    icon: const Icon(Icons.more_vert_rounded,
                                        color: Colors.white70),
                                    onSelected: (action) {
                                      switch (action) {
                                        case 'play':
                                          playback.playQueueItem(index);
                                        case 'up':
                                          playback.moveUpcomingTrack(
                                              index, index - 1);
                                        case 'down':
                                          playback.moveUpcomingTrack(
                                              index, index + 1);
                                        case 'remove':
                                          playback.removeUpcomingAt(index);
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                          value: 'play',
                                          child: Text('Tocar agora')),
                                      if (index > upcomingStart)
                                        const PopupMenuItem(
                                            value: 'up',
                                            child: Text('Mover para cima')),
                                      if (index < playback.queue.length - 1)
                                        const PopupMenuItem(
                                            value: 'down',
                                            child: Text('Mover para baixo')),
                                      const PopupMenuItem(
                                          value: 'remove',
                                          child: Text('Remover da fila')),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ]),
            ),
          );
        },
      );

  Widget _queueAction({
    required String tooltip,
    required IconData icon,
    required bool active,
    required VoidCallback? onPressed,
  }) =>
      IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon),
        color: active ? const Color(0xFF1ED760) : Colors.white70,
      );

  Future<void> _showTimerChoices(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF282828),
      builder: (sheetContext) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const ListTile(title: Text('Parar de tocar em')),
          for (final minutes in [5, 10, 15, 30, 45, 60])
            ListTile(
              title: Text(minutes == 60 ? '1 hora' : '$minutes min'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onSetTimer(Duration(minutes: minutes));
              },
            ),
          ListTile(
            title: const Text('Quando a faixa acabar'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              onSetTimer(null);
            },
          ),
          if (playback.hasSleepTimer)
            ListTile(
              title: const Text('Cancelar timer'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                onSetTimer(Duration.zero);
              },
            ),
        ]),
      ),
    );
  }
}
