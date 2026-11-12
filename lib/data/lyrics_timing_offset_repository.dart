import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../domain/audio_track.dart';
import 'app_data_directory.dart';

/// Keeps a user's lyric timing correction on this device, per audio track.
class LyricsTimingOffsetRepository {
  const LyricsTimingOffsetRepository();

  Future<int> read(AudioTrack track) async {
    try {
      final file = await _fileFor(track);
      if (!await file.exists()) return 0;
      final value = int.tryParse((await file.readAsString()).trim()) ?? 0;
      return value.clamp(-5000, 5000).toInt();
    } on Object {
      return 0;
    }
  }

  Future<void> write(AudioTrack track, int milliseconds) async {
    final value = milliseconds.clamp(-5000, 5000).toInt();
    final file = await _fileFor(track);
    await file.parent.create(recursive: true);
    if (value == 0) {
      if (await file.exists()) await file.delete();
    } else {
      await file.writeAsString('$value', flush: true);
    }
  }

  Future<File> _fileFor(AudioTrack track) async {
    final root = await pulseAppDataDirectory();
    final key = sha256
        .convert(utf8.encode([
          track.source.name,
          track.id,
          track.path,
        ].join('\u0000')))
        .toString();
    return File('${root.path}${Platform.pathSeparator}lyrics_offsets'
        '${Platform.pathSeparator}$key.txt');
  }
}
