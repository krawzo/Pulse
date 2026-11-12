import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import 'secure_session_store.dart';

/// Stores a session encrypted for the current Windows user via DPAPI.
class WindowsSecureSessionStore implements SecureSessionStore {
  WindowsSecureSessionStore(
      {Directory? storageDirectory, String fileName = 'jellyfin-session.dpapi'})
      : _storageDirectory = storageDirectory,
        _fileName = fileName;

  final Directory? _storageDirectory;
  final String _fileName;

  @override
  Future<String?> read() async {
    final file = _file();
    final backup = File('${file.path}.bak');
    if (!await file.exists() && await backup.exists()) {
      await backup.rename(file.path);
    }
    if (!await file.exists()) return null;
    final encrypted = await file.readAsBytes();
    return utf8.decode(_crypt(encrypted, protect: false));
  }

  @override
  Future<void> write(String value) async {
    final file = _file();
    await file.parent.create(recursive: true);
    final encrypted = _crypt(utf8.encode(value), protect: true);
    final temporary = File('${file.path}.tmp');
    await temporary.writeAsBytes(encrypted, flush: true);
    final backup = File('${file.path}.bak');
    if (await backup.exists()) await backup.delete();
    if (await file.exists()) await file.rename(backup.path);
    try {
      await temporary.rename(file.path);
      if (await backup.exists()) await backup.delete();
    } on Object {
      if (await backup.exists() && !await file.exists()) {
        await backup.rename(file.path);
      }
      rethrow;
    }
  }

  @override
  Future<void> delete() async {
    final file = _file();
    if (await file.exists()) await file.delete();
  }

  File _file() {
    final base = _storageDirectory?.path ??
        Platform.environment['LOCALAPPDATA'] ??
        Platform.environment['APPDATA'];
    if (base == null || base.isEmpty) {
      throw const FileSystemException('Pasta local indisponível.');
    }
    final directory = _storageDirectory ??
        Directory('$base${Platform.pathSeparator}PulseFlutter');
    return File('${directory.path}${Platform.pathSeparator}$_fileName');
  }

  Uint8List _crypt(List<int> input, {required bool protect}) {
    if (!Platform.isWindows) {
      throw UnsupportedError('Armazenamento seguro disponível no Windows.');
    }
    final inputBytes = calloc<Uint8>(input.length);
    final inputBlob = calloc<CRYPT_INTEGER_BLOB>();
    final outputBlob = calloc<CRYPT_INTEGER_BLOB>();
    try {
      inputBytes.asTypedList(input.length).setAll(0, input);
      inputBlob.ref
        ..cbData = input.length
        ..pbData = inputBytes;
      final result = protect
          ? CryptProtectData(inputBlob, null, null, null, 0, outputBlob)
          : CryptUnprotectData(inputBlob, null, null, null, 0, outputBlob);
      if (!result.value) {
        throw const FileSystemException(
            'Falha ao proteger a sessão do servidor.');
      }
      return Uint8List.fromList(
          outputBlob.ref.pbData.asTypedList(outputBlob.ref.cbData));
    } finally {
      inputBytes.asTypedList(input.length).fillRange(0, input.length, 0);
      calloc.free(inputBytes);
      calloc.free(inputBlob);
      if (outputBlob.ref.pbData != nullptr) {
        HLOCAL(outputBlob.ref.pbData.cast()).close();
      }
      calloc.free(outputBlob);
    }
  }
}
