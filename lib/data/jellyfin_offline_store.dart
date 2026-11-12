import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../domain/audio_track.dart';
import 'app_data_directory.dart';

class JellyfinOfflineEntry {
  const JellyfinOfflineEntry({
    required this.itemId,
    required this.fileName,
    required this.title,
    this.artist,
    this.album,
    this.durationMillis,
    this.artworkFileName,
    this.lyricsFileName,
  });

  final String itemId;
  final String fileName;
  final String title;
  final String? artist;
  final String? album;
  final int? durationMillis;
  final String? artworkFileName;
  final String? lyricsFileName;

  factory JellyfinOfflineEntry.fromJson(Map<String, dynamic> json) =>
      JellyfinOfflineEntry(
        itemId: json['itemId'] as String,
        fileName: json['fileName'] as String,
        title: json['title'] as String,
        artist: json['artist'] as String?,
        album: json['album'] as String?,
        durationMillis: json['durationMillis'] as int?,
        artworkFileName: json['artworkFileName'] as String?,
        lyricsFileName: json['lyricsFileName'] as String?,
      );

  Map<String, Object?> toJson() => {
        'itemId': itemId,
        'fileName': fileName,
        'title': title,
        'artist': artist,
        'album': album,
        'durationMillis': durationMillis,
        'artworkFileName': artworkFileName,
        'lyricsFileName': lyricsFileName,
      };
}

/// Keeps downloaded Jellyfin files and metadata private to one server/user.
class JellyfinOfflineStore {
  JellyfinOfflineStore({Directory? root}) : _root = root;

  final Directory? _root;
  Directory? _directory;
  String _idPrefix = 'jellyfin';
  final Map<String, JellyfinOfflineEntry> _entries = {};
  Future<void> _writes = Future<void>.value();

  bool contains(String itemId) => _entries.containsKey(itemId);
  JellyfinOfflineEntry? entry(String itemId) => _entries[itemId];
  Iterable<JellyfinOfflineEntry> get entries => _entries.values;

  Future<void> open(String accountFingerprint,
      {String idPrefix = 'jellyfin'}) async {
    await _writes;
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(accountFingerprint)) {
      throw const FormatException('Conta Jellyfin inválida para download.');
    }
    final root = _root ?? await pulseAppDataDirectory();
    _idPrefix = idPrefix;
    _directory = Directory(
        '${root.path}${Platform.pathSeparator}offline${Platform.pathSeparator}$accountFingerprint');
    await _directory!.create(recursive: true);
    _entries.clear();
    final manifest =
        File('${_directory!.path}${Platform.pathSeparator}manifest.json');
    final backup = File('${manifest.path}.bak');
    if (!await manifest.exists() && await backup.exists()) {
      await backup.rename(manifest.path);
    }
    if (!await manifest.exists()) return;
    try {
      final data = jsonDecode(await manifest.readAsString());
      if (data is! List) return;
      for (final value in data) {
        if (value is! Map<String, dynamic>) continue;
        final entry = JellyfinOfflineEntry.fromJson(value);
        if (!_safeName(entry.fileName) ||
            entry.artworkFileName != null &&
                !_safeName(entry.artworkFileName!) ||
            entry.lyricsFileName != null && !_safeName(entry.lyricsFileName!)) {
          continue;
        }
        if (await audioFile(entry).exists()) _entries[entry.itemId] = entry;
      }
    } on Object {
      // Damaged metadata cannot make the player fail to start.
    }
  }

  File audioFile(JellyfinOfflineEntry entry) =>
      File('${_directory!.path}${Platform.pathSeparator}${entry.fileName}');

  File? artworkFile(JellyfinOfflineEntry entry) => entry.artworkFileName == null
      ? null
      : File(
          '${_directory!.path}${Platform.pathSeparator}${entry.artworkFileName}');

  File? lyricsFile(JellyfinOfflineEntry entry) => entry.lyricsFileName == null
      ? null
      : File(
          '${_directory!.path}${Platform.pathSeparator}${entry.lyricsFileName}');

  File target(String itemId, String extension) {
    if (_directory == null ||
        !RegExp(r'^\.[a-z0-9]{2,6}$').hasMatch(extension)) {
      throw StateError('Download Jellyfin não preparado.');
    }
    final key = sha256.convert(utf8.encode(itemId)).toString();
    return File('${_directory!.path}${Platform.pathSeparator}$key$extension');
  }

  AudioTrack asTrack(JellyfinOfflineEntry entry) {
    final art = artworkFile(entry);
    return AudioTrack(
      id: '$_idPrefix:${entry.itemId}',
      path: entry.itemId,
      title: entry.title,
      artist: entry.artist,
      album: entry.album,
      sizeBytes: 0,
      modifiedAtMillis: 0,
      durationMillis: entry.durationMillis,
      source: AudioSource.jellyfin,
      artworkUrl: art != null && art.existsSync() ? art.uri.toString() : null,
    );
  }

  Future<void> put(JellyfinOfflineEntry entry) async {
    final previous = _entries[entry.itemId];
    _entries[entry.itemId] = entry;
    try {
      await _save();
    } on Object {
      if (previous == null) {
        _entries.remove(entry.itemId);
      } else {
        _entries[entry.itemId] = previous;
      }
      rethrow;
    }
  }

  Future<void> remove(String itemId) async {
    final entry = _entries.remove(itemId);
    if (entry == null) return;
    try {
      await _save();
    } on Object {
      _entries[itemId] = entry;
      rethrow;
    }
    final audio = audioFile(entry);
    if (await audio.exists()) await audio.delete();
    final art = artworkFile(entry);
    if (art != null && await art.exists()) await art.delete();
    final lyrics = lyricsFile(entry);
    if (lyrics != null && await lyrics.exists()) await lyrics.delete();
  }

  Future<void> _save() {
    final snapshot = _entries.values.map((entry) => entry.toJson()).toList();
    final next = _writes.then((_) => _writeSnapshot(snapshot));
    _writes = next.catchError((Object _) {});
    return next;
  }

  Future<void> _writeSnapshot(List<Map<String, Object?>> entries) async {
    final directory = _directory!;
    final manifest =
        File('${directory.path}${Platform.pathSeparator}manifest.json');
    final temporary = File('${manifest.path}.tmp');
    final backup = File('${manifest.path}.bak');
    await temporary.writeAsString(jsonEncode(entries), flush: true);
    if (await backup.exists()) await backup.delete();
    if (await manifest.exists()) await manifest.rename(backup.path);
    try {
      await temporary.rename(manifest.path);
      if (await backup.exists()) await backup.delete();
    } on Object {
      if (await backup.exists() && !await manifest.exists()) {
        await backup.rename(manifest.path);
      }
      rethrow;
    }
  }

  static bool _safeName(String name) =>
      RegExp(r'^[a-f0-9]{64}\.[a-z0-9]{2,6}$').hasMatch(name);
}
