import 'package:flutter/material.dart';

import '../app/pulse_theme.dart';
import '../domain/audio_track.dart';
import '../domain/library_search.dart';
import 'pulse_navigation.dart';
import 'pulse_track_artwork.dart';

/// Desktop library surface: a compact collection browser, not a second menu.
class PulseDesktopLibrarySidebar extends StatefulWidget {
  const PulseDesktopLibrarySidebar({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onSelectPlaylist,
    required this.onSelectRemotePlaylist,
    required this.onPlayPlaylist,
    required this.onPlayTrack,
    required this.onPlaylistContextMenu,
    required this.onOpenAlbum,
    required this.onCreatePlaylist,
    required this.onCollapse,
    required this.onFocusSearch,
    required this.playlists,
    required this.remotePlaylists,
    required this.tracks,
    required this.favoriteIds,
    required this.width,
    this.selectedPlaylistId,
    this.selectedRemotePlaylistId,
    this.compact = false,
  });

  final PulseDestination selected;
  final ValueChanged<PulseDestination> onSelect;
  final ValueChanged<String> onSelectPlaylist;
  final ValueChanged<String> onSelectRemotePlaylist;
  final ValueChanged<String> onPlayPlaylist;
  final ValueChanged<AudioTrack> onPlayTrack;
  final void Function(String playlistId, Offset position) onPlaylistContextMenu;
  final ValueChanged<String> onOpenAlbum;
  final VoidCallback? onCreatePlaylist;
  final VoidCallback onCollapse;
  final VoidCallback onFocusSearch;
  final List<PulsePlaylist> playlists;
  final List<Map<String, dynamic>> remotePlaylists;
  final List<AudioTrack> tracks;
  final Set<String> favoriteIds;
  final String? selectedPlaylistId;
  final String? selectedRemotePlaylistId;
  final double width;
  final bool compact;

  @override
  State<PulseDesktopLibrarySidebar> createState() =>
      _PulseDesktopLibrarySidebarState();
}

