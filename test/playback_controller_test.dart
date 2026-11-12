import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_flutter/domain/audio_track.dart';
import 'package:pulse_flutter/state/playback_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(_mockAudioPlayerPlatform);

  test('restores the exact persisted queue order', () {
    final controller =
        PlaybackController(onPlayTrack: (track, position) async {});
    addTearDown(controller.dispose);
    final tracks = _tracks(['a', 'b', 'c']);

    expect(controller.restoreCheckpoint(tracks, 'b', 1200, ['c', 'b', 'a']),
        isTrue);
    expect(controller.queue.map((track) => track.id), ['c', 'b', 'a']);
    expect(controller.currentTrack?.id, 'b');
  });

  test('omits unavailable queue IDs and preserves remaining order', () {
    final controller = PlaybackController();
    addTearDown(controller.dispose);
    final tracks = _tracks(['a', 'c']);

    expect(controller.restoreCheckpoint(tracks, 'c', 0, ['c', 'missing', 'a']),
        isFalse);
    expect(controller.queue.map((track) => track.id), ['c', 'a']);
    expect(controller.currentTrack?.id, 'c');
  });

  test('an empty saved queue restores catalog tracks without duplication', () {
    final controller = PlaybackController();
    addTearDown(controller.dispose);
    final tracks = _tracks(['a', 'b']);

    expect(controller.restoreCheckpoint(tracks, 'b', 0), isTrue);
    expect(controller.queue.map((track) => track.id), ['a', 'b']);
    expect(controller.queue.where((track) => track.id == 'b'), hasLength(1));
  });

  test('restores the current track when every saved queue ID disappeared', () {
    final controller = PlaybackController();
    addTearDown(controller.dispose);
    final tracks = _tracks(['current']);

    expect(
      controller.restoreCheckpoint(
        tracks,
        'current',
        4000,
        ['gone-1', 'gone-2'],
      ),
      isFalse,
    );
    expect(controller.queue.map((track) => track.id), ['current']);
    expect(controller.currentTrack?.id, 'current');
  });

  test('shuffle keeps the current track and restores the original queue', () {
    final controller = PlaybackController(random: Random(11));
    addTearDown(controller.dispose);
    final tracks = _tracks(['a', 'b', 'c', 'd']);
    controller.restoreCheckpoint(tracks, 'b', 0);

    controller.setShuffleEnabled(true);
    expect(controller.currentTrack?.id, 'b');
    expect(controller.queue.map((track) => track.id).toSet(),
        {'a', 'b', 'c', 'd'});
    expect(controller.queue, hasLength(4));

    controller.setShuffleEnabled(false);
    expect(controller.queue.map((track) => track.id), ['a', 'b', 'c', 'd']);
    expect(controller.currentTrack?.id, 'b');
  });

  test('repeat mode cycles off, queue, track, then off', () {
    final controller = PlaybackController();
    addTearDown(controller.dispose);

    expect(controller.repeatMode, PulseRepeatMode.off);
    controller.cycleRepeatMode();
    expect(controller.repeatMode, PulseRepeatMode.queue);
    controller.cycleRepeatMode();
    expect(controller.repeatMode, PulseRepeatMode.track);
    controller.cycleRepeatMode();
    expect(controller.repeatMode, PulseRepeatMode.off);
  });

  test('repeat queue wraps from the last track to the first', () async {
    final controller = PlaybackController(
      onPlayTrack: (track, position) async {},
    );
    addTearDown(controller.dispose);
    final tracks = _tracks(['a', 'b']);
    controller.restoreCheckpoint(tracks, 'b', 0);
    controller.cycleRepeatMode();

    await controller.skipNext();

    expect(controller.currentTrack?.id, 'a');
  });
}

List<AudioTrack> _tracks(List<String> ids) => [
      for (final id in ids)
        AudioTrack(
          id: id,
          path: 'C:\\Review\\$id.mp3',
          title: 'Track $id',
          sizeBytes: 100,
          modifiedAtMillis: 1,
        ),
    ];

void _mockAudioPlayerPlatform() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const globalMethodChannel = MethodChannel('xyz.luan/audioplayers.global');
  const globalEventChannel = EventChannel(
    'xyz.luan/audioplayers.global/events',
  );
  const playerMethodChannel = MethodChannel('xyz.luan/audioplayers');

  messenger.setMockMethodCallHandler(globalMethodChannel, (call) async => null);
  messenger.setMockStreamHandler(
    globalEventChannel,
    MockStreamHandler.inline(onListen: (arguments, events) {}),
  );
  messenger.setMockMethodCallHandler(playerMethodChannel, (call) async {
    if (call.method == 'create') {
      final arguments = call.arguments! as Map<Object?, Object?>;
      final playerId = arguments['playerId']! as String;
      messenger.setMockStreamHandler(
        EventChannel('xyz.luan/audioplayers/events/$playerId'),
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.success({'event': 'audio.onPrepared', 'value': true});
          },
        ),
      );
    }
    return null;
  });
}
