import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../app/pulse_theme.dart';
import '../domain/audio_track.dart';
import '../domain/pulse_preferences.dart';
import '../data/local_artwork_cache.dart';
import '../data/jellyfin_client.dart';
import '../data/app_data_directory.dart';
import '../domain/library_search.dart';
import '../state/library_controller.dart';
import '../state/jellyfin_controller.dart';
import '../state/playback_controller.dart';
import '../state/pulse_connect_controller.dart';
import 'compact_mini_player.dart';
import 'pulse_collection_card.dart';
import 'pulse_collection_hero.dart';
import 'pulse_header.dart';
import 'pulse_library_shortcut.dart';
import 'pulse_track_artwork.dart';
import 'pulse_navigation.dart';
import 'pulse_navigation_widgets.dart';
import 'pulse_mobile_navigation.dart';
import 'pulse_mobile_browse.dart';
import 'pulse_library_insights.dart';
import 'pulse_mobile_now_playing.dart';
import 'pulse_mobile_playlist_page.dart';
import 'pulse_lyrics_sheet.dart';
import 'pulse_mobile_queue.dart';
import 'pulse_desktop_library_sidebar.dart';
import 'pulse_playlist_add_panel.dart';
import 'pulse_device_panel.dart';
import 'pulse_player_dock.dart';
import 'pulse_now_playing_panel.dart';
import 'pulse_queue_panel.dart';
import 'pulse_panel_resize_handle.dart';
import 'pulse_expanded_player_view.dart';
import 'pulse_playback_mode_buttons.dart';
import 'pulse_track_row.dart';
import 'pulse_settings_page.dart';
import 'pulse_account_page.dart';
import '../platform/windows_fullscreen_controller.dart';

class PulseHomePage extends StatefulWidget {
  PulseHomePage({
    super.key,
    required this.library,
    JellyfinController? jellyfin,
    required this.playback,
    this.connect,
    this.customTitleBar = false,
    this.preferences = const PulsePreferences(),
    this.onPreferencesChanged,
    this.startupNotice,
  }) : jellyfin = jellyfin ?? JellyfinController();

  final LibraryController library;
  final JellyfinController jellyfin;
  final PlaybackController playback;
  final PulseConnectController? connect;
  final bool customTitleBar;
  final PulsePreferences preferences;
  final Future<void> Function(PulsePreferences)? onPreferencesChanged;
  final String? startupNotice;

  @override
  State<PulseHomePage> createState() => _PulseHomePageState();
}

