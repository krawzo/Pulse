import 'package:flutter/material.dart';

import '../domain/audio_track.dart';
import '../domain/library_search.dart';
import '../state/jellyfin_controller.dart';

/// Read-only catalog checks. Nothing here edits or retags the music files.
class PulseLibraryInsights extends StatefulWidget {
  const PulseLibraryInsights({super.key, required this.jellyfin});

  final JellyfinController jellyfin;

  @override
  State<PulseLibraryInsights> createState() => _PulseLibraryInsightsState();
}

class _PulseLibraryInsightsState extends State<PulseLibraryInsights> {
  bool _scanningLyrics = false;
  int _checkedLyrics = 0;
  final List<AudioTrack> _withoutLyrics = [];

  Future<void> _scanLyrics() async {
    if (_scanningLyrics) return;
    setState(() {
      _scanningLyrics = true;
      _checkedLyrics = 0;
      _withoutLyrics.clear();
    });
    final tracks = widget.jellyfin.tracks
        .where((track) => track.source == AudioSource.jellyfin)
        .toList(growable: false);
    for (final track in tracks) {
      if (!mounted) return;
      try {
        if (await widget.jellyfin.lyricsFor(track) == null) {
          _withoutLyrics.add(track);
        }
      } on Object {
        // A connection error is inconclusive, so do not count this track.
      }
      if (mounted) setState(() => _checkedLyrics++);
    }
    if (mounted) setState(() => _scanningLyrics = false);
  }

  @override
  Widget build(BuildContext context) {
    final tracks = widget.jellyfin.tracks
        .where((track) => track.source == AudioSource.jellyfin)
        .toList(growable: false);
    final withoutArtist = tracks
        .where((track) => track.artist?.trim().isNotEmpty != true)
        .toList(growable: false);
    final withoutAlbum = tracks
        .where((track) => track.album?.trim().isNotEmpty != true)
        .toList(growable: false);
    final withoutGenre = tracks
        .where((track) => track.genre?.trim().isNotEmpty != true)
        .toList(growable: false);
    final genericGenre = tracks
        .where((track) => {'music', 'musica', 'unknown', 'desconhecido'}
            .contains(normalizeSearchText(track.genre ?? '')))
        .toList(growable: false);
    final groups = <String, List<AudioTrack>>{};
    for (final track in tracks) {
      final key = '${normalizeSearchText(track.title)}|'
          '${normalizeSearchText(track.artist ?? '')}|'
          '${(track.durationMillis ?? 0) ~/ 3000}';
      groups.putIfAbsent(key, () => []).add(track);
    }
    final duplicates =
        groups.values.where((group) => group.length > 1).toList();
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          Text('Qualidade da biblioteca',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text(
              'Análise das faixas do Jellyfin. Os arquivos não são alterados.'),
          const SizedBox(height: 20),
          _group('Novas na biblioteca', widget.jellyfin.newTracks),
          _group('Sem artista', withoutArtist),
          _group('Sem álbum', withoutAlbum),
          _group('Sem gênero', withoutGenre),
          _group('Gênero genérico', genericGenre),
          ExpansionTile(
            title: Text('Possíveis duplicatas: ${duplicates.length} grupos'),
            subtitle: const Text('Mesmo título, artista e duração aproximada'),
            children: [
              for (final group in duplicates.take(40))
                ListTile(
                  dense: true,
                  title: Text(group.first.title),
                  subtitle: Text(
                      '${group.first.artist ?? 'Artista desconhecido'} · ${group.length} versões'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(_scanningLyrics
                ? 'Verificando letras: $_checkedLyrics/${tracks.length}'
                : _checkedLyrics == 0
                    ? 'Verificar letras ausentes'
                    : 'Sem letra: ${_withoutLyrics.length} de $_checkedLyrics verificadas'),
            subtitle: const Text(
                'Consulta o Jellyfin faixa por faixa; pode demorar.'),
            trailing: _scanningLyrics
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right_rounded),
            onTap: _scanningLyrics ? null : _scanLyrics,
          ),
          if (_withoutLyrics.isNotEmpty)
            _group('Faixas sem letra', _withoutLyrics),
        ],
      ),
    );
  }

  Widget _group(String title, List<AudioTrack> tracks) => ExpansionTile(
        title: Text('$title: ${tracks.length}'),
        children: [
          for (final track in tracks.take(40))
            ListTile(
              dense: true,
              title: Text(track.title),
              subtitle: Text(track.artist ?? 'Artista desconhecido'),
            ),
        ],
      );
}
