import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:win32/win32.dart';

import '../app/pulse_theme.dart';
import '../data/embedded_lyrics_reader.dart';
import '../data/local_artwork_cache.dart';
import '../data/remote_artwork_cache.dart';
import '../data/lyrics_timing_offset_repository.dart';
import '../data/synchronized_lyrics_repository.dart';
import '../domain/audio_track.dart';
import '../domain/pulse_lyrics.dart';
import '../state/jellyfin_controller.dart';
import '../state/playback_controller.dart';

class PulseLyricsSheet extends StatefulWidget {
  const PulseLyricsSheet({
    super.key,
    required this.playback,
    required this.jellyfin,
    required this.onlineLookupEnabled,
    this.workspace = false,
    this.onClose,
    this.headerLabel,
    this.previewOnly = false,
    this.fullScreenMobile = false,
    this.onShowFullLyrics,
    this.onActiveLineChanged,
    this.onShare,
    this.onMore,
  });

  final PlaybackController playback;
  final JellyfinController jellyfin;
  final bool onlineLookupEnabled;
  final bool workspace;
  final VoidCallback? onClose;
  final String? headerLabel;
  final bool previewOnly;
  final bool fullScreenMobile;
  final VoidCallback? onShowFullLyrics;
  final ValueChanged<String?>? onActiveLineChanged;
  final VoidCallback? onShare;
  final VoidCallback? onMore;

  static Future<void> show(BuildContext context, PlaybackController playback,
      JellyfinController jellyfin, bool onlineLookupEnabled) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF242424),
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => FractionallySizedBox(
        heightFactor: .86,
        child: PulseLyricsSheet(
          playback: playback,
          jellyfin: jellyfin,
          onlineLookupEnabled: onlineLookupEnabled,
        ),
      ),
    );
  }

  @override
  State<PulseLyricsSheet> createState() => _PulseLyricsSheetState();
}

class _PulseLyricsSheetState extends State<PulseLyricsSheet> {
  static const _screenChannel = MethodChannel('pulse/screen');

