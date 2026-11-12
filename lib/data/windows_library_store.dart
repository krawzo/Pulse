import 'dart:convert';
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

import '../domain/audio_track.dart';
import '../domain/library_snapshot.dart';
import 'app_data_directory.dart';

class NoMp3FilesFound implements Exception {
  const NoMp3FilesFound();
}

class PartialLibraryScan implements Exception {
  const PartialLibraryScan({required this.failedLocations});

  final int failedLocations;
}

class LibrarySourceReadException implements Exception {
  const LibrarySourceReadException();
}

class LibraryCatalogRecoveryException implements Exception {
  const LibraryCatalogRecoveryException({
    required this.primaryPath,
    required this.backupPath,
    this.primaryFailure,
    this.backupFailure,
  });

  final String primaryPath;
  final String backupPath;
  final Object? primaryFailure;
  final Object? backupFailure;
}

class _InvalidLibrarySnapshot implements Exception {
  const _InvalidLibrarySnapshot(this.path, this.cause);

  final String path;
  final Object cause;
}

class WindowsLibraryStore {
  WindowsLibraryStore({Directory? storageDirectory})
      : _storageDirectory = storageDirectory;

  final Directory? _storageDirectory;
  bool _recoveredFromBackup = false;
  bool _backupDamaged = false;
  bool _primaryWasDamaged = false;
  String? _preservedDamagedPath;
  String? _recoveryBackupPath;
  String? _primaryCatalogPath;

  bool get recoveredFromBackup => _recoveredFromBackup;
  bool get backupDamaged => _backupDamaged;
  bool get primaryWasDamaged => _primaryWasDamaged;
  String? get preservedDamagedPath => _preservedDamagedPath;
  String? get recoveryBackupPath => _recoveryBackupPath;
  String? get primaryCatalogPath => _primaryCatalogPath;

  Future<LibrarySnapshot> load() async {
    final file = await _snapshotFile();
    final backup = File('${file.path}.bak');
    _primaryCatalogPath = file.path;
    _recoveryBackupPath = backup.path;
    _recoveredFromBackup = false;
    _backupDamaged = false;
    _primaryWasDamaged = false;
    _preservedDamagedPath = null;
    _recoveryBackupPath = null;
    final primaryExists = await file.exists();
    final backupExists = await backup.exists();

    if (!primaryExists && !backupExists) return const LibrarySnapshot();

    Object? primaryFailure;
    if (primaryExists) {
      try {
        final snapshot = await _readSnapshot(file);
        if (backupExists) {
          try {
            await _readSnapshot(backup);
          } on Object {
            _backupDamaged = true;
          }
        }
        return snapshot;
      } on Object catch (error) {
        primaryFailure = error;
      }
    }

    Object? backupFailure;
    if (backupExists) {
      try {
        final snapshot = await _readSnapshot(backup);
        _recoveredFromBackup = true;
        _primaryWasDamaged = primaryFailure != null;
        _recoveryBackupPath = backup.path;
        if (primaryFailure != null) {
          try {
            final preserved = await _preserveFile(file, '.corrupt');
            _preservedDamagedPath = preserved.path;
            final temporary = File('${file.path}.recovery.tmp');
            await temporary.writeAsBytes(await backup.readAsBytes(),
                flush: true);
            await _readSnapshot(temporary);
            await _promote(temporary, file);
          } on Object {
            // The validated backup remains usable in memory; originals stay available.
          }
        } else if (!primaryExists) {
          try {
            final temporary = File('${file.path}.recovery.tmp');
            await temporary.writeAsBytes(await backup.readAsBytes(),
                flush: true);
            await _readSnapshot(temporary);
            await _promote(temporary, file);
          } on Object {
            // The validated backup remains usable in memory if repair is unavailable.
          }
        }
        return snapshot;
      } on Object catch (error) {
        backupFailure = error;
      }
    }

    throw LibraryCatalogRecoveryException(
      primaryPath: file.path,
      backupPath: backup.path,
      primaryFailure: primaryFailure,
      backupFailure: backupFailure,
    );
  }

