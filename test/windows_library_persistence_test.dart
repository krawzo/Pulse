import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pulse_flutter/data/windows_library_store.dart';
import 'package:pulse_flutter/domain/audio_track.dart';
import 'package:pulse_flutter/domain/library_snapshot.dart';
import 'package:pulse_flutter/state/library_controller.dart';

void main() {
  late Directory temporaryDirectory;
  late Directory storageDirectory;
  late Directory musicDirectory;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp('pulse-test-');
    storageDirectory = Directory('${temporaryDirectory.path}/app-data');
    musicDirectory = Directory('${temporaryDirectory.path}/synthetic-music');
    await musicDirectory.create();
    await _writeMp3(musicDirectory, 'first-track.mp3');
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('chosen folder, favorites, and playlists survive a restart', () async {
    final firstRun = LibraryController(
      WindowsLibraryStore(storageDirectory: storageDirectory),
    );
    await firstRun.load();
    await firstRun.addFolder(musicDirectory.path);
    final track = firstRun.snapshot.tracks.single;
    await firstRun.toggleFavorite(track);
    await firstRun.createPlaylist('Favoritas');
    final playlist = firstRun.snapshot.playlists.single;
    await firstRun.addToPlaylist(playlist.id, track);
    firstRun.dispose();

    final secondRun = LibraryController(
      WindowsLibraryStore(storageDirectory: storageDirectory),
    );
    await secondRun.load();

    expect(secondRun.snapshot.rootPath, musicDirectory.path);
    expect(secondRun.snapshot.tracks.map((item) => item.id), [track.id]);
    expect(secondRun.snapshot.favoriteIds, {track.id});
    expect(secondRun.snapshot.playlists.single.name, 'Favoritas');
    expect(secondRun.snapshot.playlists.single.trackIds, [track.id]);
    expect(secondRun.sourceState, LibrarySourceState.available);
    secondRun.dispose();
  });

  test('corrupt primary recovers valid backup and preserves corrupt bytes',
      () async {
    final initial = LibraryController(
      WindowsLibraryStore(storageDirectory: storageDirectory),
    );
    await initial.load();
    await initial.addFolder(musicDirectory.path);
    final expected = initial.snapshot;
    initial.dispose();

    final primary = File('${storageDirectory.path}/library.json');
    final backup = File('${primary.path}.bak');
    await backup.writeAsBytes(await primary.readAsBytes());
    const corrupt = '{ broken catalog';
    await primary.writeAsString(corrupt);

    final store = WindowsLibraryStore(storageDirectory: storageDirectory);
    final recovered = await store.load();
    expect(recovered.toJson(), expected.toJson());
    expect(store.recoveredFromBackup, isTrue);
    expect(await primary.readAsString(), isNot(contains('broken')));
    expect(await File('${primary.path}.corrupt').readAsString(), corrupt);
    expect((await backup.readAsString()), isNotEmpty);
  });

  test('both invalid catalogs block writes and preserve both files', () async {
    final primary = File('${storageDirectory.path}/library.json');
    final backup = File('${primary.path}.bak');
    await storageDirectory.create(recursive: true);
    await primary.writeAsString('{ invalid primary');
    await backup.writeAsString('{ invalid backup');

    final controller = LibraryController(
      WindowsLibraryStore(storageDirectory: storageDirectory),
    );
    await controller.load();
    expect(controller.writesAllowed, isFalse);
    expect(controller.errorMessage, contains('não foi alterado'));
    final beforePrimary = await primary.readAsBytes();
    final beforeBackup = await backup.readAsBytes();

    await controller.createPlaylist('Não salvar');
    await controller.load();

    expect(await primary.readAsBytes(), beforePrimary);
    expect(await backup.readAsBytes(), beforeBackup);
    expect(controller.snapshot.playlists, isEmpty);
    expect(controller.writesAllowed, isFalse);
    controller.dispose();
  });

  test('missing primary is rebuilt from a valid backup', () async {
    final primary = File('${storageDirectory.path}/library.json');
    final store = WindowsLibraryStore(storageDirectory: storageDirectory);
    await store.save(const LibrarySnapshot());
    final backup = File('${primary.path}.bak');
    expect(await backup.exists(), isTrue);
    await primary.delete();

    final loaded = await store.load();
    expect(loaded.toJson(), const LibrarySnapshot().toJson());
    expect(store.recoveredFromBackup, isTrue);
    expect(await primary.exists(), isTrue);
    expect(await backup.exists(), isTrue);
  });

  test('repeated saves keep one valid backup and no historical snapshots',
      () async {
    final store = WindowsLibraryStore(storageDirectory: storageDirectory);
    for (var revision = 0; revision < 8; revision++) {
      await store.save(LibrarySnapshot(scannedAtMillis: revision));
    }

    final files = await storageDirectory.list().toList();
    final names = files
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .toSet();
    expect(names, {'library.json', 'library.json.bak'});
    expect(await store.load(), isA<LibrarySnapshot>());
    expect(store.backupDamaged, isFalse);
  });

  test('invalid backup is retained for diagnosis while valid backup rotates',
      () async {
    final store = WindowsLibraryStore(storageDirectory: storageDirectory);
    await store.save(const LibrarySnapshot(scannedAtMillis: 1));
    final backup = File('${storageDirectory.path}/library.json.bak');
    await backup.writeAsString('{ broken backup');

    await store.save(const LibrarySnapshot(scannedAtMillis: 2));

    expect(
        await File('${backup.path}.corrupt').readAsString(), '{ broken backup');
    expect(await backup.readAsString(), contains('"scannedAtMillis":1'));
    final names = (await storageDirectory.list().toList())
        .whereType<File>()
        .map((file) => file.uri.pathSegments.last)
        .toSet();
    expect(
        names,
        containsAll(
            {'library.json', 'library.json.bak', 'library.json.bak.corrupt'}));
    expect(names.where((name) => name.contains('.previous')), isEmpty);
  });

  test('missing folder preserves the last snapshot; reconnect refreshes it',
      () async {
    final controller = LibraryController(
      WindowsLibraryStore(storageDirectory: storageDirectory),
    );
    await controller.load();
    await controller.addFolder(musicDirectory.path);
    final track = controller.snapshot.tracks.single;
    await controller.toggleFavorite(track);
    await controller.createPlaylist('Fila local');
    final playlistId = controller.snapshot.playlists.single.id;
    await controller.addToPlaylist(playlistId, track);
    final savedSnapshot = controller.snapshot;

    final offlineDirectory = Directory('${temporaryDirectory.path}/offline');
    await musicDirectory.rename(offlineDirectory.path);
    await controller.load();

    expect(controller.sourceState, LibrarySourceState.disconnected);
    expect(controller.snapshot.tracks.map((item) => item.id), [track.id]);
    await controller.addFolder(musicDirectory.path);
    expect(controller.snapshot.toJson(), savedSnapshot.toJson());
    expect(controller.sourceState, LibrarySourceState.disconnected);

    await offlineDirectory.rename(musicDirectory.path);
    await _writeMp3(musicDirectory, 'second-track.mp3');
    await controller.addFolder(musicDirectory.path);

    expect(controller.sourceState, LibrarySourceState.available);
    expect(controller.snapshot.tracks, hasLength(2));
    expect(controller.snapshot.favoriteIds, {track.id});
    expect(controller.snapshot.playlists.single.id, playlistId);
    expect(controller.snapshot.playlists.single.trackIds, [track.id]);
    expect(controller.noticeMessage, contains('Pasta reconectada'));
    controller.dispose();
  });

  test('accessible folder with no MP3 is not left marked disconnected',
      () async {
    final controller = LibraryController(
      WindowsLibraryStore(storageDirectory: storageDirectory),
    );
    await controller.load();
    await controller.addFolder(musicDirectory.path);
    final savedSnapshot = controller.snapshot;

    final offlineDirectory = Directory('${temporaryDirectory.path}/offline');
    await musicDirectory.rename(offlineDirectory.path);
    await controller.load();
    expect(controller.sourceState, LibrarySourceState.disconnected);

    await musicDirectory.create();
    await controller.addFolder(musicDirectory.path);

    expect(controller.sourceState, LibrarySourceState.available);
    expect(controller.scanAttemptState, LibraryScanAttemptState.noMp3Files);
    expect(controller.snapshot.toJson(), savedSnapshot.toJson());
    expect(controller.errorMessage, contains('Nenhum arquivo MP3'));
    controller.dispose();
  });

  test('partial scan of a new folder stays separate from disconnected source',
      () async {
    final initialController = LibraryController(
      WindowsLibraryStore(storageDirectory: storageDirectory),
    );
    await initialController.load();
    await initialController.addFolder(musicDirectory.path);
    final track = initialController.snapshot.tracks.single;
    await initialController.toggleFavorite(track);
    await initialController.createPlaylist('Fila salva');
    final savedSnapshot = initialController.snapshot;
    initialController.dispose();

    final offlineDirectory = Directory('${temporaryDirectory.path}/offline');
    await musicDirectory.rename(offlineDirectory.path);
    final newSource = Directory('${temporaryDirectory.path}/new-source');
    await newSource.create();
    await _writeMp3(newSource, 'new-track.mp3');

    final controller = LibraryController(_PartialScanStore(storageDirectory));
    await controller.load();
    expect(controller.sourceState, LibrarySourceState.disconnected);
    await controller.addFolder(newSource.path);

    expect(controller.sourceState, LibrarySourceState.disconnected);
    expect(controller.scanAttemptState, LibraryScanAttemptState.partial);
    expect(controller.scanAttemptPath, newSource.path);
    expect(controller.errorMessage, contains('new-source'));
    expect(controller.errorMessage, contains('leitura parcial'));
    expect(controller.snapshot.toJson(), savedSnapshot.toJson());
    expect(controller.snapshot.favoriteIds, {track.id});
    expect(controller.snapshot.playlists.single.name, 'Fila salva');
    controller.dispose();
  });

  test('partial scan keeps the previously saved catalog and collections',
      () async {
    final initialStore =
        WindowsLibraryStore(storageDirectory: storageDirectory);
    final initialController = LibraryController(initialStore);
    await initialController.load();
    await initialController.addFolder(musicDirectory.path);
    final track = initialController.snapshot.tracks.single;
    await initialController.toggleFavorite(track);
    await initialController.createPlaylist('Favoritas');
    final beforeFailure = initialController.snapshot;
    initialController.dispose();

    final partialController = LibraryController(
      _PartialScanStore(storageDirectory),
    );
    await partialController.load();
    await partialController.addFolder(musicDirectory.path);

    expect(partialController.sourceState, LibrarySourceState.partial);
    expect(
      partialController.scanAttemptState,
      LibraryScanAttemptState.partial,
    );
    expect(partialController.snapshot.toJson(), beforeFailure.toJson());
    expect(partialController.errorMessage, isNull);
    partialController.dispose();
  });
}

Future<File> _writeMp3(Directory directory, String name) async =>
    File('${directory.path}/$name')..writeAsBytesSync([1, 2, 3, 4, 5]);

class _PartialScanStore extends WindowsLibraryStore {
  _PartialScanStore(Directory storageDirectory)
      : super(storageDirectory: storageDirectory);

  @override
  Future<List<AudioTrack>> scanMp3Folder(String rootPath) async =>
      throw const PartialLibraryScan(failedLocations: 1);
}
