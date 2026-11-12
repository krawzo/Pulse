import 'dart:convert';
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

import '../domain/pulse_lyrics.dart';

/// Reads ID3v2 and Opus lyrics without changing or copying the audio file.
class EmbeddedLyricsReader {
  static const maxTagBytes = 8 * 1024 * 1024;

  static Future<PulseLyrics?> fromFile(File file) async {
    if (!await file.exists()) return null;
    if (file.path.toLowerCase().endsWith('.opus')) {
      try {
        final lyrics = readMetadata(file, getImage: false).lyrics;
        return lyrics == null ? null : PulseLyrics.fromText(lyrics);
      } on Object {
        return null;
      }
    }
    final handle = await file.open();
    try {
      final header = await handle.read(10);
      final size = tagLength(header);
      if (size == null ||
          size > maxTagBytes ||
          await handle.length() < size) {
        return null;
      }
      await handle.setPosition(0);
      return fromBytes(await handle.read(size));
    } finally {
      await handle.close();
    }
  }

  static int? tagLength(List<int> bytes) {
    if (bytes.length < 10 ||
        bytes[0] != 0x49 || bytes[1] != 0x44 || bytes[2] != 0x33 ||
        bytes[3] < 3 || bytes[3] > 4 ||
        bytes.skip(6).take(4).any((value) => value > 0x7f)) {
      return null;
    }
    final size = _synchsafe(bytes, 6);
    final total = 10 + size + ((bytes[5] & 0x10) != 0 ? 10 : 0);
    return total <= maxTagBytes ? total : null;
  }

  static PulseLyrics? fromBytes(List<int> bytes) {
    final total = tagLength(bytes);
    if (total == null || bytes.length < total) return null;
    final version = bytes[3];
    final end = 10 + _synchsafe(bytes, 6);
    var offset = 10;
    if ((bytes[5] & 0x40) != 0) {
      if (version == 3 && offset + 4 <= end) {
        offset += 4 + _int32(bytes, offset);
      } else if (version == 4 && offset + 4 <= end) {
        offset += _synchsafe(bytes, offset);
      }
    }
    PulseLyrics? unsynced;
    while (offset + 10 <= end && offset + 10 <= bytes.length) {
      final id = ascii.decode(bytes.sublist(offset, offset + 4), allowInvalid: true);
      if (!RegExp(r'^[A-Z0-9]{4}$').hasMatch(id)) break;
      final size = version == 4
          ? _synchsafe(bytes, offset + 4)
          : _int32(bytes, offset + 4);
      final next = offset + 10 + size;
      if (size <= 0 || next > end || next > bytes.length) break;
      final flags = bytes[offset + 9];
      // Compressed and encrypted frames cannot be decoded as text.
      if ((flags & (version == 4 ? 0x0c : 0xc0)) == 0 &&
          (id == 'USLT' || id == 'SYLT' || id == 'TXXX')) {
        final frame = bytes.sublist(offset + 10, next);
        final parsed = id == 'SYLT'
            ? _readSynchronized(frame)
            : id == 'USLT'
                ? _readUnsynchronized(frame)
                : _readCustom(frame);
        if (parsed?.synchronized == true) return parsed;
        unsynced ??= parsed;
      }
      offset = next;
    }
    return unsynced;
  }

  static PulseLyrics? _readUnsynchronized(List<int> bytes) {
    if (bytes.length < 5) return null;
    final encoding = bytes[0];
    final split = _terminator(bytes, 4, encoding);
    if (split < 0) return null;
    return PulseLyrics.fromText(_decode(bytes.sublist(split + _termSize(encoding)), encoding));
  }

  static PulseLyrics? _readCustom(List<int> bytes) {
    if (bytes.length < 3) return null;
    final encoding = bytes[0];
    final split = _terminator(bytes, 1, encoding);
    if (split < 0) return null;
    final name = _decode(bytes.sublist(1, split), encoding).toLowerCase();
    if (!name.contains('lyric')) return null;
    return PulseLyrics.fromText(_decode(bytes.sublist(split + _termSize(encoding)), encoding));
  }

  static PulseLyrics? _readSynchronized(List<int> bytes) {
    if (bytes.length < 8 || bytes[4] != 2) return null; // milliseconds
    final encoding = bytes[0];
    final descriptionEnd = _terminator(bytes, 6, encoding);
    if (descriptionEnd < 0) return null;
    var offset = descriptionEnd + _termSize(encoding);
    final lines = <PulseLyricLine>[];
    while (offset < bytes.length) {
      final textEnd = _terminator(bytes, offset, encoding);
      if (textEnd < 0 || textEnd + _termSize(encoding) + 4 > bytes.length) break;
      final lyric = _decode(bytes.sublist(offset, textEnd), encoding).trim();
      final stampAt = textEnd + _termSize(encoding);
      if (lyric.isNotEmpty) {
        lines.add(PulseLyricLine(lyric,
            Duration(milliseconds: _int32(bytes, stampAt))));
      }
      offset = stampAt + 4;
    }
    lines.sort((a, b) => a.start!.compareTo(b.start!));
    return lines.isEmpty ? null : PulseLyrics(lines);
  }

  static int _termSize(int encoding) => encoding == 1 || encoding == 2 ? 2 : 1;

  static int _terminator(List<int> bytes, int start, int encoding) {
    if (_termSize(encoding) == 1) return bytes.indexOf(0, start);
    for (var i = start; i + 1 < bytes.length; i += 2) {
      if (bytes[i] == 0 && bytes[i + 1] == 0) return i;
    }
    return -1;
  }

  static String _decode(List<int> bytes, int encoding) {
    if (bytes.isEmpty) return '';
    if (encoding == 3) return utf8.decode(bytes, allowMalformed: true).replaceAll('\u0000', '');
    if (encoding == 0) return latin1.decode(bytes).replaceAll('\u0000', '');
    var start = 0;
    var littleEndian = false;
    if (bytes.length >= 2 && bytes[0] == 0xff && bytes[1] == 0xfe) {
      littleEndian = true;
      start = 2;
    } else if (bytes.length >= 2 && bytes[0] == 0xfe && bytes[1] == 0xff) {
      start = 2;
    }
    final units = <int>[];
    for (var i = start; i + 1 < bytes.length; i += 2) {
      final value = littleEndian
          ? bytes[i] | (bytes[i + 1] << 8)
          : (bytes[i] << 8) | bytes[i + 1];
      if (value != 0) units.add(value);
    }
    return String.fromCharCodes(units);
  }

  static int _synchsafe(List<int> bytes, int at) =>
      (bytes[at] << 21) | (bytes[at + 1] << 14) |
      (bytes[at + 2] << 7) | bytes[at + 3];

  static int _int32(List<int> bytes, int at) =>
      (bytes[at] << 24) | (bytes[at + 1] << 16) |
      (bytes[at + 2] << 8) | bytes[at + 3];
}
