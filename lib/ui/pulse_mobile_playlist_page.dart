import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/local_artwork_cache.dart';
import '../data/remote_artwork_cache.dart';
import '../domain/audio_track.dart';
import 'pulse_track_artwork.dart';

/// The mobile playlist has one coordinated scroll: its artwork leaves the
/// viewport while navigation and playback stay reachable.
class PulseMobilePlaylistPage extends StatefulWidget {
  const PulseMobilePlaylistPage({
    super.key,
    required this.title,
    required this.owner,
    required this.durationLabel,
    required this.tracks,
    required this.content,
    required this.searchController,
    required this.onSearchChanged,
    required this.onBack,
    required this.onPlay,
    required this.onShuffle,
    required this.shuffleActive,
    required this.onAdd,
    required this.onEdit,
    required this.onRename,
    required this.onMore,
    this.onDownload,
    this.onShare,
  });

  final String title;
  final String owner;
  final String durationLabel;
  final List<AudioTrack> tracks;
  final Widget content;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onBack;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;
  final bool shuffleActive;
  final VoidCallback onAdd;
  final VoidCallback onEdit;
  final VoidCallback onRename;
  final VoidCallback onMore;
  final VoidCallback? onDownload;
  final VoidCallback? onShare;

  @override
  State<PulseMobilePlaylistPage> createState() =>
      _PulseMobilePlaylistPageState();
}

class _PulseMobilePlaylistPageState extends State<PulseMobilePlaylistPage> {
  final ScrollController _outerController = ScrollController();
  bool _collapsed = false;
  Future<Color?>? _coverColor;
  String? _artworkSignature;

  @override
  void initState() {
    super.initState();
    _outerController.addListener(_onScroll);
    _loadColor();
  }

  @override
  void didUpdateWidget(covariant PulseMobilePlaylistPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final signature = _signatureFor(widget.tracks);
    if (signature != _artworkSignature) _loadColor();
  }

  String? _signatureFor(List<AudioTrack> tracks) {
    if (tracks.isEmpty) return null;
    final track = tracks.first;
    return '${track.id}\u0000${track.path}\u0000${track.modifiedAtMillis}\u0000${track.artworkUrl ?? ''}';
  }

  void _loadColor() {
    _artworkSignature = _signatureFor(widget.tracks);
    _coverColor = widget.tracks.isEmpty
        ? Future.value(null)
        : _extractColor(widget.tracks.first);
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
  void dispose() {
    _outerController.removeListener(_onScroll);
    _outerController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_outerController.hasClients) return;
    final position = _outerController.position;
    final collapsed = position.maxScrollExtent > 0 &&
        position.pixels >= position.maxScrollExtent - 8;
    if (collapsed != _collapsed && mounted) {
      setState(() => _collapsed = collapsed);
    }
  }

  Widget _playButton({double size = 48}) => Material(
        color: widget.onPlay == null ? Colors.grey : const Color(0xFF1ED760),
        shape: const CircleBorder(),
        child: InkWell(
          onTap: widget.onPlay,
          customBorder: const CircleBorder(),
          child: SizedBox.square(
            dimension: size,
            child: Icon(Icons.play_arrow_rounded,
                color: Colors.black, size: size * .57),
          ),
        ),
      );

