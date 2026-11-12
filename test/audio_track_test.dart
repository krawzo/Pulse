import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_flutter/domain/audio_track.dart';

void main() {
  test('MP3 track round-trips ID3 metadata in the local catalog', () {
    const track = AudioTrack(
      id: 'track-1',
      path: r'C:\Music\album\song.mp3',
      title: 'Song title',
      artist: 'Artist name',
      album: 'Album name',
      sizeBytes: 4096,
      modifiedAtMillis: 1791462000000,
    );

    final restored = AudioTrack.fromJson(track.toJson());

    expect(restored.id, track.id);
    expect(restored.path, track.path);
    expect(restored.title, track.title);
    expect(restored.artist, track.artist);
    expect(restored.album, track.album);
    expect(restored.sizeBytes, track.sizeBytes);
    expect(restored.modifiedAtMillis, track.modifiedAtMillis);
  });

  test('legacy catalog entries keep missing ID3 fields empty', () {
    final restored = AudioTrack.fromJson({
      'id': 'legacy-track',
      'path': r'C:\Music\legacy.mp3',
      'title': 'legacy',
      'sizeBytes': 12,
      'modifiedAtMillis': 0,
    });

    expect(restored.artist, isNull);
    expect(restored.album, isNull);
  });
}
