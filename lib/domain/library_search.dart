import 'audio_track.dart';

/// Makes searches tolerant of accents and cedillas without changing the
/// original titles displayed to the user.
String normalizeSearchText(String value) {
  var result = value.toLowerCase().replaceAll(RegExp(r'[\u0300-\u036f]'), '');
  const replacements = <String, String>{
    'a': 'áàâãäåāăą',
    'c': 'çćĉċč',
    'e': 'éèêëēĕėęě',
    'i': 'íìîïĩīĭįı',
    'n': 'ñńņň',
    'o': 'óòôõöøōŏő',
    's': 'śŝşš',
    'u': 'úùûüũūŭůűų',
    'y': 'ýÿŷ',
    'z': 'źżž',
  };
  for (final entry in replacements.entries) {
    result = result.replaceAll(RegExp('[${entry.value}]'), entry.key);
  }
  return result
      .replaceAll('æ', 'ae')
      .replaceAll('œ', 'oe')
      .replaceAll('ß', 'ss');
}

bool trackMatchesLibraryQuery(AudioTrack track, String query) {
  final normalizedQuery = normalizeSearchText(query.trim());
  if (normalizedQuery.isEmpty) return true;
  final fields = [track.title, track.artist, track.album, track.genre]
      .whereType<String>()
      .where((value) => value.trim().isNotEmpty);
  return fields.any(
    (value) => normalizeSearchText(value).contains(normalizedQuery),
  );
}
