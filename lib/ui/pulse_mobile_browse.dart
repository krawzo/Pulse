import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../domain/audio_track.dart';
import '../domain/library_search.dart';
import 'pulse_mobile_navigation.dart';
import 'pulse_mobile_track_swipe.dart';
import 'pulse_track_artwork.dart';

enum _LibraryFilter { all, playlists, albums, artists, tracks }

/// Mobile browsing uses the same Pulse library and playback actions as desktop.
class PulseMobileBrowse extends StatefulWidget {
  const PulseMobileBrowse({
    super.key,
    required this.tab,
    required this.tracks,
    required this.newTracks,
    required this.onOpenInsights,
    required this.onMarkNewSeen,
    required this.playlists,
    required this.remotePlaylists,
    this.remotePlaylistPrefix = 'jellyfin',
    required this.favoriteIds,
    required this.currentTrackId,
    required this.query,
    required this.searchController,
    required this.onQueryChanged,
    required this.onClearQuery,
    required this.onOpenSettings,
    required this.onOpenAccount,
    this.accountName,
    this.accountImageUrl,
    required this.onOpenFavorites,
    required this.onOpenPlaylist,
    required this.onOpenRemotePlaylist,
    required this.onPlaylistMore,
    required this.onOpenAlbum,
    required this.onOpenArtist,
    required this.onImportMusic,
    required this.onCreatePlaylist,
    required this.onPlayTrack,
    required this.onPlayNext,
    required this.onTrackMore,
    required this.onSelectTab,
  });

  final PulseMobileTab tab;
  final List<AudioTrack> tracks;
  final List<AudioTrack> newTracks;
  final VoidCallback onOpenInsights;
  final VoidCallback onMarkNewSeen;
  final List<PulsePlaylist> playlists;
  final List<Map<String, dynamic>> remotePlaylists;
  final String remotePlaylistPrefix;
  final Set<String> favoriteIds;
  final String? currentTrackId;
  final String query;
  final TextEditingController searchController;
  final ValueChanged<String> onQueryChanged;
  final VoidCallback onClearQuery;
  final VoidCallback onOpenSettings;
  final VoidCallback onOpenAccount;
  final String? accountName;
  final String? accountImageUrl;
  final VoidCallback onOpenFavorites;
  final ValueChanged<String> onOpenPlaylist;
  final ValueChanged<String> onOpenRemotePlaylist;
  final ValueChanged<String> onPlaylistMore;
  final ValueChanged<AudioTrack> onOpenAlbum;
  final ValueChanged<AudioTrack> onOpenArtist;
  final VoidCallback onImportMusic;
  final VoidCallback onCreatePlaylist;
  final ValueChanged<AudioTrack> onPlayTrack;
  final ValueChanged<AudioTrack> onPlayNext;
  final ValueChanged<AudioTrack> onTrackMore;
  final ValueChanged<PulseMobileTab> onSelectTab;

  @override
  State<PulseMobileBrowse> createState() => _PulseMobileBrowseState();
}

