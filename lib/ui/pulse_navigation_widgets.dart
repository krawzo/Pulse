import 'package:flutter/material.dart';

import '../app/pulse_theme.dart';
import '../domain/audio_track.dart';
import '../state/playback_controller.dart';
import 'pulse_navigation.dart';

class PulseExpandedSidebar extends StatelessWidget {
  const PulseExpandedSidebar({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.playback,
    required this.playlists,
    required this.remotePlaylists,
    required this.selectedPlaylistId,
    required this.onSelectPlaylist,
    required this.onSelectRemotePlaylist,
    this.onPlaylistContextMenu,
    this.selectedRemotePlaylistId,
    required this.onCreatePlaylist,
    required this.onFocusSearch,
    this.onCollapse,
    this.width = 232,
  });

  final PulseDestination selected;
  final ValueChanged<PulseDestination> onSelect;
  final PlaybackController playback;
  final double width;
  final List<PulsePlaylist> playlists;
  final List<Map<String, dynamic>> remotePlaylists;
  final String? selectedPlaylistId;
  final String? selectedRemotePlaylistId;
  final ValueChanged<String> onSelectPlaylist;
  final ValueChanged<String> onSelectRemotePlaylist;
  final void Function(String playlistId, Offset position)?
      onPlaylistContextMenu;
  final VoidCallback? onCreatePlaylist;
  final VoidCallback onFocusSearch;
  final VoidCallback? onCollapse;

  @override
  Widget build(BuildContext context) {
    final light = Theme.of(context).brightness == Brightness.light;
    final palette = PulsePaletteTheme.of(context);
    const destinations = [
      (PulseDestination.library, 'Biblioteca', Icons.library_music_outlined),
      (PulseDestination.tracks, 'Faixas', Icons.music_note_rounded),
      (PulseDestination.albums, 'Álbuns', Icons.album_outlined),
      (PulseDestination.artists, 'Artistas', Icons.person_outline_rounded),
      (PulseDestination.favorites, 'Favoritos', Icons.favorite_border_rounded),
    ];
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: palette.sidebar,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              width < 220 ? 8 : 20,
              width < 220 ? 8 : 16,
              width < 220 ? 8 : 12,
              width < 220 ? 8 : 14,
            ),
            child: width < 220
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          IconButton(
                            tooltip: 'Focar busca da biblioteca',
                            visualDensity: VisualDensity.compact,
                            onPressed: onFocusSearch,
                            icon: const Icon(Icons.search_rounded),
                          ),
                          const Spacer(),
                          if (onCollapse case final collapse?)
                            IconButton(
                              tooltip: 'Ocultar biblioteca',
                              visualDensity: VisualDensity.compact,
                              onPressed: collapse,
                              icon: const Icon(Icons.chevron_left_rounded),
                            ),
                        ],
                      ),
                      Text(
                        'SUA BIBLIOTECA',
                        style: TextStyle(
                          color: light ? palette.mutedInk : Colors.white54,
                          fontSize: 8,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Text(
                          'SUA BIBLIOTECA',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: light ? palette.mutedInk : Colors.white54,
                            fontSize: 11,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Focar busca da biblioteca',
                        visualDensity: VisualDensity.compact,
                        onPressed: onFocusSearch,
                        icon: const Icon(Icons.search_rounded),
                      ),
                      if (onCollapse case final collapse?)
                        IconButton(
                          tooltip: 'Ocultar biblioteca',
                          visualDensity: VisualDensity.compact,
                          onPressed: collapse,
                          icon: const Icon(Icons.chevron_left_rounded),
                        ),
                    ],
                  ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final item in destinations)
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: width < 220 ? 4 : 12,
                        vertical: 2,
                      ),
                      child: _PulseNavigationItem(
                        icon: item.$3,
                        label: item.$2,
                        selected: selected == item.$1,
                        onTap: () => onSelect(item.$1),
                        compact: width < 220,
                      ),
                    ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(20, 18, 16, 4),
                    child: Divider(height: 1),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 10, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextButton(
                            style: TextButton.styleFrom(
                              alignment: Alignment.centerLeft,
                              foregroundColor: selected ==
                                      PulseDestination.playlists
                                  ? (light ? palette.accent : pulseDarkText)
                                  : (light ? palette.mutedInk : Colors.white70),
                              padding: EdgeInsets.zero,
                            ),
                            onPressed: () =>
                                onSelect(PulseDestination.playlists),
                            child: const Text(
                              'PLAYLISTS',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ),
                        if (onCreatePlaylist case final onCreatePlaylist?)
                          IconButton(
                            tooltip: 'Nova playlist',
                            visualDensity: VisualDensity.compact,
                            onPressed: onCreatePlaylist,
                            icon: const Icon(Icons.add_rounded),
                          ),
                      ],
                    ),
                  ),
                  if (playlists.isEmpty && remotePlaylists.isEmpty)
                    Padding(
                      padding: EdgeInsets.fromLTRB(28, 4, 16, 12),
                      child: Text(
                        'Suas listas aparecem aqui',
                        style: TextStyle(
                            color: light ? palette.mutedInk : Colors.white54,
                            fontSize: 12),
                      ),
                    )
                  else
                    for (final playlist in playlists)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 1,
                        ),
                        child: _PulseNavigationItem(
                          icon: Icons.queue_music_rounded,
                          label: playlist.folderName == null
                              ? playlist.name
                              : '${playlist.folderName} / ${playlist.name}',
                          selected: selected == PulseDestination.playlists &&
                              selectedPlaylistId == playlist.id,
                          onTap: () => onSelectPlaylist(playlist.id),
                          onSecondaryTapDown: onPlaylistContextMenu == null
                              ? null
                              : (position) => onPlaylistContextMenu!(
                                    playlist.id,
                                    position,
                                  ),
                        ),
                      ),
                  for (final playlist in remotePlaylists)
                    if (playlist['Id']?.toString() case final id?)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 1),
                        child: _PulseNavigationItem(
                          icon: Icons.queue_music_rounded,
                          label: playlist['Name']?.toString() ?? 'Playlist',
                          selected: selected == PulseDestination.playlists &&
                              selectedRemotePlaylistId == id,
                          onTap: () => onSelectRemotePlaylist(id),
                        ),
                      ),
                ],
              ),
            ),
          ),
          if (_playerStatus(playback) case final status?)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                status,
                style: TextStyle(
                  color: light ? palette.mutedInk : Colors.white38,
                  fontSize: 10,
                  letterSpacing: 1.3,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String? _playerStatus(PlaybackController playback) {
  if (playback.errorMessage != null) return 'ERRO NA REPRODUÇÃO';
  if (playback.currentTrack == null) return 'PLAYER PRONTO';
  return playback.isPlaying ? 'REPRODUZINDO' : null;
}

class PulseMediumRail extends StatelessWidget {
  const PulseMediumRail({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onFocusSearch,
    required this.onOpenSettings,
  });

  final PulseDestination selected;
  final ValueChanged<PulseDestination> onSelect;
  final VoidCallback onFocusSearch;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 72,
        child: Column(
          children: [
            IconButton(
              tooltip: 'Focar busca da biblioteca',
              onPressed: onFocusSearch,
              icon: const Icon(Icons.search_rounded),
            ),
            Expanded(
              child: NavigationRail(
                minWidth: 72,
                selectedIndex: rootIndex(selected),
                onDestinationSelected: (index) =>
                    onSelect(compactDestination(index)),
                labelType: NavigationRailLabelType.none,
                destinations: const [
                  NavigationRailDestination(
                    icon: Tooltip(
                      message: 'Biblioteca',
                      child: Icon(Icons.library_music_outlined),
                    ),
                    label: Text('Biblioteca'),
                  ),
                  NavigationRailDestination(
                    icon: Tooltip(
                      message: 'Favoritos',
                      child: Icon(Icons.favorite_border_rounded),
                    ),
                    label: Text('Favoritos'),
                  ),
                  NavigationRailDestination(
                    icon: Tooltip(
                      message: 'Playlists',
                      child: Icon(Icons.queue_music_rounded),
                    ),
                    label: Text('Playlists'),
                  ),
                ],
              ),
            ),
            if (MediaQuery.sizeOf(context).width < 840)
              IconButton(
                tooltip: 'Configurações',
                onPressed: onOpenSettings,
                icon: const Icon(Icons.settings_outlined),
              ),
          ],
        ),
      );
}

