import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

/// Announces Pulse on the LAN. Packets carry presence and the receiver port,
/// never audio, session tokens or playback commands.
class PulsePeer {
  const PulsePeer({
    required this.id,
    required this.name,
    required this.platform,
    required this.address,
    required this.lastSeen,
    this.controlPort,
  });

  final String id;
  final String name;
  final String platform;
  final InternetAddress address;
  final DateTime lastSeen;
  final int? controlPort;
}

class PulsePeerDiscovery extends ChangeNotifier {
  static const port = 47249;
  static const _signature = 'pulse-peer-v1';
  static const _peerLifetime = Duration(seconds: 18);
  String _instanceId = _newInstanceId();
  String? _accountFingerprint;

  static String _newInstanceId() {
    final random = Random.secure();
    return List.generate(16, (_) => random.nextInt(16).toRadixString(16))
        .join();
  }

  RawDatagramSocket? _socket;
  StreamSubscription<RawSocketEvent>? _subscription;
  Timer? _announceTimer;
  Timer? _expiryTimer;
  final Map<String, PulsePeer> _peers = {};
  bool _disposed = false;
  String? _error;
  int? _controlPort;

  List<PulsePeer> get peers => List.unmodifiable(_peers.values.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())));
  String? get error => _error;

  void configure(
      {required String deviceId, required String? accountFingerprint}) {
    final changed =
        _accountFingerprint != accountFingerprint || _instanceId != deviceId;
    if (!changed) return;
    _instanceId = deviceId;
    _accountFingerprint = accountFingerprint;
    if (changed) {
      _peers.clear();
      notifyListeners();
    }
    unawaited(refresh());
  }

  Future<void> start({int? controlPort}) async {
    if (_disposed) return;
    // The receiver may have supplied its port before discovery starts.
    // Starting discovery without an override must keep that port advertised.
    _controlPort = controlPort ?? _controlPort;
    if (_socket != null) {
      await refresh();
      return;
    }
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
      );
      if (_disposed) {
        socket.close();
        return;
      }
      socket.broadcastEnabled = true;
      socket.writeEventsEnabled = false;
      _socket = socket;
      _subscription = socket.listen(
        (event) {
          if (event != RawSocketEvent.read) return;
          Datagram? packet;
          while ((packet = socket.receive()) != null) {
            _receive(packet!);
          }
        },
        onError: (Object _) {
          _error = 'A descoberta Pulse perdeu acesso à rede local.';
          if (!_disposed) notifyListeners();
        },
      );
      _announceTimer = Timer.periodic(
        const Duration(seconds: 6),
        (_) => unawaited(refresh()),
      );
      _expiryTimer =
          Timer.periodic(const Duration(seconds: 6), (_) => _prune());
      await refresh();
    } on Object {
      _error = 'Não foi possível iniciar a descoberta Pulse nesta rede.';
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> setControlPort(int? controlPort) async {
    if (_disposed) return;
    _controlPort = controlPort;
    await refresh();
  }

  Future<void> refresh() async {
    final socket = _socket;
    if (socket == null || _disposed || _accountFingerprint == null) return;
    final payload = _packet('query');
    final targets = <String>{'255.255.255.255'};
    try {
      for (final interface in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      )) {
        for (final address in interface.addresses) {
          final parts = address.address.split('.');
          if (parts.length != 4 || !_isPrivateIpv4(parts)) continue;
          targets.add('${parts[0]}.${parts[1]}.${parts[2]}.255');
        }
      }
    } on Object {
      // The limited broadcast still covers the default LAN interface.
    }
    for (final target in targets) {
      try {
        socket.send(payload, InternetAddress(target), port);
      } on Object {
        // Another interface may still be reachable.
      }
    }
    _prune();
  }

  bool _isPrivateIpv4(List<String> parts) {
    final first = int.tryParse(parts[0]);
    final second = int.tryParse(parts[1]);
    return first == 10 ||
        first == 192 && second == 168 ||
        first == 172 && second != null && second >= 16 && second <= 31;
  }

  List<int> _packet(String kind) => utf8.encode(jsonEncode({
        'signature': _signature,
        'kind': kind,
        'id': _instanceId,
        'account': _accountFingerprint,
        'name': Platform.isAndroid ? 'celular Android' : Platform.localHostname,
        'platform': Platform.isWindows ? 'windows' : 'android',
        if (_controlPort != null) 'controlPort': _controlPort,
      }));

  void _receive(Datagram packet) {
    if (packet.data.length > 1024 || _disposed) return;
    try {
      final data = jsonDecode(utf8.decode(packet.data));
      if (data is! Map<String, dynamic> ||
          data['signature'] != _signature ||
          data['id'] == _instanceId ||
          _accountFingerprint == null ||
          data['account'] != _accountFingerprint) {
        return;
      }
      final id = data['id'];
      final name = data['name'];
      final platform = data['platform'];
      final kind = data['kind'];
      final announcedPort = data['controlPort'];
      if (id is! String ||
          id.length != 32 ||
          name is! String ||
          name.trim().isEmpty ||
          platform != 'windows' && platform != 'android' ||
          kind != 'query' && kind != 'hello') {
        return;
      }
      final controlPort =
          announcedPort is int && announcedPort > 0 && announcedPort <= 65535
              ? announcedPort
              : null;
      _peers[id] = PulsePeer(
        id: id,
        name: name.trim().substring(0, min(48, name.trim().length)),
        platform: platform as String,
        address: packet.address,
        lastSeen: DateTime.now(),
        controlPort: controlPort,
      );
      notifyListeners();
      if (kind == 'query') {
        _socket?.send(_packet('hello'), packet.address, packet.port);
      }
    } on Object {
      // Ignore unrelated or malformed LAN traffic.
    }
  }

  void _prune() {
    final now = DateTime.now();
    final before = _peers.length;
    _peers.removeWhere(
      (_, peer) => now.difference(peer.lastSeen) > _peerLifetime,
    );
    if (!_disposed && before != _peers.length) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _announceTimer?.cancel();
    _expiryTimer?.cancel();
    unawaited(_subscription?.cancel());
    _socket?.close();
    super.dispose();
  }
}