class _PulseDesktopLibrarySidebarState
    extends State<PulseDesktopLibrarySidebar> {
  final _search = TextEditingController();
  final _filterScrollController = ScrollController();
  bool _canScrollFiltersBack = false;
  bool _canScrollFiltersForward = false;
  bool _searchOpen = false;
  bool _reverse = false;
  String? _hoveredEntryId;
  List<AudioTrack>? _groupedTracks;
  Map<String, List<AudioTrack>> _albums = const {};
  Map<String, List<AudioTrack>> _artists = const {};

  @override
  void initState() {
    super.initState();
    _filterScrollController.addListener(_updateFilterScrollIndicators);
  }

  @override
  void dispose() {
    _search.dispose();
    _filterScrollController.dispose();
    super.dispose();
  }

  void _updateFilterScrollIndicators() {
    if (!mounted || !_filterScrollController.hasClients) return;
    final position = _filterScrollController.position;
    final back = position.pixels > position.minScrollExtent + 2;
    final forward = position.pixels < position.maxScrollExtent - 2;
    if (back != _canScrollFiltersBack || forward != _canScrollFiltersForward) {
      setState(() {
        _canScrollFiltersBack = back;
        _canScrollFiltersForward = forward;
      });
    }
  }

  void _scrollFilters({required bool forward}) {
    if (!_filterScrollController.hasClients) return;
    final position = _filterScrollController.position;
    final step = position.viewportDimension * 0.75;
    final target = (_filterScrollController.offset + (forward ? step : -step))
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    _filterScrollController.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = PulsePaletteTheme.of(context);
    final byId = {for (final track in widget.tracks) track.id: track};
    if (!identical(_groupedTracks, widget.tracks)) {
      final albums = <String, List<AudioTrack>>{};
      final artists = <String, List<AudioTrack>>{};
      for (final track in widget.tracks) {
        final album = track.album?.trim();
        if (album != null && album.isNotEmpty) {
          final artist = track.artist?.trim() ?? '';
          albums.putIfAbsent('$artist\u0000$album', () => []).add(track);
        }
        if (track.artist?.trim().isNotEmpty == true) {
          artists.putIfAbsent(track.artist!.trim(), () => []).add(track);
        }
      }
      _groupedTracks = widget.tracks;
      _albums = albums;
      _artists = artists;
    }
    final filter = [
      PulseDestination.tracks,
      PulseDestination.albums,
      PulseDestination.artists,
      PulseDestination.playlists,
    ].contains(widget.selected)
        ? widget.selected
        : PulseDestination.library;
    final entries = <_LibraryEntry>[
      if (filter == PulseDestination.library)
        _LibraryEntry(
          title: 'Músicas curtidas',
          subtitle: 'Playlist • ${widget.favoriteIds.length} faixas',
          identity: 'favorites',
          artwork: widget.tracks
              .where((track) => widget.favoriteIds.contains(track.id))
              .take(4)
              .toList(),
          icon: Icons.favorite_rounded,
          selected: widget.selected == PulseDestination.favorites,
          onTap: () => widget.onSelect(PulseDestination.favorites),
        ),
      if (filter == PulseDestination.library ||
          filter == PulseDestination.playlists)
        for (final playlist in widget.playlists)
          _LibraryEntry(
            title: playlist.name,
            subtitle: playlist.folderName == null
                ? 'Playlist • ${playlist.trackIds.length} faixas'
                : '${playlist.folderName} • ${playlist.trackIds.length} faixas',
            identity: playlist.id,
            artwork: [
              for (final id in playlist.trackIds)
                if (byId[id] case final track?) track,
            ],
            icon: Icons.queue_music_rounded,
            selected: widget.selected == PulseDestination.playlists &&
                widget.selectedPlaylistId == playlist.id,
            onTap: () => widget.onSelectPlaylist(playlist.id),
            onPlay: () => widget.onPlayPlaylist(playlist.id),
            onSecondaryTapDown: (position) =>
                widget.onPlaylistContextMenu(playlist.id, position),
          ),
      if (filter == PulseDestination.library ||
          filter == PulseDestination.playlists)
        for (final playlist in widget.remotePlaylists)
          if (playlist['Id']?.toString() case final id?)
            _LibraryEntry(
              title: playlist['Name']?.toString() ?? 'Playlist',
              subtitle: 'Playlist • Jellyfin',
              identity: 'jellyfin-playlist:$id',
              artwork: const [],
              icon: Icons.queue_music_rounded,
              selected: widget.selected == PulseDestination.playlists &&
                  widget.selectedRemotePlaylistId == id,
              onTap: () => widget.onSelectRemotePlaylist(id),
            ),
      if (filter == PulseDestination.library ||
          filter == PulseDestination.albums)
        for (final album in _albums.entries)
          _LibraryEntry(
            title: album.value.first.album!.trim(),
            subtitle:
                'Álbum • ${album.value.first.artist ?? 'Artista não informado'}',
            identity: album.key,
            artwork: album.value,
            icon: Icons.album_rounded,
            selected: false,
            onTap: () => widget.onOpenAlbum(album.key),
          ),
      if (filter == PulseDestination.artists)
        for (final artist in _artists.entries)
          _LibraryEntry(
            title: artist.key,
            subtitle: 'Artista • ${artist.value.length} faixas',
            identity: artist.key,
            artwork: artist.value,
            icon: Icons.person_rounded,
            selected: false,
            onTap: () => widget.onSelect(PulseDestination.artists),
          ),
      if (filter == PulseDestination.tracks)
        for (final track in widget.tracks)
          _LibraryEntry(
            title: track.title,
            subtitle: track.artist ?? 'Arquivo local',
            identity: track.id,
            artwork: [track],
            icon: Icons.music_note_rounded,
            selected: false,
            onTap: () => widget.onPlayTrack(track),
            onPlay: () => widget.onPlayTrack(track),
          ),
    ];
    entries.sort((a, b) => _reverse
        ? b.title.toLowerCase().compareTo(a.title.toLowerCase())
        : a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    final query = normalizeSearchText(_search.text.trim());
    final visible = query.isEmpty
        ? entries
        : entries
            .where((entry) =>
                normalizeSearchText(entry.title).contains(query) ||
                normalizeSearchText(entry.subtitle).contains(query))
            .toList();

    return ColoredBox(
      color: palette.sidebar,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 6),
          child: Row(children: [
            IconButton(
              tooltip: 'Ocultar biblioteca',
              onPressed: widget.onCollapse,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
                child: InkWell(
              onTap: () => widget.onSelect(PulseDestination.library),
              child: Text('Sua biblioteca',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
            )),
            if (widget.onCreatePlaylist case final create?)
              IconButton(
                tooltip: 'Nova playlist',
                onPressed: create,
                icon: const Icon(Icons.add_rounded),
              ),
          ]),
        ),
        SizedBox(
          height: 44,
          child: LayoutBuilder(builder: (context, _) {
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _updateFilterScrollIndicators());
            return Stack(children: [
              ListView(
                controller: _filterScrollController,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                children: [
                  for (final (destination, label) in const [
                    (PulseDestination.library, 'Tudo'),
                    (PulseDestination.tracks, 'Faixas'),
                    (PulseDestination.albums, 'Álbuns'),
                    (PulseDestination.artists, 'Artistas'),
                    (PulseDestination.playlists, 'Playlists'),
                  ])
                    Padding(
                        padding: const EdgeInsets.only(right: 7),
                        child: ChoiceChip(
                          label: Text(label),
                          selected: widget.selected == destination,
                          onSelected: (_) => widget.onSelect(destination),
                        )),
                ],
              ),
              if (_canScrollFiltersBack)
                Positioned(
                  left: 7,
                  top: 4,
                  child: _FilterScrollArrow(
                    icon: Icons.chevron_left_rounded,
                    tooltip: 'Ver filtros anteriores',
                    onPressed: () => _scrollFilters(forward: false),
                  ),
                ),
              if (_canScrollFiltersForward)
                Positioned(
                  right: 7,
                  top: 4,
                  child: _FilterScrollArrow(
                    icon: Icons.chevron_right_rounded,
                    tooltip: 'Ver mais filtros',
                    onPressed: () => _scrollFilters(forward: true),
                  ),
                ),
            ]);
          }),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
          child: Row(children: [
            IconButton(
              tooltip: 'Focar busca da biblioteca',
              visualDensity: VisualDensity.compact,
              onPressed: () {
                setState(() => _searchOpen = !_searchOpen);
              },
              icon: const Icon(Icons.search_rounded, size: 21),
            ),
            if (_searchOpen)
              Expanded(
                  child: SizedBox(
                      height: 36,
                      child: TextField(
                        controller: _search,
                        autofocus: true,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          hintText: 'Buscar em Sua biblioteca',
                          contentPadding: EdgeInsets.symmetric(horizontal: 10),
                        ),
                      )))
            else
              const Spacer(),
            TextButton.icon(
              onPressed: () => setState(() => _reverse = !_reverse),
              icon: const Icon(Icons.sort_rounded, size: 18),
              label: Text(_reverse ? 'Z–A' : 'A–Z'),
            ),
          ]),
        ),
        Expanded(
            child: ListView.builder(
          key: const PageStorageKey<String>('desktop-library-list'),
          padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
          itemCount: visible.length,
          itemBuilder: (context, index) {
            final entry = visible[index];
            return Material(
              color: entry.selected ? palette.selected : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
              child: InkWell(
                onTap: entry.onTap,
                onSecondaryTapDown: entry.onSecondaryTapDown == null
                    ? null
                    : (details) =>
                        entry.onSecondaryTapDown!(details.globalPosition),
                onHover: entry.onPlay == null
                    ? null
                    : (hovering) {
                        final next = hovering ? entry.identity : null;
                        if (_hoveredEntryId != next) {
                          setState(() => _hoveredEntryId = next);
                        }
                      },
                borderRadius: BorderRadius.circular(4),
                hoverColor: palette.hover,
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: 8, vertical: widget.compact ? 3 : 6),
                  child: Row(children: [
                    Stack(alignment: Alignment.center, children: [
                      PulseTrackArtwork(
                        artworkTracks: entry.artwork,
                        title: entry.title,
                        creator: entry.identity,
                        fallbackIcon: entry.icon,
                        size: widget.compact ? 36 : 48,
                        borderRadius: entry.identity == 'favorites' ? 4 : 3,
                      ),
                      if (entry.onPlay != null &&
                          _hoveredEntryId == entry.identity)
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: .42),
                              borderRadius: BorderRadius.circular(
                                  entry.identity == 'favorites' ? 4 : 3),
                            ),
                            child: Center(
                              child: IconButton(
                                tooltip: 'Reproduzir ${entry.title}',
                                visualDensity: VisualDensity.compact,
                                constraints: const BoxConstraints.tightFor(
                                  width: 36,
                                  height: 36,
                                ),
                                padding: EdgeInsets.zero,
                                onPressed: entry.onPlay,
                                icon: const Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 26,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ]),
                    SizedBox(width: widget.compact ? 8 : 12),
                    Expanded(
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: entry.selected ? palette.accent : null,
                                )),
                        Text(entry.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: palette.mutedInk)),
                      ],
                    )),
                  ]),
                ),
              ),
            );
          },
        )),
      ]),
    );
  }
}

class _FilterScrollArrow extends StatelessWidget {
  const _FilterScrollArrow({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF292929),
        shape: const CircleBorder(),
        elevation: 3,
        child: IconButton(
          tooltip: tooltip,
          icon: Icon(icon, size: 24),
          color: Colors.white,
          onPressed: onPressed,
          constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          padding: EdgeInsets.zero,
        ),
      );
}

class _LibraryEntry {
  const _LibraryEntry(
      {required this.title,
      required this.subtitle,
      required this.identity,
      required this.artwork,
      required this.icon,
      required this.selected,
      required this.onTap,
      this.onPlay,
      this.onSecondaryTapDown});
  final String title;
  final String subtitle;
  final String identity;
  final List<AudioTrack> artwork;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onPlay;
  final ValueChanged<Offset>? onSecondaryTapDown;
}
