import 'dart:io';

import 'package:flutter/material.dart';

import '../domain/pulse_preferences.dart';

const pulseBackground = Color(0xFF121212);
const pulseDarkText = Color(0xFFF8F8F8);
const pulseAccent = Color(0xFF1ED760);
const pulseCanvasSurface = Color(0xFF000000);
const pulseDockSurface = pulseCanvasSurface;
const pulseSidebarSurface = Color(0xFF121212);
const pulseSurface = Color(0xFF121212);
const pulseRaisedSurface = Color(0xFF242424);
const pulseSelectedSurface = Color(0xFF2A2A2A);
const pulseSelectedMarker = pulseAccent;
const pulseHoverSurface = Color(0xFF242424);
const pulseCardRadius = 8.0;
const pulseLightBackground = Color(0xFFF8F8F8);
const pulseLightDockSurface = pulseLightBackground;
const pulseLightSurface = Color(0xFFF8F8F8);
const pulseLightCardSurface = Color(0xFFFFFFFF);
const pulseLightRaised = Color(0xFFEEF2F5);
final pulseLightSelected =
    Color.alphaBlend(pulseAccent.withValues(alpha: 0.10), pulseLightSurface);
const pulseLightAccent = Color(0xFF007D10);
final pulseLightDivider = pulseBackground.withValues(alpha: 0.14);
final pulseLightHoverSurface = Color.alphaBlend(
  pulseBackground.withValues(alpha: 0.05),
  pulseLightSurface,
);
final pulseLightMutedText = pulseBackground.withValues(alpha: 0.78);

class PulsePaletteTheme extends ThemeExtension<PulsePaletteTheme> {
  const PulsePaletteTheme({required this.palette, required this.light});

  final PulsePalette palette;
  final bool light;

  static PulsePaletteTheme of(BuildContext context) =>
      Theme.of(context).extension<PulsePaletteTheme>() ??
      PulsePaletteTheme(
        palette: PulsePalette.navyGreen,
        light: Theme.of(context).brightness == Brightness.light,
      );

  bool get isOriginal => palette == PulsePalette.navyGreen;
  bool get isDesktopSmoke => palette == PulsePalette.desktopSmoke;
  bool get isFrosted => Platform.isWindows && !light;
  Color get accent => switch (palette) {
        PulsePalette.navyGreen => light ? pulseLightAccent : pulseAccent,
        PulsePalette.redNavy => const Color(0xFFA30505),
        PulsePalette.blueNavy => const Color(0xFF0356C5),
        PulsePalette.purpleDeepBlue => const Color(0xFF600053),
        PulsePalette.desktopSmoke =>
          light ? const Color(0xFF3B4650) : const Color(0xFFCAD3DB),
      };
  Color get darkBase => isFrosted
      ? const Color(0xFF1D2327)
      : switch (palette) {
          PulsePalette.purpleDeepBlue => const Color(0xFF0A1A3A),
          PulsePalette.desktopSmoke => const Color(0xFF15191D),
          _ => pulseBackground,
        };
  Color get canvas => light
      ? pulseLightBackground
      : isFrosted
          ? Colors.transparent
          : pulseCanvasSurface;
  Color get dock => light
      ? pulseLightDockSurface
      : isFrosted
          ? Colors.transparent
          : pulseDockSurface;
  Color get sidebar => light
      ? pulseLightSurface
      : isFrosted
          ? const Color(0x6623292E)
          : isOriginal
              ? pulseSidebarSurface
              : Color.alphaBlend(
                  pulseDarkText.withValues(alpha: 0.05), darkBase);
  Color get surface => light
      ? pulseLightCardSurface
      : isFrosted
          ? const Color(0x62242A2F)
          : isOriginal
              ? pulseSurface
              : Color.alphaBlend(
                  pulseDarkText.withValues(alpha: 0.08), darkBase);
  Color get raised => light
      ? pulseLightRaised
      : isFrosted
          ? const Color(0x8040474D)
          : isOriginal
              ? pulseRaisedSurface
              : Color.alphaBlend(
                  pulseDarkText.withValues(alpha: 0.12), darkBase);
  Color get selected => light
      ? isOriginal
          ? pulseLightSelected
          : Color.alphaBlend(accent.withValues(alpha: 0.10), pulseLightSurface)
      : isFrosted
          ? const Color(0xA03B444A)
          : isOriginal
              ? pulseSelectedSurface
              : Color.alphaBlend(accent.withValues(alpha: 0.12), surface);
  Color get hover => light
      ? isOriginal
          ? pulseLightHoverSurface
          : Color.alphaBlend(
              darkBase.withValues(alpha: 0.05), pulseLightSurface)
      : isFrosted
          ? const Color(0xAE1B2329)
          : isOriginal
              ? pulseHoverSurface
              : Color.alphaBlend(
                  pulseDarkText.withValues(alpha: 0.06), surface);
  Color get ink => light ? darkBase : pulseDarkText;
  Color get mutedInk => light
      ? isOriginal
          ? pulseLightMutedText
          : darkBase.withValues(alpha: 0.78)
      : pulseDarkText.withValues(alpha: 0.60);
  Color get selectedInk => isOriginal
      ? light
          ? pulseBackground
          : pulseDarkText
      : light
          ? darkBase
          : Colors.white;
  Color get selectedIcon => isOriginal
      ? light
          ? pulseLightAccent
          : pulseDarkText
      : light
          ? accent
          : Colors.white;
  Color get selectedMarker => isFrosted
      ? accent
      : !isOriginal && !light
          ? Colors.white
          : accent;
  Color get emphasisInk => isFrosted
      ? accent
      : !isOriginal && !light
          ? pulseDarkText
          : accent;
  Color get lightDivider =>
      isOriginal ? pulseLightDivider : darkBase.withValues(alpha: 0.14);
  LinearGradient? get selectionGradient =>
      isFrosted || isOriginal || isDesktopSmoke
          ? null
          : LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [accent, darkBase],
            );
  LinearGradient? get reverseGradient =>
      isFrosted || isOriginal || isDesktopSmoke
          ? null
          : LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [darkBase, accent],
            );
  LinearGradient? get functionalSelectionGradient =>
      light ? null : selectionGradient;
  LinearGradient? get functionalReverseGradient =>
      light ? null : reverseGradient;

  @override
  PulsePaletteTheme copyWith({PulsePalette? palette, bool? light}) =>
      PulsePaletteTheme(
        palette: palette ?? this.palette,
        light: light ?? this.light,
      );

  @override
  PulsePaletteTheme lerp(ThemeExtension<PulsePaletteTheme>? other, double t) =>
      t < 0.5 || other is! PulsePaletteTheme ? this : other;
}