  Widget _mosaic(double size) {
    final unique = <AudioTrack>[];
    final seen = <String>{};
    for (final track in widget.tracks) {
      final identity = track.artworkUrl ?? track.path;
      if (seen.add(identity)) unique.add(track);
      if (unique.length == 4) break;
    }
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: SizedBox.square(
          dimension: size,
          child: unique.isEmpty
              ? const ColoredBox(
                  color: Color(0xFF303030),
                  child: Icon(Icons.queue_music_rounded,
                      color: Colors.white54, size: 82),
                )
              : Column(children: [
                  for (var row = 0; row < 2; row++)
                    Expanded(
                      child: Row(children: [
                        for (var column = 0; column < 2; column++)
                          Expanded(
                            child: unique.length > row * 2 + column
                                ? PulseTrackArtwork(
                                    track: unique[row * 2 + column],
                                    title: unique[row * 2 + column].title,
                                    creator:
                                        unique[row * 2 + column].artist ?? '',
                                    size: size / 2,
                                    borderRadius: 0,
                                  )
                                : const ColoredBox(
                                    color: Color(0xFF292929),
                                    child: Center(
                                      child: Icon(Icons.music_note_rounded,
                                          color: Colors.white30),
                                    ),
                                  ),
                          ),
                      ]),
                    ),
                ]),
        ),
      ),
    );
  }

  Widget _chip(String label, IconData icon, VoidCallback action) => ActionChip(
        avatar: Icon(icon, color: Colors.white, size: 16),
        label: Text(label),
        onPressed: action,
        backgroundColor: const Color(0xFF2B2B2B),
        side: BorderSide.none,
        labelStyle:
            const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      );

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final coverSize = math.min(math.max(width - 96, 160.0), 224.0);
    final palette = Theme.of(context).colorScheme;
    return FutureBuilder<Color?>(
      future: _coverColor,
      builder: (context, snapshot) {
        final hsv = HSVColor.fromColor(snapshot.data ?? palette.primary);
        final vivid = hsv
            .withSaturation(math.max(hsv.saturation, .68))
            .withValue(math.max(hsv.value, .60))
            .toColor();
        final topLeft = Color.lerp(vivid, Colors.black, .14)!;
        final middle = Color.lerp(vivid, Colors.black, .36)!;
        final lower = Color.lerp(vivid, Colors.black, .65)!;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [topLeft, middle, lower, const Color(0xFF121212)],
              stops: const [0, .35, .68, 1],
            ),
          ),
          child: NestedScrollView(
            controller: _outerController,
            headerSliverBuilder: (context, innerBoxIsScrolled) => [
              SliverAppBar(
                pinned: true,
                toolbarHeight: 64,
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                scrolledUnderElevation: 0,
                flexibleSpace: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [topLeft, middle],
                    ),
                  ),
                ),
                leading: IconButton(
                  tooltip: 'Voltar para playlists',
                  onPressed: widget.onBack,
                  icon:
                      const Icon(Icons.arrow_back_rounded, color: Colors.white),
                ),
                title: AnimatedOpacity(
                  opacity: _collapsed ? 1 : 0,
                  duration: const Duration(milliseconds: 150),
                  child: Text(widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w800)),
                ),
                actions: [
                  if (_collapsed)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _playButton(size: 44),
                    )
                  else
                    IconButton(
                      tooltip: 'Mais opções da playlist',
                      onPressed: widget.onMore,
                      icon: const Icon(Icons.more_vert_rounded,
                          color: Colors.white),
                    ),
                ],
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: widget.searchController,
                        onChanged: widget.onSearchChanged,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: 'Procurar nesta playlist',
                          hintStyle: const TextStyle(color: Colors.white70),
                          prefixIcon: const Icon(Icons.search_rounded,
                              color: Colors.white),
                          suffixIcon: widget.searchController.text.isEmpty
                              ? null
                              : IconButton(
                                  tooltip: 'Limpar busca',
                                  onPressed: () {
                                    widget.searchController.clear();
                                    widget.onSearchChanged('');
                                  },
                                  icon: const Icon(Icons.close_rounded),
                                ),
                          filled: true,
                          fillColor: Colors.white.withValues(alpha: .11),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(5),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 16),
                      _mosaic(coverSize),
                      const SizedBox(height: 18),
                      Text(widget.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 27,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Row(children: [
                        const CircleAvatar(
                          radius: 12,
                          backgroundColor: Color(0xFF1ED760),
                          child: Icon(Icons.person_rounded,
                              size: 16, color: Colors.black),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(widget.owner,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700)),
                        ),
                      ]),
                      const SizedBox(height: 6),
                      Text(widget.durationLabel,
                          style: const TextStyle(color: Colors.white70)),
                      const SizedBox(height: 6),
                      Row(children: [
                        if (widget.tracks.isNotEmpty)
                          PulseTrackArtwork(
                            track: widget.tracks.first,
                            title: widget.tracks.first.title,
                            size: 34,
                            borderRadius: 3,
                          ),
                        if (widget.tracks.isNotEmpty) const SizedBox(width: 6),
                        if (widget.onDownload != null)
                          IconButton(
                            tooltip: 'Baixar faixas da playlist',
                            onPressed: widget.onDownload,
                            icon: const Icon(
                                Icons.download_for_offline_outlined,
                                size: 20),
                            color: Colors.white70,
                          ),
                        if (widget.onShare != null)
                          IconButton(
                            tooltip: 'Compartilhar playlist',
                            onPressed: widget.onShare,
                            icon: const Icon(Icons.share_outlined, size: 20),
                            color: Colors.white70,
                          ),
                        const Spacer(),
                        if (widget.onShuffle != null)
                          IconButton(
                            tooltip: 'Reproduzir aleatoriamente',
                            onPressed: widget.onShuffle,
                            icon: const Icon(Icons.shuffle_rounded, size: 20),
                            color: widget.shuffleActive
                                ? const Color(0xFF1ED760)
                                : Colors.white70,
                          ),
                        _playButton(),
                      ]),
                      const SizedBox(height: 4),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(children: [
                          _chip('Adicionar', Icons.add_rounded, widget.onAdd),
                          const SizedBox(width: 8),
                          _chip('Editar', Icons.format_list_bulleted_rounded,
                              widget.onEdit),
                          const SizedBox(width: 8),
                          _chip('Nome e detalhes', Icons.edit_outlined,
                              widget.onRename),
                        ]),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            body: Stack(
              fit: StackFit.expand,
              children: [
                const ColoredBox(color: Color(0xFF121212)),
                if (!_collapsed)
                  Align(
                    alignment: Alignment.topCenter,
                    child: SizedBox(
                      height: 210,
                      width: double.infinity,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color.lerp(middle, lower, .62)!,
                              const Color(0x00121212),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                widget.content,
              ],
            ),
          ),
        );
      },
    );
  }
}