class PulseCompactNavigation extends StatelessWidget {
  const PulseCompactNavigation({
    super.key,
    required this.selected,
    required this.onSelect,
  });

  final PulseDestination selected;
  final ValueChanged<PulseDestination> onSelect;

  @override
  Widget build(BuildContext context) => NavigationBar(
        selectedIndex: rootIndex(selected),
        onDestinationSelected: (index) => onSelect(compactDestination(index)),
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
      );
}

class _PulseNavigationItem extends StatelessWidget {
  const _PulseNavigationItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.onSecondaryTapDown,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final ValueChanged<Offset>? onSecondaryTapDown;
  final bool compact;

  @override
  Widget build(BuildContext context) => GestureDetector(
      onSecondaryTapDown: onSecondaryTapDown == null
          ? null
          : (details) => onSecondaryTapDown!(details.globalPosition),
      child: Material(
        color: Colors.transparent,
        child: Builder(builder: (context) {
          final light = Theme.of(context).brightness == Brightness.light;
          final palette = PulsePaletteTheme.of(context);
          return Container(
              decoration: BoxDecoration(
                border: selected
                    ? Border(
                        left:
                            BorderSide(color: palette.selectedMarker, width: 3))
                    : null,
                borderRadius: BorderRadius.circular(12),
                gradient: selected ? palette.functionalSelectionGradient : null,
              ),
              child: ListTile(
                selected: selected,
                minTileHeight: 48,
                minLeadingWidth: compact ? 24 : null,
                horizontalTitleGap: compact ? 8 : null,
                contentPadding:
                    compact ? const EdgeInsets.symmetric(horizontal: 8) : null,
                selectedTileColor: palette.functionalSelectionGradient == null
                    ? palette.selected
                    : Colors.transparent,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                leading: Icon(
                  icon,
                  color: selected
                      ? palette.selectedIcon
                      : (light ? palette.mutedInk : Colors.white60),
                ),
                title: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: selected
                          ? palette.selectedInk
                          : (light ? palette.ink : Colors.white70)),
                ),
                onTap: onTap,
              ));
        }),
      ));
}
