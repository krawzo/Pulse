import 'dart:collection';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

/// Loads embedded artwork only when a track is shown and retains small,
/// decoded thumbnails in a bounded process-local cache.
class LocalArtworkCache {
  LocalArtworkCache._();

  static final LocalArtworkCache instance = LocalArtworkCache._();

  static const _maxTagBytes = 24 * 1024 * 1024;
  static const _maxEntries = 40;
  static const _maxCachedBytes = 4 * 1024 * 1024;
  static const _thumbnailEdge = 192;

  final LinkedHashMap<String, Uint8List> _images = LinkedHashMap();
  final Map<String, Future<Uint8List?>> _pending = {};
  int _cachedBytes = 0;
  int _generation = 0;
  Future<void> _queue = Future<void>.value();

  int get cachedEntryCount => _images.length;

  Future<Uint8List?> imageFor(String path, int size, int modifiedAtMillis) {
    final key = '$path\u0000$size\u0000$modifiedAtMillis';
    final image = _images.remove(key);
    if (image != null) {
      _images[key] = image;
      return Future.value(image.isEmpty ? null : image);
    }
    return _pending.putIfAbsent(key, () {
      final generation = _generation;
      final future = _enqueue(() => _load(path, key, generation));
      future.whenComplete(() => _pending.remove(key));
      return future;
    });
  }

  void clear() {
    _generation++;
    _images.clear();
    _cachedBytes = 0;
  }

  Future<Uint8List?> imageForTracks(
      Iterable<({String path, int size, int modifiedAtMillis})> tracks) async {
    for (final track in tracks) {
      final image = await imageFor(
        track.path,
        track.size,
        track.modifiedAtMillis,
      );
      if (image != null) return image;
    }
    return null;
  }

  Future<Uint8List?> _enqueue(Future<Uint8List?> Function() task) {
    final result = _queue.then((_) => task());
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<Uint8List?> _load(String path, String key, int generation) async {
    try {
      final raw = await Isolate.run(() => _readCover(path));
      if (raw == null || raw.isEmpty) {
        if (generation == _generation) _put(key, Uint8List(0));
        return null;
      }
      final buffer = await ui.ImmutableBuffer.fromUint8List(raw);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      final scale = _thumbnailEdge /
          (descriptor.width > descriptor.height
              ? descriptor.width
              : descriptor.height);
      final targetWidth =
          (descriptor.width * scale).round().clamp(1, _thumbnailEdge);
      final targetHeight =
          (descriptor.height * scale).round().clamp(1, _thumbnailEdge);
      try {
        final codec = await descriptor.instantiateCodec(
          targetWidth: targetWidth,
          targetHeight: targetHeight,
        );
        try {
          final frame = await codec.getNextFrame();
          try {
            final data = await frame.image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            if (data == null) return null;
            final thumbnail = data.buffer.asUint8List(
              data.offsetInBytes,
              data.lengthInBytes,
            );
            if (thumbnail.lengthInBytes > _maxCachedBytes) return null;
            if (generation == _generation) _put(key, thumbnail);
            return thumbnail;
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      } finally {
        descriptor.dispose();
        buffer.dispose();
      }
    } on Object {
      return null;
    }
  }

  void _put(String key, Uint8List bytes) {
    final previous = _images.remove(key);
    if (previous != null) _cachedBytes -= previous.lengthInBytes;
    while (_images.isNotEmpty &&
        (_images.length >= _maxEntries ||
            _cachedBytes + bytes.lengthInBytes > _maxCachedBytes)) {
      final oldestKey = _images.keys.first;
      _cachedBytes -= _images.remove(oldestKey)!.lengthInBytes;
    }
    _images[key] = bytes;
    _cachedBytes += bytes.lengthInBytes;
  }
}

Uint8List? _readCover(String path) {
  final file = File(path);
  if (!file.existsSync() || _hasOversizedTag(file)) return null;
  final pictures = readMetadata(file, getImage: true).pictures;
  if (pictures.isEmpty) return null;
  return pictures
      .where((picture) => picture.pictureType == PictureType.coverFront)
      .firstOrNull
      ?.bytes;
}

bool _hasOversizedTag(File file) {
  final reader = file.openSync();
  try {
    final length = reader.lengthSync();
    if (length >= 10) {
      reader.setPositionSync(0);
      final header = reader.readSync(10);
      if (String.fromCharCodes(header.take(3)) == 'ID3') {
        final tagSize = ((header[6] & 0x7F) << 21) |
            ((header[7] & 0x7F) << 14) |
            ((header[8] & 0x7F) << 7) |
            (header[9] & 0x7F);
        if (tagSize > LocalArtworkCache._maxTagBytes) return true;
      }
    }

    for (final footerOffset in [length - 32, length - 160]) {
      if (footerOffset < 0) continue;
      reader.setPositionSync(footerOffset);
      final footer = reader.readSync(32);
      if (footer.length < 32 ||
          String.fromCharCodes(footer.take(8)) != 'APETAGEX') {
        continue;
      }
      final tagSize = footer[12] |
          (footer[13] << 8) |
          (footer[14] << 16) |
          (footer[15] << 24);
      if (tagSize > LocalArtworkCache._maxTagBytes) return true;
    }
    return false;
  } finally {
    reader.closeSync();
  }
}
