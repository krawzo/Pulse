import 'package:flutter/foundation.dart';

import '../data/windows_library_store.dart';
import '../domain/audio_track.dart';
import '../domain/library_snapshot.dart';

enum LibrarySourceState {
  notConfigured,
  available,
  disconnected,
  readError,
  partial,
}

enum LibraryScanAttemptState {
  none,
  completed,
  noMp3Files,
  disconnected,
  readError,
  partial,
}

class LibraryController extends ChangeNotifier {
  LibraryController(this._store);

  final WindowsLibraryStore _store;
  LibrarySnapshot _snapshot = const LibrarySnapshot();
  bool _loading = false;
  bool _catalogLoaded = false;
  bool _writesAllowed = false;
  bool _catalogRecoveryRequired = false;
  bool _scanning = false;
  String? _errorMessage;
  String? _noticeMessage;
  LibrarySourceState _sourceState = LibrarySourceState.notConfigured;
  LibraryScanAttemptState _scanAttemptState = LibraryScanAttemptState.none;
  String? _scanAttemptPath;

  LibrarySnapshot get snapshot => _snapshot;
  bool get loading => _loading;
  bool get scanning => _scanning;
  String? get errorMessage => _errorMessage;
  String? get noticeMessage => _noticeMessage;
  LibrarySourceState get sourceState => _sourceState;
  LibraryScanAttemptState get scanAttemptState => _scanAttemptState;
  String? get scanAttemptPath => _scanAttemptPath;
  bool get writesAllowed => _writesAllowed;
  bool get catalogRecoveryRequired => _catalogRecoveryRequired;
  String? get preservedDamagedCatalogPath => _store.preservedDamagedPath;
  String? get recoveryBackupPath => _store.recoveryBackupPath;
  String? get primaryCatalogPath => _store.primaryCatalogPath;
  bool get recoveredFromBackup => _store.recoveredFromBackup;
  bool get recoveredPrimaryWasDamaged => _store.primaryWasDamaged;