  String _formatTime(Duration value) =>
      '${value.inMinutes.remainder(60).toString().padLeft(2, '0')}:${value.inSeconds.remainder(60).toString().padLeft(2, '0')}';
  PulseLyrics? _lyrics;
  String? _trackSignature;
  bool _loading = false;
  bool _syncing = false;
  bool _syncedFromOnline = false;
  int _generation = 0;
  int _lastActive = -2;
  int _offsetMillis = 0;
  Future<void> _offsetWrite = Future.value();
  List<GlobalKey> _lineKeys = const [];
  Future<Color?>? _coverColor;
  String? _lastReportedLine;
  final _synchronized = const SynchronizedLyricsRepository();
  final _offsets = const LyricsTimingOffsetRepository();

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid && !widget.previewOnly) {
      unawaited(_setScreenAwake(true));
    }
    if (Platform.isWindows) {
      SetThreadExecutionState(ES_CONTINUOUS | ES_DISPLAY_REQUIRED);
    }
    widget.playback.addListener(_onPlaybackChanged);
    _load();
  }

  Future<void> _setScreenAwake(bool enabled) async {
    try {
      await _screenChannel.invokeMethod<void>('keepAwakeForLyrics', enabled);
    } on MissingPluginException {
      // The lyrics view also runs on platforms without this Android channel.
    } on PlatformException {
      // Screen timeout falls back to the device setting if Android declines.
    }
  }

  @override
  void didUpdateWidget(covariant PulseLyricsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (Platform.isAndroid && oldWidget.previewOnly != widget.previewOnly) {
      unawaited(_setScreenAwake(!widget.previewOnly));
    }
    if (oldWidget.playback != widget.playback) {
      oldWidget.playback.removeListener(_onPlaybackChanged);
      widget.playback.addListener(_onPlaybackChanged);
      _load();
    } else if (oldWidget.onlineLookupEnabled != widget.onlineLookupEnabled) {
      _load();
    }
  }

  void _onPlaybackChanged() {
    final track = widget.playback.currentTrack;
    final signature = track == null
        ? null
        : '${track.source}:${track.id}:${track.modifiedAtMillis}';
    if (signature != _trackSignature) {
      _load();
    } else if (mounted && _lyrics?.synchronized == true) {
      setState(() {});
      _reportActiveLine();
    }
  }

  void _reportActiveLine() {
    if (widget.onActiveLineChanged == null) return;
    final lyrics = _lyrics;
    final index = lyrics == null || lyrics.lines.isEmpty
        ? -1
        : math.max(0, _activeIndex(lyrics));
    final line = index < 0 ? null : lyrics!.lines[index].text;
    if (line == _lastReportedLine) return;
    _lastReportedLine = line;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onActiveLineChanged?.call(line);
    });
  }

  Future<void> _load({bool refresh = false}) async {
    final track = widget.playback.currentTrack;
    final signature = track == null
        ? null
        : '${track.source}:${track.id}:${track.modifiedAtMillis}';
    final generation = ++_generation;
    _coverColor = track == null ? Future.value(null) : _extractColor(track);
    if (mounted) {
      setState(() {
        _trackSignature = signature;
        _loading = track != null;
        _syncing = false;
        _syncedFromOnline = false;
        _lyrics = null;
        _lastActive = -2;
        _offsetMillis = 0;
        _lineKeys = const [];
      });
      _reportActiveLine();
    }
    if (track == null) return;
    final offset = await _offsets.read(track);
    if (!mounted || generation != _generation) return;
    setState(() => _offsetMillis = offset);
    PulseLyrics? result;
    try {
      result = track.source == AudioSource.jellyfin
          ? await widget.jellyfin.lyricsFor(track)
          : await _localLyrics(track);
    } on Object {
      result = null;
    }
    if (!mounted || generation != _generation) return;
    final needsTiming = result != null && !result.synchronized;
    setState(() {
      _lyrics = result;
      _lineKeys = List.generate(result?.lines.length ?? 0, (_) => GlobalKey());
      _loading = false;
      _syncing = needsTiming;
    });
    _reportActiveLine();
    if (!needsTiming) return;
    final timing = track.durationMillis != null && track.durationMillis! > 0
        ? Duration(milliseconds: track.durationMillis!)
        : widget.playback.duration;
    PulseLyrics? synchronized;
    try {
      synchronized = await _synchronized.find(
        track,
        result,
        duration: timing,
        allowNetwork: widget.onlineLookupEnabled,
        refresh: refresh,
      );
    } on Object {
      synchronized = null;
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      if (synchronized?.synchronized == true) {
        _lyrics = synchronized;
        _syncedFromOnline = true;
        _lineKeys =
            List.generate(synchronized!.lines.length, (_) => GlobalKey());
        _lastActive = -2;
      }
      _syncing = false;
    });
    _reportActiveLine();
  }

  Future<PulseLyrics?> _localLyrics(AudioTrack track) async {
    final embedded = await EmbeddedLyricsReader.fromFile(File(track.path));
    if (embedded != null) return embedded;
    final dot = track.path.lastIndexOf('.');
    if (dot < 0) return null;
    final base = track.path.substring(0, dot);
    for (final extension in ['.lrc', '.elrc', '.txt']) {
      final file = File('$base$extension');
      if (await file.exists() && await file.length() <= 1024 * 1024) {
        final parsed = PulseLyrics.fromText(await file.readAsString());
        if (parsed != null) return parsed;
      }
    }
    return null;
  }

  Future<Color?> _extractColor(AudioTrack track) async {
    try {
      ImageProvider? provider;
      if (track.source == AudioSource.jellyfin && track.artworkUrl != null) {
        final cached = await RemoteArtworkCache.instance.imageFor(track);
        provider = cached == null
            ? NetworkImage(track.artworkUrl!)
            : FileImage(cached);
      } else if (track.source == AudioSource.local) {
        final bytes = await LocalArtworkCache.instance.imageForTracks([
          (
            path: track.path,
            size: track.sizeBytes,
            modifiedAtMillis: track.modifiedAtMillis
          ),
        ]);
        if (bytes != null) provider = MemoryImage(bytes);
      }
      if (provider == null) return null;
      final scheme = await ColorScheme.fromImageProvider(
          provider: provider, brightness: Brightness.dark);
      return scheme.primary;
    } on Object {
      return null;
    }
  }

  int _activeIndex(PulseLyrics lyrics) {
    if (!lyrics.synchronized) return -1;
    final now = widget.playback.position;
    var active = -1;
    for (var i = 0; i < lyrics.lines.length; i++) {
      final start = lyrics.lines[i].start;
      final adjusted = start == null ? null : _adjustedStart(start);
      if (adjusted != null && adjusted <= now) active = i;
      if (adjusted != null && adjusted > now) break;
    }
    return active;
  }

  Duration _adjustedStart(Duration start) => Duration(
      milliseconds:
          (start.inMilliseconds + _offsetMillis).clamp(0, 1 << 31).toInt());

  Future<void> _changeOffset(int delta) async {
    final track = widget.playback.currentTrack;
    if (track == null) return;
    final value = (_offsetMillis + delta).clamp(-5000, 5000).toInt();
    if (value == _offsetMillis) return;
    setState(() {
      _offsetMillis = value;
      _lastActive = -2;
    });
    final save = _offsetWrite
        .catchError((Object _) {})
        .then((_) => _offsets.write(track, value));
    _offsetWrite = save;
    try {
      await save;
    } on Object {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
            content: Text('Não foi possível salvar o ajuste da letra.')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final track = widget.playback.currentTrack;
    final lyrics = _lyrics;
    final active = lyrics == null ? -1 : _activeIndex(lyrics);
    if (widget.previewOnly) {
      final center = active < 0 ? 0 : active;
      final first = lyrics == null
          ? 0
          : (center - 3).clamp(0, math.max(0, lyrics.lines.length - 5)).toInt();
      final last =
          lyrics == null ? 0 : math.min(lyrics.lines.length, first + 5);
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Prévia da letra',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 60),
            Expanded(
              child: _loading || lyrics == null || lyrics.lines.isEmpty
                  ? Center(
                      child: Text(
                        _loading
                            ? 'Carregando letra…'
                            : 'Letra indisponível para esta faixa',
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 18),
                      ),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: last - first,
                      itemBuilder: (context, index) {
                        final lineIndex = first + index;
                        final line = lyrics.lines[lineIndex];
                        final selected = lineIndex == center;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: InkWell(
                            onTap: line.start == null
                                ? null
                                : () => widget.playback
                                    .seek(_adjustedStart(line.start!)),
                            child: Text(line.text,
                                style: TextStyle(
                                  color: selected
                                      ? Colors.white
                                      : Colors.white.withValues(alpha: .70),
                                  fontSize: selected ? 19 : 16,
                                  height: 1.22,
                                  fontWeight: selected
                                      ? FontWeight.w800
                                      : FontWeight.w600,
                                )),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: widget.onShowFullLyrics,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
              ),
              child: const Text('Mostrar letra'),
            ),
          ],
        ),
      );
    }
    if (widget.fullScreenMobile) {
      if (active != _lastActive) {
        _lastActive = active;
        if (active >= 0 && active < _lineKeys.length) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final lineContext = _lineKeys[active].currentContext;
            if (mounted && lineContext != null) {
              Scrollable.ensureVisible(lineContext,
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeInOut,
                  alignment: .38);
            }
          });
        }
      }
      return FutureBuilder<Color?>(
        future: _coverColor,
        builder: (context, snapshot) {
          final raw = snapshot.data ?? const Color(0xFF9D2629);
          final hsv = HSVColor.fromColor(raw);
          final source = hsv
              .withSaturation(math.max(hsv.saturation, .70))
              .withValue(math.max(hsv.value, .62))
              .toColor();
          final sourceHsv = HSVColor.fromColor(source);
          final topLeft = sourceHsv
              .withSaturation(math.max(sourceHsv.saturation, .88))
              .withValue(sourceHsv.value * .70)
              .toColor();
          final bottomRight = sourceHsv
              .withSaturation(math.max(.58, sourceHsv.saturation - .07))
              .withValue(math.min(1, sourceHsv.value * .90))
              .toColor();
          final middle = Color.lerp(topLeft, bottomRight, .52)!;
          final frosted = PulsePaletteTheme.of(context).isFrosted;
          final durationMs = widget.playback.duration.inMilliseconds;
          final positionMs = widget.playback.position.inMilliseconds
              .clamp(0, durationMs > 0 ? durationMs : 1);
          return Scaffold(
            backgroundColor: frosted ? Colors.transparent : topLeft,
            body: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: frosted
                      ? const [
                          Color(0x702B3338),
                          Color(0x68242B30),
                          Color(0x6020272C),
                        ]
                      : [topLeft, middle, bottomRight],
                  stops: const [0, .52, 1],
                ),
              ),
              child: SafeArea(
                child: Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(children: [
                      IconButton(
                        tooltip: 'Voltar à reprodução',
                        onPressed:
                            widget.onClose ?? () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.keyboard_arrow_down_rounded,
                            color: Colors.white, size: 32),
                      ),
                      Expanded(
                        child: Column(children: [
                          Text(track?.title ?? 'Letra',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800)),
                          Text(track?.artist ?? 'Artista não informado',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white70)),
                        ]),
                      ),
                      const SizedBox(width: 48),
                    ]),
                  ),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : lyrics == null || lyrics.lines.isEmpty
                            ? const Center(
                                child: Text(
                                    'Letra indisponível para esta faixa',
                                    style: TextStyle(
                                        color: Colors.white70, fontSize: 18)))
                            : ShaderMask(
                                shaderCallback: (bounds) =>
                                    const LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black,
                                    Colors.black,
                                    Colors.transparent,
                                  ],
                                  stops: [0, .04, .89, 1],
                                ).createShader(bounds),
                                blendMode: BlendMode.dstIn,
                                child: SingleChildScrollView(
                                  padding:
                                      const EdgeInsets.fromLTRB(24, 52, 24, 52),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      for (var i = 0;
                                          i < lyrics.lines.length;
                                          i++)
                                        Padding(
                                          key: _lineKeys[i],
                                          padding:
                                              const EdgeInsets.only(bottom: 17),
                                          child: InkWell(
                                            onTap: lyrics.lines[i].start == null
                                                ? null
                                                : () => widget.playback.seek(
                                                    _adjustedStart(lyrics
                                                        .lines[i].start!)),
                                            child: Text(lyrics.lines[i].text,
                                                style: TextStyle(
                                                  color: i == active
                                                      ? Colors.white
                                                      : Colors.white70,
                                                  fontSize:
                                                      i == active ? 21 : 18,
                                                  height: 1.23,
                                                  fontWeight: i == active
                                                      ? FontWeight.w800
                                                      : FontWeight.w600,
                                                )),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    child: Row(children: [
                      IconButton(
                        tooltip: 'Compartilhar faixa',
                        onPressed: widget.onShare,
                        icon: const Icon(Icons.share_outlined,
                            color: Colors.white),
                      ),
                      const Spacer(),
                      IconButton(
                        tooltip: 'Mais opções',
                        onPressed: widget.onMore,
                        icon: const Icon(Icons.more_vert_rounded,
                            color: Colors.white),
                      ),
                    ]),
                  ),
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: Colors.white,
                      inactiveTrackColor: Colors.white38,
                      thumbColor: Colors.white,
                    ),
                    child: Slider(
                      value: positionMs.toDouble(),
                      min: 0,
                      max: durationMs > 0 ? durationMs.toDouble() : 1,
                      onChanged: durationMs <= 0
                          ? null
                          : (value) => widget.playback
                              .seek(Duration(milliseconds: value.round())),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(children: [
                      Text(_formatTime(widget.playback.position)),
                      const Spacer(),
                      Text(_formatTime(widget.playback.duration)),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  IconButton.filled(
                    tooltip:
                        widget.playback.isPlaying ? 'Pausar' : 'Reproduzir',
                    onPressed:
                        track == null ? null : widget.playback.togglePlayback,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      fixedSize: const Size(68, 68),
                    ),
                    icon: Icon(
                        widget.playback.isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 42),
                  ),
                  const SizedBox(height: 18),
                ]),
              ),
            ),
          );
        },
      );
    }
    if (active != _lastActive) {
      _lastActive = active;
      if (active >= 0 && active < _lineKeys.length) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final lineContext = _lineKeys[active].currentContext;
          if (mounted && lineContext != null) {
            Scrollable.ensureVisible(lineContext,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeInOut,
                alignment: .38);
          }
        });
      }
    }
    final content = Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Row(children: [
          Expanded(
            child: Text(widget.headerLabel ?? 'Letras',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: widget.workspace ? 16 : 22,
                    fontWeight: FontWeight.bold)),
          ),
          if (lyrics != null && !_syncing)
            Tooltip(
              message: lyrics.synchronized
                  ? (_syncedFromOnline
                      ? 'Tempos encontrados no LRCLIB'
                      : 'Tempos embutidos na faixa')
                  : 'Esta letra não tem tempos por linha',
              child: Text(
                lyrics.synchronized ? 'Sincronizada' : 'Sem tempos',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ),
          if (_syncing)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          IconButton(
            tooltip: 'Atualizar letra e sincronização',
            onPressed: track == null ? null : () => _load(refresh: true),
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
          ),
          IconButton(
            tooltip: 'Fechar',
            onPressed: widget.onClose ?? () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Colors.white),
          ),
        ]),
      ),
      if (track != null && !widget.workspace)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
                '${track.title} · ${track.artist ?? 'Artista não informado'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70)),
          ),
        ),
      if (track != null && lyrics?.synchronized == true)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(children: [
            const Text('Sincronia',
                style: TextStyle(color: Colors.white70, fontSize: 12)),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Adiantar letra em 0,5 segundo',
              onPressed:
                  _offsetMillis <= -5000 ? null : () => _changeOffset(-500),
              icon: const Icon(Icons.remove_circle_outline),
              color: Colors.white,
            ),
            Text(
              '${_offsetMillis > 0 ? '+' : ''}${(_offsetMillis / 1000).toStringAsFixed(1).replaceAll('.', ',')} s',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
            IconButton(
              tooltip: 'Atrasar letra em 0,5 segundo',
              onPressed:
                  _offsetMillis >= 5000 ? null : () => _changeOffset(500),
              icon: const Icon(Icons.add_circle_outline),
              color: Colors.white,
            ),
            if (_offsetMillis != 0)
              TextButton(
                onPressed: () => _changeOffset(-_offsetMillis),
                child: const Text('Restaurar'),
              ),
          ]),
        ),
      Expanded(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : lyrics == null
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Letra indisponível para esta faixa.',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: Colors.white70, fontSize: 18)),
                    ),
                  )
                : LayoutBuilder(builder: (context, constraints) {
                    final wide =
                        widget.workspace && constraints.maxWidth >= 900;
                    return SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                          widget.workspace ? 28 : 24,
                          widget.workspace ? 8 : 18,
                          widget.workspace ? 28 : 24,
                          100),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                              maxWidth:
                                  widget.workspace ? 880 : double.infinity),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (widget.workspace)
                                SizedBox(
                                    height: (constraints.maxHeight * .20)
                                        .clamp(55.0, 190.0)),
                              for (var i = 0; i < lyrics.lines.length; i++)
                                Padding(
                                  key: _lineKeys[i],
                                  padding: EdgeInsets.symmetric(
                                      vertical: widget.workspace ? 12 : 8),
                                  child: InkWell(
                                    onTap: lyrics.lines[i].start == null
                                        ? null
                                        : () => widget.playback.seek(
                                            _adjustedStart(
                                                lyrics.lines[i].start!)),
                                    child: Text(
                                      lyrics.lines[i].text,
                                      style: TextStyle(
                                        color:
                                            lyrics.synchronized && i != active
                                                ? Colors.white60
                                                : Colors.white,
                                        fontSize: widget.workspace
                                            ? (wide ? 46 : 34)
                                            : 23,
                                        fontWeight:
                                            i == active || !lyrics.synchronized
                                                ? FontWeight.w800
                                                : FontWeight.w700,
                                        height: 1.25,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
      ),
    ]);
    if (!widget.workspace) return content;
    return FutureBuilder<Color?>(
      future: _coverColor,
      builder: (context, snapshot) {
        final source = snapshot.data ?? const Color(0xFF45504B);
        final top = Color.lerp(source, Colors.black, .42)!;
        final bottom = Color.lerp(source, Colors.black, .68)!;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [top, bottom],
            ),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: content,
        );
      },
    );
  }

  @override
  void dispose() {
    if (Platform.isAndroid) unawaited(_setScreenAwake(false));
    if (Platform.isWindows) SetThreadExecutionState(ES_CONTINUOUS);
    _generation++;
    widget.playback.removeListener(_onPlaybackChanged);
    super.dispose();
  }
}
