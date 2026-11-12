import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_flutter/data/pulse_preferences_store.dart';
import 'package:pulse_flutter/domain/pulse_preferences.dart';

void main() {
  test('preferences and playback queue survive a local save and reload',
      () async {
    final directory = await Directory.systemTemp.createTemp('pulse-prefs-');
    addTearDown(() => directory.delete(recursive: true));
    final store = PulsePreferencesStore(storageDirectory: directory);
    const preferences = PulsePreferences(
      continuePlayback: false,
      autoPlayNext: false,
      appearance: PulseAppearance.light,
      palette: PulsePalette.blueNavy,
      density: PulseDensity.comfortable,
      lastTrackId: 'track-1',
      lastPositionMillis: 12345,
      lastQueueIds: ['track-1', 'track-2'],
    );

    await store.save(preferences);

    expect((await store.load()).toJson(), preferences.toJson());
  });

  test(
      'each palette survives save and reload; older data defaults to Navy/Verde',
      () async {
    final directory = await Directory.systemTemp.createTemp('pulse-palettes-');
    addTearDown(() => directory.delete(recursive: true));
    final store = PulsePreferencesStore(storageDirectory: directory);
    for (final palette in PulsePalette.values) {
      final preferences = PulsePreferences(
        appearance: PulseAppearance.light,
        palette: palette,
      );
      await store.save(preferences);
      final restored =
          await PulsePreferencesStore(storageDirectory: directory).load();
      expect(restored.palette, palette);
      expect(restored.appearance, PulseAppearance.light);
    }
    expect(PulsePreferences.fromJson({'appearance': 'dark'}).palette,
        PulsePalette.navyGreen);
    expect(PulsePreferences.fromJson({'palette': 'unknown'}).palette,
        PulsePalette.navyGreen);
  });
}
