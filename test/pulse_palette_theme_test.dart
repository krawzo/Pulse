import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_flutter/app/pulse_theme.dart';
import 'package:pulse_flutter/domain/pulse_preferences.dart';

double _contrast(Color first, Color second) {
  final a = first.computeLuminance();
  final b = second.computeLuminance();
  final lighter = a > b ? a : b;
  final darker = a > b ? b : a;
  return (lighter + 0.05) / (darker + 0.05);
}

void main() {
  test('Navy/Verde keeps the original theme values', () {
    final dark = buildPulseTheme();
    final light = buildPulseTheme(light: true);
    expect(dark.colorScheme.primary, pulseAccent);
    expect(dark.colorScheme.surface, pulseSurface);
    expect(dark.scaffoldBackgroundColor, pulseCanvasSurface);
    expect(light.colorScheme.primary, pulseLightAccent);
    expect(light.colorScheme.surface, pulseLightCardSurface);
    expect(light.scaffoldBackgroundColor, pulseLightBackground);
    expect(dark.extension<PulsePaletteTheme>()!.selectionGradient, isNull);
  });

  test('new palette gradients keep white content readable throughout', () {
    for (final palette in PulsePalette.values.skip(1)) {
      final dark = buildPulseTheme(palette: palette);
      final light = buildPulseTheme(light: true, palette: palette);
      final tokens = dark.extension<PulsePaletteTheme>()!;
      expect(dark.colorScheme.primary, tokens.accent);
      expect(dark.colorScheme.surface, tokens.surface);
      expect(dark.colorScheme.onSurface, pulseDarkText);
      expect(light.colorScheme.onSurface, tokens.darkBase);
      expect(dark.colorScheme.onPrimary, Colors.white);
      expect(light.colorScheme.onPrimary, Colors.white);
      expect(tokens.selectionGradient, isNotNull);
      expect(tokens.reverseGradient, isNotNull);
      for (var step = 0; step <= 100; step++) {
        final color = Color.lerp(tokens.accent, tokens.darkBase, step / 100)!;
        expect(_contrast(Colors.white, color), greaterThanOrEqualTo(4.5),
            reason: '${palette.name} gradient at $step%');
      }
    }
  });
}
