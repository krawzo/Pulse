import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../domain/audio_track.dart';
import '../domain/library_search.dart';
import 'pulse_mobile_track_swipe.dart';
import 'pulse_track_artwork.dart';

/// Suggestions for a playlist. The caller chooses the allowed source and
/// persists additions; this panel never writes directly to local or remote data.
class PulsePlaylistAddPanel extends StatefulWidget {
  const PulsePlaylistAddPanel({
    super.key,
    required this.tracks,
    required this.existingIds,
    required this.favoriteIds,
    required this.onAdd,
    required this.onClose,
    this.onPlayNext,
    this.query = '',
    this.onQueryChanged,
  });

  final List<AudioTrack> tracks;
  final Set<String> existingIds;
  final Set<String> favoriteIds;
  final Future<bool> Function(AudioTrack) onAdd;
  final VoidCallback onClose;
  final ValueChanged<AudioTrack>? onPlayNext;
  final String query;
  final ValueChanged<String>? onQueryChanged;

  @override
  State<PulsePlaylistAddPanel> createState() => _PulsePlaylistAddPanelState();
}

class _PulsePlaylistAddPanelState extends State<PulsePlaylistAddPanel> {
  late final TextEditingController _searchController;
  final Set<String> _addedIds = {};
  String? _addingId;
  bool _favoritesOnly = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.query);
  }

  @override
  void didUpdateWidget(covariant PulsePlaylistAddPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != _searchController.text) {
      _searchController.value = TextEditingValue(
        text: widget.query,
        selection: TextSelection.collapsed(offset: widget.query.length),
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _add(AudioTrack track) async {
    if (_addingId != null || _addedIds.contains(track.id)) return;
    setState(() => _addingId = track.id);
    try {
      final added = await widget.onAdd(track);
      if (mounted && added) setState(() => _addedIds.add(track.id));
    } finally {
      if (mounted) setState(() => _addingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    final available = widget.tracks.where((track) {
      if (widget.existingIds.contains(track.id) || _addedIds.contains(track.id)) {
        return false;
      }
      if (_favoritesOnly && !widget.favoriteIds.contains(track.id)) {
        return false;
      }
      return query.isEmpty || trackMatchesLibraryQuery(track, query);
    }).toList(growable: false);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 8, 6),
        child: Row(children: [
          const Expanded(
            child: Text('Adicionar à playlist',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ),
          IconButton(
            tooltip: 'Fechar',
            onPressed: widget.onClose,
            icon: const Icon(Icons.close_rounded),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: TextField(
          controller: _searchController,
          onChanged: (value) {
            setState(() {});
            widget.onQueryChanged?.call(value);
          },
          decoration: InputDecoration(
            hintText: 'Buscar músicas',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpar busca',
                    onPressed: () {
                      _searchController.clear();
                      setState(() {});
                      widget.onQueryChanged?.call('');
                    },
                    icon: const Icon(Icons.close_rounded),
                  ),
            filled: true,
            fillColor: const Color(0xFF292929),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(24),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(children: [
          ChoiceChip(
            label: const Text('Das suas faixas'),
            selected: !_favoritesOnly,
            onSelected: (_) => setState(() => _favoritesOnly = false),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('Músicas curtidas'),
            selected: _favoritesOnly,
            onSelected: (_) => setState(() => _favoritesOnly = true),
          ),
        ]),
      ),
      const SizedBox(height: 8),
      const Divider(height: 1),
      Expanded(
        child: available.isEmpty
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    query.isNotEmpty
                        ? 'Nenhuma música encontrada.'
                        : _favoritesOnly
                            ? 'Nenhuma música curtida disponível.'
                            : 'Todas as suas faixas já estão nesta playlist.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white60),
                  ),
                ),
              )
            : ListView.builder(
                itemCount: available.length,
                itemBuilder: (context, index) {
                  final track = available[index];
                  final tile = ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    leading: PulseTrackArtwork(
                      track: track,
                      title: track.title,
                      creator: track.artist ?? '',
                      size: 44,
                    ),
                    title: Text(track.title,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(track.artist ?? 'Artista não informado',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      tooltip: 'Adicionar ${track.title}',
                      onPressed: _addingId == null ? () => _add(track) : null,
                      icon: _addingId == track.id
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_circle_outline_rounded),
                    ),
                  );
                  if (widget.onPlayNext == null ||
                      defaultTargetPlatform != TargetPlatform.android) {
                    return tile;
                  }
                  return PulseMobileTrackSwipe(
                    key: ValueKey('playlist-add-swipe:${track.id}'),
                    onPlayNext: () => widget.onPlayNext!(track),
                    child: tile,
                  );
                },
              ),
      ),
    ]);
  }
}
