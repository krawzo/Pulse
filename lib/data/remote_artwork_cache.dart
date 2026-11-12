import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../domain/audio_track.dart';
import 'app_data_directory.dart';

/// Keeps small remote covers on the device, separate for each server account.
class RemoteArtworkCache {
  RemoteArtworkCache._();

  static final instance = RemoteArtworkCache._();
  static const _maxImageBytes = 4 * 1024 * 1024;
  static const _maxCacheBytes = 150 * 1024 * 1024;
  static const _maxEntries = 1200;

  String? _account;
  final Map<String, Future<File?>> _inFlight = {};
  final Map<String, File> _ready = {};
  bool _pruning = false;
  int _writesSincePrune = 0;

  void setAccount(String? fingerprint) {
    if (_account == fingerprint) return;
    _account = fingerprint;
    _inFlight.clear();
    _ready.clear();
  }

  File? readyImageFor(AudioTrack track) {
    final key = _keyFor(track);
    return key == null ? null : _ready[key];
  }

  String? _keyFor(AudioTrack track) {
    final account = _account;
    final uri = Uri.tryParse(track.artworkUrl ?? '');
    if (account == null ||
        uri == null ||
        uri.scheme != 'http' ||
        uri.host != InternetAddress.loopbackIPv4.address ||
        uri.pathSegments.length != 3 ||
        uri.pathSegments[1] != 'image') {
      return null;
    }
    return sha256
        .convert(utf8.encode('$account|${uri.pathSegments.last}'))
        .toString();
  }

  Future<File?> imageFor(AudioTrack track) {
    final account = _account;
    final uri = Uri.tryParse(track.artworkUrl ?? '');
    if (!(Platform.isAndroid || Platform.isWindows) ||
        account == null ||
        uri == null ||
        uri.scheme != 'http' ||
        uri.host != InternetAddress.loopbackIPv4.address ||
        uri.pathSegments.length != 3 ||
        uri.pathSegments[1] != 'image') {
      return Future.value(null);
    }
    // The proxy port and nonce change at each start; the image ID does not.
    final key = _keyFor(track)!;
    if (_ready[key] case final ready?) return Future.value(ready);
    return _inFlight.putIfAbsent(key, () async {
      try {
        final file = await _loadOrFetch(account, key, uri);
        if (file != null && _account == account) {
          if (_ready.length >= _maxEntries) _ready.remove(_ready.keys.first);
          _ready[key] = file;
        }
        return file;
      } finally {
        _inFlight.remove(key);
      }
    });
  }

  Future<File?> _loadOrFetch(String account, String key, Uri uri) async {
    final root = await pulseAppDataDirectory();
    final directory = Directory(
        '${root.path}${Platform.pathSeparator}artwork${Platform.pathSeparator}$account');
    await directory.create(recursive: true);
    final file = File('${directory.path}${Platform.pathSeparator}$key.image');
    if (await file.exists() && await file.length() > 0) return file;

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri);
      final response =
          await request.close().timeout(const Duration(seconds: 12));
      if (response.statusCode != HttpStatus.ok ||
          response.contentLength > _maxImageBytes) {
        await response.drain<void>();
        return null;
      }
      final bytes = <int>[];
      await for (final chunk in response.timeout(const Duration(seconds: 12))) {
        bytes.addAll(chunk);
        if (bytes.length > _maxImageBytes) return null;
      }
      if (bytes.isEmpty) return null;
      final temporary = File('${file.path}.tmp');
      try {
        await temporary.writeAsBytes(bytes, flush: true);
        await temporary.rename(file.path);
      } finally {
        if (await temporary.exists()) await temporary.delete();
      }
      if (++_writesSincePrune >= 40) {
        _writesSincePrune = 0;
        unawaited(_prune(directory));
      }
      return file;
    } on Object {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _prune(Directory directory) async {
    if (_pruning) return;
    _pruning = true;
    try {
      final entries = <({File file, DateTime modified, int bytes})>[];
      await for (final item in directory.list()) {
        if (item is! File || !item.path.endsWith('.image')) continue;
        final stat = await item.stat();
        entries.add((file: item, modified: stat.modified, bytes: stat.size));
      }
      entries.sort((a, b) => b.modified.compareTo(a.modified));
      var totalBytes = 0;
      for (var index = 0; index < entries.length; index++) {
        totalBytes += entries[index].bytes;
        if (index >= _maxEntries || totalBytes > _maxCacheBytes) {
          totalBytes -= entries[index].bytes;
          _ready
              .removeWhere((_, file) => file.path == entries[index].file.path);
          await entries[index].file.delete();
        }
      }
    } on Object {
      // Cache cleanup never interrupts browsing.
    } finally {
      _pruning = false;
    }
  }
}
