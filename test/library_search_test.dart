import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_flutter/domain/audio_track.dart';
import 'package:pulse_flutter/domain/library_search.dart';

void main() {
  const track = AudioTrack(
    id: 'track-1',
    path: r'C:\Music\album\song.mp3',
    title: 'Song title',
    artist: 'Artist name',
    album: 'Album name',
    sizeBytes: 4096,
    modifiedAtMillis: 0,
  );

  test('search matches title, artist, and album without case sensitivity', () {
    expect(trackMatchesLibraryQuery(track, 'song'), isTrue);
    expect(trackMatchesLibraryQuery(track, 'ARTIST'), isTrue);
    expect(trackMatchesLibraryQuery(track, 'album name'), isTrue);
    expect(trackMatchesLibraryQuery(track, 'missing'), isFalse);
  });

  test('blank search matches all tracks and missing tags stay absent', () {
    const legacyTrack = AudioTrack(
      id: 'legacy',
      path: r'C:\Music\legacy.mp3',
      title: 'Legacy song',
      sizeBytes: 1,
      modifiedAtMillis: 0,
    );

    expect(trackMatchesLibraryQuery(legacyTrack, '   '), isTrue);
    expect(trackMatchesLibraryQuery(legacyTrack, 'artist'), isFalse);
  });
}
