import 'audio_track.dart';

class LibrarySnapshot {
  const LibrarySnapshot({
    this.rootPath,
    this.tracks = const [],
    this.favoriteIds = const {},
    this.playlists = const [],
    this.scannedAtMillis,
  });

  final String? rootPath;
  final List<AudioTrack> tracks;
  final Set<String> favoriteIds;
  final List<PulsePlaylist> playlists;
  final int? scannedAtMillis;

  LibrarySnapshot copyWith({
    String? rootPath,
    List<AudioTrack>? tracks,
    Set<String>? favoriteIds,
    List<PulsePlaylist>? playlists,
    int? scannedAtMillis,
  }) =>
      LibrarySnapshot(
        rootPath: rootPath ?? this.rootPath,
        tracks: tracks ?? this.tracks,
        favoriteIds: favoriteIds ?? this.favoriteIds,
        playlists: playlists ?? this.playlists,
        scannedAtMillis: scannedAtMillis ?? this.scannedAtMillis,
      );

  factory LibrarySnapshot.fromJson(Map<String, Object?> json) =>
      LibrarySnapshot(
        rootPath: json['rootPath'] as String?,
        tracks: (json['tracks']! as List)
            .map((value) => AudioTrack.fromJson(value as Map<String, Object?>))
            .toList(growable: false),
        favoriteIds: Set<String>.from(json['favoriteIds']! as List),
        playlists: (json['playlists']! as List)
            .map(
              (value) => PulsePlaylist.fromJson(value as Map<String, Object?>),
            )
            .toList(growable: false),
        scannedAtMillis: json['scannedAtMillis'] as int?,
      );

  Map<String, Object?> toJson() => {
        'rootPath': rootPath,
        'tracks': tracks.map((track) => track.toJson()).toList(growable: false),
        'favoriteIds': favoriteIds.toList(growable: false),
        'playlists': playlists
            .map((playlist) => playlist.toJson())
            .toList(growable: false),
        'scannedAtMillis': scannedAtMillis,
      };
}
