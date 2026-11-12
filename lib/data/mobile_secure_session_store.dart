import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'secure_session_store.dart';

class MobileSecureSessionStore implements SecureSessionStore {
  MobileSecureSessionStore(
      {FlutterSecureStorage? storage, String key = 'jellyfin-session'})
      : _storage = storage ?? const FlutterSecureStorage(),
        _key = key;

  final String _key;
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);

  @override
  Future<void> delete() => _storage.delete(key: _key);
}