  Future<void> save(LibrarySnapshot snapshot) async {
    final file = await _snapshotFile();
    final temporary = File('${file.path}.tmp');
    final backup = File('${file.path}.bak');
    await temporary.writeAsString(jsonEncode(snapshot.toJson()), flush: true);

    await _readSnapshot(temporary);
    final primaryExists = await file.exists();
    final backupExists = await backup.exists();
    var primaryIsValid = false;
    if (primaryExists) {
      try {
        await _readSnapshot(file);
        primaryIsValid = true;
      } on _InvalidLibrarySnapshot {
        // A valid backup is required before replacing a damaged primary.
      }
    }

    LibrarySnapshot? backupSnapshot;
    if (backupExists) {
      try {
        backupSnapshot = await _readSnapshot(backup);
      } on _InvalidLibrarySnapshot {
        // Keep invalid backup bytes as a diagnostic copy before rotation.
      }
    }

    if (primaryExists && !primaryIsValid && backupSnapshot == null) {
      throw LibraryCatalogRecoveryException(
        primaryPath: file.path,
        backupPath: backup.path,
      );
    }
    if (!primaryExists && backupExists && backupSnapshot == null) {
      throw LibraryCatalogRecoveryException(
        primaryPath: file.path,
        backupPath: backup.path,
        backupFailure: const _InvalidLibrarySnapshot('backup', 'invalid'),
      );
    }

    if (primaryIsValid) {
      await _rotateBackupFrom(file, backup);
    } else if (!primaryExists && !backupExists) {
      await _writeBackupFrom(temporary, backup);
    }

    if (primaryExists && !primaryIsValid) {
      await _preserveFile(file, '.corrupt');
    }
    await _promote(temporary, file);
    _recoveredFromBackup = false;
    _backupDamaged = false;
    _primaryWasDamaged = false;
  }

  Future<LibrarySnapshot> _readSnapshot(File file) async {
    final source = await file.readAsString();
    try {
      final decoded = jsonDecode(source);
      if (decoded is! Map) {
        throw const FormatException('Catalog root must be a JSON object.');
      }
      return LibrarySnapshot.fromJson(Map<String, Object?>.from(decoded));
    } on Object catch (error) {
      throw _InvalidLibrarySnapshot(file.path, error);
    }
  }

  Future<void> _rotateBackupFrom(File source, File backup) async {
    final backupTemporary = File('${backup.path}.tmp');
    final stagedBackup = _nextAvailableFile('${backup.path}.rotate');
    await backupTemporary.writeAsBytes(await source.readAsBytes(), flush: true);
    await _readSnapshot(backupTemporary);

    if (await backup.exists()) {
      try {
        await _readSnapshot(backup);
      } on Object {
        await _preserveFile(backup, '.corrupt');
      }
      await backup.rename(stagedBackup.path);
    }

    try {
      await backupTemporary.rename(backup.path);
    } catch (_) {
      if (!await backup.exists() && await stagedBackup.exists()) {
        await stagedBackup.rename(backup.path);
      }
      rethrow;
    }

    if (await stagedBackup.exists()) {
      await stagedBackup.delete();
    }

    // A previous valid backup is replaced by the current primary snapshot;
    // invalid bytes survive only in the diagnostic .corrupt copy above.
  }

  File _nextAvailableFile(String basePath) {
    var candidate = File(basePath);
    var index = 1;
    while (candidate.existsSync()) {
      candidate = File('$basePath.$index');
      index++;
    }
    return candidate;
  }

  Future<void> _writeBackupFrom(File source, File backup) async {
    final backupTemporary = File('${backup.path}.tmp');
    await backupTemporary.writeAsBytes(await source.readAsBytes(), flush: true);
    await _readSnapshot(backupTemporary);
    await backupTemporary.rename(backup.path);
  }

  Future<File> _preserveFile(File source, String suffix) async {
    var target = File('${source.path}$suffix');
    var index = 1;
    while (await target.exists()) {
      target = File('${source.path}$suffix.$index');
      index++;
    }
    final originalBytes = await source.readAsBytes();
    await target.writeAsBytes(originalBytes, flush: true);
    final preservedBytes = await target.readAsBytes();
    if (!_sameBytes(originalBytes, preservedBytes)) {
      await target.delete();
      throw FileSystemException(
          'Could not preserve the catalog file.', target.path);
    }
    return target;
  }

