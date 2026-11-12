import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// One Android audio-output subscription shared by the mini and full players.
class MobileAudioOutput extends ChangeNotifier {
  MobileAudioOutput._();

  static final instance = MobileAudioOutput._();

  StreamSubscription<dynamic>? _subscription;
  String? _deviceName;

  String? get deviceName => _deviceName;

  void start() {
    if (!Platform.isAndroid || _subscription != null) return;
    _subscription = const EventChannel('pulse/audio_output')
        .receiveBroadcastStream()
        .listen(
          (value) => _setDeviceName(value?.toString()),
          onError: (Object _) => _setDeviceName(null),
        );
  }

  void _setDeviceName(String? value) {
    final name = value?.trim();
    final next = name == null || name.isEmpty ? null : name;
    if (_deviceName == next) return;
    _deviceName = next;
    notifyListeners();
  }
}
