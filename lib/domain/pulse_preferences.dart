enum PulseAppearance { dark, light }

enum PulsePalette { navyGreen, redNavy, blueNavy, purpleDeepBlue, desktopSmoke }

enum PulseDensity { compact, standard, comfortable }

enum PulseStartupBehavior { disabled, normal, minimized }

enum PulseVolumeLevel { quiet, normal, loud }

class PulsePreferences {
  const PulsePreferences({
    this.continuePlayback = true,
    this.autoPlayNext = true,
    this.appearance = PulseAppearance.dark,
    this.palette = PulsePalette.navyGreen,
    this.density = PulseDensity.compact,
    this.compactLibraryLayout = false,
    this.showLocalFiles = false,
    this.onlineSyncedLyrics = true,
    this.closeToMinimize = false,
    this.startupBehavior = PulseStartupBehavior.disabled,
    this.crossfadeEnabled = false,
    this.crossfadeSeconds = 5,
    this.automixEnabled = false,
    this.normalizeVolume = false,
    this.volumeLevel = PulseVolumeLevel.normal,
    this.monoAudio = false,
    this.lastTrackId,
    this.lastPositionMillis = 0,
    this.lastQueueIds = const [],
  });

  final bool continuePlayback;
  final bool autoPlayNext;
  final PulseAppearance appearance;
  final PulsePalette palette;
  final PulseDensity density;
  final bool compactLibraryLayout;
  final bool showLocalFiles;
  final bool onlineSyncedLyrics;
  final bool closeToMinimize;
  final PulseStartupBehavior startupBehavior;
  final bool crossfadeEnabled;
  final int crossfadeSeconds;
  final bool automixEnabled;
  final bool normalizeVolume;
  final PulseVolumeLevel volumeLevel;
  final bool monoAudio;
  final String? lastTrackId;
  final int lastPositionMillis;
  final List<String> lastQueueIds;

  PulsePreferences copyWith(
          {bool? continuePlayback,
          bool? autoPlayNext,
          PulseAppearance? appearance,
          PulsePalette? palette,
          PulseDensity? density,
          bool? compactLibraryLayout,
          bool? showLocalFiles,
          bool? onlineSyncedLyrics,
          bool? closeToMinimize,
          PulseStartupBehavior? startupBehavior,
          bool? crossfadeEnabled,
          int? crossfadeSeconds,
          bool? automixEnabled,
          bool? normalizeVolume,
          PulseVolumeLevel? volumeLevel,
          bool? monoAudio,
          String? lastTrackId,
          int? lastPositionMillis,
          List<String>? lastQueueIds,
          bool clearCheckpoint = false}) =>
      PulsePreferences(
        continuePlayback: continuePlayback ?? this.continuePlayback,
        autoPlayNext: autoPlayNext ?? this.autoPlayNext,
        appearance: appearance ?? this.appearance,
        palette: palette ?? this.palette,
        density: density ?? this.density,
        compactLibraryLayout: compactLibraryLayout ?? this.compactLibraryLayout,
        showLocalFiles: showLocalFiles ?? this.showLocalFiles,
        onlineSyncedLyrics: onlineSyncedLyrics ?? this.onlineSyncedLyrics,
        closeToMinimize: closeToMinimize ?? this.closeToMinimize,
        startupBehavior: startupBehavior ?? this.startupBehavior,
        crossfadeEnabled: crossfadeEnabled ?? this.crossfadeEnabled,
        crossfadeSeconds: crossfadeSeconds ?? this.crossfadeSeconds,
        automixEnabled: automixEnabled ?? this.automixEnabled,
        normalizeVolume: normalizeVolume ?? this.normalizeVolume,
        volumeLevel: volumeLevel ?? this.volumeLevel,
        monoAudio: monoAudio ?? this.monoAudio,
        lastTrackId: clearCheckpoint ? null : lastTrackId ?? this.lastTrackId,
        lastPositionMillis:
            clearCheckpoint ? 0 : lastPositionMillis ?? this.lastPositionMillis,
        lastQueueIds:
            clearCheckpoint ? const [] : lastQueueIds ?? this.lastQueueIds,
      );

  Map<String, Object?> toJson() => {
        'continuePlayback': continuePlayback,
        'autoPlayNext': autoPlayNext,
        'appearance': appearance.name,
        'palette': palette.name,
        'density': density.name,
        'compactLibraryLayout': compactLibraryLayout,
        'showLocalFiles': showLocalFiles,
        'onlineSyncedLyrics': onlineSyncedLyrics,
        'closeToMinimize': closeToMinimize,
        'startupBehavior': startupBehavior.name,
        'crossfadeEnabled': crossfadeEnabled,
        'crossfadeSeconds': crossfadeSeconds,
        'automixEnabled': automixEnabled,
        'normalizeVolume': normalizeVolume,
        'volumeLevel': volumeLevel.name,
        'monoAudio': monoAudio,
        'lastTrackId': lastTrackId,
        'lastPositionMillis': lastPositionMillis,
        'lastQueueIds': lastQueueIds,
      };

  factory PulsePreferences.fromJson(Map<String, dynamic> json) =>
      PulsePreferences(
        continuePlayback: json['continuePlayback'] is bool
            ? json['continuePlayback'] as bool
            : true,
        autoPlayNext:
            json['autoPlayNext'] is bool ? json['autoPlayNext'] as bool : true,
        appearance: PulseAppearance.values
                .where((v) => v.name == json['appearance'])
                .firstOrNull ??
            PulseAppearance.dark,
        palette: PulsePalette.values
                .where((value) => value.name == json['palette'])
                .firstOrNull ??
            PulsePalette.navyGreen,
        density: PulseDensity.values
                .where((v) => v.name == json['density'])
                .firstOrNull ??
            PulseDensity.compact,
        compactLibraryLayout: json['compactLibraryLayout'] is bool
            ? json['compactLibraryLayout'] as bool
            : false,
        showLocalFiles: json['showLocalFiles'] is bool
            ? json['showLocalFiles'] as bool
            : false,
        onlineSyncedLyrics: json['onlineSyncedLyrics'] is bool
            ? json['onlineSyncedLyrics'] as bool
            : true,
        closeToMinimize: json['closeToMinimize'] is bool
            ? json['closeToMinimize'] as bool
            : false,
        startupBehavior: PulseStartupBehavior.values
                .where((v) => v.name == json['startupBehavior'])
                .firstOrNull ??
            PulseStartupBehavior.disabled,
        crossfadeEnabled: json['crossfadeEnabled'] == true,
        crossfadeSeconds: json['crossfadeSeconds'] is int
            ? (json['crossfadeSeconds'] as int).clamp(0, 12)
            : 5,
        automixEnabled: json['automixEnabled'] == true,
        normalizeVolume: json['normalizeVolume'] == true,
        volumeLevel: PulseVolumeLevel.values
                .where((v) => v.name == json['volumeLevel'])
                .firstOrNull ??
            PulseVolumeLevel.normal,
        monoAudio: json['monoAudio'] == true,
        lastTrackId: json['lastTrackId'] as String?,
        lastPositionMillis: json['lastPositionMillis'] is int
            ? json['lastPositionMillis'] as int
            : 0,
        lastQueueIds: json['lastQueueIds'] is List
            ? (json['lastQueueIds'] as List)
                .whereType<String>()
                .toList(growable: false)
            : const [],
      );
}
