import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_flutter/app/pulse_theme.dart';

void main() {
  test('Pulse palette uses the agreed base colors with readable pairs', () {
    expect(pulseBackground, const Color(0xFF121212));
    expect(pulseCanvasSurface, const Color(0xFF000000));
    expect(pulseDockSurface, const Color(0xFF000000));
    expect(pulseLightDockSurface, const Color(0xFFF8F8F8));
    expect(pulseAccent, const Color(0xFF1ED760));
    expect(pulseDarkText, const Color(0xFFF8F8F8));
    expect(pulseSurface, const Color(0xFF121212));
    expect(pulseSelectedSurface, const Color(0xFF2A2A2A));
    expect(pulseLightSurface, const Color(0xFFF8F8F8));

    for (final light in [false, true]) {
      final scheme = buildPulseTheme(light: light).colorScheme;
      expect(_contrast(scheme.onSurface, scheme.surface), greaterThan(4.5));
      expect(_contrast(scheme.primary, scheme.surface), greaterThan(3.0));
      expect(
        _contrast(scheme.onSecondaryContainer, scheme.secondaryContainer),
        greaterThan(4.5),
      );
      expect(
        _contrast(scheme.onPrimary, scheme.primary),
        greaterThan(4.5),
      );
    }
  });
}

double _contrast(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  final lighter = a > b ? a : b;
  final darker = a > b ? b : a;
  return (lighter + 0.05) / (darker + 0.05);
}