class _PulseMobileBrowseState extends State<PulseMobileBrowse> {
  _LibraryFilter _filter = _LibraryFilter.all;
  bool _filterRestored = false;
  List<AudioTrack>? _indexedTracks;
  Map<String, List<AudioTrack>> _cachedAlbums = const {};
  Map<String, List<AudioTrack>> _cachedArtists = const {};
  List<AudioTrack> _alphabeticalTracks = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_filterRestored) return;
    _filterRestored = true;
    final saved = PageStorage.of(context)
        .readState(context, identifier: 'pulse-mobile-library-filter');
    if (saved is int && saved >= 0 && saved < _LibraryFilter.values.length) {
      _filter = _LibraryFilter.values[saved];
    }
  }

  void _setLibraryFilter(_LibraryFilter filter) {
    if (_filter == filter) return;
    setState(() => _filter = filter);
    PageStorage.of(context).writeState(context, filter.index,
        identifier: 'pulse-mobile-library-filter');
  }

  void _indexTracks() {
    if (identical(_indexedTracks, widget.tracks)) return;
    final albums = <String, List<AudioTrack>>{};
    final artists = <String, List<AudioTrack>>{};
    for (final track in widget.tracks) {
      final album = track.album?.trim();
      if (album != null && album.isNotEmpty) {
        albums
            .putIfAbsent('${track.artist ?? ''}\u0000$album', () => [])
            .add(track);
      }
      final artist = track.artist?.trim();
      if (artist != null && artist.isNotEmpty) {
        artists.putIfAbsent(artist, () => []).add(track);
      }
    }
    final alphabetical = List<AudioTrack>.of(widget.tracks)
      ..sort((first, second) {
        final byTitle = normalizeSearchText(first.title.trim())
            .compareTo(normalizeSearchText(second.title.trim()));
        if (byTitle != 0) return byTitle;
        final byArtist = normalizeSearchText(first.artist ?? '')
            .compareTo(normalizeSearchText(second.artist ?? ''));
        return byArtist != 0 ? byArtist : first.id.compareTo(second.id);
      });
    _indexedTracks = widget.tracks;
    _cachedAlbums = albums;
    _cachedArtists = artists;
    _alphabeticalTracks = alphabetical;
  }

  Map<String, List<AudioTrack>> get _albums {
    _indexTracks();
    return _cachedAlbums;
  }

  Map<String, List<AudioTrack>> get _artists {
    _indexTracks();
    return _cachedArtists;
  }

  List<AudioTrack> _tracksAlphabetically() {
    _indexTracks();
    return _alphabeticalTracks;
  }

  @override
  Widget build(BuildContext context) => switch (widget.tab) {
        PulseMobileTab.home => _home(),
        PulseMobileTab.search => _search(),
        PulseMobileTab.library => _library(),
      };

  Widget _header(String title, {VoidCallback? action, IconData? icon}) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 16, 12),
        child: Row(children: [
          Expanded(
            child: Text(title,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 27,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5)),
          ),
          IconButton(
            tooltip:
                widget.accountName == null ? 'Entrar no Pulse' : 'Sua conta',
            onPressed: widget.onOpenAccount,
            icon: CircleAvatar(
              radius: 16,
              backgroundColor: const Color(0xFF1ED760),
              foregroundImage: widget.accountImageUrl == null
                  ? null
                  : NetworkImage(widget.accountImageUrl!),
              child: widget.accountName?.trim().isNotEmpty == true
                  ? Text(widget.accountName!.trim()[0].toUpperCase(),
                      style: const TextStyle(
                          color: Colors.black, fontWeight: FontWeight.w800))
                  : const Icon(Icons.person_rounded,
                      color: Colors.black, size: 20),
            ),
          ),
          if (action != null)
            IconButton(
              onPressed: action,
              icon: Icon(icon ?? Icons.settings_outlined),
              color: Colors.white,
              tooltip: icon == Icons.add_rounded
                  ? 'Criar playlist'
                  : 'Configurações',
            ),
        ]),
      );

  Widget _section(String title, {VoidCallback? onSeeAll}) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 18, 12),
        child: Row(children: [
          Expanded(
              child: Text(title,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.w800))),
          if (onSeeAll != null)
            TextButton(
                onPressed: onSeeAll,
                child: const Text('Ver tudo',
                    style: TextStyle(color: Colors.white70))),
        ]),
      );

  Widget _home() {
    final favoriteTracks = widget.tracks
        .where((track) => widget.favoriteIds.contains(track.id))
        .toList(growable: false);
    final albumEntries = _albums.entries.take(12).toList(growable: false);
    final shortcuts = <({
      String title,
      AudioTrack? art,
      IconData icon,
      VoidCallback tap,
      VoidCallback? more
    })>[
      (
        title: 'Músicas curtidas',
        art: favoriteTracks.firstOrNull,
        icon: Icons.favorite_rounded,
        tap: widget.onOpenFavorites,
        more: null,
      ),
      for (final playlist in widget.playlists.take(7))
        (
          title: playlist.name,
          art: _firstPlaylistTrack(playlist),
          icon: Icons.queue_music_rounded,
          tap: () => widget.onOpenPlaylist(playlist.id),
          more: () => widget.onPlaylistMore(playlist.id),
        ),
      for (final playlist in widget.remotePlaylists.take(7))
        if (playlist['Id']?.toString() case final id?)
          (
            title: playlist['Name']?.toString() ?? 'Playlist',
            art: null,
            icon: Icons.queue_music_rounded,
            tap: () => widget.onOpenRemotePlaylist(id),
            more: null,
          ),
    ];
    return ListView(
      padding: const EdgeInsets.only(bottom: 180),
      children: [
        _header('Pulse', action: widget.onOpenSettings),
        SizedBox(
          height: 44,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            scrollDirection: Axis.horizontal,
            children: [
              _homeChip('Tudo', null, selected: true),
              _homeChip('Curtidas', widget.onOpenFavorites),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (shortcuts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LayoutBuilder(builder: (context, limits) {
              final tileWidth = (limits.maxWidth - 8) / 2;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final shortcut in shortcuts)
                    SizedBox(
                      width: tileWidth,
                      child: Material(
                        color: const Color(0xFF242424),
                        borderRadius: BorderRadius.circular(6),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          onTap: shortcut.tap,
                          onLongPress: shortcut.more,
                          child: SizedBox(
                            height: 56,
                            child: Row(children: [
                              shortcut.art == null
                                  ? Container(
                                      width: 56,
                                      height: 56,
                                      color: const Color(0xFF384873),
                                      child: Icon(shortcut.icon,
                                          color: Colors.white))
                                  : PulseTrackArtwork(
                                      track: shortcut.art,
                                      title: shortcut.title,
                                      size: 56,
                                      borderRadius: 0),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(shortcut.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700)),
                              ),
                              const SizedBox(width: 5),
                            ]),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            }),
          ),
        _section('Novas na biblioteca', onSeeAll: widget.onOpenInsights),
        if (widget.newTracks.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text('Nenhuma faixa nova desde a última atualização.',
                style: TextStyle(color: Colors.white70)),
          )
        else ...[
          for (final track in widget.newTracks.take(5)) _trackTile(track),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: widget.onMarkNewSeen,
                child: const Text('Marcar como vistas'),
              ),
            ),
          ),
        ],
        if (albumEntries.isNotEmpty) ...[
          _section('Seus álbuns'),
          SizedBox(
            height: 192,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              scrollDirection: Axis.horizontal,
              itemCount: albumEntries.length,
              separatorBuilder: (_, index) => const SizedBox(width: 14),
              itemBuilder: (context, index) {
                final tracks = albumEntries[index].value;
                final first = tracks.first;
                return SizedBox(
                  width: 138,
                  child: InkWell(
                    onTap: () => widget.onOpenAlbum(first),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PulseTrackArtwork(
                            track: first,
                            title: first.album!,
                            creator: first.artist ?? '',
                            size: 138,
                            borderRadius: 6),
                        const SizedBox(height: 7),
                        Text(first.album!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700)),
                        Text(first.artist ?? 'Álbum',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white60, fontSize: 12)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
        _section('Para ouvir agora'),
        if (widget.tracks.isEmpty)
          _empty(
              'Sua música começa aqui',
              widget.accountName == null
                  ? 'Entre na sua conta para ver suas músicas.'
                  : 'Atualize a biblioteca nas configurações para ver suas músicas.',
              onAction: widget.accountName == null
                  ? widget.onOpenAccount
                  : widget.onOpenSettings,
              actionLabel: widget.accountName == null
                  ? 'Entrar na conta'
                  : 'Abrir configurações')
        else
          for (final track in widget.tracks.take(12)) _trackTile(track),
        if (widget.tracks.isNotEmpty)
          TextButton(
            onPressed: () => widget.onSelectTab(PulseMobileTab.library),
            child: const Text('Ver sua biblioteca'),
          ),
      ],
    );
  }

  Widget _homeChip(String label, VoidCallback? onTap,
          {bool selected = false}) =>
      Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ActionChip(
          label: Text(label),
          onPressed: onTap ?? () {},
          backgroundColor:
              selected ? const Color(0xFF1ED760) : const Color(0xFF242424),
          labelStyle: TextStyle(
              color: selected ? Colors.black : Colors.white,
              fontWeight: FontWeight.w600),
          side: BorderSide.none,
        ),
      );

  AudioTrack? _firstPlaylistTrack(PulsePlaylist playlist) {
    final ids = playlist.trackIds.toSet();
    for (final track in widget.tracks) {
      if (ids.contains(track.id)) return track;
    }
    return null;
  }

  Widget _search() {
    final query = normalizeSearchText(widget.query.trim());
    final songs = query.isEmpty
        ? const <AudioTrack>[]
        : widget.tracks
            .where((track) => trackMatchesLibraryQuery(track, query))
            .take(60)
            .toList(growable: false);
    final playlists = query.isEmpty
        ? const <PulsePlaylist>[]
        : widget.playlists
            .where((playlist) =>
                normalizeSearchText(playlist.name).contains(query))
            .toList(growable: false);
    final remotePlaylists = query.isEmpty
        ? const <Map<String, dynamic>>[]
        : widget.remotePlaylists
            .where((playlist) =>
                normalizeSearchText(playlist['Name']?.toString() ?? '')
                    .contains(query))
            .toList(growable: false);
    final albums = query.isEmpty
        ? const <List<AudioTrack>>[]
        : _albums.values
            .where((group) =>
                normalizeSearchText(group.first.album!).contains(query) ||
                normalizeSearchText(group.first.artist ?? '').contains(query))
            .take(15)
            .toList(growable: false);
    final artists = query.isEmpty
        ? const <List<AudioTrack>>[]
        : _artists.values
            .where((group) =>
                normalizeSearchText(group.first.artist!).contains(query))
            .take(15)
            .toList(growable: false);
    return ListView(
      padding: const EdgeInsets.only(bottom: 180),
      children: [
        _header('Buscar'),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: TextField(
            controller: widget.searchController,
            onChanged: widget.onQueryChanged,
            style: const TextStyle(color: Colors.black),
            decoration: InputDecoration(
              hintText: 'O que você quer ouvir?',
              hintStyle: const TextStyle(color: Colors.black54),
              prefixIcon: const Icon(Icons.search_rounded, color: Colors.black),
              suffixIcon: query.isEmpty
                  ? null
                  : IconButton(
                      onPressed: widget.onClearQuery,
                      icon:
                          const Icon(Icons.close_rounded, color: Colors.black),
                      tooltip: 'Limpar busca'),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(vertical: 14),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(7),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
        if (query.isEmpty) ...[
          _section('Explore sua biblioteca'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LayoutBuilder(builder: (context, limits) {
              final width = (limits.maxWidth - 8) / 2;
              return Wrap(spacing: 8, runSpacing: 8, children: [
                _category('Músicas curtidas', const Color(0xFF5445A6),
                    Icons.favorite_rounded, width, widget.onOpenFavorites),
                _category(
                    'Playlists',
                    const Color(0xFF8B3A61),
                    Icons.queue_music_rounded,
                    width,
                    () => _openLibraryFilter(_LibraryFilter.playlists)),
                _category(
                    'Álbuns',
                    const Color(0xFF386B72),
                    Icons.album_rounded,
                    width,
                    () => _openLibraryFilter(_LibraryFilter.albums)),
                _category(
                    'Artistas',
                    const Color(0xFF5A4F91),
                    Icons.mic_rounded,
                    width,
                    () => _openLibraryFilter(_LibraryFilter.artists)),
              ]);
            }),
          ),
        ] else if (songs.isEmpty &&
            playlists.isEmpty &&
            remotePlaylists.isEmpty &&
            albums.isEmpty &&
            artists.isEmpty)
          _empty('Nenhum resultado',
              'Tente outro nome de faixa, artista ou álbum.')
        else ...[
          if (playlists.isNotEmpty || remotePlaylists.isNotEmpty) ...[
            _section('Playlists'),
            for (final playlist in playlists)
              _collectionTile(
                playlist.name,
                'Playlist • ${playlist.trackIds.length} faixas',
                _firstPlaylistTrack(playlist),
                () => widget.onOpenPlaylist(playlist.id),
                onLongPress: () => widget.onPlaylistMore(playlist.id),
                fallback: Icons.queue_music_rounded,
              ),
            for (final playlist in remotePlaylists)
              if (playlist['Id']?.toString() case final id?)
                _collectionTile(
                  playlist['Name']?.toString() ?? 'Playlist',
                  'Playlist',
                  null,
                  () => widget.onOpenRemotePlaylist(id),
                  fallback: Icons.queue_music_rounded,
                ),
          ],
          if (artists.isNotEmpty) ...[
            _section('Artistas'),
            for (final group in artists)
              _collectionTile(
                group.first.artist!,
                'Artista',
                group.first,
                () => widget.onOpenArtist(group.first),
                round: true,
              ),
          ],
          if (albums.isNotEmpty) ...[
            _section('Álbuns'),
            for (final group in albums)
              _collectionTile(
                group.first.album!,
                'Álbum • ${group.first.artist ?? 'Artista não informado'}',
                group.first,
                () => widget.onOpenAlbum(group.first),
              ),
          ],
          if (songs.isNotEmpty) ...[
            _section('Faixas'),
            for (final track in songs) _trackTile(track),
          ],
        ],
      ],
    );
  }

  void _openLibraryFilter(_LibraryFilter filter) {
    _setLibraryFilter(filter);
    widget.onSelectTab(PulseMobileTab.library);
  }

  Widget _category(String name, Color color, IconData icon, double width,
          VoidCallback onTap) =>
      SizedBox(
        width: width,
        height: 104,
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(6),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Stack(children: [
                Align(
                    alignment: Alignment.topLeft,
                    child: Text(name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w800))),
                Align(
                    alignment: Alignment.bottomRight,
                    child: Icon(icon,
                        size: 42, color: Colors.white.withValues(alpha: .4))),
              ]),
            ),
          ),
        ),
      );

  Widget _library() {
    if (_filter == _LibraryFilter.tracks) {
      final tracks = _tracksAlphabetically();
      return ListView.builder(
        key: const PageStorageKey('pulse-mobile-library-tracks'),
        padding: const EdgeInsets.only(bottom: 180),
        itemCount: tracks.isEmpty ? 4 : tracks.length + 3,
        itemBuilder: (context, index) => switch (index) {
          0 => _header('Sua biblioteca',
              action: widget.onCreatePlaylist, icon: Icons.add_rounded),
          1 => _libraryFilters(),
          2 => _librarySectionLabel(),
          _ => tracks.isEmpty
              ? _empty('Nenhuma faixa na biblioteca',
                  'Atualize sua biblioteca para encontrar suas músicas.')
              : _trackTile(tracks[index - 3]),
        },
      );
    }
    final albums = _albums.values.toList(growable: false);
    final artists = _artists.values.toList(growable: false);
    final playlistGroups = <String, List<PulsePlaylist>>{};
    for (final playlist in widget.playlists) {
      playlistGroups
          .putIfAbsent(playlist.folderName?.trim() ?? '', () => [])
          .add(playlist);
    }
    final playlistFolders = playlistGroups.keys.toList()
      ..sort((first, second) {
        if (first.isEmpty) return -1;
        if (second.isEmpty) return 1;
        return first.toLowerCase().compareTo(second.toLowerCase());
      });
    return ListView(
      key: PageStorageKey('pulse-mobile-library-${_filter.name}'),
      padding: const EdgeInsets.only(bottom: 180),
      children: [
        _header('Sua biblioteca',
            action: widget.onCreatePlaylist, icon: Icons.add_rounded),
        _libraryFilters(),
        _librarySectionLabel(),
        if (_filter == _LibraryFilter.all) ...[
          _collectionTile(
              'Músicas curtidas',
              'Playlist • ${widget.favoriteIds.length} músicas',
              null,
              widget.onOpenFavorites,
              fallback: Icons.favorite_rounded,
              fallbackColor: const Color(0xFF5445A6)),
        ],
        if (_filter == _LibraryFilter.all ||
            _filter == _LibraryFilter.playlists)
          for (final folder in playlistFolders) ...[
            if (folder.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Row(children: [
                  const Icon(Icons.folder_outlined,
                      size: 19, color: Colors.white70),
                  const SizedBox(width: 8),
                  Text(folder,
                      style: const TextStyle(
                          color: Colors.white70, fontWeight: FontWeight.w700)),
                ]),
              ),
            for (final playlist in playlistGroups[folder]!)
              _collectionTile(
                playlist.name,
                'Playlist • ${playlist.trackIds.length} faixas',
                _firstPlaylistTrack(playlist),
                () => widget.onOpenPlaylist(playlist.id),
                onLongPress: () => widget.onPlaylistMore(playlist.id),
                fallback: Icons.queue_music_rounded,
              ),
          ],
        if (_filter == _LibraryFilter.all ||
            _filter == _LibraryFilter.playlists)
          for (final playlist in widget.remotePlaylists)
            if (playlist['Id']?.toString() case final id?)
              _collectionTile(
                playlist['Name']?.toString() ?? 'Playlist',
                'Playlist',
                null,
                () => widget.onOpenRemotePlaylist(id),
                onLongPress: () =>
                    widget.onPlaylistMore('${widget.remotePlaylistPrefix}:$id'),
                fallback: Icons.queue_music_rounded,
              ),
        if (_filter == _LibraryFilter.albums)
          for (final album in albums)
            _collectionTile(
              album.first.album!,
              'Álbum • ${album.first.artist ?? 'Artista não informado'}',
              album.first,
              () => widget.onOpenAlbum(album.first),
            ),
        if (_filter == _LibraryFilter.artists)
          for (final artist in artists)
            _collectionTile(
              artist.first.artist!,
              'Artista • ${artist.length} faixas',
              artist.first,
              () => widget.onOpenArtist(artist.first),
              round: true,
            ),
        if (widget.tracks.isEmpty &&
            widget.playlists.isEmpty &&
            widget.remotePlaylists.isEmpty)
          _empty(
              'Sua biblioteca começa aqui',
              widget.accountName == null
                  ? 'Entre na sua conta para ver as músicas do Jellyfin.'
                  : 'Atualize sua biblioteca nas configurações.',
              onAction: widget.accountName == null
                  ? widget.onOpenAccount
                  : widget.onOpenSettings,
              actionLabel: widget.accountName == null
                  ? 'Entrar na conta'
                  : 'Abrir configurações'),
      ],
    );
  }

  Widget _libraryFilters() => SizedBox(
        height: 43,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          children: [
            _filterChip('Tudo', _LibraryFilter.all),
            _filterChip('Playlists', _LibraryFilter.playlists),
            _filterChip('Álbuns', _LibraryFilter.albums),
            _filterChip('Artistas', _LibraryFilter.artists),
            _filterChip('Faixas', _LibraryFilter.tracks),
          ],
        ),
      );

  Widget _librarySectionLabel() => const Padding(
        padding: EdgeInsets.fromLTRB(22, 20, 22, 8),
        child: Text('Sua música',
            style: TextStyle(color: Colors.white60, fontSize: 13)),
      );

  Widget _filterChip(String text, _LibraryFilter filter) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(
          label: Text(text),
          selected: _filter == filter,
          onSelected: (_) => _setLibraryFilter(filter),
          selectedColor: const Color(0xFF1ED760),
          labelStyle: TextStyle(
              color: _filter == filter ? Colors.black : Colors.white,
              fontWeight: FontWeight.w600),
          backgroundColor: const Color(0xFF242424),
          side: BorderSide.none,
        ),
      );

  Widget _collectionTile(
      String title, String subtitle, AudioTrack? art, VoidCallback onTap,
      {IconData fallback = Icons.album_rounded,
      Color fallbackColor = const Color(0xFF333333),
      bool round = false,
      VoidCallback? onLongPress}) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 3),
      onTap: onTap,
      onLongPress: onLongPress,
      leading: art == null
          ? Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                  color: fallbackColor,
                  borderRadius: BorderRadius.circular(round ? 27 : 5)),
              child: Icon(fallback, color: Colors.white))
          : PulseTrackArtwork(
              track: art, title: title, size: 54, borderRadius: round ? 27 : 5),
      title: Text(title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.white60)),
    );
  }

  Widget _trackTile(AudioTrack track) => PulseMobileTrackSwipe(
        key: ValueKey('browse-swipe:${track.id}'),
        enabled: defaultTargetPlatform == TargetPlatform.android,
        onPlayNext: () => widget.onPlayNext(track),
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(20, 2, 10, 2),
          onTap: () => widget.onPlayTrack(track),
          leading: PulseTrackArtwork(
              track: track,
              title: track.title,
              creator: track.artist ?? '',
              size: 52,
              borderRadius: 5),
          title: Text(track.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: widget.currentTrackId == track.id
                      ? const Color(0xFF1ED760)
                      : Colors.white,
                  fontWeight: FontWeight.w600)),
          subtitle: Text(
              [
                track.artist?.trim().isNotEmpty == true
                    ? track.artist!.trim()
                    : 'Artista não informado',
                if (track.genre?.trim().isNotEmpty == true) track.genre!.trim(),
              ].join(' • '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white60)),
          trailing: IconButton(
            onPressed: () => widget.onTrackMore(track),
            icon: const Icon(Icons.more_vert_rounded),
            color: Colors.white70,
            tooltip: 'Mais opções para ${track.title}',
          ),
        ),
      );

  Widget _empty(String title, String message,
          {VoidCallback? onAction,
          String actionLabel = 'Abrir configurações'}) =>
      Padding(
        padding: const EdgeInsets.all(30),
        child: Column(children: [
          const Icon(Icons.library_music_rounded,
              color: Colors.white54, size: 40),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700)),
          const SizedBox(height: 7),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white60)),
          if (onAction != null) ...[
            const SizedBox(height: 16),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ]),
      );
}
