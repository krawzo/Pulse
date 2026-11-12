import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../domain/audio_track.dart';
import '../domain/pulse_lyrics.dart';
import 'app_data_directory.dart';

/// Finds timing for lyrics already owned by the user; never edits audio files.
class SynchronizedLyricsRepository {
  const SynchronizedLyricsRepository();

  Future<PulseLyrics?> find(
    AudioTrack track,
    PulseLyrics embedded, {
    required Duration duration,
    required bool allowNetwork,
    bool refresh = false,
  }) async {
    if (embedded.synchronized || embedded.lines.isEmpty) return embedded;
    final file = await _cacheFile(track, embedded, duration);
    PulseLyrics? cached;
    if (await file.exists()) {
      try {
        cached = PulseLyrics.fromText(await file.readAsString());
        if (cached?.synchronized == true && (!refresh || !allowNetwork)) {
          return cached;
        }
      } on Object {
        // A damaged cache is ignored and can be replaced on the next lookup.
      }
    }
    if (!allowNetwork ||
        track.title.trim().isEmpty ||
        (track.artist?.trim().isEmpty ?? true)) {
      return cached;
    }
    final seconds =
        duration.inMilliseconds > 0 ? duration.inMilliseconds / 1000 : null;
    final candidates = <Map<String, dynamic>>[];
    final exact = await _get('get', {
      'track_name': track.title,
      'artist_name': track.artist!,
      if (seconds != null) 'duration': seconds.round().toString(),
    });
    if (exact is Map) candidates.add(Map<String, dynamic>.from(exact));
    if (!_hasMatch(candidates, track, embedded, seconds)) {
      final search = await _get('search', {
        'track_name': track.title,
        'artist_name': track.artist!,
      });
      if (search is List) {
        candidates.addAll(search
            .whereType<Map>()
            .take(20)
            .map((item) => Map<String, dynamic>.from(item)));
      }
    }
    for (final candidate in candidates) {
      final lrc = candidate['syncedLyrics'];
      if (lrc is! String || lrc.trim().isEmpty) continue;
      final parsed = PulseLyrics.fromText(lrc);
      if (parsed?.synchronized != true || parsed!.lines.length < 3) continue;
      if (!_matches(candidate, track, embedded, parsed, seconds)) continue;
      try {
        await file.parent.create(recursive: true);
        await file.writeAsString(lrc, flush: true);
      } on Object {
        // Lyrics remain usable in memory if the device is low on storage.
      }
      return parsed;
    }
    return cached;
  }

  bool _hasMatch(List<Map<String, dynamic>> candidates, AudioTrack track,
          PulseLyrics embedded, double? seconds) =>
      candidates.any((item) {
        final text = item['syncedLyrics'];
        final parsed = text is String ? PulseLyrics.fromText(text) : null;
        return parsed?.synchronized == true &&
            _matches(item, track, embedded, parsed!, seconds);
      });

  bool _matches(Map<String, dynamic> item, AudioTrack track,
      PulseLyrics embedded, PulseLyrics candidate, double? seconds) {
    if (_normalize(item['trackName']?.toString() ?? '') !=
        _normalize(track.title)) {
      return false;
    }
    final artist = _normalize(item['artistName']?.toString() ?? '');
    final wantedArtist = _normalize(track.artist ?? '');
    if (artist.isEmpty || wantedArtist.isEmpty) return false;
    if (artist != wantedArtist &&
        !artist.contains(wantedArtist) &&
        !wantedArtist.contains(artist)) {
      return false;
    }
    final candidateDuration = item['duration'];
    if (seconds != null &&
        candidateDuration is num &&
        (candidateDuration - seconds).abs() > (seconds * .02).clamp(3.0, 6.0)) {
      return false;
    }
    final original = embedded.lines
        .map((line) => _normalize(line.text))
        .where((line) => line.length >= 9)
        .toSet();
    final compared = candidate.lines
        .map((line) => _normalize(line.text))
        .where((line) => line.length >= 9)
        .toSet();
    if (original.isEmpty || compared.isEmpty) return false;
    final matches = original.intersection(compared).length;
    final shorter =
        original.length < compared.length ? original.length : compared.length;
    return matches >= (shorter * .35).ceil().clamp(2, 6);
  }

  String _normalize(String value) {
    const accents = {
      'á': 'a',
      'à': 'a',
      'â': 'a',
      'ã': 'a',
      'ä': 'a',
      'é': 'e',
      'ê': 'e',
      'è': 'e',
      'ë': 'e',
      'í': 'i',
      'ì': 'i',
      'î': 'i',
      'ï': 'i',
      'ó': 'o',
      'ò': 'o',
      'ô': 'o',
      'õ': 'o',
      'ö': 'o',
      'ú': 'u',
      'ù': 'u',
      'û': 'u',
      'ü': 'u',
      'ç': 'c',
      'ñ': 'n',
    };
    final lowered = value.toLowerCase();
    final plain = lowered.split('').map((c) => accents[c] ?? c).join();
    return plain.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  Future<File> _cacheFile(
      AudioTrack track, PulseLyrics lyrics, Duration duration) async {
    final root = await pulseAppDataDirectory();
    final key = sha256
        .convert(utf8.encode([
          track.source.name,
          track.path,
          track.title,
          track.artist ?? '',
          duration.inMilliseconds.toString(),
          ...lyrics.lines.map((line) => line.text),
        ].join('\u0000')))
        .toString();
    return File('${root.path}${Platform.pathSeparator}lyrics'
        '${Platform.pathSeparator}$key.lrc');
  }

  Future<dynamic> _get(String endpoint, Map<String, String> parameters) async {
    final uri = Uri.https('lrclib.net', '/api/$endpoint', parameters);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request =
          await client.getUrl(uri).timeout(const Duration(seconds: 8));
      request.headers.set(
          HttpHeaders.userAgentHeader, 'Pulse/0.3.20 (personal music player)');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response =
          await request.close().timeout(const Duration(seconds: 8));
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>();
        return null;
      }
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.timeout(const Duration(seconds: 8))) {
        bytes.add(chunk);
        if (bytes.length > 2 * 1024 * 1024) return null;
      }
      return jsonDecode(utf8.decode(bytes.takeBytes()));
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