  Future<void> load() async {
    _loading = true;
    _noticeMessage = null;
    notifyListeners();
    try {
      _snapshot = await _store.load();
      _catalogLoaded = true;
      _writesAllowed = true;
      _catalogRecoveryRequired = false;
      final rootPath = _snapshot.rootPath;
      _sourceState = rootPath == null
          ? LibrarySourceState.notConfigured
          : await _store.isFolderAvailable(rootPath)
              ? LibrarySourceState.available
              : LibrarySourceState.disconnected;
      _errorMessage = null;
      if (_store.recoveredFromBackup) {
        _noticeMessage = _store.primaryWasDamaged
            ? _store.preservedDamagedPath != null
                ? 'O Pulse abriu a última cópia válida. O arquivo danificado foi preservado para diagnóstico.'
                : 'O Pulse abriu a última cópia válida. O arquivo primário permaneceu no local original.'
            : 'O Pulse abriu a cópia de segurança válida do catálogo local.';
      } else if (_store.backupDamaged) {
        _noticeMessage =
            'Catálogo carregado. A cópia de segurança está danificada e foi preservada.';
      }
      _scanAttemptState = LibraryScanAttemptState.none;
      _scanAttemptPath = null;
    } on Object catch (error) {
      _catalogLoaded = false;
      _writesAllowed = false;
      _catalogRecoveryRequired = true;
      _errorMessage = error is LibraryCatalogRecoveryException
          ? 'O catálogo não foi alterado. Verifique os arquivos de recuperação antes de criar uma biblioteca nova.'
          : 'Não foi possível carregar os dados locais. Nenhuma alteração será salva até a leitura funcionar.';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> addFolder(String rootPath) async {
    if (!_canMutate) return;
    _scanning = true;
    _errorMessage = null;
    _noticeMessage = null;
    _scanAttemptState = LibraryScanAttemptState.none;
    _scanAttemptPath = rootPath;
    notifyListeners();
    try {
      final tracks = await _store.scanMp3Folder(rootPath);
      final isReconnect =
          _snapshot.rootPath?.toLowerCase() == rootPath.toLowerCase() &&
              _sourceState != LibrarySourceState.available;
      final next = _snapshot.copyWith(
        rootPath: rootPath,
        tracks: tracks,
        scannedAtMillis: DateTime.now().millisecondsSinceEpoch,
      );
      await _saveSnapshot(next);
      _sourceState = LibrarySourceState.available;
      _scanAttemptState = LibraryScanAttemptState.completed;
      if (isReconnect) {
        _noticeMessage = 'Pasta reconectada. Biblioteca atualizada.';
      }
    } on NoMp3FilesFound {
      _scanAttemptState = LibraryScanAttemptState.noMp3Files;
      if (_samePath(_snapshot.rootPath, rootPath)) {
        _sourceState = LibrarySourceState.available;
        _errorMessage =
            'Nenhum arquivo MP3 ou Opus foi encontrado. A biblioteca anterior foi preservada.';
      } else {
        _errorMessage =
            'Nenhum arquivo MP3 ou Opus foi encontrado em “${_folderName(rootPath)}”. A fonte e o catálogo atuais foram mantidos.';
      }
    } on PartialLibraryScan {
      _scanAttemptState = LibraryScanAttemptState.partial;
      if (_samePath(_snapshot.rootPath, rootPath)) {
        _sourceState = LibrarySourceState.partial;
        _errorMessage = null;
      } else {
        _errorMessage =
            'A pasta escolhida “${_folderName(rootPath)}” teve leitura parcial. A fonte e o catálogo atuais foram mantidos.';
      }
    } on LibrarySourceReadException {
      _scanAttemptState = LibraryScanAttemptState.readError;
      if (_samePath(_snapshot.rootPath, rootPath)) {
        _sourceState = LibrarySourceState.readError;
        _errorMessage = null;
      } else {
        _errorMessage =
            'A pasta escolhida “${_folderName(rootPath)}” não pôde ser lida. A fonte e o catálogo atuais foram mantidos.';
      }
    } on Object {
      if (!await _store.isFolderAvailable(rootPath)) {
        _scanAttemptState = LibraryScanAttemptState.disconnected;
        if (_samePath(_snapshot.rootPath, rootPath)) {
          _sourceState = LibrarySourceState.disconnected;
          _errorMessage = null;
        } else {
          _errorMessage =
              'A pasta escolhida “${_folderName(rootPath)}” não está acessível. A fonte e o catálogo atuais foram mantidos.';
        }
      } else if (_samePath(_snapshot.rootPath, rootPath)) {
        _scanAttemptState = LibraryScanAttemptState.readError;
        _sourceState = LibrarySourceState.readError;
        _errorMessage = null;
      } else {
        _scanAttemptState = LibraryScanAttemptState.readError;
        _errorMessage =
            'A pasta escolhida “${_folderName(rootPath)}” não pôde ser lida. A fonte e o catálogo atuais foram mantidos.';
      }
    } finally {
      _scanning = false;
      notifyListeners();
    }
  }

  Future<void> toggleFavorite(AudioTrack track) async {
    if (!_canMutate) return;
    final ids = Set<String>.from(_snapshot.favoriteIds);
    if (!ids.add(track.id)) ids.remove(track.id);
    await _saveSnapshot(_snapshot.copyWith(favoriteIds: ids));
  }

  Future<void> createPlaylist(String name) =>
      createPlaylistWithTracks(name, const <AudioTrack>[]);

  Future<void> createPlaylistWithTracks(
    String name,
    Iterable<AudioTrack> tracks,
  ) async {
    if (!_canMutate) return;
    final cleanName = name.trim();
    if (cleanName.isEmpty) return;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    final next = _snapshot.copyWith(
      playlists: [
        ..._snapshot.playlists,
        PulsePlaylist(
          id: id,
          name: cleanName,
          trackIds: tracks.map((track) => track.id).toSet().toList(),
        ),
      ],
    );
    await _saveSnapshot(next);
  }

  Future<void> addToPlaylist(String playlistId, AudioTrack track) async {
    if (!_canMutate) return;
    await addTracksToPlaylist(playlistId, [track]);
  }

  Future<void> addTracksToPlaylist(
    String playlistId,
    Iterable<AudioTrack> tracks,
  ) async {
    if (!_canMutate) return;
    final additions = tracks.map((track) => track.id).toSet();
    if (additions.isEmpty) return;
    final playlists = _snapshot.playlists
        .map(
          (playlist) => playlist.id == playlistId
              ? PulsePlaylist(
                  id: playlist.id,
                  name: playlist.name,
                  trackIds: [
                    ...playlist.trackIds,
                    ...additions.where((id) => !playlist.trackIds.contains(id))
                  ],
                  description: playlist.description,
                  folderName: playlist.folderName,
                )
              : playlist,
        )
        .toList(growable: false);
    await _saveSnapshot(_snapshot.copyWith(playlists: playlists));
  }

  Future<void> replacePlaylistTrackIds(
      String playlistId, List<String> trackIds) async {
    if (!_canMutate) return;
    final uniqueIds = trackIds.toSet().toList(growable: false);
    final playlists = _snapshot.playlists
        .map((playlist) => playlist.id == playlistId
            ? PulsePlaylist(
                id: playlist.id,
                name: playlist.name,
                trackIds: uniqueIds,
                description: playlist.description,
                folderName: playlist.folderName,
              )
            : playlist)
        .toList(growable: false);
    await _saveSnapshot(_snapshot.copyWith(playlists: playlists));
  }

  Future<void> updatePlaylistDetails(
    String playlistId, {
    required String name,
    required String description,
  }) async {
    if (!_canMutate) return;
    final cleanName = name.trim();
    if (cleanName.isEmpty) return;
    final playlists = _snapshot.playlists
        .map(
          (playlist) => playlist.id == playlistId
              ? PulsePlaylist(
                  id: playlist.id,
                  name: cleanName,
                  trackIds: playlist.trackIds,
                  description: description.trim(),
                  folderName: playlist.folderName,
                )
              : playlist,
        )
        .toList(growable: false);
    await _saveSnapshot(_snapshot.copyWith(playlists: playlists));
  }

  Future<void> movePlaylistToFolder(
    String playlistId,
    String? folderName,
  ) async {
    if (!_canMutate) return;
    final cleanFolder = folderName?.trim();
    final nextFolder =
        cleanFolder == null || cleanFolder.isEmpty ? null : cleanFolder;
    final playlists = _snapshot.playlists
        .map(
          (playlist) => playlist.id == playlistId
              ? PulsePlaylist(
                  id: playlist.id,
                  name: playlist.name,
                  trackIds: playlist.trackIds,
                  description: playlist.description,
                  folderName: nextFolder,
                )
              : playlist,
        )
        .toList(growable: false);
    await _saveSnapshot(_snapshot.copyWith(playlists: playlists));
  }

  Future<void> deletePlaylist(String playlistId) async {
    if (!_canMutate) return;
    final playlists = _snapshot.playlists
        .where((playlist) => playlist.id != playlistId)
        .toList(growable: false);
    if (playlists.length == _snapshot.playlists.length) return;
    await _saveSnapshot(_snapshot.copyWith(playlists: playlists));
  }

  Future<void> _saveSnapshot(LibrarySnapshot next) async {
    if (!_canMutate) return;
    await _store.save(next);
    _snapshot = next;
    notifyListeners();
  }

  bool get _canMutate => _catalogLoaded && _writesAllowed && !_loading;

  bool _samePath(String? first, String second) {
    if (first == null) return false;
    String normalize(String path) => path
        .replaceAll('/', '\\')
        .replaceAll(RegExp(r'\\+$'), '')
        .toLowerCase();
    return normalize(first) == normalize(second);
  }

  String _folderName(String path) => path.split(RegExp(r'[\\/]')).last;
}