ThemeData buildPulseTheme(
    {String? fontFamily,
    bool light = false,
    PulsePalette palette = PulsePalette.navyGreen,
    VisualDensity density = VisualDensity.standard}) {
  final tokens = PulsePaletteTheme(palette: palette, light: light);
  final onAccent = tokens.isOriginal
      ? (light ? Colors.white : pulseBackground)
      : tokens.isDesktopSmoke
          ? (light ? Colors.white : tokens.darkBase)
          : Colors.white;

  return ThemeData(
    fontFamily: fontFamily,
    extensions: [tokens],
    brightness: light ? Brightness.light : Brightness.dark,
    visualDensity: density,
    canvasColor: tokens.canvas,
    scaffoldBackgroundColor: tokens.dock,
    colorScheme: light
        ? ColorScheme.light(
            primary: tokens.accent,
            onPrimary: onAccent,
            primaryContainer: tokens.selected,
            onPrimaryContainer: tokens.ink,
            secondary: tokens.accent,
            secondaryContainer: tokens.selected,
            onSecondaryContainer: tokens.ink,
            surface: pulseLightCardSurface,
            onSurface: tokens.ink,
            surfaceContainerHighest: tokens.hover,
            outlineVariant: tokens.lightDivider,
            error: Color(0xFFB42318),
          )
        : ColorScheme.dark(
            primary: tokens.accent,
            onPrimary: onAccent,
            primaryContainer: tokens.selected,
            onPrimaryContainer: pulseDarkText,
            secondary: tokens.accent,
            onSecondary: onAccent,
            secondaryContainer: tokens.selected,
            onSecondaryContainer: pulseDarkText,
            surface: tokens.surface,
            onSurface: pulseDarkText,
            surfaceContainerHighest: tokens.hover,
            outlineVariant: pulseDarkText.withValues(alpha: 0.18),
            surfaceTint: tokens.accent,
            error: Color(0xFFFF7777),
          ),
    useMaterial3: true,
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: light ? tokens.accent : pulseDarkText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: light ? tokens.accent : pulseDarkText,
      ),
    ),
    cardTheme: CardThemeData(color: tokens.surface, elevation: 0),
    dividerColor:
        light ? tokens.lightDivider : pulseDarkText.withValues(alpha: 0.18),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: tokens.raised,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    navigationBarTheme: NavigationBarThemeData(
      indicatorColor: tokens.selected,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        return TextStyle(
          color: tokens.ink,
        );
      }),
    ),
    navigationRailTheme: NavigationRailThemeData(
      indicatorColor: tokens.selected,
      selectedIconTheme: IconThemeData(color: tokens.selectedIcon),
    ),
    listTileTheme: tokens.isOriginal
        ? null
        : ListTileThemeData(
            selectedColor: light ? tokens.accent : pulseDarkText,
          ),
  );
}