  Future<void> _promote(File temporary, File file) async {
    File? displaced;
    if (await file.exists()) {
      var candidate = File('${file.path}.swap');
      var index = 1;
      while (await candidate.exists()) {
        candidate = File('${file.path}.swap.$index');
        index++;
      }
      displaced = candidate;
      await file.rename(displaced.path);
    }
    try {
      await temporary.rename(file.path);
    } catch (_) {
      if (!await file.exists() &&
          displaced != null &&
          await displaced.exists()) {
        await displaced.rename(file.path);
      }
      rethrow;
    }
    if (displaced != null && await displaced.exists()) {
      await displaced.delete();
    }
  }

  bool _sameBytes(List<int> first, List<int> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  Future<List<AudioTrack>> scanMp3Folder(String rootPath) async {
    final root = Directory(rootPath);
    if (!await root.exists()) {
      throw FileSystemException(
        'A pasta selecionada não está acessível.',
        rootPath,
      );
    }

    final found = <AudioTrack>[];
    final pending = <Directory>[root];
    var failedLocations = 0;
    var rootReadFailed = false;
    while (pending.isNotEmpty) {
      final directory = pending.removeLast();
      try {
        await for (final entity
            in directory.list(followLinks: false, recursive: false)) {
          if (entity is Directory) {
            pending.add(entity);
            continue;
          }
          if (entity is! File || !_isSupportedAudio(entity.path)) continue;
          try {
            final stat = await entity.stat();
            final fallbackTitle = _fileTitle(entity.path);
            String? title;
            String? artist;
            String? album;
            String? genre;
            int? durationMillis;
            try {
              final metadata = readMetadata(entity, getImage: false);
              title = _cleanTag(metadata.title);
              artist = _cleanTag(metadata.artist);
              album = _cleanTag(metadata.album);
              genre = _cleanTag(metadata.genres.firstOrNull);
              durationMillis = metadata.duration?.inMilliseconds;
            } on Object {
              // Unsupported/damaged tags use the filename without inventing tags.
            }
            final normalizedPath = entity.absolute.path.toLowerCase();
            final id = base64Url
                .encode(utf8.encode(normalizedPath))
                .replaceAll('=', '');
            found.add(
              AudioTrack(
                id: id,
                path: entity.absolute.path,
                title: title ?? fallbackTitle,
                artist: artist,
                album: album,
                genre: genre,
                sizeBytes: stat.size,
                modifiedAtMillis: stat.modified.millisecondsSinceEpoch,
                durationMillis: durationMillis,
              ),
            );
          } on FileSystemException {
            failedLocations++;
          }
        }
      } on FileSystemException {
        failedLocations++;
        if (directory.path == root.path) rootReadFailed = true;
      }
    }

    found.sort(
      (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
    );
    if (rootReadFailed) throw const LibrarySourceReadException();
    if (failedLocations > 0) {
      throw PartialLibraryScan(failedLocations: failedLocations);
    }
    if (found.isEmpty) throw const NoMp3FilesFound();
    return found;
  }

  Future<bool> isFolderAvailable(String rootPath) =>
      Directory(rootPath).exists();

  Future<File> _snapshotFile() async {
    if (_storageDirectory case final directory?) {
      await directory.create(recursive: true);
      return File('${directory.path}${Platform.pathSeparator}library.json');
    }
    final appDirectory = await pulseAppDataDirectory();
    return File('${appDirectory.path}${Platform.pathSeparator}library.json');
  }

  bool _isSupportedAudio(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.mp3') || lower.endsWith('.opus');
  }

  String _fileTitle(String path) {
    final name = path.split(Platform.pathSeparator).last;
    final extension = name.lastIndexOf('.');
    return extension > 0 ? name.substring(0, extension) : name;
  }

  String? _cleanTag(String? value) {
    final cleaned = value?.trim();
    return cleaned == null || cleaned.isEmpty ? null : cleaned;
  }
}
