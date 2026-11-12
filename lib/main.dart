import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart' as acrylic;
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'app/pulse_app.dart';
import 'app/pulse_audio_handler.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  PulseAudioHandler? audioHandler;
  if (Platform.isAndroid) {
    audioHandler = await AudioService.init(
      builder: PulseAudioHandler.new,
      config: const AudioServiceConfig(
        androidNotificationChannelId: 'com.example.pulse_flutter.playback',
        androidNotificationChannelName: 'Reprodução do Pulse',
        androidStopForegroundOnPause: false,
      ),
    );
  }
  var customTitleBar = false;
  if (Platform.isWindows) {
    try {
      await acrylic.Window.initialize();
      await windowManager.ensureInitialized();
      await windowManager.setTitleBarStyle(
        TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
      customTitleBar = true;
    } on Object {
      // Keep the native title bar if the window plugin cannot initialize.
    }
  }
  runApp(PulseApp(
    audioHandler: audioHandler,
    customTitleBar: customTitleBar,
    enableWindowsAccessibility: args.contains('--enable-windows-accessibility'),
  ));
}
