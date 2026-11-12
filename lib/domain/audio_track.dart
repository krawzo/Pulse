class AudioTrack {
  const AudioTrack({
    required this.id,
    required this.path,
    required this.title,
    required this.sizeBytes,
    required this.modifiedAtMillis,
    this.artist,
    this.album,
    this.genre,
    this.source = AudioSource.local,
    this.artworkUrl,
    this.durationMillis,
  });

  final String id;
  final String path;
  final String title;
  final int sizeBytes;
  final int modifiedAtMillis;
  final String? artist;
  final String? album;
  final String? genre;
  final AudioSource source;
  final String? artworkUrl;
  final int? durationMillis;

  factory AudioTrack.fromJson(Map<String, Object?> json) => AudioTrack(
        id: json['id']! as String,
        path: json['path']! as String,
        title: json['title'] as String? ?? 'Faixa sem título',
        sizeBytes: json['sizeBytes'] as int? ?? 0,
        modifiedAtMillis: json['modifiedAtMillis'] as int? ?? 0,
        artist: json['artist'] as String?,
        album: json['album'] as String?,
        genre: json['genre'] as String?,
        source: AudioSource.values.firstWhere(
          (value) => value.name == json['source'],
          orElse: () => AudioSource.local,
        ),
        artworkUrl: json['artworkUrl'] as String?,
        durationMillis: json['durationMillis'] as int?,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'path': path,
        'title': title,
        'sizeBytes': sizeBytes,
        'modifiedAtMillis': modifiedAtMillis,
        'artist': artist,
        'album': album,
        if (genre != null) 'genre': genre,
        if (source != AudioSource.local) 'source': source.name,
        if (source != AudioSource.local && artworkUrl != null)
          'artworkUrl': artworkUrl,
        if (durationMillis != null) 'durationMillis': durationMillis,
      };
}

enum AudioSource { local, jellyfin }

class PulsePlaylist {
  const PulsePlaylist({
    required this.id,
    required this.name,
    required this.trackIds,
    this.description,
    this.folderName,
  });

  final String id;
  final String name;
  final List<String> trackIds;
  final String? description;
  final String? folderName;

  PulsePlaylist withTrack(String trackId) => PulsePlaylist(
        id: id,
        name: name,
        trackIds:
            trackIds.contains(trackId) ? trackIds : [...trackIds, trackId],
        description: description,
        folderName: folderName,
      );

  factory PulsePlaylist.fromJson(Map<String, Object?> json) => PulsePlaylist(
        id: json['id']! as String,
        name: json['name']! as String,
        trackIds: List<String>.from(json['trackIds']! as List),
        description: json['description'] as String?,
        folderName: json['folderName'] as String?,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'trackIds': trackIds,
        if (description?.trim().isNotEmpty == true) 'description': description,
        if (folderName?.trim().isNotEmpty == true) 'folderName': folderName,
      };
}