class _PulseHomePageState extends State<PulseHomePage>
    with WidgetsBindingObserver {
  static const _mobileFolderChannel = MethodChannel('pulse/mobile_folder');
  final _searchController = TextEditingController();
  final _playlistSearchController = TextEditingController();
  final _playlistDiscoveryController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _normalFocusNode = FocusNode();
  final _expandedFocusNode = FocusNode();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _pageStorageBucket = PageStorageBucket();
  final _windowsFullscreen = WindowsFullscreenController();
  final _deviceTapRegionGroup = Object();
  double? _sidebarWidth;
  bool _libraryPanelOpen = true;
  bool _nowPlayingPanelOpen = true;
  bool _rightPanelQueue = false;
  bool _playlistAddPanelOpen = false;
  String _playlistAddQuery = '';
  bool _lyricsViewOpen = false;
  bool _devicePanelOpen = false;
  double? _nowPlayingPanelWidth;
  bool _isPlayerExpanded = false;
  bool _playerTransitionInProgress = false;
  bool _playerTransitionCoverVisible = false;
  PulseDestination _destination = PulseDestination.library;
  PulseMobileTab _mobileTab = PulseMobileTab.home;
  String? _selectedPlaylistId;
  String? _selectedAlbumKey;
  String? _selectedArtist;
  String? _selectedRemotePlaylistId;
  String? _selectedRemoteArtist;
  String? _selectedRemoteAlbumKey;
  Future<List<AudioTrack>>? _remotePlaylistTracks;
  Timer? _playlistSyncTimer;
  bool _playlistSyncing = false;
  AppLifecycleState _appLifecycleState = AppLifecycleState.resumed;
  String _query = '';
  String _playlistQuery = '';
  bool _playlistSearchOpen = false;
  _PlaylistSort _playlistSort = _PlaylistSort.custom;
  String? _playlistDurationSignature;
  Future<int?>? _playlistDurationFuture;
  final List<_PulseLocation> _navigationHistory = [
    const _PulseLocation(destination: PulseDestination.library),
  ];
  int _historyIndex = 0;
  PulseDestination _destinationBeforeSettings = PulseDestination.library;
  Future<void> _mobileNavigationWrites = Future<void>.value();
  bool _mobileNavigationTouched = false;
  bool _restoredRemotePlaylistNeedsRefresh = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _playlistSyncTimer = Timer.periodic(
      const Duration(seconds: 45),
      (_) => unawaited(_syncJellyfinPlaylists()),
    );
    widget.connect?.onPeerApprovalRequested = _approvePeerConnection;
    if (Platform.isAndroid || Platform.isWindows) {
      widget.jellyfin.addListener(_refreshRestoredRemotePlaylist);
      unawaited(_restoreMobileNavigation());
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appLifecycleState = state;
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.jellyfin.warmConnection().then(
            (_) => _syncJellyfinPlaylists(),
          ));
      if (Platform.isAndroid &&
          widget.jellyfin.connected &&
          !widget.jellyfin.loading &&
          widget.jellyfin.tracks.isEmpty) {
        unawaited(widget.jellyfin.refresh());
      }
    }
  }

  Future<File> _mobileNavigationFile() async {
    final directory = await pulseAppDataDirectory();
    return File(
        '${directory.path}${Platform.pathSeparator}${Platform.isWindows ? 'desktop_navigation' : 'mobile_navigation'}.json');
  }

  Future<void> _restoreMobileNavigation() async {
    try {
      final file = await _mobileNavigationFile();
      if (!await file.exists()) return;
      final value = jsonDecode(await file.readAsString());
      if (value is! Map<String, dynamic>) return;
      final tab = PulseMobileTab.values
          .where((item) => item.name == value['tab'])
          .firstOrNull;
      final destination = PulseDestination.values
          .where((item) => item.name == value['destination'])
          .firstOrNull;
      if (tab == null || destination == null) return;
      final location = _PulseLocation(
        destination: destination,
        playlistId: value['playlistId'] as String?,
        remotePlaylistId: value['remotePlaylistId'] as String?,
        albumKey: value['albumKey'] as String?,
        artist: value['artist'] as String?,
      );
      if (!mounted || _mobileNavigationTouched) return;
      setState(() {
        _mobileTab = tab;
        _navigationHistory
          ..clear()
          ..add(const _PulseLocation(destination: PulseDestination.library));
        if (!_navigationHistory.first.matches(location)) {
          _navigationHistory.add(location);
        }
        _historyIndex = _navigationHistory.length - 1;
        _applyLocation(location);
        _restoredRemotePlaylistNeedsRefresh =
            location.remotePlaylistId != null && widget.jellyfin.tracks.isEmpty;
      });
    } on Object {
      // A damaged navigation snapshot should never block the music library.
    }
  }

  void _saveMobileNavigation() {
    if (!(Platform.isAndroid || Platform.isWindows)) return;
    _mobileNavigationTouched = true;
    final location = _navigationHistory[_historyIndex];
    final snapshot = jsonEncode({
      'tab': _mobileTab.name,
      'destination': location.destination.name,
      'playlistId': location.playlistId,
      'remotePlaylistId': location.remotePlaylistId,
      'albumKey': location.albumKey,
      'artist': location.artist,
    });
    _mobileNavigationWrites = _mobileNavigationWrites.then((_) async {
      final file = await _mobileNavigationFile();
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(snapshot, flush: true);
      if (Platform.isWindows && await file.exists()) await file.delete();
      await temporary.rename(file.path);
    }).catchError((Object _) {});
  }

  void _refreshRestoredRemotePlaylist() {
    if (!_restoredRemotePlaylistNeedsRefresh ||
        !widget.jellyfin.connected ||
        widget.jellyfin.loading ||
        widget.jellyfin.tracks.isEmpty ||
        !mounted) {
      return;
    }
    _restoredRemotePlaylistNeedsRefresh = false;
    final id = _selectedRemotePlaylistId;
    if (id != null) {
      setState(
          () => _remotePlaylistTracks = widget.jellyfin.playlistTracks(id));
    }
  }

  Future<void> _syncJellyfinPlaylists() async {
    if (!mounted ||
        _playlistSyncing ||
        !widget.jellyfin.connected ||
        widget.jellyfin.loading ||
        _appLifecycleState == AppLifecycleState.paused ||
        _appLifecycleState == AppLifecycleState.hidden) {
      return;
    }
    _playlistSyncing = true;
    try {
      await widget.jellyfin.refreshPlaylists();
      if (!mounted) {
        return;
      }
      if (_selectedRemotePlaylistId case final id?) {
        if (widget.jellyfin.playlists
            .any((playlist) => playlist['Id']?.toString() == id)) {
          setState(() {
            _remotePlaylistTracks = widget.jellyfin.playlistTracks(id);
          });
        } else {
          _navigateTo(
              const _PulseLocation(destination: PulseDestination.playlists));
        }
      }
    } on Object {
      // A temporary network failure keeps the last visible playlist list.
    } finally {
      _playlistSyncing = false;
    }
  }

  Future<bool> _approvePeerConnection(String name, String address) async {
    if (!mounted) return false;
    BuildContext? approvalContext;
    unawaited(Future<void>.delayed(const Duration(seconds: 55), () {
      if (approvalContext?.mounted == true) {
        Navigator.of(approvalContext!).pop(false);
      }
    }));
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            approvalContext = dialogContext;
            return AlertDialog(
              title: const Text('Conectar outro Pulse?'),
              content: Text(
                '$name ($address) quer reproduzir música neste aparelho. '
                'Aceite apenas se reconhecer o dispositivo na sua rede.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Recusar'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('Permitir'),
                ),
              ],
            );
          },
        ) ??
        false;
  }

  @override
  void dispose() {
    _playlistSyncTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    if (Platform.isAndroid || Platform.isWindows) {
      widget.jellyfin.removeListener(_refreshRestoredRemotePlaylist);
    }
    widget.connect?.onPeerApprovalRequested = null;
    _searchController.dispose();
    _playlistSearchController.dispose();
    _playlistDiscoveryController.dispose();
    _searchFocusNode.dispose();
    _normalFocusNode.dispose();
    _expandedFocusNode.dispose();
    super.dispose();
  }

  Future<void> _addFolder() async {
    if (Platform.isAndroid) {
      final choice = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        backgroundColor: const Color(0xFF242424),
        builder: (sheetContext) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const ListTile(title: Text('Adicionar músicas locais')),
            ListTile(
              leading: const Icon(Icons.folder_open_rounded),
              title: const Text('Selecionar pasta inteira'),
              subtitle: const Text(
                  'Inclui MP3 e Opus de subpastas e permite atualizar depois.'),
              onTap: () => Navigator.of(sheetContext).pop('folder'),
            ),
            ListTile(
              leading: const Icon(Icons.audio_file_rounded),
              title: const Text('Escolher arquivos MP3 ou Opus'),
              subtitle:
                  const Text('Selecione músicas individuais no aparelho.'),
              onTap: () => Navigator.of(sheetContext).pop('files'),
            ),
          ]),
        ),
      );
      if (!mounted) return;
      final currentRoot = widget.library.snapshot.rootPath;
      final changingSource = currentRoot != null &&
          ((choice == 'folder' && !currentRoot.contains('/folder_sources/')) ||
              (choice == 'files' && !currentRoot.endsWith('/mobile_music')));
      if (changingSource && !await _confirmMobileSourceChange()) return;
      if (choice == 'folder') await _selectMobileFolder();
      if (choice == 'files') await _importMobileMusic();
      return;
    }
    try {
      final path = await getDirectoryPath();
      if (!mounted || path == null) return;
      final currentPath = widget.library.snapshot.rootPath;
      if (currentPath != null && !_samePath(currentPath, path)) {
        final replace = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Trocar pasta da biblioteca?'),
            content: const Text(
              'O Pulse vai ler a nova pasta. Seus arquivos não serão movidos, e o '
              'catálogo atual permanece disponível até a leitura terminar.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Trocar pasta'),
              ),
            ],
          ),
        );
        if (replace != true) return;
      }
      await widget.library.addFolder(path);
      if (widget.library.scanAttemptState ==
          LibraryScanAttemptState.completed) {
        await _enableLocalFilesAfterImport();
      }
    } on Object catch (error) {
      if (!mounted) return;
      _showMessage('Não foi possível abrir a seleção de pasta: $error');
    }
  }

  Future<bool> _confirmMobileSourceChange() async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Trocar fonte da biblioteca?'),
          content: const Text(
              'O catálogo da fonte atual fica preservado até a nova leitura terminar. Playlists e músicas curtidas continuam salvas.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Continuar'),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _selectMobileFolder() async {
    try {
      final path = await _mobileFolderChannel.invokeMethod<String>('pick');
      if (!mounted || path == null) return;
      await widget.library.addFolder(path);
      if (!mounted) return;
      if (widget.library.scanAttemptState ==
          LibraryScanAttemptState.completed) {
        await _enableLocalFilesAfterImport();
        _showMessage(
            'Pasta de músicas importada. Os originais foram preservados.');
      } else if (widget.library.errorMessage case final error?) {
        _showMessage(error);
      }
    } on PlatformException catch (error) {
      if (mounted) {
        _showMessage(error.message ?? 'Não foi possível importar a pasta.');
      }
    } on Object catch (error) {
      if (mounted) _showMessage('Não foi possível importar a pasta: $error');
    }
  }

  Future<void> _importMobileMusic() async {
    try {
      final selected = await openFiles(acceptedTypeGroups: const [
        XTypeGroup(
            label: 'Músicas MP3 e Opus',
            extensions: ['mp3', 'opus'],
            mimeTypes: ['audio/mpeg', 'audio/ogg', 'audio/opus']),
      ]);
      if (!mounted || selected.isEmpty) return;
      final support = await pulseAppDataDirectory();
      final destination =
          Directory('${support.path}${Platform.pathSeparator}mobile_music');
      await destination.create(recursive: true);
      var imported = 0;
      for (final selectedFile in selected) {
        final source = File(selectedFile.path);
        if (!await source.exists()) continue;
        final name =
            selectedFile.name.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
        final lowerName = name.toLowerCase();
        if (!lowerName.endsWith('.mp3') && !lowerName.endsWith('.opus')) {
          continue;
        }
        final sourceKey = source.parent.uri.pathSegments
            .where((segment) => segment.isNotEmpty)
            .last
            .replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
        final songDirectory =
            Directory('${destination.path}${Platform.pathSeparator}$sourceKey');
        await songDirectory.create(recursive: true);
        final target =
            File('${songDirectory.path}${Platform.pathSeparator}$name');
        if (await target.exists() &&
            await target.length() == await source.length()) {
          continue;
        }
        await source.copy(target.path);
        imported++;
      }
      await widget.library.addFolder(destination.path);
      if (!mounted) return;
      if (widget.library.scanAttemptState ==
          LibraryScanAttemptState.completed) {
        await _enableLocalFilesAfterImport();
        _showMessage('$imported música(s) importada(s) para o Pulse.');
      } else if (widget.library.errorMessage case final error?) {
        _showMessage(error);
      }
    } on Object catch (error) {
      if (mounted) _showMessage('Não foi possível importar as músicas: $error');
    }
  }

  Future<void> _enableLocalFilesAfterImport() async {
    if (widget.preferences.showLocalFiles) return;
    await widget.onPreferencesChanged
        ?.call(widget.preferences.copyWith(showLocalFiles: true));
  }

  bool _samePath(String first, String second) =>
      _normalizedPath(first) == _normalizedPath(second);

  String _normalizedPath(String path) =>
      path.replaceAll('/', '\\').replaceAll(RegExp(r'\\+$'), '').toLowerCase();

  Future<void> _retryLibraryScan() async {
    final rootPath = widget.library.snapshot.rootPath;
    if (rootPath == null) return;
    if (Platform.isAndroid && rootPath.contains('/folder_sources/')) {
      try {
        await _mobileFolderChannel.invokeMethod<String>('refresh');
      } on PlatformException catch (error) {
        if (mounted) {
          _showMessage(error.message ?? 'Não foi possível atualizar a pasta.');
        }
        return;
      }
    }
    await widget.library.addFolder(rootPath);
  }

  Future<void> _reconnectSavedFolder() => _retryLibraryScan();

  Future<void> _createPlaylist() async {
    final name = await _promptCollectionName(
      title: 'Nova playlist',
      fieldLabel: 'Nome',
      confirmLabel: 'Criar',
    );
    if (name == null) return;
    await _runStoreAction(() async {
      if (widget.jellyfin.connected) {
        await widget.jellyfin.createPlaylist(name, const []);
        if (mounted) {
          _showMessage(
              'Playlist salva na sua conta ${widget.jellyfin.serverName}.');
        }
      } else {
        await widget.library.createPlaylist(name);
      }
    }, retryAfterSignIn: true);
  }

  List<PulsePlaylist> _playlistChoicesForTrack(AudioTrack track) {
    if (track.source != AudioSource.jellyfin) {
      return widget.library.snapshot.playlists;
    }
    return [
      for (final playlist in widget.jellyfin.playlists)
        if (playlist['Id']?.toString() case final id?)
          PulsePlaylist(
            id: '${widget.jellyfin.serverKind.name}:$id',
            name: playlist['Name']?.toString() ?? 'Playlist',
            trackIds: const [],
          ),
    ];
  }

  Future<void> _addTrackToPlaylist(String playlistId, AudioTrack track) async {
    if (playlistId.startsWith('${widget.jellyfin.serverKind.name}:')) {
      if (track.source != AudioSource.jellyfin) {
        throw ArgumentError(
            'A playlist sincronizada aceita apenas músicas do servidor.');
      }
      final id =
          playlistId.substring(widget.jellyfin.serverKind.name.length + 1);
      await widget.jellyfin.addTracksToPlaylist(id, [track]);
      if (mounted && _selectedRemotePlaylistId == id) {
        setState(() {
          _remotePlaylistTracks = widget.jellyfin.playlistTracks(id);
        });
      }
      return;
    }
    await widget.library.addToPlaylist(playlistId, track);
  }

  Future<String?> _promptCollectionName({
    required String title,
    required String fieldLabel,
    required String confirmLabel,
  }) async {
    var enteredName = '';
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          autofocus: true,
          maxLength: 48,
          decoration: InputDecoration(labelText: fieldLabel),
          onChanged: (value) => enteredName = value,
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(enteredName),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    final cleanName = name?.trim();
    return cleanName == null || cleanName.isEmpty ? null : cleanName;
  }

  void _toggleCurrentFavorite() {
    final track = widget.playback.currentTrack;
    if (track != null) {
      _runStoreAction(() => track.source == AudioSource.jellyfin
          ? widget.jellyfin.toggleFavorite(track)
          : widget.library.toggleFavorite(track));
    }
  }

  bool _isFavorite(AudioTrack? track) =>
      track != null &&
      (track.source == AudioSource.jellyfin
          ? widget.jellyfin.favoriteIds.contains(track.id)
          : widget.library.snapshot.favoriteIds.contains(track.id));

  Future<void> _runStoreAction(Future<void> Function() action,
      {bool retryAfterSignIn = false}) async {
    try {
      await action();
    } on JellyfinException catch (error) {
      if (!mounted) return;
      if (error.statusCode == 401) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            duration: const Duration(seconds: 10),
            content: Text(
                'O ${widget.jellyfin.serverName} recusou a sessão. Entre novamente para salvar a playlist.'),
            action: SnackBarAction(
              label: 'Reconectar',
              onPressed: () => unawaited(() async {
                final signedIn = await _openAccount(forceSignIn: true);
                if (signedIn && mounted && retryAfterSignIn) {
                  await _runStoreAction(action);
                }
              }()),
            ),
          ));
      } else {
        _showMessage('Não foi possível salvar a alteração: $error');
      }
    } on Object catch (error) {
      if (mounted) _showMessage('Não foi possível salvar a alteração: $error');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _exitPulse() async {
    try {
      if (Platform.isWindows) {
        await const MethodChannel('pulse/window').invokeMethod<void>('quit');
      } else {
        await SystemNavigator.pop();
      }
    } on Object {
      if (mounted) _showMessage('Não foi possível encerrar o Pulse.');
    }
  }

  void _setSleepTimer(Duration? duration) {
    if (duration == null) {
      if (widget.playback.currentTrack == null) {
        _showMessage('Inicie uma faixa para usar esse timer.');
        return;
      }
      widget.playback.stopAfterCurrentTrack();
      _showMessage('A reprodução vai parar quando a faixa atual acabar.');
    } else if (duration == Duration.zero) {
      widget.playback.cancelSleepTimer();
      _showMessage('Timer cancelado.');
    } else {
      widget.playback.setSleepTimer(duration);
      _showMessage('Timer de ${duration.inMinutes} min ativado.');
    }
  }

  Future<void> _shareTrack(AudioTrack track) async {
    try {
      final file = track.source == AudioSource.local
          ? File(track.path)
          : await widget.jellyfin.prepareTrackForSharing(track);
      if (!await file.exists()) {
        throw StateError('O arquivo desta faixa não está disponível.');
      }
      if (Platform.isWindows) {
        await _showTrackShareDialog(track, file);
        return;
      }
      final details = [
        track.title,
        if (track.artist?.trim().isNotEmpty == true) track.artist!.trim(),
      ].join(' • ');
      final result = await SharePlus.instance.share(
        ShareParams(
          title: track.title,
          text: details,
          files: [XFile(file.path)],
        ),
      );
      if (result.status == ShareResultStatus.success) {
        _showMessage('Faixa enviada.');
      } else if (result.status == ShareResultStatus.unavailable) {
        _showMessage('O Windows não confirmou o envio da faixa.');
      }
    } on Object catch (error) {
      if (mounted) {
        _showMessage('Não foi possível compartilhar a faixa: $error');
      }
    }
  }

  Future<void> _toggleDownload(AudioTrack track) async {
    if (track.source != AudioSource.jellyfin) return;
    try {
      if (widget.jellyfin.isDownloaded(track)) {
        await widget.jellyfin.removeDownload(track);
        if (mounted) _showMessage('Download de “${track.title}” removido.');
      } else {
        await widget.jellyfin.downloadTrack(track);
        if (mounted) _showMessage('“${track.title}” disponível sem internet.');
      }
    } on Object catch (error) {
      if (mounted) _showMessage('Não foi possível baixar a faixa: $error');
    }
  }

  Future<void> _showTrackShareDialog(AudioTrack track, File file) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Enviar “${track.title}”'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Abra a pasta da faixa e anexe o arquivo na conversa desejada.'),
              const SizedBox(height: 12),
              SelectableText(file.path),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: file.path));
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              if (mounted) _showMessage('Caminho da faixa copiado.');
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copiar caminho'),
          ),
          FilledButton.icon(
            onPressed: () async {
              try {
                await Process.start('explorer.exe', [file.parent.path]);
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
              } on Object catch (error) {
                if (mounted) {
                  _showMessage('Não foi possível abrir a pasta: $error');
                }
              }
            },
            icon: const Icon(Icons.folder_open_rounded),
            label: const Text('Abrir pasta'),
          ),
        ],
      ),
    );
  }

  Future<void> _showRecoveryDetails() async {
    final damagedPath = widget.library.preservedDamagedCatalogPath;
    final primaryPath = widget.library.primaryCatalogPath;
    final backupPath = widget.library.recoveryBackupPath;
    final paths = [
      if (damagedPath != null) damagedPath,
      if (damagedPath == null && primaryPath != null) primaryPath,
      if (backupPath != null) backupPath,
    ];
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Arquivos de recuperação'),
        content: SelectableText(paths.join('\n\n')),
        actions: [
          TextButton.icon(
            onPressed: paths.isEmpty
                ? null
                : () async {
                    await Clipboard.setData(
                      ClipboardData(text: paths.join('\n')),
                    );
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    if (mounted) _showMessage('Caminhos copiados.');
                  },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copiar caminhos'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> _showQueue() async {
    if (Platform.isAndroid && MediaQuery.sizeOf(context).width < 600) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: false,
        backgroundColor: Colors.transparent,
        showDragHandle: false,
        builder: (sheetContext) => SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height,
          child: PulseMobileQueue(
            playback: widget.playback,
            onClose: () => Navigator.of(sheetContext).pop(),
            onSetTimer: _setSleepTimer,
          ),
        ),
      );
      return;
    }
    if (MediaQuery.sizeOf(context).width >= 1120) {
      setState(() {
        _lyricsViewOpen = false;
        _nowPlayingPanelOpen = true;
        _rightPanelQueue = !_rightPanelQueue;
      });
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
                child: Text(
                  'Fila',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: widget.playback.queue.length,
                  itemBuilder: (context, index) {
                    final track = widget.playback.queue[index];
                    return ListTile(
                      selected: index == widget.playback.currentIndex,
                      leading: PulseTrackArtwork(
                        track: track,
                        title: track.title,
                        creator: '${track.artist ?? ''}${track.album ?? ''}',
                        size: 40,
                      ),
                      title: Text(track.title),
                      subtitle: Text(track.artist ?? 'Artista não informado'),
                      onTap: () {
                        widget.playback.playQueueItem(index);
                        Navigator.of(context).pop();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showNowPlaying() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: !Platform.isAndroid,
      showDragHandle: false,
      backgroundColor: Platform.isAndroid ? Colors.transparent : null,
      builder: (context) => _NowPlayingSheet(
        playback: widget.playback,
        connect: widget.connect,
        onOpenArtist: (artist) {
          Navigator.of(context).pop();
          _openArtist(artist);
        },
        jellyfin: widget.jellyfin,
        onlineLookupEnabled: widget.preferences.onlineSyncedLyrics,
        onShowQueue: _showQueue,
        onShowDevices: _showMobileDevices,
        onShowTimer: _showMobileTimerChoices,
        onShare: () {
          final track = widget.playback.currentTrack;
          if (track != null) unawaited(_shareTrack(track));
        },
        isFavorite: _isFavorite,
        onToggleFavorite: _toggleCurrentFavorite,
        onMore: () {
          final track = widget.playback.currentTrack;
          if (track != null) _showMobileTrackActions(track);
        },
        onExpand: () {
          Navigator.of(context).pop();
          _expandPlayer();
        },
      ),
    );
  }

  Future<void> _showMobileDevices() async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFF121212),
      builder: (sheetContext) => SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .72,
          child: PulseDevicePanel(
            onClose: () => Navigator.of(sheetContext).pop(),
            connect: widget.connect,
            playback: widget.playback,
          ),
        ),
      ),
    );
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  void _clearPlaylistSearch() {
    _playlistSearchController.clear();
    setState(() => _playlistQuery = '');
  }

  Future<void> _showPlaylistSearchDialog() async {
    var draftQuery = _playlistQuery;
    final query = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Buscar nesta playlist'),
        content: TextFormField(
          initialValue: _playlistQuery,
          autofocus: true,
          decoration:
              const InputDecoration(hintText: 'Título, artista ou álbum'),
          onChanged: (value) => draftQuery = value,
          onFieldSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, ''),
            child: const Text('Limpar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, draftQuery),
            child: const Text('Buscar'),
          ),
        ],
      ),
    );
    if (!mounted || query == null) return;
    _playlistSearchController.text = query;
    setState(() => _playlistQuery = query);
  }

  Widget _buildPlaylistToolbar(bool compact) {
    final foreground = Colors.white.withValues(alpha: .82);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_playlistSearchOpen && !compact)
          SizedBox(
            width: 180,
            child: TextField(
              controller: _playlistSearchController,
              autofocus: true,
              onChanged: (value) => setState(() => _playlistQuery = value),
              style: const TextStyle(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Buscar nesta playlist',
                hintStyle: TextStyle(color: foreground),
                border: const UnderlineInputBorder(),
              ),
            ),
          ),
        IconButton(
          tooltip: 'Buscar nesta playlist',
          color: foreground,
          icon: Icon(_playlistSearchOpen && !compact
              ? Icons.close_rounded
              : Icons.search_rounded),
          onPressed: compact
              ? _showPlaylistSearchDialog
              : () {
                  if (_playlistSearchOpen) _playlistSearchController.clear();
                  setState(() {
                    _playlistSearchOpen = !_playlistSearchOpen;
                    if (!_playlistSearchOpen) _playlistQuery = '';
                  });
                },
        ),
        PopupMenuButton<_PlaylistSort>(
          tooltip: 'Ordenar faixas da playlist',
          initialValue: _playlistSort,
          onSelected: (value) => setState(() => _playlistSort = value),
          itemBuilder: (context) => [
            for (final value in _PlaylistSort.values)
              PopupMenuItem(value: value, child: Text(value.label)),
          ],
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!compact) ...[
                  Text(
                    _playlistSort.label,
                    style: TextStyle(color: foreground, fontSize: 13),
                  ),
                  const SizedBox(width: 5),
                ],
                Icon(Icons.sort_rounded, color: foreground, size: 22),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<AudioTrack> _sortedPlaylistTracks(List<AudioTrack> tracks) {
    if (_playlistSort == _PlaylistSort.custom) return tracks;
    final sorted = List<AudioTrack>.of(tracks);
    String valueFor(AudioTrack track) => switch (_playlistSort) {
          _PlaylistSort.custom => '',
          _PlaylistSort.title => track.title,
          _PlaylistSort.artist => track.artist ?? '',
          _PlaylistSort.album => track.album ?? '',
        };
    sorted.sort((a, b) {
      final comparison =
          valueFor(a).toLowerCase().compareTo(valueFor(b).toLowerCase());
      return comparison != 0
          ? comparison
          : a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return sorted;
  }

  Future<int?> _playlistDuration(List<AudioTrack> tracks) {
    final signature = tracks
        .map((track) =>
            '${track.id}:${track.sizeBytes}:${track.modifiedAtMillis}:${track.durationMillis ?? ''}')
        .join('|');
    if (_playlistDurationSignature == signature &&
        _playlistDurationFuture != null) {
      return _playlistDurationFuture!;
    }
    _playlistDurationSignature = signature;
    _playlistDurationFuture = _calculatePlaylistDuration(tracks);
    return _playlistDurationFuture!;
  }

  Future<int?> _calculatePlaylistDuration(List<AudioTrack> tracks) async {
    var total = 0;
    final missingPaths = <String>[];
    for (final track in tracks) {
      final known = track.durationMillis;
      if (known != null && known > 0) {
        total += known;
      } else if (track.source == AudioSource.local) {
        missingPaths.add(track.path);
      } else {
        return null;
      }
    }
    if (missingPaths.isEmpty) return total;
    final discovered = await compute(_readLocalDurations, missingPaths);
    for (final millis in discovered) {
      if (millis == null || millis <= 0) return null;
      total += millis;
    }
    return total;
  }

  String get _searchEmptyTitle => 'Nenhum resultado para “${_query.trim()}”';

  String get _searchEmptyMessage =>
      'Tente outro termo ou limpe a busca para ver a biblioteca completa.';

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation:
          Listenable.merge([widget.library, widget.playback, widget.jellyfin]),
      builder: (context, _) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final mobileAndroid = Platform.isAndroid && width < 600;
          final collectionOpen = _selectedPlaylistId != null ||
              _selectedRemotePlaylistId != null ||
              _selectedAlbumKey != null ||
              _selectedArtist != null;
          final statusHsv =
              HSVColor.fromColor(Theme.of(context).colorScheme.primary);
          final statusVivid = statusHsv
              .withSaturation(
                  statusHsv.saturation < .68 ? .68 : statusHsv.saturation)
              .withValue(statusHsv.value < .60 ? .60 : statusHsv.value)
              .toColor();
          final mobileStatusColor = collectionOpen
              ? Color.lerp(statusVivid, const Color(0xFF1B1020), .16)!
              : const Color(0xFF121212);
          final compactHeader = width < (widget.customTitleBar ? 900 : 600);
          final rail = width >= 600 && width < 840;
          final desktop = width >= 840;
          final defaultSidebarWidth = width >= 1440
              ? (width * .22).clamp(340.0, 420.0)
              : width >= 1200
                  ? (width * .25).clamp(300.0, 330.0)
                  : width >= 1120
                      ? (width * .21).clamp(220.0, 240.0)
                      : (width * .20).clamp(160.0, 200.0);
          final minSidebarWidth = width >= 1440
              ? 300.0
              : width >= 1200
                  ? 280.0
                  : width >= 1120
                      ? 200.0
                      : 160.0;
          final requestedSidebarWidth = (_sidebarWidth ?? defaultSidebarWidth)
              .clamp(minSidebarWidth, defaultSidebarWidth);
          final defaultPanelWidth = width >= 1440
              ? (width * .21).clamp(360.0, 420.0)
              : width >= 1200
                  ? (width * .21).clamp(280.0, 320.0)
                  : 280.0;
          final leadingWidth = width < 600
              ? 0.0
              : rail
                  ? 72.0
                  : _libraryPanelOpen
                      ? requestedSidebarWidth
                      : 48.0;
          final minCenterWidth = width >= 1440 ? 640.0 : 560.0;
          final minPanelWidth = width >= 1440 ? 320.0 : 240.0;
          final availablePanelWidth =
              width - leadingWidth - minCenterWidth - 48;
          final maxPanelWidth = availablePanelWidth < defaultPanelWidth
              ? availablePanelWidth
              : defaultPanelWidth;
          final panelFits = width >= 1120 && maxPanelWidth >= minPanelWidth;
          final panelWidth = panelFits
              ? (_nowPlayingPanelWidth ?? defaultPanelWidth)
                  .clamp(minPanelWidth, maxPanelWidth)
              : defaultPanelWidth;
          final showPlaylistAddPanel = desktop &&
              panelFits &&
              _playlistAddPanelOpen &&
              _destination == PulseDestination.playlists &&
              (_selectedPlaylistId != null ||
                  _selectedRemotePlaylistId != null) &&
              !_lyricsViewOpen;
          final showPanel = showPlaylistAddPanel ||
              (desktop &&
                  panelFits &&
                  _nowPlayingPanelOpen &&
                  !_lyricsViewOpen);
          final minSidebarCenterWidth = width >= 1440
              ? 640.0
              : width >= 1120
                  ? 560.0
                  : 600.0;
          final maxSidebarWidth = (width -
                  minSidebarCenterWidth -
                  (showPanel ? panelWidth : 0) -
                  (showPanel ? 48 : 32))
              .clamp(minSidebarWidth, defaultSidebarWidth);
          final sidebarWidth =
              requestedSidebarWidth.clamp(minSidebarWidth, maxSidebarWidth);
          final expanded = desktop;
          final dockLeadingWidth = !desktop && rail ? 80.0 : 0.0;
          return PopScope(
            canPop: !Platform.isAndroid ||
                width >= 600 ||
                (_historyIndex == 0 && _mobileTab == PulseMobileTab.home),
            onPopInvokedWithResult: (didPop, _) {
              if (didPop || !Platform.isAndroid) return;
              if (_historyIndex > 0) {
                _goBack();
              } else if (_mobileTab != PulseMobileTab.home) {
                _selectMobileTab(PulseMobileTab.home);
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                IndexedStack(
                  index: _isPlayerExpanded ? 1 : 0,
                  sizing: StackFit.expand,
                  children: [
                    Scaffold(
                      key: _scaffoldKey,
                      extendBody: mobileAndroid,
                      backgroundColor: mobileAndroid
                          ? mobileStatusColor
                          : PulsePaletteTheme.of(context).dock,
                      drawer: width < 600
                          ? Drawer(
                              width: (width - 48).clamp(260.0, 340.0),
                              child: SafeArea(
                                child: PulseExpandedSidebar(
                                  selected: _destination,
                                  onSelect: (destination) {
                                    Navigator.of(context).pop();
                                    destination == PulseDestination.settings
                                        ? _openSettings()
                                        : _selectDestination(destination);
                                  },
                                  playback: widget.playback,
                                  width: (width - 48).clamp(260.0, 340.0),
                                  playlists: widget.library.snapshot.playlists,
                                  remotePlaylists: widget.jellyfin.playlists,
                                  selectedPlaylistId: _selectedPlaylistId,
                                  selectedRemotePlaylistId:
                                      _selectedRemotePlaylistId,
                                  onSelectRemotePlaylist: (id) {
                                    Navigator.of(context).pop();
                                    _openRemotePlaylist(id);
                                  },
                                  onSelectPlaylist: (id) {
                                    Navigator.of(context).pop();
                                    _openPlaylist(id);
                                  },
                                  onPlaylistContextMenu:
                                      _showPlaylistContextMenu,
                                  onCreatePlaylist: () {
                                    Navigator.of(context).pop();
                                    _createPlaylist();
                                  },
                                  onFocusSearch: () {
                                    Navigator.of(context).pop();
                                    _searchFocusNode.requestFocus();
                                  },
                                ),
                              ),
                            )
                          : null,
                      body: SafeArea(
                        bottom: !mobileAndroid,
                        child: CallbackShortcuts(
                          bindings: <ShortcutActivator, VoidCallback>{
                            const SingleActivator(LogicalKeyboardKey.keyF,
                                    control: true):
                                () => _searchFocusNode.requestFocus(),
                            const SingleActivator(LogicalKeyboardKey.escape):
                                () {
                              if (_devicePanelOpen) {
                                _closeDevices();
                              } else if (_lyricsViewOpen) {
                                setState(() => _lyricsViewOpen = false);
                              } else if (_isPlayerExpanded) {
                                _collapsePlayer();
                              } else if (_searchFocusNode.hasFocus) {
                                _searchFocusNode.unfocus();
                              }
                            },
                            const _PlayPauseSpaceActivator():
                                widget.playback.togglePlayback,
                            const SingleActivator(
                                    LogicalKeyboardKey.mediaPlayPause):
                                widget.playback.togglePlayback,
                            const SingleActivator(
                                    LogicalKeyboardKey.mediaTrackNext):
                                widget.playback.skipNext,
                            const SingleActivator(
                                    LogicalKeyboardKey.mediaTrackPrevious):
                                widget.playback.skipPrevious,
                          },
                          child: Focus(
                            focusNode: _normalFocusNode,
                            autofocus: !_isPlayerExpanded,
                            child: Column(
                              children: [
                                if (!(Platform.isAndroid && width < 600))
                                  PulseHeader(
                                    destination: _destination,
                                    compact: compactHeader,
                                    showWindowControls: widget.customTitleBar,
                                    hasLibrarySource:
                                        widget.library.snapshot.rootPath !=
                                            null,
                                    showPrimaryAction: false,
                                    queryController: _searchController,
                                    searchFocusNode: _searchFocusNode,
                                    onQueryChanged: (value) =>
                                        setState(() => _query = value),
                                    onClearQuery: _clearSearch,
                                    onAddFolder: _addFolder,
                                    onCreatePlaylist: _createPlaylist,
                                    onOpenSettings: _openSettings,
                                    onOpenAccount: _openAccount,
                                    accountName: widget.jellyfin.connected
                                        ? widget.jellyfin.username
                                        : null,
                                    accountImageUrl:
                                        widget.jellyfin.profileImageUrl,
                                    onExit: _exitPulse,
                                    onHome: () => _selectDestination(
                                        PulseDestination.library),
                                    showSettingsAction: !desktop && !rail,
                                    showSettingsLeading: false,
                                    showSearch: true,
                                    showHistoryNavigation: desktop,
                                    showNowPlayingAction: desktop && !panelFits,
                                    nowPlayingPanelOpen: showPanel,
                                    onOpenDrawer: width < 600
                                        ? () => _scaffoldKey.currentState
                                            ?.openDrawer()
                                        : null,
                                    onToggleNowPlayingPanel: panelFits
                                        ? () => setState(() =>
                                            _nowPlayingPanelOpen =
                                                !_nowPlayingPanelOpen)
                                        : null,
                                    onOpenNowPlaying: _showNowPlaying,
                                    canGoBack: _historyIndex > 0,
                                    canGoForward: _historyIndex <
                                        _navigationHistory.length - 1,
                                    onGoBack: _goBack,
                                    onGoForward: _goForward,
                                  ),
                                Expanded(
                                  child: Padding(
                                    padding: desktop
                                        ? EdgeInsets.fromLTRB(
                                            8,
                                            8,
                                            8,
                                            PulsePaletteTheme.of(context)
                                                    .isFrosted
                                                ? 8
                                                : 0,
                                          )
                                        : Platform.isAndroid && width < 600
                                            ? EdgeInsets.zero
                                            : const EdgeInsets.all(8),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Row(
                                          children: [
                                            if (desktop &&
                                                _libraryPanelOpen &&
                                                !_lyricsViewOpen)
                                              SizedBox(
                                                width: sidebarWidth,
                                                child: _WorkspaceCard(
                                                  child: width < 1120
                                                      ? PulseExpandedSidebar(
                                                          selected:
                                                              _destination,
                                                          onSelect:
                                                              _selectDestination,
                                                          playback:
                                                              widget.playback,
                                                          width: sidebarWidth,
                                                          playlists: widget
                                                              .library
                                                              .snapshot
                                                              .playlists,
                                                          remotePlaylists:
                                                              widget.jellyfin
                                                                  .playlists,
                                                          selectedPlaylistId:
                                                              _selectedPlaylistId,
                                                          selectedRemotePlaylistId:
                                                              _selectedRemotePlaylistId,
                                                          onSelectRemotePlaylist:
                                                              _openRemotePlaylist,
                                                          onSelectPlaylist:
                                                              _openPlaylist,
                                                          onPlaylistContextMenu:
                                                              _showPlaylistContextMenu,
                                                          onCreatePlaylist:
                                                              _createPlaylist,
                                                          onFocusSearch: () =>
                                                              _searchFocusNode
                                                                  .requestFocus(),
                                                          onCollapse: () =>
                                                              setState(() =>
                                                                  _libraryPanelOpen =
                                                                      false),
                                                        )
                                                      : PulseDesktopLibrarySidebar(
                                                          selected:
                                                              _destination,
                                                          onSelect: (destination) => destination ==
                                                                  PulseDestination
                                                                      .settings
                                                              ? _openSettings()
                                                              : _selectDestination(
                                                                  destination),
                                                          width: sidebarWidth,
                                                          playlists: widget
                                                              .library
                                                              .snapshot
                                                              .playlists,
                                                          remotePlaylists:
                                                              widget.jellyfin
                                                                  .playlists,
                                                          tracks:
                                                              _availablePlaylistTracks,
                                                          compact: widget
                                                              .preferences
                                                              .compactLibraryLayout,
                                                          favoriteIds: {
                                                            ...widget
                                                                .library
                                                                .snapshot
                                                                .favoriteIds,
                                                            ...widget.jellyfin
                                                                .favoriteIds,
                                                          },
                                                          selectedPlaylistId:
                                                              _selectedPlaylistId,
                                                          selectedRemotePlaylistId:
                                                              _selectedRemotePlaylistId,
                                                          onSelectRemotePlaylist:
                                                              _openRemotePlaylist,
                                                          onSelectPlaylist:
                                                              _openPlaylist,
                                                          onPlaylistContextMenu:
                                                              _showPlaylistContextMenu,
                                                          onPlayPlaylist:
                                                              _playPlaylistFromSidebar,
                                                          onPlayTrack: (track) {
                                                            final tracks =
                                                                _availablePlaylistTracks;
                                                            final index = tracks
                                                                .indexWhere(
                                                                    (item) =>
                                                                        item.id ==
                                                                        track
                                                                            .id);
                                                            if (index >= 0) {
                                                              widget.playback
                                                                  .playQueue(
                                                                      tracks,
                                                                      index);
                                                            }
                                                          },
                                                          onOpenAlbum:
                                                              _openAlbum,
                                                          onCreatePlaylist: widget
                                                                  .library
                                                                  .catalogRecoveryRequired
                                                              ? null
                                                              : _createPlaylist,
                                                          onFocusSearch: () =>
                                                              _searchFocusNode
                                                                  .requestFocus(),
                                                          onCollapse: () =>
                                                              setState(() =>
                                                                  _libraryPanelOpen =
                                                                      false),
                                                        ),
                                                ),
                                              ),
                                            if (desktop &&
                                                !_libraryPanelOpen &&
                                                !_lyricsViewOpen)
                                              SizedBox(
                                                width: 48,
                                                child: _WorkspaceCard(
                                                  child: Center(
                                                    child: IconButton(
                                                      tooltip:
                                                          'Mostrar biblioteca',
                                                      onPressed: () => setState(
                                                          () =>
                                                              _libraryPanelOpen =
                                                                  true),
                                                      icon: const Icon(Icons
                                                          .chevron_right_rounded),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            if (rail)
                                              SizedBox(
                                                width: 72,
                                                child: _WorkspaceCard(
                                                  child: PulseMediumRail(
                                                    selected: _rootDestination,
                                                    onSelect:
                                                        _selectDestination,
                                                    onFocusSearch: () =>
                                                        _searchFocusNode
                                                            .requestFocus(),
                                                    onOpenSettings:
                                                        _openSettings,
                                                  ),
                                                ),
                                              ),
                                            if (width >= 600)
                                              SizedBox(width: desktop ? 16 : 8),
                                            Expanded(
                                              child: _WorkspaceCard(
                                                child: Stack(
                                                  fit: StackFit.expand,
                                                  children: [
                                                    Column(
                                                      children: [
                                                        if (widget
                                                            .library.scanning)
                                                          _ProgressBanner(
                                                            message: widget
                                                                        .library
                                                                        .scanAttemptPath ==
                                                                    null
                                                                ? 'Lendo a biblioteca…'
                                                                : 'Lendo “${_pathDisplayName(widget.library.scanAttemptPath!)}”…',
                                                          ),
                                                        if (widget.library.sourceState == LibrarySourceState.disconnected ||
                                                            widget.library
                                                                    .sourceState ==
                                                                LibrarySourceState
                                                                    .readError ||
                                                            widget.library
                                                                    .sourceState ==
                                                                LibrarySourceState
                                                                    .partial)
                                                          _SourceStatusBanner(
                                                            state: widget
                                                                .library
                                                                .sourceState,
                                                            rootPath: widget
                                                                .library
                                                                .snapshot
                                                                .rootPath,
                                                            scanning: widget
                                                                .library
                                                                .scanning,
                                                            scanAttemptPath: widget
                                                                .library
                                                                .scanAttemptPath,
                                                            onReconnect:
                                                                _reconnectSavedFolder,
                                                            onRetry:
                                                                _retryLibraryScan,
                                                          ),
                                                        if (widget.library
                                                                .noticeMessage
                                                            case final message?)
                                                          _TimedBanner(
                                                            key: ValueKey(
                                                                'library-notice:$message'),
                                                            child:
                                                                _NoticeBanner(
                                                              message: message,
                                                              title: widget
                                                                      .library
                                                                      .recoveredFromBackup
                                                                  ? 'Catálogo recuperado'
                                                                  : null,
                                                              onShowDetails: widget
                                                                      .library
                                                                      .recoveredFromBackup
                                                                  ? _showRecoveryDetails
                                                                  : null,
                                                            ),
                                                          ),
                                                        if (widget.startupNotice
                                                            case final message?)
                                                          _TimedBanner(
                                                            key: ValueKey(
                                                                'startup-notice:$message'),
                                                            child: _NoticeBanner(
                                                                message:
                                                                    message),
                                                          ),
                                                        if (widget.library
                                                                .errorMessage
                                                            case final message?
                                                            when !widget.library
                                                                .catalogRecoveryRequired)
                                                          _TimedBanner(
                                                            key: ValueKey(
                                                                'library-error:$message'),
                                                            child: _StatusBanner(
                                                                message:
                                                                    message),
                                                          ),
                                                        if (widget.jellyfin
                                                                .sessionExpired &&
                                                            _availablePlaylistTracks
                                                                .isNotEmpty)
                                                          _StatusBanner(
                                                            message:
                                                                'A sessão ${widget.jellyfin.serverName} expirou. Entre novamente para sincronizar sua biblioteca.',
                                                            actionLabel:
                                                                'Entrar',
                                                            onAction: () =>
                                                                _openAccount(
                                                                    forceSignIn:
                                                                        true),
                                                          ),
                                                        if (widget.playback
                                                                .errorMessage
                                                            case final message?)
                                                          _TimedBanner(
                                                            key: ValueKey(
                                                                'playback-error:$message'),
                                                            child: _StatusBanner(
                                                                message:
                                                                    message),
                                                          ),
                                                        if (widget
                                                                    .playback
                                                                    .currentTrack
                                                                    ?.source ==
                                                                AudioSource
                                                                    .jellyfin &&
                                                            widget.jellyfin
                                                                    .streamError !=
                                                                null)
                                                          _TimedBanner(
                                                            key: ValueKey(
                                                                'stream-error:${widget.jellyfin.streamError}'),
                                                            child: _StatusBanner(
                                                                message:
                                                                    'Resposta do ${widget.jellyfin.serverName}: ${widget.jellyfin.streamError}'),
                                                          ),
                                                        Expanded(
                                                          child: PageStorage(
                                                            bucket:
                                                                _pageStorageBucket,
                                                            child: _lyricsViewOpen &&
                                                                    desktop
                                                                ? PulseLyricsSheet(
                                                                    playback: widget
                                                                        .playback,
                                                                    jellyfin: widget
                                                                        .jellyfin,
                                                                    onlineLookupEnabled: widget
                                                                        .preferences
                                                                        .onlineSyncedLyrics,
                                                                    workspace:
                                                                        true,
                                                                    headerLabel:
                                                                        'Letras',
                                                                    onClose: () =>
                                                                        setState(() =>
                                                                            _lyricsViewOpen =
                                                                                false),
                                                                  )
                                                                : _buildContent(
                                                                    expanded:
                                                                        expanded),
                                                          ),
                                                        ),
                                                        if (!desktop &&
                                                            !mobileAndroid &&
                                                            (!Platform
                                                                    .isAndroid ||
                                                                widget.playback
                                                                        .currentTrack !=
                                                                    null))
                                                          CompactMiniPlayer(
                                                            mobile: Platform
                                                                    .isAndroid &&
                                                                width < 600,
                                                            track: widget
                                                                .playback
                                                                .currentTrack,
                                                            isPlaying: widget
                                                                .playback
                                                                .isPlaying,
                                                            position: widget
                                                                .playback
                                                                .position,
                                                            duration: widget
                                                                .playback
                                                                .duration,
                                                            onToggle: widget
                                                                .playback
                                                                .togglePlayback,
                                                            onSeek: widget
                                                                .playback.seek,
                                                            onOpenNowPlaying:
                                                                _showNowPlaying,
                                                            onPrevious: widget
                                                                .playback
                                                                .skipPrevious,
                                                            onNext: widget
                                                                .playback
                                                                .skipNext,
                                                          ),
                                                      ],
                                                    ),
                                                    if (mobileAndroid &&
                                                        widget.playback
                                                                .currentTrack !=
                                                            null)
                                                      Positioned(
                                                        left: 0,
                                                        right: 0,
                                                        bottom: 64 +
                                                            MediaQuery
                                                                    .viewPaddingOf(
                                                                        context)
                                                                .bottom,
                                                        child:
                                                            CompactMiniPlayer(
                                                          mobile: true,
                                                          track: widget.playback
                                                              .currentTrack,
                                                          isPlaying: widget
                                                              .playback
                                                              .isPlaying,
                                                          position: widget
                                                              .playback
                                                              .position,
                                                          duration: widget
                                                              .playback
                                                              .duration,
                                                          onToggle: widget
                                                              .playback
                                                              .togglePlayback,
                                                          onSeek: widget
                                                              .playback.seek,
                                                          onOpenNowPlaying:
                                                              _showNowPlaying,
                                                          onPrevious: widget
                                                              .playback
                                                              .skipPrevious,
                                                          onNext: widget
                                                              .playback
                                                              .skipNext,
                                                          onShowDevices:
                                                              _showMobileDevices,
                                                          onToggleFavorite:
                                                              _toggleCurrentFavorite,
                                                          isFavorite:
                                                              _isFavorite(widget
                                                                  .playback
                                                                  .currentTrack),
                                                        ),
                                                      ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                            if (showPanel)
                                              const SizedBox(width: 16),
                                            if (showPanel)
                                              SizedBox(
                                                width: panelWidth,
                                                child: _WorkspaceCard(
                                                  child: showPlaylistAddPanel
                                                      ? _buildPlaylistAddPanel()
                                                      : _rightPanelQueue
                                                          ? PulseQueuePanel(
                                                              playback: widget
                                                                  .playback,
                                                              onClose: () =>
                                                                  setState(() =>
                                                                      _rightPanelQueue =
                                                                          false),
                                                            )
                                                          : PulseNowPlayingPanel(
                                                              playback: widget
                                                                  .playback,
                                                              onOpenArtist:
                                                                  _openArtist,
                                                              onShowLyrics:
                                                                  _toggleLyricsView,
                                                              width: panelWidth,
                                                              isFavorite:
                                                                  _isFavorite(widget
                                                                      .playback
                                                                      .currentTrack),
                                                              onToggleFavorite:
                                                                  _toggleCurrentFavorite,
                                                              onShowQueue:
                                                                  _showQueue,
                                                              onExpandPlayer:
                                                                  _expandPlayer,
                                                              onHidePanel: () =>
                                                                  setState(() =>
                                                                      _nowPlayingPanelOpen =
                                                                          false),
                                                              playlists: widget
                                                                          .playback
                                                                          .currentTrack ==
                                                                      null
                                                                  ? const []
                                                                  : _playlistChoicesForTrack(widget
                                                                      .playback
                                                                      .currentTrack!),
                                                              onAddToPlaylist:
                                                                  (playlistId) {
                                                                final track = widget
                                                                    .playback
                                                                    .currentTrack;
                                                                if (track !=
                                                                    null) {
                                                                  _runStoreAction(() =>
                                                                      _addTrackToPlaylist(
                                                                          playlistId,
                                                                          track));
                                                                }
                                                              },
                                                            ),
                                                ),
                                              ),
                                            if (desktop &&
                                                panelFits &&
                                                !showPanel &&
                                                !_lyricsViewOpen)
                                              const SizedBox(width: 16),
                                            if (desktop &&
                                                panelFits &&
                                                !showPanel)
                                              SizedBox(
                                                width: 48,
                                                child: _WorkspaceCard(
                                                  child: Center(
                                                    child: IconButton(
                                                      tooltip:
                                                          'Mostrar a tela Tocando agora',
                                                      onPressed: () =>
                                                          setState(() {
                                                        _nowPlayingPanelOpen =
                                                            true;
                                                        _rightPanelQueue =
                                                            false;
                                                      }),
                                                      icon: const Icon(Icons
                                                          .chevron_left_rounded),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                        if (desktop &&
                                            _libraryPanelOpen &&
                                            !_lyricsViewOpen)
                                          Positioned(
                                            left: sidebarWidth - 2,
                                            top: 0,
                                            bottom: 0,
                                            width: 12,
                                            child: PulsePanelResizeHandle(
                                              key: const ValueKey(
                                                  'sidebar-resize-handle'),
                                              panelWidth: sidebarWidth,
                                              increaseTowardsRight: true,
                                              semanticLabel:
                                                  'Redimensionar biblioteca',
                                              tooltip:
                                                  'Redimensionar biblioteca',
                                              onResize: (delta) => setState(() {
                                                _sidebarWidth =
                                                    (sidebarWidth + delta)
                                                        .clamp(
                                                  minSidebarWidth,
                                                  maxSidebarWidth,
                                                );
                                              }),
                                            ),
                                          ),
                                        if (showPanel)
                                          Positioned(
                                            right: panelWidth - 2,
                                            top: 0,
                                            bottom: 0,
                                            width: 12,
                                            child: PulsePanelResizeHandle(
                                              key: const ValueKey(
                                                  'now-playing-resize-handle'),
                                              panelWidth: panelWidth,
                                              onResize: (delta) => setState(() {
                                                _nowPlayingPanelWidth =
                                                    (panelWidth + delta).clamp(
                                                  minPanelWidth,
                                                  maxPanelWidth,
                                                );
                                              }),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                                if (desktop)
                                  Padding(
                                    padding: PulsePaletteTheme.of(context)
                                            .isFrosted
                                        ? const EdgeInsets.fromLTRB(8, 0, 8, 8)
                                        : EdgeInsets.zero,
                                    child: PulsePlayerDock(
                                      playback: widget.playback,
                                      onOpenArtist: _openArtistFromPlayer,
                                      connect: widget.connect,
                                      onToggleDevices: _toggleDevices,
                                      deviceTapRegionGroup:
                                          _deviceTapRegionGroup,
                                      devicesOpen: _devicePanelOpen,
                                      isFavorite: _isFavorite(
                                          widget.playback.currentTrack),
                                      onToggleFavorite: _toggleCurrentFavorite,
                                      onShowQueue: _showQueue,
                                      onToggleLyrics: _toggleLyricsView,
                                      lyricsOpen: _lyricsViewOpen,
                                      onExpand: _togglePlayerExpansion,
                                      expanded: _isPlayerExpanded,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      bottomNavigationBar: width < 600
                          ? Platform.isAndroid
                              ? PulseMobileNavigation(
                                  selected: _mobileTab,
                                  onSelect: _selectMobileTab,
                                )
                              : PulseCompactNavigation(
                                  selected: _rootDestination,
                                  onSelect: _selectDestination,
                                )
                          : null,
                    ),
                    Scaffold(
                      backgroundColor: Colors.black,
                      body: SafeArea(
                        child: CallbackShortcuts(
                          bindings: <ShortcutActivator, VoidCallback>{
                            const SingleActivator(LogicalKeyboardKey.escape):
                                () => _devicePanelOpen
                                    ? _closeDevices()
                                    : _collapsePlayer(),
                            const _PlayPauseSpaceActivator():
                                widget.playback.togglePlayback,
                            const SingleActivator(
                                    LogicalKeyboardKey.mediaPlayPause):
                                widget.playback.togglePlayback,
                            const SingleActivator(
                                    LogicalKeyboardKey.mediaTrackNext):
                                widget.playback.skipNext,
                            const SingleActivator(
                                    LogicalKeyboardKey.mediaTrackPrevious):
                                widget.playback.skipPrevious,
                          },
                          child: Focus(
                            focusNode: _expandedFocusNode,
                            autofocus: _isPlayerExpanded,
                            child: Column(
                              children: [
                                Expanded(
                                  child: PulseExpandedPlayerView(
                                    playback: widget.playback,
                                    onOpenArtist: _openArtistFromPlayer,
                                  ),
                                ),
                                Padding(
                                  padding: desktop
                                      ? PulsePaletteTheme.of(context).isFrosted
                                          ? const EdgeInsets.fromLTRB(
                                              8, 0, 8, 8)
                                          : EdgeInsets.zero
                                      : const EdgeInsets.fromLTRB(8, 0, 8, 8),
                                  child: Row(
                                    children: [
                                      if (dockLeadingWidth > 0)
                                        SizedBox(width: dockLeadingWidth),
                                      Expanded(
                                        child: desktop
                                            ? PulsePlayerDock(
                                                playback: widget.playback,
                                                onOpenArtist:
                                                    _openArtistFromPlayer,
                                                connect: widget.connect,
                                                onToggleDevices: _toggleDevices,
                                                deviceTapRegionGroup:
                                                    _deviceTapRegionGroup,
                                                devicesOpen: _devicePanelOpen,
                                                isFavorite: _isFavorite(widget
                                                    .playback.currentTrack),
                                                onToggleFavorite:
                                                    _toggleCurrentFavorite,
                                                onShowQueue: _showQueue,
                                                onToggleLyrics:
                                                    _toggleLyricsView,
                                                lyricsOpen: _lyricsViewOpen,
                                                onExpand:
                                                    _togglePlayerExpansion,
                                                expanded: true,
                                              )
                                            : CompactMiniPlayer(
                                                mobile: Platform.isAndroid &&
                                                    width < 600,
                                                connect: widget.connect,
                                                track: widget
                                                    .playback.currentTrack,
                                                isPlaying:
                                                    widget.playback.isPlaying,
                                                position:
                                                    widget.playback.position,
                                                duration:
                                                    widget.playback.duration,
                                                onToggle: widget
                                                    .playback.togglePlayback,
                                                onSeek: widget.playback.seek,
                                                onOpenNowPlaying:
                                                    _showNowPlaying,
                                                onPrevious: widget
                                                    .playback.skipPrevious,
                                                onNext:
                                                    widget.playback.skipNext,
                                                onShowDevices:
                                                    _showMobileDevices,
                                                onToggleFavorite:
                                                    _toggleCurrentFavorite,
                                                isFavorite: _isFavorite(widget
                                                    .playback.currentTrack),
                                              ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      bottomNavigationBar: width < 600
                          ? Platform.isAndroid
                              ? PulseMobileNavigation(
                                  selected: _mobileTab,
                                  onSelect: _selectMobileTab,
                                )
                              : PulseCompactNavigation(
                                  selected: _rootDestination,
                                  onSelect: _selectDestination,
                                )
                          : null,
                    ),
                  ],
                ),
                if (desktop && _devicePanelOpen)
                  Positioned(
                    top: 8,
                    right: 8,
                    bottom: 96,
                    width: 314,
                    child: TapRegion(
                      groupId: _deviceTapRegionGroup,
                      onTapOutside: (_) => _closeDevices(),
                      child: CallbackShortcuts(
                        bindings: <ShortcutActivator, VoidCallback>{
                          const SingleActivator(LogicalKeyboardKey.escape):
                              _closeDevicesAndRestoreFocus,
                        },
                        child: Focus(
                          autofocus: true,
                          child: Material(
                            color: PulsePaletteTheme.of(context).sidebar,
                            elevation: 12,
                            borderRadius: BorderRadius.circular(10),
                            clipBehavior: Clip.antiAlias,
                            child: PulseDevicePanel(
                              onClose: _closeDevicesAndRestoreFocus,
                              connect: widget.connect,
                              playback: widget.playback,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (Platform.isWindows)
                  Positioned.fill(
                    child: IgnorePointer(
                      ignoring: !_playerTransitionCoverVisible,
                      child: AnimatedOpacity(
                        opacity: _playerTransitionCoverVisible ? 1 : 0,
                        duration: const Duration(milliseconds: 140),
                        curve: Curves.easeInOut,
                        child: const ColoredBox(color: Colors.black),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _expandPlayer() => _setPlayerExpanded(true);

  void _collapsePlayer() => _setPlayerExpanded(false);

  void _togglePlayerExpansion() => _setPlayerExpanded(!_isPlayerExpanded);

  void _toggleLyricsView() {
    if (_isPlayerExpanded) _collapsePlayer();
    setState(() {
      _lyricsViewOpen = !_lyricsViewOpen;
      _devicePanelOpen = false;
    });
  }

  void _toggleDevices() => setState(() => _devicePanelOpen = !_devicePanelOpen);

  void _closeDevices() {
    if (_devicePanelOpen) setState(() => _devicePanelOpen = false);
  }

  void _closeDevicesAndRestoreFocus() {
    _closeDevices();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (_isPlayerExpanded ? _expandedFocusNode : _normalFocusNode)
          .requestFocus();
    });
  }

  Future<void> _setPlayerExpanded(bool expanded) async {
    if (_isPlayerExpanded == expanded || _playerTransitionInProgress) return;
    _playerTransitionInProgress = true;
    if (Platform.isWindows) {
      setState(() => _playerTransitionCoverVisible = true);
      await Future<void>.delayed(const Duration(milliseconds: 140));
      if (!mounted) return;
    }
    if (expanded && !_windowsFullscreen.enter()) {
      setState(() => _playerTransitionCoverVisible = false);
      _playerTransitionInProgress = false;
      return;
    }
    if (!expanded) _windowsFullscreen.exit();
    setState(() => _isPlayerExpanded = expanded);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      (expanded ? _expandedFocusNode : _normalFocusNode).requestFocus();
    });
    if (Platform.isWindows) {
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (mounted) setState(() => _playerTransitionCoverVisible = false);
    }
    _playerTransitionInProgress = false;
  }

  PulseDestination get _rootDestination {
    if (_destination == PulseDestination.favorites ||
        _destination == PulseDestination.playlists) {
      return _destination;
    }
    return PulseDestination.library;
  }

  void _selectMobileTab(PulseMobileTab tab) {
    if (Platform.isAndroid) {
      setState(() {
        _mobileTab = tab;
        _navigationHistory
          ..clear()
          ..add(const _PulseLocation(destination: PulseDestination.library));
        _historyIndex = 0;
        _applyLocation(_navigationHistory.first);
      });
      _saveMobileNavigation();
      return;
    }
    if (_mobileTab != tab) setState(() => _mobileTab = tab);
    _selectDestination(PulseDestination.library);
  }

  void _selectDestination(PulseDestination destination) {
    if (destination == PulseDestination.settings &&
        _destination != PulseDestination.settings) {
      _destinationBeforeSettings = _destination;
    }
    _navigateTo(_PulseLocation(destination: destination));
  }

  void _openSettings() {
    if (_destination == PulseDestination.settings) {
      _selectDestination(_destinationBeforeSettings);
    } else {
      _selectDestination(PulseDestination.settings);
    }
  }

  Future<bool> _openAccount({bool forceSignIn = false}) async {
    if (Platform.isAndroid) {
      return await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            backgroundColor: const Color(0xFF181818),
            builder: (sheetContext) => AnimatedPadding(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(sheetContext).bottom),
              child: FractionallySizedBox(
                heightFactor: MediaQuery.viewInsetsOf(sheetContext).bottom > 0
                    ? .96
                    : .86,
                child: PulseAccountPage(
                  jellyfin: widget.jellyfin,
                  forceSignIn: forceSignIn,
                  onConnected: () {
                    Navigator.of(sheetContext).pop(true);
                    _selectMobileTab(PulseMobileTab.home);
                    unawaited(_restoreNavidromeQueueAfterLogin());
                  },
                  onClose: () => Navigator.of(sheetContext).pop(false),
                ),
              ),
            ),
          ) ??
          false;
    }
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => Dialog(
            backgroundColor: const Color(0xFF181818),
            child: SizedBox(
              width: 480,
              height: 620,
              child: PulseAccountPage(
                jellyfin: widget.jellyfin,
                forceSignIn: forceSignIn,
                onConnected: () {
                  Navigator.of(dialogContext).pop(true);
                  _selectDestination(PulseDestination.library);
                },
                onClose: () => Navigator.of(dialogContext).pop(false),
              ),
            ),
          ),
        ) ??
        false;
  }

  Future<void> _restoreNavidromeQueueAfterLogin() async {
    if (!mounted ||
        widget.jellyfin.serverKind != MusicServerKind.navidrome ||
        widget.playback.currentTrack != null) {
      return;
    }
    try {
      final saved = await widget.jellyfin.savedNavidromeQueue();
      if (!mounted || saved == null || widget.playback.currentTrack != null) {
        return;
      }
      widget.playback.restoreCheckpoint(
        widget.jellyfin.tracks,
        saved.trackId,
        saved.positionMillis,
        saved.queueIds,
      );
    } on Object {
      // A server queue is optional; login and library browsing still work.
    }
  }

  void _openPlaylist(String playlistId) {
    _navigateTo(
      _PulseLocation(
        destination: PulseDestination.playlists,
        playlistId: playlistId,
      ),
    );
  }

  void _openRemotePlaylist(String playlistId) {
    _navigateTo(_PulseLocation(
      destination: PulseDestination.playlists,
      remotePlaylistId: playlistId,
    ));
  }

  void _playPlaylistFromSidebar(String playlistId) {
    final playlists = widget.library.snapshot.playlists;
    final playlistIndex = playlists.indexWhere((item) => item.id == playlistId);
    if (playlistIndex < 0) return;

    final tracksById = {
      for (final track in _availablePlaylistTracks) track.id: track,
    };
    final tracks = playlists[playlistIndex]
        .trackIds
        .map((id) => tracksById[id])
        .whereType<AudioTrack>()
        .toList(growable: false);
    if (tracks.isEmpty) {
      _showMessage('Esta playlist não tem faixas disponíveis para tocar.');
      return;
    }
    widget.playback.playPlaylistQueue(tracks, 0);
  }

  void _openAlbum(String albumKey) {
    _navigateTo(
      _PulseLocation(
        destination: PulseDestination.albums,
        albumKey: albumKey,
      ),
    );
  }

  void _openArtist(String artist) {
    _navigateTo(
      _PulseLocation(
        destination: PulseDestination.artists,
        artist: artist,
      ),
    );
  }

  Future<void> _openArtistFromPlayer(String artist) async {
    if (_isPlayerExpanded) await _setPlayerExpanded(false);
    if (mounted) _openArtist(artist);
  }

  void _openRemoteArtist(String artist) {
    _openArtist(artist);
  }

  void _openRemoteAlbum(AudioTrack track) {
    final album = track.album?.trim();
    if (album == null || album.isEmpty) return;
    _openAlbum('${track.artist?.trim() ?? ''}\u0000$album');
  }

  void _navigateTo(_PulseLocation location) {
    if (_navigationHistory[_historyIndex].matches(location)) {
      if (_lyricsViewOpen) setState(() => _lyricsViewOpen = false);
      return;
    }
    setState(() {
      _lyricsViewOpen = false;
      _navigationHistory.removeRange(
          _historyIndex + 1, _navigationHistory.length);
      _navigationHistory.add(location);
      _historyIndex = _navigationHistory.length - 1;
      _applyLocation(location);
    });
    _saveMobileNavigation();
  }

  void _goBack() {
    if (_lyricsViewOpen) {
      setState(() => _lyricsViewOpen = false);
      return;
    }
    if (_historyIndex == 0) return;
    setState(() {
      _historyIndex--;
      _applyLocation(_navigationHistory[_historyIndex]);
    });
    _saveMobileNavigation();
  }

  void _goBackFromCollection(PulseDestination fallback) {
    if (Platform.isAndroid &&
        MediaQuery.sizeOf(context).width < 600 &&
        _historyIndex > 0) {
      _goBack();
    } else {
      _selectDestination(fallback);
    }
  }

  void _goForward() {
    if (_lyricsViewOpen) {
      setState(() => _lyricsViewOpen = false);
      return;
    }
    if (_historyIndex >= _navigationHistory.length - 1) return;
    setState(() {
      _historyIndex++;
      _applyLocation(_navigationHistory[_historyIndex]);
    });
    _saveMobileNavigation();
  }

  void _applyLocation(_PulseLocation location) {
    if (_selectedPlaylistId != location.playlistId ||
        _selectedRemotePlaylistId != location.remotePlaylistId) {
      _playlistAddPanelOpen =
          location.playlistId != null || location.remotePlaylistId != null;
      _playlistAddQuery = '';
      _playlistDiscoveryController.clear();
    }
    if (_selectedPlaylistId != location.playlistId) {
      _playlistSearchController.clear();
      _playlistQuery = '';
      _playlistSearchOpen = false;
      _playlistSort = _PlaylistSort.custom;
    }
    _destination = location.destination;
    _selectedPlaylistId = location.playlistId;
    if (_selectedRemotePlaylistId != location.remotePlaylistId) {
      _remotePlaylistTracks = location.remotePlaylistId == null
          ? null
          : widget.jellyfin.playlistTracks(location.remotePlaylistId!);
    }
    _selectedRemotePlaylistId = location.remotePlaylistId;
    _selectedAlbumKey = location.albumKey;
    _selectedArtist = location.artist;
  }

  List<AudioTrack> get _visibleLocalTracks => widget.preferences.showLocalFiles
      ? widget.library.snapshot.tracks
      : const <AudioTrack>[];

  List<AudioTrack>? _combinedTracks;
  List<AudioTrack>? _combinedRemote;
  List<AudioTrack>? _combinedLocal;

  List<AudioTrack> get _availablePlaylistTracks {
    final remote = widget.jellyfin.tracks;
    final local = _visibleLocalTracks;
    if (!identical(remote, _combinedRemote) ||
        !identical(local, _combinedLocal)) {
      _combinedRemote = remote;
      _combinedLocal = local;
      _combinedTracks = List.unmodifiable([...remote, ...local]);
    }
    return _combinedTracks!;
  }

  void _openPlaylistAddPanel() {
    if (_selectedPlaylistId == null && _selectedRemotePlaylistId == null) {
      return;
    }
    if (MediaQuery.sizeOf(context).width < 1120) {
      unawaited(_showPlaylistAddSheet());
      return;
    }
    setState(() {
      _playlistAddPanelOpen = true;
      _rightPanelQueue = false;
    });
  }

  void _updatePlaylistAddQuery(String value) {
    if (_playlistAddQuery == value) return;
    setState(() {
      _playlistAddQuery = value;
      _playlistAddPanelOpen = true;
    });
    if (_playlistDiscoveryController.text != value) {
      _playlistDiscoveryController.value = TextEditingValue(
        text: value,
        selection: TextSelection.collapsed(offset: value.length),
      );
    }
  }

  Future<bool> _addFromPlaylistPanel(
      String playlistId, AudioTrack track) async {
    try {
      await _addTrackToPlaylist(playlistId, track);
      return true;
    } on Object catch (error) {
      if (mounted) {
        _showMessage(
            playlistId.startsWith('${widget.jellyfin.serverKind.name}:')
                ? _remotePlaylistError(error)
                : 'Não foi possível adicionar a faixa: $error');
      }
      return false;
    }
  }

  Widget _playlistAddPanelFor(
      String playlistId, List<AudioTrack> tracks, Set<String> existingIds,
      {VoidCallback? onClose}) {
    return PulsePlaylistAddPanel(
      key: ValueKey('playlist-add:$playlistId'),
      tracks: tracks,
      existingIds: existingIds,
      favoriteIds: {
        ...widget.library.snapshot.favoriteIds,
        ...widget.jellyfin.favoriteIds,
      },
      query: _playlistAddQuery,
      onQueryChanged: _updatePlaylistAddQuery,
      onAdd: (track) => _addFromPlaylistPanel(playlistId, track),
      onPlayNext: (track) {
        widget.playback.playNext(track);
        _showMessage('${track.title} será a próxima faixa.');
      },
      onClose: onClose ?? () => setState(() => _playlistAddPanelOpen = false),
    );
  }

  Widget _buildPlaylistAddPanel() {
    if (_selectedRemotePlaylistId case final remoteId?) {
      return FutureBuilder<List<AudioTrack>>(
        future: _remotePlaylistTracks,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Não foi possível abrir a playlist.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return _playlistAddPanelFor(
            '${widget.jellyfin.serverKind.name}:$remoteId',
            widget.jellyfin.tracks,
            snapshot.data!.map((track) => track.id).toSet(),
          );
        },
      );
    }
    final localId = _selectedPlaylistId;
    final playlist = widget.library.snapshot.playlists
        .where((item) => item.id == localId)
        .firstOrNull;
    if (playlist == null) return const SizedBox.shrink();
    return _playlistAddPanelFor(
      playlist.id,
      _availablePlaylistTracks,
      playlist.trackIds.toSet(),
    );
  }

  Future<void> _showPlaylistAddSheet() async {
    final remoteId = _selectedRemotePlaylistId;
    final localId = _selectedPlaylistId;
    if (remoteId == null && localId == null) return;
    List<AudioTrack> tracks;
    Set<String> existingIds;
    String playlistId;
    try {
      if (remoteId != null) {
        playlistId = '${widget.jellyfin.serverKind.name}:$remoteId';
        tracks = widget.jellyfin.tracks;
        existingIds = (await widget.jellyfin.playlistTracks(remoteId))
            .map((track) => track.id)
            .toSet();
      } else {
        playlistId = localId!;
        tracks = _availablePlaylistTracks;
        existingIds = widget.library.snapshot.playlists
                .where((item) => item.id == localId)
                .firstOrNull
                ?.trackIds
                .toSet() ??
            <String>{};
      }
    } on Object catch (error) {
      if (mounted) _showMessage(_remotePlaylistError(error));
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFF1E1E1E),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * .82,
          child: _playlistAddPanelFor(
            playlistId,
            tracks,
            existingIds,
            onClose: () => Navigator.of(sheetContext).pop(),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyPlaylistDiscovery() => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Vamos incrementar sua playlist',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: TextField(
                controller: _playlistDiscoveryController,
                readOnly: MediaQuery.sizeOf(context).width < 1120,
                onTap: MediaQuery.sizeOf(context).width < 1120
                    ? _openPlaylistAddPanel
                    : null,
                onChanged: _updatePlaylistAddQuery,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Buscar músicas',
                  filled: true,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildMobileBrowse() => PulseMobileBrowse(
        tab: _mobileTab,
        tracks: _availablePlaylistTracks,
        newTracks: widget.jellyfin.newTracks,
        onOpenInsights: _openLibraryInsights,
        onMarkNewSeen: () => widget.jellyfin.markNewTracksSeen(),
        playlists: widget.library.snapshot.playlists,
        remotePlaylists: widget.jellyfin.playlists,
        remotePlaylistPrefix: widget.jellyfin.serverKind.name,
        favoriteIds: {
          ...widget.library.snapshot.favoriteIds,
          ...widget.jellyfin.favoriteIds,
        },
        currentTrackId: widget.playback.currentTrack?.id,
        query: _query,
        searchController: _searchController,
        onQueryChanged: (value) => setState(() => _query = value),
        onClearQuery: _clearSearch,
        onOpenSettings: _openSettings,
        onOpenAccount: _openAccount,
        accountName:
            widget.jellyfin.connected ? widget.jellyfin.username : null,
        accountImageUrl: widget.jellyfin.profileImageUrl,
        onOpenFavorites: () => _selectDestination(PulseDestination.favorites),
        onOpenPlaylist: _openPlaylist,
        onOpenRemotePlaylist: _openRemotePlaylist,
        onPlaylistMore: _showMobilePlaylistActions,
        onOpenAlbum: (track) => track.source == AudioSource.jellyfin
            ? _openRemoteAlbum(track)
            : _openAlbum(
                '${track.artist?.trim() ?? ''}\u0000${track.album!.trim()}'),
        onOpenArtist: (track) => track.source == AudioSource.jellyfin
            ? _openRemoteArtist(track.artist!.trim())
            : _openArtist(track.artist!.trim()),
        onImportMusic: _addFolder,
        onCreatePlaylist: _createPlaylist,
        onPlayTrack: (track) {
          final tracks = _availablePlaylistTracks;
          final index = tracks.indexWhere((item) => item.id == track.id);
          if (index >= 0) widget.playback.playQueue(tracks, index);
        },
        onPlayNext: (track) {
          widget.playback.playNext(track);
          _showMessage('${track.title} será a próxima faixa.');
        },
        onTrackMore: _showMobileTrackActions,
        onSelectTab: _selectMobileTab,
      );

  void _openLibraryInsights() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => FractionallySizedBox(
        heightFactor: .88,
        child: PulseLibraryInsights(jellyfin: widget.jellyfin),
      ),
    );
  }

  Future<void> _showMobileTrackActions(AudioTrack track) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFF242424),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            ListTile(
              leading: PulseTrackArtwork(
                  track: track,
                  title: track.title,
                  creator: track.artist ?? '',
                  size: 48),
              title: Text(track.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                  [
                    track.artist?.trim().isNotEmpty == true
                        ? track.artist!.trim()
                        : 'Artista não informado',
                    if (track.genre?.trim().isNotEmpty == true)
                      'Gênero: ${track.genre!.trim()}',
                  ].join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: const Text('Adicionar à playlist'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showMobilePlaylistPicker(track);
              },
            ),
            ListTile(
              leading: Icon(_isFavorite(track)
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded),
              title: Text(_isFavorite(track)
                  ? 'Remover de músicas curtidas'
                  : 'Adicionar a músicas curtidas'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _runStoreAction(() => track.source == AudioSource.jellyfin
                    ? widget.jellyfin.toggleFavorite(track)
                    : widget.library.toggleFavorite(track));
              },
            ),
            ListTile(
              leading: const Icon(Icons.queue_music_rounded),
              title: const Text('Adicionar à fila'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                widget.playback.addToQueue(track);
                _showMessage('${track.title} foi adicionada à fila.');
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_play_rounded),
              title: const Text('Tocar a seguir'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                widget.playback.playNext(track);
                _showMessage('${track.title} será a próxima faixa.');
              },
            ),
            if (track.source == AudioSource.jellyfin)
              ListTile(
                leading: Icon(widget.jellyfin.isDownloaded(track)
                    ? Icons.download_done_rounded
                    : Icons.download_outlined),
                title: Text(widget.jellyfin.isDownloading(track)
                    ? 'Baixando…'
                    : widget.jellyfin.isDownloaded(track)
                        ? 'Remover download'
                        : 'Baixar'),
                onTap: widget.jellyfin.isDownloading(track)
                    ? null
                    : () {
                        Navigator.of(sheetContext).pop();
                        _toggleDownload(track);
                      },
              ),
            ListTile(
              leading: const Icon(Icons.timer_outlined),
              title: const Text('Timer'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showMobileTimerChoices();
              },
            ),
            if (track.artist?.trim().isNotEmpty == true)
              ListTile(
                leading: const Icon(Icons.person_outline_rounded),
                title: const Text('Ir para o artista'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  track.source == AudioSource.jellyfin
                      ? _openRemoteArtist(track.artist!.trim())
                      : _openArtist(track.artist!.trim());
                },
              ),
            if (track.album?.trim().isNotEmpty == true)
              ListTile(
                leading: const Icon(Icons.album_outlined),
                title: const Text('Ir para o álbum'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  track.source == AudioSource.jellyfin
                      ? _openRemoteAlbum(track)
                      : _openAlbum(
                          '${track.artist?.trim() ?? ''}\u0000${track.album!.trim()}');
                },
              ),
            ListTile(
              leading: const Icon(Icons.share_outlined),
              title: const Text('Compartilhar'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _shareTrack(track);
              },
            ),
          ]),
        ),
      ),
    );
  }

  Future<void> _showMobileTimerChoices() async {
    final selected = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF242424),
      builder: (sheetContext) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const ListTile(title: Text('Parar de tocar em')),
          for (final minutes in [5, 10, 15, 30, 45, 60])
            ListTile(
              title: Text(minutes == 60 ? '1 hora' : '$minutes min'),
              onTap: () => Navigator.of(sheetContext).pop(minutes),
            ),
          ListTile(
            title: const Text('Quando a faixa acabar'),
            onTap: () => Navigator.of(sheetContext).pop(-1),
          ),
          if (widget.playback.hasSleepTimer)
            ListTile(
              title: const Text('Cancelar timer'),
              onTap: () => Navigator.of(sheetContext).pop(0),
            ),
        ]),
      ),
    );
    if (!mounted || selected == null) return;
    _setSleepTimer(selected < 0 ? null : Duration(minutes: selected));
  }

  Future<void> _showMobilePlaylistPicker(AudioTrack track) async {
    final playlists = _playlistChoicesForTrack(track);
    if (playlists.isEmpty) {
      await _createMobilePlaylistWithTrack(track);
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF242424),
      builder: (sheetContext) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          const ListTile(title: Text('Adicionar à playlist')),
          for (final playlist in playlists)
            ListTile(
              leading: const Icon(Icons.queue_music_rounded),
              title: Text(playlist.name),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _runStoreAction(() => _addTrackToPlaylist(playlist.id, track));
              },
            ),
          ListTile(
            leading: const Icon(Icons.add_rounded),
            title: const Text('Criar playlist'),
            onTap: () {
              Navigator.of(sheetContext).pop();
              _createMobilePlaylistWithTrack(track);
            },
          ),
        ]),
      ),
    );
  }

  Future<void> _createMobilePlaylistWithTrack(AudioTrack track) async {
    final name = await _promptCollectionName(
      title: 'Nova playlist',
      fieldLabel: 'Nome',
      confirmLabel: 'Criar',
    );
    if (name == null) return;
    await _runStoreAction(() async {
      if (track.source == AudioSource.jellyfin) {
        await widget.jellyfin.createPlaylist(name, [track]);
        if (mounted) {
          _showMessage(
              'Playlist sincronizada com o ${widget.jellyfin.serverName}.');
        }
      } else {
        await widget.library.createPlaylistWithTracks(name, [track]);
      }
    });
  }

  Widget _buildContent({required bool expanded}) {
    final compactAndroid =
        Platform.isAndroid && MediaQuery.sizeOf(context).width < 600;
    if (_destination == PulseDestination.settings) {
      return PulseSettingsPage(
          preferences: widget.preferences,
          library: widget.library,
          jellyfin: widget.jellyfin,
          onPreferencesChanged: widget.onPreferencesChanged ?? (_) async {},
          onChooseFolder: _addFolder,
          onRescan: _retryLibraryScan,
          onExit: _exitPulse,
          desktop: expanded,
          onClearArtwork: () {
            // Clears decoded thumbnails in both Pulse's bounded cache and Flutter's image cache.
            LocalArtworkCache.instance.clear();
            PaintingBinding.instance.imageCache.clear();
            PaintingBinding.instance.imageCache.clearLiveImages();
            _showMessage('Cache de capas limpo.');
          });
    }
    if (_destination == PulseDestination.jellyfin) {
      return _buildJellyfin();
    }
    if (widget.library.loading && widget.jellyfin.tracks.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.library.catalogRecoveryRequired &&
        widget.jellyfin.tracks.isEmpty) {
      return _CatalogRecoveryState(
        message:
            widget.library.errorMessage ?? 'O catálogo não pôde ser carregado.',
        onRetry: widget.library.load,
        onShowDetails: _showRecoveryDetails,
      );
    }
    if (compactAndroid && _destination == PulseDestination.library) {
      return _buildMobileBrowse();
    }
    if (_destination == PulseDestination.playlists) {
      return _buildPlaylists();
    }
    if (_destination == PulseDestination.favorites) {
      final favorites = _availablePlaylistTracks
          .where((track) => _isFavorite(track))
          .toList(growable: false);
      return _buildFavorites(favorites);
    }
    if (_destination == PulseDestination.library && _query.trim().isEmpty) {
      return Column(
        children: [
          if (!expanded && !compactAndroid)
            _LibraryTabs(
              selected: _destination,
              onSelect: _selectDestination,
            ),
          Expanded(child: _buildLibraryOverview(expanded: expanded)),
        ],
      );
    }

    final isLibraryView = _destination == PulseDestination.library ||
        _destination == PulseDestination.tracks ||
        _destination == PulseDestination.albums ||
        _destination == PulseDestination.artists;
    return Column(
      children: [
        if (isLibraryView && !expanded && !compactAndroid)
          _LibraryTabs(selected: _destination, onSelect: _selectDestination),
        Expanded(
          child: switch (_destination) {
            PulseDestination.albums => _selectedAlbumKey == null
                ? _buildTagGroups(byAlbum: true)
                : _buildAlbumDetail(),
            PulseDestination.artists => _selectedArtist == null
                ? _buildTagGroups(byAlbum: false)
                : _buildArtistDetail(),
            _ => _buildTrackCollection(
                _availablePlaylistTracks,
                emptyTitle: 'Sua biblioteca começa aqui',
                emptyMessage: widget.jellyfin.connected
                    ? 'Atualize o catálogo para ver suas músicas.'
                    : 'Entre na sua conta para ver as músicas do servidor.',
              ),
          },
        ),
      ],
    );
  }

  Widget _buildTagGroups({required bool byAlbum}) {
    final tracks = _availablePlaylistTracks;
    final groups =
        byAlbum ? _groupTracksByAlbum(tracks) : _groupTracksByArtist(tracks);
    if (groups.isEmpty) {
      return _EmptyState(
        title: byAlbum ? 'Nenhum álbum nas tags' : 'Nenhum artista nas tags',
        message:
            'Adicione MP3 ou Opus com título, artista e álbum nas tags para organizar esta lista.',
        icon: byAlbum ? Icons.album_outlined : Icons.person_outline_rounded,
      );
    }
    final normalizedQuery = _query.trim().toLowerCase();
    final entries = groups.entries
        .map((entry) {
          final matchingTracks = normalizedQuery.isEmpty
              ? entry.value
              : entry.value
                  .where(
                    (track) => trackMatchesLibraryQuery(track, normalizedQuery),
                  )
                  .toList(growable: false);
          return MapEntry(entry.key, matchingTracks);
        })
        .where((entry) => entry.value.isNotEmpty)
        .toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    if (entries.isEmpty) {
      return _EmptyState(
        title: _searchEmptyTitle,
        message: _searchEmptyMessage,
        icon: Icons.search_off_rounded,
        actionLabel: 'Limpar busca',
        actionIcon: Icons.search_off_rounded,
        onAction: _clearSearch,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(24),
      itemCount: entries.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final entry = entries[index];
        final tracksInGroup = entry.value;
        final first = tracksInGroup.first;
        final title = byAlbum ? first.album!.trim() : entry.key;
        final artist = first.artist?.trim();
        final subtitle = byAlbum
            ? [
                if (artist != null && artist.isNotEmpty) artist,
                '${tracksInGroup.length} faixas',
              ].join(' • ')
            : '${tracksInGroup.length} faixas';
        return ListTile(
          leading: PulseTrackArtwork(
            artworkTracks: _stableArtworkOrder(tracksInGroup),
            title: title,
            creator: subtitle,
            size: 48,
          ),
          title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(subtitle),
          trailing: IconButton(
            tooltip: byAlbum ? 'Reproduzir álbum' : 'Reproduzir grupo',
            onPressed: () => widget.playback.playQueue(tracksInGroup, 0),
            icon: const Icon(Icons.play_arrow_rounded),
          ),
          onTap: byAlbum
              ? () => _openAlbum(entry.key)
              : () => _openArtist(entry.key),
        );
      },
    );
  }

  Widget _buildFavorites(List<AudioTrack> tracks) {
    if (tracks.isEmpty) {
      return _buildTrackCollection(
        tracks,
        emptyTitle: 'Ainda sem favoritos',
        emptyMessage:
            'Suas faixas favoritas aparecem aqui quando você toca no coração.',
      );
    }
    return PulseCollectionHero(
      title: 'Músicas curtidas',
      type: 'Playlist',
      colorOverride: Platform.isWindows ? const Color(0xFF5E49A6) : null,
      metadata: 'Pulse • ${tracks.length} faixas',
      tracks: tracks,
      onBack: () => _goBackFromCollection(PulseDestination.library),
      onPlay: () => widget.playback.playPlaylistQueue(tracks, 0),
      backTooltip: 'Voltar para a biblioteca',
      playTooltip: 'Reproduzir músicas curtidas',
      onShuffle: () {
        widget.playback.setShuffleEnabled(!widget.playback.shuffleEnabled);
        widget.playback.playPlaylistQueue(tracks, 0);
      },
      shuffleActive: widget.playback.shuffleEnabled,
      onAddToQueue: () {
        widget.playback.addTracksToQueue(tracks);
        _showMessage('${tracks.length} faixa(s) adicionada(s) à fila.');
      },
      artworkBuilder: (size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color(0xFF4D12E8),
              Color(0xFF8F78E8),
              Color(0xFFA7D6CC),
            ],
          ),
        ),
        child: Icon(
          Icons.favorite_rounded,
          size: size * .36,
          color: Colors.white,
        ),
      ),
      menuItems: const [
        PopupMenuItem(
          value: 'add_queue',
          child: Text('Adicionar à fila'),
        ),
        PopupMenuItem(
          value: 'share',
          child: Text('Compartilhar músicas curtidas'),
        ),
      ],
      onMenuAction: (action) {
        if (action == 'add_queue') {
          widget.playback.addTracksToQueue(tracks);
          _showMessage('${tracks.length} faixa(s) adicionada(s) à fila.');
        } else if (action == 'share') {
          _shareTrackCollection('Músicas curtidas', tracks);
        }
      },
      content: _buildTrackCollection(
        tracks,
        emptyTitle: 'Ainda sem favoritos',
        emptyMessage:
            'Suas faixas favoritas aparecem aqui quando você toca no coração.',
        tableHeader: true,
      ),
    );
  }

  Widget _buildArtistDetail() {
    final tracks =
        _groupTracksByArtist(_availablePlaylistTracks)[_selectedArtist];
    if (tracks == null || tracks.isEmpty) {
      return Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _goBackFromCollection(PulseDestination.artists),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Artistas'),
            ),
          ),
          const Expanded(
            child: _EmptyState(
              title: 'Artista indisponível',
              message:
                  'As tags deste artista mudaram ou não estão mais na pasta.',
              icon: Icons.person_outline_rounded,
            ),
          ),
        ],
      );
    }

    return PulseCollectionHero(
      title: _selectedArtist!,
      type: 'Artista',
      metadata: '${tracks.length} faixas',
      tracks: _stableArtworkOrder(tracks),
      onBack: () => _goBackFromCollection(PulseDestination.artists),
      onPlay: () => widget.playback.playQueue(tracks, 0),
      backTooltip: 'Voltar para Artistas',
      playTooltip: 'Reproduzir artista',
      content: _buildTrackCollection(
        tracks,
        emptyTitle: 'Nenhuma faixa disponível',
        tableHeader: true,
      ),
    );
  }

  Widget _buildAlbumDetail() {
    final groups = _groupTracksByAlbum(_availablePlaylistTracks);
    final tracks = groups[_selectedAlbumKey];
    if (tracks == null || tracks.isEmpty) {
      return Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => _goBackFromCollection(PulseDestination.albums),
              icon: const Icon(Icons.arrow_back_rounded),
              label: const Text('Álbuns'),
            ),
          ),
          const Expanded(
            child: _EmptyState(
              title: 'Álbum indisponível',
              message:
                  'As tags deste álbum mudaram ou não estão mais na pasta.',
              icon: Icons.album_outlined,
            ),
          ),
        ],
      );
    }

    final first = tracks.first;
    final album = first.album?.trim() ?? 'Álbum';
    final artist = first.artist?.trim();
    return PulseCollectionHero(
      title: album,
      type: 'Álbum',
      metadata:
          '${artist ?? 'Artista não informado'} • ${tracks.length} faixas',
      tracks: _stableArtworkOrder(tracks),
      onBack: () => _goBackFromCollection(PulseDestination.albums),
      onPlay: () => widget.playback.playQueue(tracks, 0),
      backTooltip: 'Voltar para Álbuns',
      playTooltip: 'Reproduzir álbum',
      content: _buildTrackCollection(
        tracks,
        emptyTitle: 'Álbum vazio',
        emptyMessage: 'Este álbum não tem faixas disponíveis.',
        tableHeader: true,
      ),
    );
  }

  Widget _buildLibraryOverview({required bool expanded}) {
    final snapshot = widget.library.snapshot;
    final tracks = _availablePlaylistTracks;
    if (tracks.isEmpty) {
      final sessionExpired = widget.jellyfin.sessionExpired;
      return _EmptyState(
        title: 'Sua biblioteca começa aqui',
        message: sessionExpired
            ? 'A sessão ${widget.jellyfin.serverName} expirou. Entre novamente para recuperar as músicas do servidor.'
            : widget.jellyfin.connected
                ? widget.jellyfin.error ??
                    'Sua conta está conectada. Atualize o catálogo para mostrar as músicas.'
                : 'Entre na sua conta para mostrar as músicas do servidor. Arquivos locais podem ser adicionados nas Configurações.',
        actionLabel: sessionExpired
            ? 'Entrar novamente'
            : widget.jellyfin.connected
                ? 'Atualizar biblioteca'
                : 'Entrar na conta',
        onAction: sessionExpired
            ? () => _openAccount(forceSignIn: true)
            : widget.jellyfin.connected
                ? widget.jellyfin.refresh
                : _openAccount,
      );
    }

    final albumGroups = _groupTracksByAlbum(tracks);
    final shortcuts = <({
      String title,
      String subtitle,
      String identity,
      VoidCallback onTap
    })>[
      (
        title: 'Favoritos',
        subtitle:
            '${snapshot.favoriteIds.length + widget.jellyfin.favoriteIds.length} faixas',
        identity: 'pulse-favorites',
        onTap: () => _selectDestination(PulseDestination.favorites),
      ),
      for (final playlist in snapshot.playlists.take(3))
        (
          title: playlist.name,
          subtitle: 'Playlist · ${playlist.trackIds.length} faixas',
          identity: 'playlist-${playlist.id}',
          onTap: () => _openPlaylist(playlist.id),
        ),
    ];
    final albumEntries = albumGroups.entries.toList()
      ..sort((a, b) => a.key.toLowerCase().compareTo(b.key.toLowerCase()));
    final visibleAlbums = albumEntries.take(expanded ? 6 : 3).toList();
    final visibleShortcuts = shortcuts.toList(growable: false);
    final pagePadding = expanded ? 24.0 : 16.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final contentWidth = constraints.maxWidth - pagePadding * 2;
        final shortcutGap = 10.0;
        final shortcutWidth = expanded
            ? ((contentWidth - 3 * shortcutGap) / 4)
                .clamp(190.0, 248.0)
                .toDouble()
            : (contentWidth - shortcutGap) / 2;
        return Container(
          decoration: BoxDecoration(
            gradient: PulsePaletteTheme.of(context).isFrosted
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x2C252D32), Color(0x0820262A)],
                  )
                : Theme.of(context).brightness == Brightness.dark
                    ? const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF252525), Color(0xFF121212)],
                        stops: [0, .48],
                      )
                    : null,
          ),
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              pagePadding,
              expanded ? 20 : 0,
              pagePadding,
              28,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionHeading(title: 'Acesso rápido'),
                const SizedBox(height: 10),
                Wrap(
                  spacing: shortcutGap,
                  runSpacing: shortcutGap,
                  children: [
                    for (final shortcut in visibleShortcuts)
                      SizedBox(
                        width: shortcutWidth,
                        child: PulseLibraryShortcut(
                          density: widget.preferences.density,
                          title: shortcut.title,
                          subtitle: shortcut.subtitle,
                          identity: shortcut.identity,
                          onTap: shortcut.onTap,
                        ),
                      ),
                  ],
                ),
                if (visibleAlbums.isNotEmpty) ...[
                  SizedBox(height: expanded ? 24 : 4),
                  _SectionHeading(
                    title: 'Álbuns',
                    actionLabel: 'Ver todos',
                    onAction: () => _selectDestination(PulseDestination.albums),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final entry in visibleAlbums) ...[
                          if (expanded)
                            SizedBox(
                              width: 172,
                              child: PulseCollectionCard(
                                artworkTracks: _stableArtworkOrder(entry.value),
                                title: entry.value.first.album!.trim(),
                                subtitle: [
                                  if ((entry.value.first.artist?.trim() ?? '')
                                      .isNotEmpty)
                                    entry.value.first.artist!.trim(),
                                  '${entry.value.length} faixas',
                                ].join(' · '),
                                identity: entry.key,
                                onTap: () => _openAlbum(entry.key),
                                density: widget.preferences.density,
                              ),
                            )
                          else
                            SizedBox(
                              width: 160,
                              child: PulseLibraryShortcut(
                                artworkTracks: _stableArtworkOrder(entry.value),
                                largeArtwork: true,
                                title: entry.value.first.album!.trim(),
                                subtitle: [
                                  if ((entry.value.first.artist?.trim() ?? '')
                                      .isNotEmpty)
                                    entry.value.first.artist!.trim(),
                                  '${entry.value.length} faixas',
                                ].join(' · '),
                                identity: entry.key,
                                onTap: () => _openAlbum(entry.key),
                                density: widget.preferences.density,
                              ),
                            ),
                          const SizedBox(width: 12),
                        ],
                      ],
                    ),
                  ),
                ],
                SizedBox(height: expanded ? 22 : 4),
                if (expanded && tracks.isNotEmpty) ...[
                  _SectionHeading(
                    title: 'Faixas',
                    actionLabel: 'Ver todas',
                    onAction: () => _selectDestination(PulseDestination.tracks),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final track in tracks.take(7)) ...[
                        SizedBox(
                            width: 172,
                            child: PulseCollectionCard(
                              artworkTracks: [track],
                              title: track.title,
                              subtitle: track.artist ?? 'Artista não informado',
                              identity: track.id,
                              onTap: () => widget.playback
                                  .playQueue(tracks, tracks.indexOf(track)),
                              density: widget.preferences.density,
                            )),
                        const SizedBox(width: 12),
                      ],
                    ]),
                  ),
                  const SizedBox(height: 22),
                ],
                _SectionHeading(
                  title: 'Faixas da biblioteca',
                  actionLabel: 'Ver todas',
                  onAction: () => _selectDestination(PulseDestination.tracks),
                ),
                const SizedBox(height: 8),
                for (final track in tracks.take(expanded ? 4 : 6))
                  PulseTrackRow(
                    density: widget.preferences.density,
                    track: track,
                    selected: widget.playback.currentTrack?.id == track.id,
                    favorite: _isFavorite(track),
                    playlists: _playlistChoicesForTrack(track),
                    onSelect: () => widget.playback.playQueue(
                      tracks,
                      tracks.indexOf(track),
                    ),
                    onFavorite: () => _runStoreAction(() =>
                        track.source == AudioSource.jellyfin
                            ? widget.jellyfin.toggleFavorite(track)
                            : widget.library.toggleFavorite(track)),
                    onAddToPlaylist: (playlistId) => _runStoreAction(
                      () => _addTrackToPlaylist(playlistId, track),
                    ),
                    onAddToQueue: () {
                      widget.playback.addToQueue(track);
                      _showMessage('${track.title} foi adicionada à fila.');
                    },
                    onPlayNext: () {
                      widget.playback.playNext(track);
                      _showMessage('${track.title} será a próxima faixa.');
                    },
                    onDownload: track.source == AudioSource.jellyfin
                        ? () => _toggleDownload(track)
                        : null,
                    downloaded: widget.jellyfin.isDownloaded(track),
                    downloading: widget.jellyfin.isDownloading(track),
                    onSetSleepTimer: _setSleepTimer,
                    sleepTimerActive: widget.playback.hasSleepTimer,
                    canStopAfterCurrentTrack:
                        widget.playback.currentTrack != null,
                    onShare: () => _shareTrack(track),
                    onOpenArtist: track.artist?.trim().isNotEmpty == true
                        ? () => _openArtist(track.artist!.trim())
                        : null,
                    onOpenAlbum: track.album?.trim().isNotEmpty == true
                        ? () => _openAlbum(
                              '${track.artist?.trim() ?? ''}\u0000${track.album!.trim()}',
                            )
                        : null,
                  ),
                const SizedBox(height: 18),
                if (widget.preferences.showLocalFiles &&
                    snapshot.rootPath != null)
                  Text(
                    'Pasta local · ${_pathDisplayName(snapshot.rootPath!)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.68)),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTrackCollection(
    List<AudioTrack> tracks, {
    required String emptyTitle,
    String? emptyMessage,
    bool showAddFolder = false,
    bool tableHeader = false,
    String? searchQuery,
  }) {
    final normalizedQuery = (searchQuery ?? _query).trim().toLowerCase();
    if (tracks.isEmpty) {
      return _EmptyState(
        title: emptyTitle,
        message: emptyMessage ??
            (showAddFolder
                ? Platform.isAndroid
                    ? 'Conecte seu servidor ou importe arquivos MP3 ou Opus para ouvir suas músicas.'
                    : 'Adicione uma pasta local para encontrar e tocar seus MP3 ou Opus sem internet.'
                : 'As faixas que você adicionar a esta coleção aparecerão aqui.'),
        actionLabel: showAddFolder
            ? Platform.isAndroid
                ? 'Importar músicas'
                : 'Adicionar pasta'
            : null,
        onAction: showAddFolder ? _addFolder : null,
      );
    }
    final visibleTracks = normalizedQuery.isEmpty
        ? tracks
        : tracks
            .where(
              (track) => trackMatchesLibraryQuery(track, normalizedQuery),
            )
            .toList();
    if (visibleTracks.isEmpty) {
      return _EmptyState(
        title: searchQuery == null
            ? _searchEmptyTitle
            : 'Nenhuma faixa para “${searchQuery.trim()}”',
        message: searchQuery == null
            ? _searchEmptyMessage
            : 'Tente outro termo na busca desta playlist.',
        icon: Icons.search_off_rounded,
        actionLabel:
            searchQuery == null ? 'Limpar busca' : 'Limpar busca da playlist',
        actionIcon: Icons.search_off_rounded,
        onAction: searchQuery == null ? _clearSearch : _clearPlaylistSearch,
      );
    }
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
          Platform.isAndroid && MediaQuery.sizeOf(context).width < 600 ? 0 : 24,
          12,
          Platform.isAndroid && MediaQuery.sizeOf(context).width < 600 ? 0 : 24,
          Platform.isAndroid && MediaQuery.sizeOf(context).width < 600
              ? 180
              : 24),
      itemCount: visibleTracks.length + (tableHeader ? 1 : 0),
      separatorBuilder: (context, index) =>
          const Divider(height: 1, indent: 56),
      itemBuilder: (context, index) {
        if (tableHeader && index == 0) {
          return SizedBox(
              height: 38,
              child: Row(children: [
                const SizedBox(width: 14),
                Text('#', style: Theme.of(context).textTheme.labelSmall),
                const SizedBox(width: 32),
                Expanded(
                    child: Text('TÍTULO',
                        style: Theme.of(context).textTheme.labelSmall)),
                if (MediaQuery.sizeOf(context).width >= 1440)
                  SizedBox(
                      width: 190,
                      child: Text('ÁLBUM',
                          style: Theme.of(context).textTheme.labelSmall)),
                const SizedBox(width: 80),
              ]));
        }
        final track = visibleTracks[index - (tableHeader ? 1 : 0)];
        return PulseTrackRow(
          density: widget.preferences.density,
          track: track,
          selected: widget.playback.currentTrack?.id == track.id,
          favorite: track.source == AudioSource.jellyfin
              ? widget.jellyfin.favoriteIds.contains(track.id)
              : widget.library.snapshot.favoriteIds.contains(track.id),
          playlists: _playlistChoicesForTrack(track),
          onSelect: () => widget.playback
              .playQueue(visibleTracks, index - (tableHeader ? 1 : 0)),
          onFavorite: () => _runStoreAction(() =>
              track.source == AudioSource.jellyfin
                  ? widget.jellyfin.toggleFavorite(track)
                  : widget.library.toggleFavorite(track)),
          onAddToPlaylist: (playlistId) => _runStoreAction(
            () => _addTrackToPlaylist(playlistId, track),
          ),
          onAddToQueue: () {
            widget.playback.addToQueue(track);
            _showMessage('${track.title} foi adicionada à fila.');
          },
          onPlayNext: () {
            widget.playback.playNext(track);
            _showMessage('${track.title} será a próxima faixa.');
          },
          onDownload: track.source == AudioSource.jellyfin
              ? () => _toggleDownload(track)
              : null,
          downloaded: widget.jellyfin.isDownloaded(track),
          downloading: widget.jellyfin.isDownloading(track),
          onSetSleepTimer: _setSleepTimer,
          sleepTimerActive: widget.playback.hasSleepTimer,
          canStopAfterCurrentTrack: widget.playback.currentTrack != null,
          onShare: () => _shareTrack(track),
          onOpenArtist: (track.artist?.trim().isNotEmpty ?? false)
              ? () => track.source == AudioSource.jellyfin
                  ? _openRemoteArtist(track.artist!.trim())
                  : _openArtist(track.artist!.trim())
              : null,
          onOpenAlbum: (track.album?.trim().isNotEmpty ?? false)
              ? () => track.source == AudioSource.jellyfin
                  ? _openRemoteAlbum(track)
                  : _openAlbum(
                      '${track.artist?.trim() ?? ''}\u0000${track.album!.trim()}',
                    )
              : null,
        );
      },
    );
  }

  Widget _buildJellyfin() {
    final remote = widget.jellyfin;
    if (!remote.connected) {
      return _EmptyState(
        title: widget.jellyfin.serverName,
        message:
            'Conecte seu servidor nas Configurações para ver a música remota.',
        icon: Icons.cloud_outlined,
        actionLabel: 'Abrir Configurações',
        onAction: _openSettings,
      );
    }
    final playlists = remote.playlists;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
        child: Row(children: [
          const Icon(Icons.cloud_done_outlined),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.jellyfin.serverName,
                  style: Theme.of(context).textTheme.headlineSmall),
              Text(
                  '${remote.tracks.length} faixas • ${remote.artists.length} artistas • ${playlists.length} playlists',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          )),
          IconButton(
            tooltip: 'Atualizar ${widget.jellyfin.serverName}',
            onPressed: remote.loading ? null : remote.refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ]),
      ),
      if (remote.error != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(remote.error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
      if (remote.loading) const LinearProgressIndicator(),
      SizedBox(
          height: 54,
          child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              children: [
                Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: const Text('Todas as faixas'),
                      selected: _selectedRemotePlaylistId == null &&
                          _selectedRemoteArtist == null &&
                          _selectedRemoteAlbumKey == null,
                      onSelected: (_) => setState(() {
                        _selectedRemotePlaylistId = null;
                        _selectedRemoteArtist = null;
                        _selectedRemoteAlbumKey = null;
                        _remotePlaylistTracks = null;
                      }),
                    )),
                for (final playlist in playlists)
                  Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        label: Text(playlist['Name']?.toString() ?? 'Playlist'),
                        selected: _selectedRemotePlaylistId ==
                            playlist['Id']?.toString(),
                        onSelected: (_) => setState(() {
                          _selectedRemotePlaylistId =
                              playlist['Id']?.toString();
                          _selectedRemoteArtist = null;
                          _selectedRemoteAlbumKey = null;
                          _remotePlaylistTracks =
                              remote.playlistTracks(_selectedRemotePlaylistId!);
                        }),
                      )),
                for (final artist in remote.artists)
                  Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        avatar:
                            const Icon(Icons.person_outline_rounded, size: 16),
                        label: Text(artist['Name']?.toString() ?? 'Artista'),
                        selected:
                            _selectedRemoteArtist == artist['Name']?.toString(),
                        onSelected: (_) => setState(() {
                          _selectedRemotePlaylistId = null;
                          _remotePlaylistTracks = null;
                          _selectedRemoteAlbumKey = null;
                          _selectedRemoteArtist = artist['Name']?.toString();
                        }),
                      )),
                if (_selectedRemoteAlbumKey != null)
                  ChoiceChip(
                    label: Text(
                        'Álbum: ${_selectedRemoteAlbumKey!.split('\u0000').last}'),
                    selected: true,
                    onSelected: (_) => setState(() {
                      _selectedRemoteAlbumKey = null;
                    }),
                  ),
              ])),
      Expanded(
          child: _remotePlaylistTracks == null
              ? _buildTrackCollection(
                  remote.tracks.where((track) {
                    if (_selectedRemoteArtist != null) {
                      return track.artist?.trim() == _selectedRemoteArtist;
                    }
                    if (_selectedRemoteAlbumKey != null) {
                      return '${track.artist?.trim() ?? ''}\u0000${track.album?.trim() ?? ''}' ==
                          _selectedRemoteAlbumKey;
                    }
                    return true;
                  }).toList(growable: false),
                  emptyTitle: 'Nenhuma faixa no ${widget.jellyfin.serverName}',
                  emptyMessage:
                      'Atualize o catálogo ou verifique a biblioteca de música no servidor.')
              : FutureBuilder<List<AudioTrack>>(
                  future: _remotePlaylistTracks,
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    return _buildTrackCollection(snapshot.data!,
                        emptyTitle:
                            'Playlist vazia no ${widget.jellyfin.serverName}');
                  },
                )),
    ]);
  }

  Future<void> _addTracksToPlaylist(PulsePlaylist playlist) async {
    final existingIds = playlist.trackIds.toSet();
    final availableTracks = _availablePlaylistTracks
        .where((track) => !existingIds.contains(track.id))
        .toList(growable: false);
    if (availableTracks.isEmpty) {
      _showMessage('Todas as faixas da biblioteca já estão nesta playlist.');
      return;
    }

    var searchQuery = '';
    final selectedIds = <String>{};
    final selected = await showDialog<Set<String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final query = searchQuery.trim().toLowerCase();
          final filteredTracks = query.isEmpty
              ? availableTracks
              : availableTracks
                  .where((track) => trackMatchesLibraryQuery(track, query))
                  .toList(growable: false);
          return AlertDialog(
            title: const Text('Adicionar faixas'),
            content: SizedBox(
              width: 560,
              height: 440,
              child: Column(
                children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Buscar na biblioteca',
                    ),
                    onChanged: (value) => setDialogState(() {
                      searchQuery = value;
                    }),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filteredTracks.isEmpty
                        ? const Center(
                            child: Text('Nenhuma faixa encontrada.'),
                          )
                        : ListView.builder(
                            itemCount: filteredTracks.length,
                            itemBuilder: (context, index) {
                              final track = filteredTracks[index];
                              final isSelected = selectedIds.contains(track.id);
                              return CheckboxListTile(
                                value: isSelected,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                secondary: PulseTrackArtwork(
                                  track: track,
                                  title: track.title,
                                  creator: track.artist ?? '',
                                  size: 40,
                                ),
                                title: Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                subtitle: Text(
                                  track.artist?.trim().isNotEmpty == true
                                      ? track.artist!.trim()
                                      : 'Artista não informado',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                onChanged: (value) => setDialogState(() {
                                  if (value == true) {
                                    selectedIds.add(track.id);
                                  } else {
                                    selectedIds.remove(track.id);
                                  }
                                }),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: selectedIds.isEmpty
                    ? null
                    : () => Navigator.pop(
                          dialogContext,
                          Set<String>.of(selectedIds),
                        ),
                child: Text('Adicionar (${selectedIds.length})'),
              ),
            ],
          );
        },
      ),
    );
    if (selected == null || selected.isEmpty) return;
    final tracksToAdd = availableTracks
        .where((track) => selected.contains(track.id))
        .toList(growable: false);
    try {
      await widget.library.addTracksToPlaylist(playlist.id, tracksToAdd);
      if (mounted) {
        _showMessage('${tracksToAdd.length} faixa(s) adicionada(s).');
      }
    } on Object catch (error) {
      if (mounted) {
        _showMessage('Não foi possível adicionar as faixas: $error');
      }
    }
  }

  Future<void> _renamePlaylist(PulsePlaylist playlist) async {
    var draftName = playlist.name;
    var draftDescription = playlist.description ?? '';
    final details = await showDialog<({String name, String description})>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nome e detalhes'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: playlist.name,
                autofocus: true,
                maxLength: 48,
                decoration: const InputDecoration(labelText: 'Nome'),
                onChanged: (value) => draftName = value,
              ),
              TextFormField(
                initialValue: playlist.description ?? '',
                maxLength: 180,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Descrição',
                  hintText: 'Opcional',
                ),
                onChanged: (value) => draftDescription = value,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(
              dialogContext,
              (
                name: draftName,
                description: draftDescription,
              ),
            ),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (details == null || details.name.trim().isEmpty) {
      return;
    }
    final description = details.description.trim();
    if (details.name.trim() == playlist.name &&
        description == (playlist.description ?? '').trim()) {
      return;
    }
    try {
      await widget.library.updatePlaylistDetails(
        playlist.id,
        name: details.name,
        description: description,
      );
      if (mounted) _showMessage('Detalhes da playlist atualizados.');
    } on Object catch (error) {
      if (mounted) _showMessage('Não foi possível renomear: $error');
    }
  }

  Future<void> _deletePlaylist(PulsePlaylist playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Apagar playlist?'),
        content: Text(
          '“${playlist.name}” será removida do Pulse. Os arquivos de música não serão apagados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Apagar playlist'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.library.deletePlaylist(playlist.id);
      if (!mounted) return;
      if (_selectedPlaylistId == playlist.id) {
        _navigateTo(
            const _PulseLocation(destination: PulseDestination.playlists));
      }
      _showMessage('Playlist apagada. Os arquivos continuam na biblioteca.');
    } on Object catch (error) {
      if (mounted) _showMessage('Não foi possível apagar a playlist: $error');
    }
  }

  String _remotePlaylistError(Object error) {
    if (error is JellyfinException) {
      return switch (error.statusCode) {
        401 =>
          'Sua sessão ${widget.jellyfin.serverName} expirou. Entre novamente.',
        403 => 'Esta conta não tem permissão para editar a playlist.',
        404 =>
          'A playlist não está mais disponível no ${widget.jellyfin.serverName}.',
        _ =>
          'O ${widget.jellyfin.serverName} recusou a alteração (HTTP ${error.statusCode}).',
      };
    }
    return 'Não foi possível alterar a playlist: $error';
  }

  Future<void> _renameRemotePlaylist(Map<String, dynamic> playlist) async {
    final id = playlist['Id']?.toString();
    if (id == null) return;
    final oldName = playlist['Name']?.toString() ?? 'Playlist';
    var draftName = oldName;
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Editar playlist'),
        content: TextFormField(
          initialValue: oldName,
          autofocus: true,
          maxLength: 48,
          decoration: const InputDecoration(labelText: 'Nome'),
          onChanged: (value) => draftName = value,
          onFieldSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, draftName),
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty || name.trim() == oldName) return;
    try {
      await widget.jellyfin.renamePlaylist(id, name);
      if (mounted) {
        _showMessage('Nome atualizado na conta ${widget.jellyfin.serverName}.');
      }
    } on Object catch (error) {
      if (mounted) _showMessage(_remotePlaylistError(error));
    }
  }

  Future<void> _editRemotePlaylistTracks(Map<String, dynamic> playlist) async {
    final id = playlist['Id']?.toString();
    if (id == null) return;
    try {
      final originalIds = await widget.jellyfin.playlistItemIds(id);
      if (!mounted) return;
      final selectedIds = originalIds.toSet();
      final catalog = widget.jellyfin.tracks;
      var searchQuery = '';
      final changedIds = await showDialog<Set<String>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) {
            final query = searchQuery.trim().toLowerCase();
            final visible = query.isEmpty
                ? catalog
                : catalog
                    .where((track) => trackMatchesLibraryQuery(track, query))
                    .toList(growable: false);
            return AlertDialog(
              title: const Text('Editar faixas da playlist'),
              content: SizedBox(
                width: 560,
                height: 440,
                child: Column(children: [
                  TextField(
                    autofocus: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Buscar músicas do servidor',
                    ),
                    onChanged: (value) => setDialogState(() {
                      searchQuery = value;
                    }),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final track = visible[index];
                        return CheckboxListTile(
                          value: selectedIds.contains(track.path),
                          title: Text(track.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(
                              track.artist ?? 'Artista não informado',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          onChanged: (checked) => setDialogState(() {
                            if (checked == true) {
                              selectedIds.add(track.path);
                            } else {
                              selectedIds.remove(track.path);
                            }
                          }),
                        );
                      },
                    ),
                  ),
                ]),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(dialogContext, Set<String>.of(selectedIds)),
                  child: const Text('Salvar faixas'),
                ),
              ],
            );
          },
        ),
      );
      if (changedIds == null || !mounted) return;
      final additions = catalog.map((track) => track.path).where((itemId) =>
          changedIds.contains(itemId) && !originalIds.contains(itemId));
      final orderedIds = [
        ...originalIds.where(changedIds.contains),
        ...additions,
      ];
      if (listEquals(orderedIds, originalIds)) return;
      await widget.jellyfin.replacePlaylistItems(id, orderedIds);
      if (!mounted) return;
      if (_selectedRemotePlaylistId == id) {
        setState(
            () => _remotePlaylistTracks = widget.jellyfin.playlistTracks(id));
      }
      _showMessage(
          'Faixas atualizadas na conta ${widget.jellyfin.serverName}.');
    } on Object catch (error) {
      if (mounted) _showMessage(_remotePlaylistError(error));
    }
  }

  Future<void> _editLocalPlaylistTracks(PulsePlaylist playlist) async {
    final available = {
      for (final track in _availablePlaylistTracks) track.id: track,
    };
    final orderedIds = List<String>.of(playlist.trackIds);
    final changed = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, update) => SafeArea(
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .82,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 12, 8),
                child: Row(children: [
                  const Expanded(
                    child: Text('Editar faixas',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w800)),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(sheetContext, orderedIds),
                    child: const Text('Salvar'),
                  ),
                ]),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 18),
                child: Text('Arraste para ordenar ou remova uma faixa.'),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  itemCount: orderedIds.length,
                  onReorderItem: (oldIndex, newIndex) => update(() {
                    final id = orderedIds.removeAt(oldIndex);
                    orderedIds.insert(newIndex, id);
                  }),
                  itemBuilder: (context, index) {
                    final id = orderedIds[index];
                    final track = available[id];
                    return ListTile(
                      key: ValueKey(id),
                      leading: track == null
                          ? const Icon(Icons.music_off_rounded)
                          : PulseTrackArtwork(
                              track: track, title: track.title, size: 42),
                      title: Text(track?.title ?? 'Faixa indisponível'),
                      subtitle: Text(track?.artist ?? ''),
                      trailing: IconButton(
                        tooltip: 'Remover da playlist',
                        onPressed: () =>
                            update(() => orderedIds.removeAt(index)),
                        icon: const Icon(Icons.remove_circle_outline_rounded),
                      ),
                    );
                  },
                ),
              ),
            ]),
          ),
        ),
      ),
    );
    if (changed == null || !mounted || listEquals(changed, playlist.trackIds)) {
      return;
    }
    await _runStoreAction(
        () => widget.library.replacePlaylistTrackIds(playlist.id, changed));
  }

  Future<void> _showRemotePlaylistActions(Map<String, dynamic> playlist) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('Editar nome'),
            onTap: () => Navigator.pop(sheetContext, 'rename'),
          ),
          ListTile(
            leading: const Icon(Icons.queue_music_rounded),
            title: const Text('Editar faixas'),
            onTap: () => Navigator.pop(sheetContext, 'edit_tracks'),
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline_rounded),
            title: const Text('Apagar playlist'),
            onTap: () => Navigator.pop(sheetContext, 'delete'),
          ),
        ]),
      ),
    );
    if (action != null && mounted) {
      await _onRemotePlaylistMenuAction(action, playlist);
    }
  }

  Future<void> _downloadRemotePlaylist(List<AudioTrack> tracks) async {
    final pending = tracks
        .where((track) =>
            track.source == AudioSource.jellyfin &&
            !widget.jellyfin.isDownloaded(track))
        .toList(growable: false);
    if (pending.isEmpty) {
      _showMessage('As faixas desta playlist já estão baixadas.');
      return;
    }
    var wifiOnly = Platform.isAndroid;
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('Baixar playlist'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${pending.length} faixa(s) ainda não baixada(s).'),
            if (Platform.isAndroid)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Somente no Wi-Fi'),
                value: wifiOnly,
                onChanged: (value) => update(() => wifiOnly = value),
              ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Baixar')),
          ],
        ),
      ),
    );
    if (approved != true || !mounted) return;
    if (wifiOnly && !await _onWifiOrEthernet()) {
      _showMessage('Conecte ao Wi-Fi para baixar esta playlist.');
      return;
    }
    if (!mounted) return;
    final progress = ValueNotifier<int>(0);
    var cancelled = false;
    final progressRoute = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Baixando playlist'),
        content: ValueListenableBuilder<int>(
          valueListenable: progress,
          builder: (_, value, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: value / pending.length),
              const SizedBox(height: 12),
              Text('$value de ${pending.length} faixas processadas'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => cancelled = true,
            child: const Text('Parar após esta faixa'),
          )
        ],
      ),
    );
    var downloaded = 0;
    var processed = 0;
    for (final track in pending) {
      if (cancelled) break;
      if (wifiOnly && !await _onWifiOrEthernet()) {
        cancelled = true;
        break;
      }
      try {
        await widget.jellyfin.downloadTrack(track);
        downloaded++;
      } on Object {
        // Continue with the other tracks; a failed one can be retried later.
      }
      progress.value = ++processed;
    }
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    await progressRoute;
    progress.dispose();
    if (mounted) {
      _showMessage('$downloaded de ${pending.length} faixa(s) baixada(s)'
          '${cancelled ? ' · download interrompido' : ''}.');
    }
  }

  Future<bool> _onWifiOrEthernet() async {
    if (!Platform.isAndroid) return true;
    try {
      return await const MethodChannel('pulse/network_status')
              .invokeMethod<bool>('isUnmeteredLocal') ??
          false;
    } on Object {
      return false;
    }
  }

  Future<void> _deleteRemotePlaylist(Map<String, dynamic> playlist) async {
    final id = playlist['Id']?.toString();
    if (id == null) return;
    final name = playlist['Name']?.toString() ?? 'Playlist';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Apagar playlist do ${widget.jellyfin.serverName}?'),
        content: Text('“$name” será apagada da conta e desaparecerá dos outros '
            'dispositivos. As músicas originais continuarão no servidor.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Apagar playlist'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.jellyfin.deletePlaylist(id);
      if (!mounted) return;
      if (_selectedRemotePlaylistId == id) {
        _navigateTo(
            const _PulseLocation(destination: PulseDestination.playlists));
      }
      _showMessage(
          'Playlist apagada no ${widget.jellyfin.serverName}. As músicas foram mantidas.');
    } on Object catch (error) {
      if (mounted) _showMessage(_remotePlaylistError(error));
    }
  }

  Future<void> _onRemotePlaylistMenuAction(
      String action, Map<String, dynamic> playlist) async {
    switch (action) {
      case 'rename':
        await _renameRemotePlaylist(playlist);
      case 'edit_tracks':
        await _editRemotePlaylistTracks(playlist);
      case 'delete':
        await _deleteRemotePlaylist(playlist);
    }
  }

  Future<void> _sharePlaylist(
    PulsePlaylist playlist,
    List<AudioTrack> tracks,
  ) =>
      _shareTrackCollection(playlist.name, tracks);

  Future<void> _shareTrackCollection(
    String title,
    List<AudioTrack> tracks,
  ) async {
    final details = tracks
        .map((track) => [
              track.title,
              if (track.artist?.trim().isNotEmpty == true) track.artist!.trim(),
            ].join(' • '))
        .join('\n');
    final shareText = '$title\n\n$details';
    if (Platform.isWindows) {
      await _showCollectionShareDialog(title, shareText);
      return;
    }
    try {
      final result = await SharePlus.instance.share(
        ShareParams(
          title: title,
          text: shareText,
        ),
      );
      if (mounted && result.status == ShareResultStatus.success) {
        _showMessage('Playlist compartilhada.');
      }
    } on Object catch (error) {
      if (mounted) _showMessage('Não foi possível compartilhar: $error');
    }
  }

  Future<void> _showCollectionShareDialog(String title, String text) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Compartilhar “$title”'),
        content: SizedBox(
          width: 440,
          height: 250,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Copie a lista para uma conversa ou salve um arquivo de texto para anexar.'),
              const SizedBox(height: 12),
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(text),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          TextButton.icon(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _saveCollectionShareText(title, text);
            },
            icon: const Icon(Icons.save_alt_rounded),
            label: const Text('Salvar lista'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (!dialogContext.mounted) return;
              Navigator.pop(dialogContext);
              if (mounted) {
                _showMessage('Lista copiada. Cole na conversa para enviar.');
              }
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copiar lista'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveCollectionShareText(String title, String text) async {
    try {
      final safeName =
          title.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
      final location = await getSaveLocation(
        suggestedName: '${safeName.isEmpty ? 'playlist' : safeName}.txt',
        acceptedTypeGroups: [
          const XTypeGroup(label: 'Arquivo de texto', extensions: ['txt']),
        ],
      );
      if (location == null) return;
      await File(location.path).writeAsString(text);
      if (mounted) _showMessage('Lista salva em ${location.path}.');
    } on Object catch (error) {
      if (mounted) _showMessage('Não foi possível salvar a lista: $error');
    }
  }

  Future<void> _addPlaylistToAnother(PulsePlaylist source) async {
    if (!widget.library.writesAllowed) {
      _showMessage(
          'O catálogo precisa estar disponível para editar playlists.');
      return;
    }
    final tracksById = {
      for (final track in _availablePlaylistTracks) track.id: track,
    };
    final tracks = source.trackIds
        .map((id) => tracksById[id])
        .whereType<AudioTrack>()
        .toList(growable: false);
    if (tracks.isEmpty) {
      _showMessage(
          'Esta playlist não tem faixas disponíveis para copiar. Conecte o servidor se necessário.');
      return;
    }

    final targets = widget.library.snapshot.playlists
        .where((playlist) => playlist.id != source.id)
        .toList(growable: false)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final choice = await showDialog<({String? targetId, bool create})>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Adicionar a outra playlist'),
        content: SizedBox(
          width: 400,
          height: ((targets.length + 1) * 56.0).clamp(112.0, 320.0).toDouble(),
          child: ListView(
            children: [
              for (final target in targets)
                ListTile(
                  leading: const Icon(Icons.queue_music_rounded),
                  title: Text(target.name),
                  subtitle: Text(target.folderName == null
                      ? '${target.trackIds.length} faixas'
                      : '${target.folderName} • ${target.trackIds.length} faixas'),
                  onTap: () => Navigator.pop(
                    dialogContext,
                    (targetId: target.id, create: false),
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.add_rounded),
                title: const Text('Nova playlist'),
                onTap: () => Navigator.pop(
                  dialogContext,
                  (targetId: null, create: true),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;

    if (choice.create) {
      final name = await _promptCollectionName(
        title: 'Nova playlist',
        fieldLabel: 'Nome',
        confirmLabel: 'Criar e adicionar',
      );
      if (!mounted || name == null) return;
      try {
        await widget.library.createPlaylistWithTracks(name, tracks);
        if (mounted) {
          _showMessage('${tracks.length} faixa(s) adicionada(s) a “$name”.');
        }
      } on Object catch (error) {
        if (mounted) _showMessage('Não foi possível criar a playlist: $error');
      }
      return;
    }

    final targetId = choice.targetId;
    final targetIndex = widget.library.snapshot.playlists.indexWhere(
      (playlist) => playlist.id == targetId,
    );
    if (targetIndex < 0) {
      _showMessage('A playlist de destino não está mais disponível.');
      return;
    }
    final target = widget.library.snapshot.playlists[targetIndex];
    final existingIds = target.trackIds.toSet();
    final additions = tracks
        .where((track) => !existingIds.contains(track.id))
        .toList(growable: false);
    if (additions.isEmpty) {
      _showMessage('Todas as faixas já estão em “${target.name}”.');
      return;
    }
    try {
      await widget.library.addTracksToPlaylist(target.id, additions);
      if (mounted) {
        _showMessage(
          '${additions.length} faixa(s) adicionada(s) a “${target.name}”.',
        );
      }
    } on Object catch (error) {
      if (mounted) _showMessage('Não foi possível copiar as faixas: $error');
    }
  }

  Future<void> _movePlaylistToFolder(PulsePlaylist playlist) async {
    if (!widget.library.writesAllowed) {
      _showMessage(
          'O catálogo precisa estar disponível para editar playlists.');
      return;
    }
    final folders = widget.library.snapshot.playlists
        .map((item) => item.folderName?.trim())
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final choice = await showDialog<({String? folderName, bool create})>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Mover para pasta'),
        content: SizedBox(
          width: 400,
          height:
              ((folders.length + 2) * 56.0 + 56).clamp(200.0, 400.0).toDouble(),
          child: Column(
            children: [
              const Text(
                'As pastas organizam playlists no Pulse. Os arquivos de música permanecem onde estão.',
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.folder_off_outlined),
                      title: const Text('Sem pasta'),
                      trailing: playlist.folderName == null
                          ? const Icon(Icons.check_rounded)
                          : null,
                      onTap: () => Navigator.pop(
                        dialogContext,
                        (folderName: null, create: false),
                      ),
                    ),
                    for (final folder in folders)
                      ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: Text(folder),
                        trailing: playlist.folderName == folder
                            ? const Icon(Icons.check_rounded)
                            : null,
                        onTap: () => Navigator.pop(
                          dialogContext,
                          (folderName: folder, create: false),
                        ),
                      ),
                    ListTile(
                      leading: const Icon(Icons.create_new_folder_outlined),
                      title: const Text('Nova pasta'),
                      onTap: () => Navigator.pop(
                        dialogContext,
                        (folderName: null, create: true),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (!mounted || choice == null) return;

    var folderName = choice.folderName;
    if (choice.create) {
      final createdName = await _promptCollectionName(
        title: 'Nova pasta de playlists',
        fieldLabel: 'Nome da pasta',
        confirmLabel: 'Criar e mover',
      );
      if (!mounted || createdName == null) return;
      folderName = createdName;
      for (final existing in folders) {
        if (existing.toLowerCase() == createdName.toLowerCase()) {
          folderName = existing;
          break;
        }
      }
    }
    if (folderName == playlist.folderName) return;
    try {
      await widget.library.movePlaylistToFolder(playlist.id, folderName);
      if (mounted) {
        _showMessage(folderName == null
            ? 'Playlist movida para “Sem pasta”.'
            : 'Playlist movida para “$folderName”.');
      }
    } on Object catch (error) {
      if (mounted) _showMessage('Não foi possível mover a playlist: $error');
    }
  }

  Future<void> _createPlaylistFolderFor(PulsePlaylist playlist) async {
    if (!widget.library.writesAllowed) {
      _showMessage('O catálogo precisa estar disponível para criar a pasta.');
      return;
    }
    final folderName = await _promptCollectionName(
      title: 'Nova pasta de playlists',
      fieldLabel: 'Nome da pasta',
      confirmLabel: 'Criar',
    );
    if (!mounted || folderName == null) return;
    final existing = widget.library.snapshot.playlists
        .map((item) => item.folderName)
        .whereType<String>()
        .any((name) => name.toLowerCase() == folderName.toLowerCase());
    if (existing) {
      _showMessage('Já existe uma pasta chamada “$folderName”.');
      return;
    }
    try {
      await widget.library.movePlaylistToFolder(playlist.id, folderName);
      if (mounted) {
        _showMessage('Pasta “$folderName” criada com “${playlist.name}”.');
      }
    } on Object catch (error) {
      if (mounted) _showMessage('Não foi possível criar a pasta: $error');
    }
  }

  Future<void> _showPlaylistContextMenu(
    String playlistId,
    Offset globalPosition,
  ) async {
    final playlistIndex = widget.library.snapshot.playlists
        .indexWhere((item) => item.id == playlistId);
    if (playlistIndex < 0) return;
    final playlist = widget.library.snapshot.playlists[playlistIndex];
    final tracksById = {
      for (final track in _availablePlaylistTracks) track.id: track,
    };
    final tracks = playlist.trackIds
        .map((id) => tracksById[id])
        .whereType<AudioTrack>()
        .toList(growable: false);
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = overlay.globalToLocal(globalPosition);
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(position.dx, position.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'add_queue',
          enabled: tracks.isNotEmpty,
          child: const _PlaylistMenuLabel(
            icon: Icons.queue_music_rounded,
            label: 'Adicionar à fila',
          ),
        ),
        const PopupMenuItem(
          value: 'rename',
          child: _PlaylistMenuLabel(
            icon: Icons.edit_outlined,
            label: 'Editar os detalhes',
          ),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: _PlaylistMenuLabel(
            icon: Icons.remove_circle_outline_rounded,
            label: 'Apagar',
          ),
        ),
        const PopupMenuItem<String>(
          enabled: false,
          child: Tooltip(
            message: 'Download de playlists ainda não está disponível.',
            child: _PlaylistMenuLabel(
              icon: Icons.download_outlined,
              label: 'Baixar',
            ),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
          value: 'create_playlist',
          child: _PlaylistMenuLabel(
            icon: Icons.playlist_add_rounded,
            label: 'Criar playlist',
          ),
        ),
        const PopupMenuItem(
          value: 'create_folder',
          child: _PlaylistMenuLabel(
            icon: Icons.create_new_folder_outlined,
            label: 'Criar pasta',
          ),
        ),
        PopupMenuItem(
          value: 'copy_to_playlist',
          enabled: playlist.trackIds.isNotEmpty,
          child: const _PlaylistMenuLabel(
            icon: Icons.playlist_add_rounded,
            label: 'Adicionar a outra playlist',
          ),
        ),
      ],
    );
    if (!mounted || action == null) return;
    if (action == 'create_playlist') {
      await _createPlaylist();
    } else if (action == 'create_folder') {
      await _createPlaylistFolderFor(playlist);
    } else {
      await _onPlaylistMenuAction(action, playlist, tracks);
    }
  }

  Future<void> _showMobilePlaylistActions(String playlistId) async {
    if (playlistId.startsWith('${widget.jellyfin.serverKind.name}:')) {
      final id =
          playlistId.substring(widget.jellyfin.serverKind.name.length + 1);
      final remote = widget.jellyfin.playlists
          .where((item) => item['Id']?.toString() == id)
          .firstOrNull;
      if (remote == null || !mounted) return;
      final action = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        backgroundColor: const Color(0xFF242424),
        builder: (sheetContext) => SafeArea(
          child: ListView(shrinkWrap: true, children: [
            ListTile(
              title: Text(remote['Name']?.toString() ?? 'Playlist',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('Playlist na conta ${widget.jellyfin.serverName}'),
            ),
            for (final item in <(String, IconData, String)>[
              ('rename', Icons.edit_outlined, 'Editar nome'),
              ('edit_tracks', Icons.queue_music_rounded, 'Editar faixas'),
              (
                'delete',
                Icons.remove_circle_outline_rounded,
                'Apagar playlist'
              ),
            ])
              ListTile(
                leading: Icon(item.$2),
                title: Text(item.$3),
                onTap: () => Navigator.of(sheetContext).pop(item.$1),
              ),
          ]),
        ),
      );
      if (mounted && action != null) {
        await _onRemotePlaylistMenuAction(action, remote);
      }
      return;
    }
    final playlist = widget.library.snapshot.playlists
        .where((item) => item.id == playlistId)
        .firstOrNull;
    if (playlist == null || !mounted) return;
    final tracksById = {
      for (final track in _availablePlaylistTracks) track.id: track,
    };
    final tracks = playlist.trackIds
        .map((id) => tracksById[id])
        .whereType<AudioTrack>()
        .toList(growable: false);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF242424),
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: Text(playlist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('${playlist.trackIds.length} faixas'),
            ),
            for (final item in <(String, IconData, String, bool)>[
              (
                'add_queue',
                Icons.queue_music_rounded,
                'Adicionar à fila',
                tracks.isNotEmpty
              ),
              ('rename', Icons.edit_outlined, 'Editar os detalhes', true),
              (
                'copy_to_playlist',
                Icons.playlist_add_rounded,
                'Adicionar a outra playlist',
                tracks.isNotEmpty
              ),
              (
                'move_to_folder',
                Icons.drive_file_move_outline,
                'Mover para pasta',
                true
              ),
              (
                'create_playlist',
                Icons.playlist_add_rounded,
                'Criar playlist',
                true
              ),
              (
                'create_folder',
                Icons.create_new_folder_outlined,
                'Criar pasta',
                true
              ),
              ('share', Icons.share_outlined, 'Compartilhar', true),
              ('delete', Icons.remove_circle_outline_rounded, 'Apagar', true),
            ])
              ListTile(
                enabled: item.$4,
                leading: Icon(item.$2),
                title: Text(item.$3),
                onTap: item.$4
                    ? () => Navigator.of(sheetContext).pop(item.$1)
                    : null,
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'create_playlist') {
      await _createPlaylist();
    } else if (action == 'create_folder') {
      await _createPlaylistFolderFor(playlist);
    } else {
      await _onPlaylistMenuAction(action, playlist, tracks);
    }
  }

  Future<void> _onPlaylistMenuAction(
    String action,
    PulsePlaylist playlist,
    List<AudioTrack> tracks,
  ) async {
    switch (action) {
      case 'add_queue':
        widget.playback.addTracksToQueue(tracks);
        _showMessage('${tracks.length} faixa(s) adicionada(s) à fila.');
      case 'rename':
        await _renamePlaylist(playlist);
      case 'move_to_folder':
        await _movePlaylistToFolder(playlist);
      case 'copy_to_playlist':
        await _addPlaylistToAnother(playlist);
      case 'share':
        await _sharePlaylist(playlist, tracks);
      case 'delete':
        await _deletePlaylist(playlist);
    }
  }

  Widget _buildPlaylists() {
    final playlists = widget.library.snapshot.playlists;
    if (_selectedRemotePlaylistId case final remoteId?) {
      final matches = widget.jellyfin.playlists
          .where((playlist) => playlist['Id']?.toString() == remoteId);
      if (matches.isEmpty) {
        return const _EmptyState(
          title: 'Playlist indisponível',
          message: 'Atualize o catálogo da sua conta.',
        );
      }
      final remotePlaylist = matches.first;
      return FutureBuilder<List<AudioTrack>>(
        future:
            _remotePlaylistTracks ?? widget.jellyfin.playlistTracks(remoteId),
        builder: (context, result) {
          if (!result.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final tracks = result.data!;
          if (Platform.isAndroid && MediaQuery.sizeOf(context).width < 600) {
            final knownDuration = tracks.every((track) =>
                track.durationMillis != null && track.durationMillis! > 0);
            final duration = knownDuration
                ? _formatPlaylistDuration(tracks.fold<int>(
                    0, (total, track) => total + track.durationMillis!))
                : 'Duração indisponível';
            return PulseMobilePlaylistPage(
              key: ValueKey('remote-playlist-$remoteId'),
              title: remotePlaylist['Name']?.toString() ?? 'Playlist',
              owner: widget.jellyfin.username ?? widget.jellyfin.serverName,
              durationLabel: duration,
              tracks: tracks,
              searchController: _playlistSearchController,
              onSearchChanged: (value) =>
                  setState(() => _playlistQuery = value),
              onBack: () => _goBackFromCollection(PulseDestination.playlists),
              onPlay: tracks.isEmpty
                  ? null
                  : () => widget.playback.playPlaylistQueue(tracks, 0),
              onShuffle: tracks.isEmpty
                  ? null
                  : () {
                      widget.playback
                          .setShuffleEnabled(!widget.playback.shuffleEnabled);
                      widget.playback.playPlaylistQueue(tracks, 0);
                    },
              shuffleActive: widget.playback.shuffleEnabled,
              onAdd: _openPlaylistAddPanel,
              onEdit: () => _editRemotePlaylistTracks(remotePlaylist),
              onRename: () => _renameRemotePlaylist(remotePlaylist),
              onMore: () => _showRemotePlaylistActions(remotePlaylist),
              onDownload:
                  tracks.isEmpty ? null : () => _downloadRemotePlaylist(tracks),
              onShare: () => _shareTrackCollection(
                  remotePlaylist['Name']?.toString() ?? 'Playlist', tracks),
              content: tracks.isEmpty
                  ? _buildEmptyPlaylistDiscovery()
                  : _buildTrackCollection(tracks,
                      emptyTitle: 'Playlist vazia',
                      searchQuery: _playlistQuery),
            );
          }
          return PulseCollectionHero(
            title: remotePlaylist['Name']?.toString() ?? 'Playlist',
            type: 'Playlist',
            metadata: '${widget.jellyfin.serverName} • ${tracks.length} faixas',
            tracks: tracks,
            onBack: () => _selectDestination(PulseDestination.playlists),
            onPlay: tracks.isEmpty
                ? null
                : () => widget.playback.playPlaylistQueue(tracks, 0),
            backTooltip: 'Voltar para playlists',
            playTooltip: 'Reproduzir playlist',
            menuItems: const [
              PopupMenuItem(
                value: 'rename',
                child: _PlaylistMenuLabel(
                    icon: Icons.edit_outlined, label: 'Editar nome'),
              ),
              PopupMenuItem(
                value: 'edit_tracks',
                child: _PlaylistMenuLabel(
                    icon: Icons.queue_music_rounded, label: 'Editar faixas'),
              ),
              PopupMenuDivider(),
              PopupMenuItem(
                value: 'delete',
                child: _PlaylistMenuLabel(
                    icon: Icons.remove_circle_outline_rounded,
                    label: 'Apagar playlist'),
              ),
            ],
            onMenuAction: (action) =>
                _onRemotePlaylistMenuAction(action, remotePlaylist),
            secondaryActions: FilledButton.tonalIcon(
              onPressed: _openPlaylistAddPanel,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Adicionar'),
            ),
            content: tracks.isEmpty
                ? _buildEmptyPlaylistDiscovery()
                : _buildTrackCollection(tracks,
                    emptyTitle: 'Playlist vazia', tableHeader: true),
          );
        },
      );
    }
    if (_selectedPlaylistId != null) {
      final playlistIndex = playlists.indexWhere(
        (item) => item.id == _selectedPlaylistId,
      );
      if (playlistIndex >= 0) {
        final playlist = playlists[playlistIndex];
        final tracksById = {
          for (final track in _availablePlaylistTracks) track.id: track,
        };
        final tracks = playlist.trackIds
            .map((id) => tracksById[id])
            .whereType<AudioTrack>()
            .toList(growable: false);
        final unavailableCount = playlist.trackIds.length - tracks.length;
        return FutureBuilder<int?>(
          future: unavailableCount == 0 ? _playlistDuration(tracks) : null,
          builder: (context, durationSnapshot) {
            if (Platform.isAndroid && MediaQuery.sizeOf(context).width < 600) {
              return PulseMobilePlaylistPage(
                key: ValueKey('local-playlist-${playlist.id}'),
                title: playlist.name,
                owner: 'Você',
                durationLabel: durationSnapshot.data == null
                    ? 'Duração indisponível'
                    : _formatPlaylistDuration(durationSnapshot.data!),
                tracks: tracks,
                searchController: _playlistSearchController,
                onSearchChanged: (value) =>
                    setState(() => _playlistQuery = value),
                onBack: () => _goBackFromCollection(PulseDestination.playlists),
                onPlay: tracks.isEmpty
                    ? null
                    : () => widget.playback.playPlaylistQueue(tracks, 0),
                onShuffle: tracks.isEmpty
                    ? null
                    : () {
                        widget.playback
                            .setShuffleEnabled(!widget.playback.shuffleEnabled);
                        widget.playback.playPlaylistQueue(tracks, 0);
                      },
                shuffleActive: widget.playback.shuffleEnabled,
                onAdd: _openPlaylistAddPanel,
                onEdit: () => _editLocalPlaylistTracks(playlist),
                onRename: () => _renamePlaylist(playlist),
                onMore: () => _showMobilePlaylistActions(playlist.id),
                onShare: () => _sharePlaylist(playlist, tracks),
                content: tracks.isEmpty && unavailableCount == 0
                    ? _buildEmptyPlaylistDiscovery()
                    : _buildTrackCollection(
                        _sortedPlaylistTracks(tracks),
                        emptyTitle: 'Playlist vazia',
                        searchQuery: _playlistQuery,
                      ),
              );
            }
            return PulseCollectionHero(
              title: playlist.name,
              type: 'Playlist do Pulse',
              metadata: [
                if (playlist.description?.trim().isNotEmpty == true)
                  playlist.description!.trim(),
                if (playlist.folderName?.trim().isNotEmpty == true)
                  'Pasta: ${playlist.folderName}',
                'Pulse • ${playlist.trackIds.length} faixas',
                if (unavailableCount > 0)
                  '$unavailableCount ${unavailableCount == 1 ? 'indisponível' : 'indisponíveis'}',
                if (unavailableCount == 0 &&
                    durationSnapshot.connectionState == ConnectionState.done)
                  durationSnapshot.data == null
                      ? 'Duração indisponível'
                      : _formatPlaylistDuration(durationSnapshot.data!),
              ].join(' • '),
              tracks: tracks,
              onBack: () => _navigateTo(const _PulseLocation(
                  destination: PulseDestination.playlists)),
              onPlay: tracks.isEmpty
                  ? null
                  : () => widget.playback.playPlaylistQueue(tracks, 0),
              backTooltip: 'Voltar para playlists',
              playTooltip: 'Reproduzir playlist',
              onShuffle: tracks.isEmpty
                  ? null
                  : () {
                      widget.playback
                          .setShuffleEnabled(!widget.playback.shuffleEnabled);
                      widget.playback.playPlaylistQueue(tracks, 0);
                    },
              shuffleActive: widget.playback.shuffleEnabled,
              trailingActionsBuilder: _buildPlaylistToolbar,
              onAddToQueue: tracks.isEmpty
                  ? null
                  : () {
                      widget.playback.addTracksToQueue(tracks);
                      _showMessage(
                          '${tracks.length} faixa(s) adicionada(s) à fila.');
                    },
              secondaryActions: Wrap(
                spacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _openPlaylistAddPanel,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Adicionar'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _renamePlaylist(playlist),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Nome e detalhes'),
                  ),
                ],
              ),
              menuItems: [
                PopupMenuItem(
                  value: 'add_queue',
                  enabled: tracks.isNotEmpty,
                  child: const _PlaylistMenuLabel(
                    icon: Icons.queue_music_rounded,
                    label: 'Adicionar à fila',
                  ),
                ),
                const PopupMenuItem(
                  value: 'rename',
                  child: _PlaylistMenuLabel(
                    icon: Icons.edit_outlined,
                    label: 'Editar os detalhes',
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: _PlaylistMenuLabel(
                    icon: Icons.remove_circle_outline_rounded,
                    label: 'Apagar',
                  ),
                ),
                const PopupMenuItem<String>(
                  enabled: false,
                  child: Row(
                    children: [
                      Icon(Icons.download_outlined, size: 20),
                      SizedBox(width: 12),
                      SizedBox(
                        width: 195,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('Baixar'),
                            Text(
                              'As faixas locais já estão no computador',
                              style: TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'move_to_folder',
                  child: _PlaylistMenuLabel(
                    icon: Icons.folder_outlined,
                    label: 'Mover para pasta',
                  ),
                ),
                PopupMenuItem(
                  value: 'copy_to_playlist',
                  enabled: playlist.trackIds.isNotEmpty,
                  child: const _PlaylistMenuLabel(
                    icon: Icons.playlist_add_rounded,
                    label: 'Adicionar a outra playlist',
                  ),
                ),
                const PopupMenuItem(
                  value: 'share',
                  child: _PlaylistMenuLabel(
                    icon: Icons.share_outlined,
                    label: 'Compartilhar',
                  ),
                ),
              ],
              onMenuAction: (action) =>
                  _onPlaylistMenuAction(action, playlist, tracks),
              onMobileMenuPressed: () =>
                  _showMobilePlaylistActions(playlist.id),
              content: tracks.isEmpty && unavailableCount == 0
                  ? _buildEmptyPlaylistDiscovery()
                  : _buildTrackCollection(
                      _sortedPlaylistTracks(tracks),
                      emptyTitle: unavailableCount > 0
                          ? 'Faixas indisponíveis'
                          : 'Playlist vazia',
                      emptyMessage: unavailableCount > 0
                          ? 'Conecte o servidor ou mostre os arquivos locais para acessar as faixas salvas nesta playlist.'
                          : 'Esta playlist ainda não tem faixas.',
                      tableHeader: true,
                      searchQuery: _playlistQuery,
                    ),
            );
          },
        );
      }
    }
    if (playlists.isEmpty && widget.jellyfin.playlists.isEmpty) {
      return _EmptyState(
        title: 'Crie sua primeira playlist',
        message: widget.jellyfin.connected
            ? 'Organize as músicas na sua conta ${widget.jellyfin.serverName}.'
            : 'Organize suas faixas sem mover ou alterar os arquivos originais.',
        actionLabel: 'Nova playlist',
        onAction: _createPlaylist,
      );
    }
    final normalizedQuery = normalizeSearchText(_query.trim());
    final tracksById = {
      for (final track in _availablePlaylistTracks) track.id: track,
    };
    final visiblePlaylists = playlists.where((playlist) {
      if (normalizedQuery.isEmpty ||
          normalizeSearchText(playlist.name).contains(normalizedQuery)) {
        return true;
      }
      return playlist.trackIds.any((id) {
        final track = tracksById[id];
        return track != null &&
            trackMatchesLibraryQuery(track, normalizedQuery);
      });
    }).toList(growable: false);
    final visibleRemotePlaylists = widget.jellyfin.playlists.where((playlist) {
      return normalizedQuery.isEmpty ||
          normalizeSearchText(playlist['Name']?.toString() ?? '')
              .contains(normalizedQuery);
    }).toList(growable: false);
    if (visiblePlaylists.isEmpty && visibleRemotePlaylists.isEmpty) {
      return _EmptyState(
        title: _searchEmptyTitle,
        message: _searchEmptyMessage,
        icon: Icons.search_off_rounded,
        actionLabel: 'Limpar busca',
        actionIcon: Icons.search_off_rounded,
        onAction: _clearSearch,
      );
    }
    final groups = <String, List<PulsePlaylist>>{};
    for (final playlist in visiblePlaylists) {
      final folder = playlist.folderName?.trim() ?? '';
      groups.putIfAbsent(folder, () => []).add(playlist);
    }
    final folders = groups.keys.toList()
      ..sort((a, b) {
        if (a == b) return 0;
        if (a.isEmpty) return -1;
        if (b.isEmpty) return 1;
        return a.toLowerCase().compareTo(b.toLowerCase());
      });
    final showHeadings =
        folders.length > 1 || (folders.isNotEmpty && folders.first.isNotEmpty);
    final rows = <({
      String? heading,
      PulsePlaylist? playlist,
      Map<String, dynamic>? remote
    })>[];
    for (final folder in folders) {
      if (showHeadings) {
        rows.add((
          heading: folder.isEmpty ? 'Sem pasta' : folder,
          playlist: null,
          remote: null
        ));
      }
      for (final playlist in groups[folder]!) {
        rows.add((heading: null, playlist: playlist, remote: null));
      }
    }
    for (final playlist in visibleRemotePlaylists) {
      rows.add((heading: null, playlist: null, remote: playlist));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        if (row.heading case final heading?) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              heading,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          );
        }
        if (row.remote case final remote?) {
          final id = remote['Id']?.toString();
          return Column(children: [
            ListTile(
              leading: const Icon(Icons.queue_music_rounded),
              title: Text(remote['Name']?.toString() ?? 'Playlist'),
              subtitle: const Text('Playlist'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: id == null ? null : () => _openRemotePlaylist(id),
            ),
            const Divider(height: 1),
          ]);
        }
        final playlist = row.playlist!;
        return Column(
          children: [
            GestureDetector(
              onSecondaryTapDown: (details) => _showPlaylistContextMenu(
                playlist.id,
                details.globalPosition,
              ),
              child: ListTile(
                leading: const Icon(Icons.queue_music_rounded),
                title: Text(playlist.name),
                subtitle: Text('${playlist.trackIds.length} faixas'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _openPlaylist(playlist.id),
              ),
            ),
            const Divider(height: 1),
          ],
        );
      },
    );
  }
}

String _pathDisplayName(String path) => path.split(RegExp(r'[\\/]')).last;

List<int?> _readLocalDurations(List<String> paths) => [
      for (final path in paths) _readLocalDuration(path),
    ];

int? _readLocalDuration(String path) {
  try {
    return readMetadata(File(path), getImage: false).duration?.inMilliseconds;
  } on Object {
    return null;
  }
}

String _formatPlaylistDuration(int millis) {
  final minutes = Duration(milliseconds: millis).inMinutes;
  final hours = minutes ~/ 60;
  final remainingMinutes = minutes % 60;
  return hours == 0
      ? '$remainingMinutes min'
      : '${hours}h ${remainingMinutes}min';
}

enum _PlaylistSort {
  custom('Ordem personalizada'),
  title('Título'),
  artist('Artista'),
  album('Álbum');

  const _PlaylistSort(this.label);
  final String label;
}

class _PlaylistMenuLabel extends StatelessWidget {
  const _PlaylistMenuLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          SizedBox(
            width: 195,
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      );
}

class _LibraryTabs extends StatelessWidget {
  const _LibraryTabs({required this.selected, required this.onSelect});

  final PulseDestination selected;
  final ValueChanged<PulseDestination> onSelect;

  @override
  Widget build(BuildContext context) {
    final activeDestination = selected == PulseDestination.library
        ? PulseDestination.tracks
        : selected;
    final destinations = const [
      (PulseDestination.tracks, 'Faixas'),
      (PulseDestination.albums, 'Álbuns'),
      (PulseDestination.artists, 'Artistas'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final destination in destinations) ...[
              ChoiceChip(
                label: Text(destination.$2),
                selected: activeDestination == destination.$1,
                showCheckmark: false,
                onSelected: (_) => onSelect(destination.$1),
              ),
              const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(onPressed: onAction, child: Text(actionLabel!)),
        ],
      );
}

class _PulseLocation {
  const _PulseLocation({
    required this.destination,
    this.playlistId,
    this.remotePlaylistId,
    this.albumKey,
    this.artist,
  });

  final PulseDestination destination;
  final String? playlistId;
  final String? remotePlaylistId;
  final String? albumKey;
  final String? artist;

  bool matches(_PulseLocation other) =>
      destination == other.destination &&
      playlistId == other.playlistId &&
      remotePlaylistId == other.remotePlaylistId &&
      albumKey == other.albumKey &&
      artist == other.artist;
}

Map<String, List<AudioTrack>> _groupTracksByAlbum(List<AudioTrack> tracks) {
  final groups = <String, List<AudioTrack>>{};
  for (final track in tracks) {
    final album = track.album?.trim();
    if (album == null || album.isEmpty) continue;
    final artist = track.artist?.trim() ?? '';
    final key = '$artist\u0000$album';
    groups.putIfAbsent(key, () => []).add(track);
  }
  return groups;
}

Map<String, List<AudioTrack>> _groupTracksByArtist(List<AudioTrack> tracks) {
  final groups = <String, List<AudioTrack>>{};
  for (final track in tracks) {
    final artist = track.artist?.trim();
    if (artist == null || artist.isEmpty) continue;
    groups.putIfAbsent(artist, () => []).add(track);
  }
  return groups;
}

class _WorkspaceCard extends StatelessWidget {
  const _WorkspaceCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final mobile = Platform.isAndroid && MediaQuery.sizeOf(context).width < 600;
    final frosted = PulsePaletteTheme.of(context).isFrosted;
    return Material(
      color: mobile ? const Color(0xFF121212) : colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(mobile
            ? 0
            : frosted
                ? 12
                : 8),
        side: frosted
            ? BorderSide(color: Colors.white.withValues(alpha: 0.16))
            : BorderSide.none,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.title,
    required this.message,
    this.icon = Icons.library_music_outlined,
    this.actionLabel,
    this.actionIcon = Icons.create_new_folder_outlined,
    this.onAction,
  });

  final String title;
  final String message;
  final IconData icon;
  final String? actionLabel;
  final IconData actionIcon;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 82,
                  height: 82,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: Icon(
                    icon,
                    color: PulsePaletteTheme.of(context).emphasisInk,
                    size: 38,
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.68),
                      height: 1.5),
                ),
                if (actionLabel != null && onAction != null) ...[
                  const SizedBox(height: 22),
                  FilledButton.icon(
                    onPressed: onAction,
                    icon: Icon(actionIcon),
                    label: Text(actionLabel!),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProgressBanner extends StatelessWidget {
  const _ProgressBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child:
                  Text(message, style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      );
}

class _SourceStatusBanner extends StatelessWidget {
  const _SourceStatusBanner({
    required this.state,
    required this.rootPath,
    required this.scanning,
    required this.scanAttemptPath,
    required this.onReconnect,
    required this.onRetry,
  });

  final LibrarySourceState state;
  final String? rootPath;
  final bool scanning;
  final String? scanAttemptPath;
  final VoidCallback onReconnect;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final folderName = rootPath == null ? 'pasta' : _pathDisplayName(rootPath!);
    final attemptName = scanAttemptPath == null
        ? folderName
        : _pathDisplayName(scanAttemptPath!);
    final readingSavedFolder = _sameLibraryPath(rootPath, scanAttemptPath);
    final (icon, title, message, action, callback) = scanning
        ? readingSavedFolder
            ? (
                Icons.sync_rounded,
                'Reconectando pasta',
                'Lendo “$attemptName”. O último catálogo segue disponível até a leitura terminar.',
                'Reconectando…',
                null,
              )
            : (
                Icons.sync_rounded,
                'Lendo nova pasta',
                'Lendo “$attemptName”. A fonte salva “$folderName” e o catálogo atual seguem disponíveis até a leitura terminar.',
                'Lendo…',
                null,
              )
        : switch (state) {
            LibrarySourceState.disconnected => (
                Icons.usb_off_rounded,
                'Pasta desconectada',
                '“$folderName” não está acessível. O último catálogo foi mantido e pode estar desatualizado.',
                'Reconectar pasta',
                onReconnect,
              ),
            LibrarySourceState.readError => (
                Icons.folder_off_outlined,
                'Falha ao ler a pasta',
                'Confira o acesso à pasta. O último catálogo foi mantido.',
                'Tentar novamente',
                onRetry,
              ),
            LibrarySourceState.partial => (
                Icons.warning_amber_rounded,
                'Leitura incompleta',
                'Parte da pasta não pôde ser verificada. O catálogo anterior foi mantido; faixas não foram removidas.',
                'Tentar novamente',
                onRetry,
              ),
            _ => (
                Icons.info_outline_rounded,
                'Biblioteca local',
                'O catálogo salvo permanece disponível.',
                'Tentar novamente',
                onRetry,
              ),
          };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Material(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, color: const Color(0xFFFFC66D)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: TextStyle(
                                color: colors.onSurface,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(message,
                            style: TextStyle(color: colors.onSurface)),
                      ],
                    ),
                  ),
                ],
              ),
              if (callback != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: callback,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(action),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

bool _sameLibraryPath(String? first, String? second) {
  if (first == null || second == null) return false;
  String normalize(String path) =>
      path.replaceAll('/', '\\').replaceAll(RegExp(r'\\+$'), '').toLowerCase();
  return normalize(first) == normalize(second);
}

class _TimedBanner extends StatefulWidget {
  const _TimedBanner({super.key, required this.child});

  final Widget child;

  @override
  State<_TimedBanner> createState() => _TimedBannerState();
}

class _TimedBannerState extends State<_TimedBanner> {
  Timer? _hideTimer;
  bool _visible = true;

  @override
  void initState() {
    super.initState();
    _hideTimer = Timer(const Duration(seconds: 8), () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _visible ? widget.child : const SizedBox.shrink();
}

class _NoticeBanner extends StatelessWidget {
  const _NoticeBanner({
    required this.message,
    this.title,
    this.onShowDetails,
  });

  final String message;
  final String? title;
  final VoidCallback? onShowDetails;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Material(
        color: colors.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.check_circle_outline_rounded,
                  color: colors.onSecondaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null)
                      Text(title!,
                          style: TextStyle(
                              color: colors.onSecondaryContainer,
                              fontWeight: FontWeight.w600)),
                    Text(message,
                        style: TextStyle(color: colors.onSecondaryContainer)),
                  ],
                ),
              ),
              if (onShowDetails != null)
                TextButton(
                  onPressed: onShowDetails,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.onSecondaryContainer,
                  ),
                  child: const Text('Ver detalhes'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: Material(
        color: colors.error.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: colors.error),
              const SizedBox(width: 10),
              Expanded(
                child: Text(message, style: TextStyle(color: colors.onSurface)),
              ),
              if (actionLabel != null && onAction != null)
                TextButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CatalogRecoveryState extends StatelessWidget {
  const _CatalogRecoveryState({
    required this.message,
    required this.onRetry,
    required this.onShowDetails,
  });

  final String message;
  final VoidCallback onRetry;
  final VoidCallback onShowDetails;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Color(0xFFFFC27A), size: 36),
                    const SizedBox(height: 12),
                    Text(
                      'Não foi possível abrir o catálogo local',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(message, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Tentar novamente'),
                    ),
                    TextButton(
                      onPressed: onShowDetails,
                      child: const Text('Ver arquivos de recuperação'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class _NowPlayingSheet extends StatefulWidget {
  const _NowPlayingSheet({
    required this.playback,
    this.connect,
    required this.onOpenArtist,
    required this.jellyfin,
    required this.onlineLookupEnabled,
    required this.onShowQueue,
    required this.onShowDevices,
    required this.onShowTimer,
    required this.onShare,
    required this.onExpand,
    required this.isFavorite,
    required this.onToggleFavorite,
    required this.onMore,
  });

  final PlaybackController playback;
  final PulseConnectController? connect;
  final ValueChanged<String> onOpenArtist;
  final JellyfinController jellyfin;
  final bool onlineLookupEnabled;
  final VoidCallback onShowQueue;
  final VoidCallback onShowDevices;
  final VoidCallback onShowTimer;
  final VoidCallback onShare;
  final VoidCallback onExpand;
  final bool Function(AudioTrack?) isFavorite;
  final VoidCallback onToggleFavorite;
  final VoidCallback onMore;

  @override
  State<_NowPlayingSheet> createState() => _NowPlayingSheetState();
}

class _NowPlayingSheetState extends State<_NowPlayingSheet> {
  double? _draggingPosition;

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid) {
      return SizedBox(
        height: MediaQuery.sizeOf(context).height,
        child: PulseMobileNowPlaying(
          playback: widget.playback,
          connect: widget.connect,
          jellyfin: widget.jellyfin,
          onlineLookupEnabled: widget.onlineLookupEnabled,
          onOpenArtist: widget.onOpenArtist,
          onShowTimer: widget.onShowTimer,
          onShare: widget.onShare,
          onClose: () => Navigator.of(context).pop(),
          onShowQueue: widget.onShowQueue,
          onShowDevices: widget.onShowDevices,
          onToggleFavorite: widget.onToggleFavorite,
          onMore: widget.onMore,
          isFavorite: widget.isFavorite,
        ),
      );
    }
    return AnimatedBuilder(
      animation: widget.playback,
      builder: (context, _) {
        final playback = widget.playback;
        final track = playback.currentTrack;
        final mobile = Platform.isAndroid;
        final screen = MediaQuery.sizeOf(context);
        final artworkSize = mobile
            ? (screen.width - 64)
                .clamp(160.0, (screen.height * .36).clamp(160.0, 320.0))
            : 144.0;
        final maxMs = playback.duration.inMilliseconds;
        final positionMs = playback.position.inMilliseconds.clamp(
          0,
          maxMs > 0 ? maxMs : 1,
        );
        final sliderValue = (_draggingPosition ?? positionMs.toDouble())
            .clamp(0, maxMs > 0 ? maxMs.toDouble() : 1)
            .toDouble();
        return SizedBox(
          height: screen.height * (mobile ? .92 : .78),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              children: [
                Row(
                  children: [
                    if (mobile)
                      IconButton(
                        tooltip: 'Fechar Tocando agora',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      ),
                    Expanded(
                      child: Text(
                        'Tocando agora',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Fila de reprodução',
                      onPressed: widget.onShowQueue,
                      icon: const Icon(Icons.queue_music_rounded),
                    ),
                    if (!mobile)
                      IconButton(
                        tooltip: 'Entrar na tela cheia',
                        onPressed: widget.onExpand,
                        icon: const Icon(Icons.open_in_full_rounded),
                      ),
                  ],
                ),
                const Spacer(),
                PulseTrackArtwork(
                  track: track,
                  title: track?.title ?? 'Pulse',
                  creator: '${track?.artist ?? ''}${track?.album ?? ''}',
                  size: artworkSize,
                  borderRadius: 24,
                ),
                const SizedBox(height: 24),
                Text(
                  track?.title ?? 'Nenhuma faixa selecionada',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  track?.artist ?? 'Escolha uma faixa na biblioteca',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.68)),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Text(_formatTime(playback.position)),
                    Expanded(
                      child: Slider(
                        min: 0,
                        max: maxMs > 0 ? maxMs.toDouble() : 1,
                        value: sliderValue,
                        onChanged: track == null || maxMs <= 0
                            ? null
                            : (value) =>
                                setState(() => _draggingPosition = value),
                        onChangeEnd: track == null || maxMs <= 0
                            ? null
                            : (value) {
                                setState(() => _draggingPosition = null);
                                playback.seek(
                                  Duration(milliseconds: value.toInt()),
                                );
                              },
                      ),
                    ),
                    Text(_formatTime(playback.duration)),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'Anterior',
                      onPressed: track == null ? null : playback.skipPrevious,
                      icon: const Icon(Icons.skip_previous_rounded, size: 32),
                    ),
                    const SizedBox(width: 16),
                    IconButton.filledTonal(
                      tooltip: playback.isPlaying ? 'Pausar' : 'Reproduzir',
                      onPressed: track == null ? null : playback.togglePlayback,
                      icon: Icon(
                        playback.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 34,
                      ),
                    ),
                    const SizedBox(width: 16),
                    IconButton(
                      tooltip: 'Próxima',
                      onPressed: track == null ? null : playback.skipNext,
                      icon: const Icon(Icons.skip_next_rounded, size: 32),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                PulsePlaybackModeButtons(
                  playback: playback,
                  showLabels: true,
                ),
                const Spacer(),
              ],
            ),
          ),
        );
      },
    );
  }
}

String _formatTime(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}

List<AudioTrack> _stableArtworkOrder(Iterable<AudioTrack> tracks) =>
    tracks.toList()
      ..sort((a, b) {
        final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
        return byTitle != 0
            ? byTitle
            : a.path.toLowerCase().compareTo(b.path.toLowerCase());
      });

/// Lets text fields receive spaces while keeping Space as a playback shortcut
/// elsewhere in the player.
class _PlayPauseSpaceActivator extends ShortcutActivator {
  const _PlayPauseSpaceActivator();

  static const _space = SingleActivator(LogicalKeyboardKey.space);

  @override
  Iterable<LogicalKeyboardKey> get triggers => _space.triggers;

  @override
  bool accepts(KeyEvent event, HardwareKeyboard state) {
    if (!_space.accepts(event, state)) return false;
    final context = FocusManager.instance.primaryFocus?.context;
    return context != null &&
        context.widget is! EditableText &&
        context.findAncestorWidgetOfExactType<EditableText>() == null;
  }

  @override
  String debugDescribeKeys() => _space.debugDescribeKeys();
}
