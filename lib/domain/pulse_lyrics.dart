class PulseLyricLine {
  const PulseLyricLine(this.text, this.start);

  final String text;
  final Duration? start;
}

class PulseLyrics {
  const PulseLyrics(this.lines);

  final List<PulseLyricLine> lines;
  bool get synchronized => lines.any((line) => line.start != null);

  static PulseLyrics? fromText(String value) {
    final source = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final timed = <PulseLyricLine>[];
    final stamp = RegExp(r'\[(\d{1,3}):(\d{2})(?:[.,](\d{1,3}))?\]');
    for (final row in source.split('\n')) {
      final matches = stamp.allMatches(row).toList();
      if (matches.isEmpty) continue;
      final lyric = row.replaceAll(stamp, '').trim();
      if (lyric.isEmpty) continue;
      for (final match in matches) {
        final fraction = match.group(3) ?? '0';
        final millis = int.parse(match.group(1)!) * 60000 +
            int.parse(match.group(2)!) * 1000 +
            int.parse(fraction.padRight(3, '0'));
        timed.add(PulseLyricLine(lyric, Duration(milliseconds: millis)));
      }
    }
    if (timed.isNotEmpty) {
      timed.sort((a, b) => a.start!.compareTo(b.start!));
      return PulseLyrics(timed);
    }
    final plain = source
        .split('\n')
        .map((row) => row.trim())
        .where((row) => row.isNotEmpty && !RegExp(r'^\[[a-zA-Z]+:').hasMatch(row))
        .map((row) => PulseLyricLine(row, null))
        .toList();
    return plain.isEmpty ? null : PulseLyrics(plain);
  }
}
