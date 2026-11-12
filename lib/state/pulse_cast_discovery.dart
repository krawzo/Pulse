import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:multicast_dns/multicast_dns.dart';

/// A Cast receiver advertised on the current local network.
class PulseCastDevice {
  const PulseCastDevice({
    required this.id,
    required this.name,
    required this.host,
    required this.port,
    this.address,
  });

  final String id;
  final String name;
  final String host;
  final int port;
  final String? address;
}

/// Performs an on-demand mDNS lookup. Discovery does not connect or route audio.
class PulseCastDiscovery extends ChangeNotifier {
  static const _service = '_googlecast._tcp.local';
  static const _androidMulticast = MethodChannel('pulse/cast_discovery');

  List<PulseCastDevice> _devices = const [];
  bool _scanning = false;
  String? _error;
  bool _disposed = false;

  List<PulseCastDevice> get devices => List.unmodifiable(_devices);
  bool get scanning => _scanning;
  String? get error => _error;

  Future<void> scan() async {
    if (_scanning || _disposed) return;
    _scanning = true;
    _error = null;
    notifyListeners();

    final client = MDnsClient();
    try {
      if (Platform.isAndroid) {
        await _androidMulticast.invokeMethod<void>('acquire');
      }
      await client.start();
      final pointers = await client
          .lookup<PtrResourceRecord>(
            ResourceRecordQuery.serverPointer(_service),
            timeout: const Duration(seconds: 4),
          )
          .toList();
      final uniquePointers = {
        for (final pointer in pointers) pointer.domainName: pointer,
      };
      final discovered = await Future.wait(
        uniquePointers.values.map((pointer) async {
          try {
            return await _resolve(client, pointer);
          } on Object {
            return null;
          }
        }),
      );
      if (_disposed) return;
      _devices = discovered.whereType<PulseCastDevice>().toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    } on Object {
      if (_disposed) return;
      _error = 'Não foi possível procurar dispositivos nesta rede.';
      _devices = const [];
    } finally {
      client.stop();
      if (Platform.isAndroid) {
        try {
          await _androidMulticast.invokeMethod<void>('release');
        } on Object {
          // Discovery already ended; the activity releases its lock on exit.
        }
      }
      if (!_disposed) {
        _scanning = false;
        notifyListeners();
      }
    }
  }

  Future<PulseCastDevice?> _resolve(
    MDnsClient client,
    PtrResourceRecord pointer,
  ) async {
    final services = await client
        .lookup<SrvResourceRecord>(
          ResourceRecordQuery.service(pointer.domainName),
          timeout: const Duration(seconds: 2),
        )
        .toList();
    if (services.isEmpty) return null;
    final service = services.first;
    final addressesFuture = client
        .lookup<IPAddressResourceRecord>(
          ResourceRecordQuery.addressIPv4(service.target),
          timeout: const Duration(seconds: 1),
        )
        .toList();
    final detailsFuture = client
        .lookup<TxtResourceRecord>(
          ResourceRecordQuery.text(pointer.domainName),
          timeout: const Duration(seconds: 1),
        )
        .toList();
    final addresses = await addressesFuture;
    final details = await detailsFuture;
    final advertisedName = details
        .expand((record) => record.text.split('\n'))
        .where((field) => field.startsWith('fn='))
        .map((field) => field.substring(3).trim())
        .where((name) => name.isNotEmpty)
        .firstOrNull;
    final serviceName = pointer.domainName.replaceFirst(
      RegExp(r'\._googlecast\._tcp\.local\.?$', caseSensitive: false),
      '',
    );
    return PulseCastDevice(
      id: pointer.domainName,
      name: advertisedName ??
          (serviceName.isEmpty ? 'Dispositivo Google Cast' : serviceName),
      host: service.target,
      port: service.port,
      address: addresses.firstOrNull?.address.address,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
