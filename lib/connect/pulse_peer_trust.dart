import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../data/mobile_secure_session_store.dart';
import '../data/secure_session_store.dart';
import '../data/windows_secure_session_store.dart';

/// A stable device ID and account-scoped pairing tickets. Tickets never go in
/// discovery packets and are protected by Android Keystore or Windows DPAPI.
class PulsePeerTrust {
  PulsePeerTrust({SecureSessionStore? storage})
      : _storage = storage ??
            (Platform.isWindows
                ? WindowsSecureSessionStore(fileName: 'pulse-peer-trust.dpapi')
                : MobileSecureSessionStore(key: 'pulse-peer-trust'));

  final SecureSessionStore _storage;
  final Map<String, String> _tickets = {};
  String? _deviceId;
  String get deviceId =>
      _deviceId ?? (throw StateError('Identidade Pulse ainda não carregada.'));

  Future<void> load() async {
    try {
      final raw = await _storage.read();
      final data = raw == null ? null : jsonDecode(raw);
      if (data is Map) {
        final id = data['deviceId'];
        if (id is String && RegExp(r'^[a-f0-9]{32}$').hasMatch(id)) {
          _deviceId = id;
        }
        final tickets = data['tickets'];
        if (tickets is Map) {
          for (final entry in tickets.entries) {
            if (entry.key is String && entry.value is String) {
              _tickets[entry.key as String] = entry.value as String;
            }
          }
        }
      }
    } on Object {
      // A corrupt or missing record starts a new device identity.
    }
    _deviceId ??= secret(16);
    await _save();
  }

  String? ticket(String account, String peerId) => _tickets['$account:$peerId'];

  Future<void> trust(String account, String peerId, String ticket) async {
    _tickets['$account:$peerId'] = ticket;
    await _save();
  }

  Future<void> _save() => _storage.write(jsonEncode({
        'deviceId': deviceId,
        'tickets': _tickets,
      }));

  static String secret(int bytes) {
    final random = Random.secure();
    return List.generate(
            bytes, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();
  }
}
