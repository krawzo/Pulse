import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/pulse_theme.dart';
import '../domain/audio_track.dart';
import '../state/playback_controller.dart';
import '../state/pulse_connect_controller.dart';
import 'pulse_playback_mode_buttons.dart';
import 'pulse_artist_link.dart';
import 'pulse_track_artwork.dart';
import 'pulse_track_navigation_swipe.dart';

class PulsePlayerDock extends StatefulWidget {
  const PulsePlayerDock(
      {super.key,
      required this.playback,
      this.connect,
      required this.onShowQueue,
      this.onToggleLyrics,
      this.lyricsOpen = false,
      required this.onToggleDevices,
      required this.deviceTapRegionGroup,
      this.devicesOpen = false,
      this.onExpand,
      this.expanded = false,
      required this.onOpenArtist,
      this.isFavorite = false,
      this.onToggleFavorite});

  final PlaybackController playback;
  final PulseConnectController? connect;
  final VoidCallback onShowQueue;
  final VoidCallback? onToggleLyrics;
  final bool lyricsOpen;
  final VoidCallback onToggleDevices;
  final Object deviceTapRegionGroup;
  final bool devicesOpen;
  final VoidCallback? onExpand;
  final bool expanded;
  final ValueChanged<String> onOpenArtist;
  final bool isFavorite;
  final VoidCallback? onToggleFavorite;

  @override
  State<PulsePlayerDock> createState() => _PulsePlayerDockState();
}

class _PulsePlayerDockState extends State<PulsePlayerDock> {
  static const _windowChannel = MethodChannel('pulse/window');
  double? _draggingPosition;
  bool _isSeekHovered = false;
  bool _isVolumeHovered = false;
  double? _draggingVolume;
  String? _localAudioOutput;
  Timer? _audioOutputTimer;

  @override
  void initState() {
    super.initState();
    widget.connect?.addListener(_onConnectionChanged);
    if (Platform.isWindows) {
      unawaited(_refreshAudioOutput());
      _audioOutputTimer = Timer.periodic(
          const Duration(seconds: 5), (_) => unawaited(_refreshAudioOutput()));
    }
  }

  @override
  void didUpdateWidget(covariant PulsePlayerDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.connect != widget.connect) {
      oldWidget.connect?.removeListener(_onConnectionChanged);
      widget.connect?.addListener(_onConnectionChanged);
    }
  }

  @override
  void dispose() {
    widget.connect?.removeListener(_onConnectionChanged);
    _audioOutputTimer?.cancel();
    super.dispose();
  }

  Future<void> _refreshAudioOutput() async {
    try {
      final name =
          (await _windowChannel.invokeMethod<String>('getAudioOutput'))?.trim();
      if (!mounted || name == _localAudioOutput) return;
      setState(
          () => _localAudioOutput = name?.isNotEmpty == true ? name : null);
    } on PlatformException {
      // The dock remains usable when the output device cannot be queried.
    } on MissingPluginException {
      // Older desktop runners do not expose the output device channel.
    }
  }

  void _onConnectionChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final playback = widget.playback;
    final track = playback.currentTrack;
    final maxMs = playback.duration.inMilliseconds;
    final positionMs =
        playback.position.inMilliseconds.clamp(0, maxMs > 0 ? maxMs : 1);
    final sliderValue = (_draggingPosition ?? positionMs.toDouble())
        .clamp(0, maxMs > 0 ? maxMs.toDouble() : 1)
        .toDouble();
    final muted =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: .65);
    final palette = PulsePaletteTheme.of(context);
    final frosted = palette.isFrosted;
    final connectedDevice = widget.connect?.connected == true &&
            widget.connect?.selectedRemote == true
        ? widget.connect?.deviceName?.trim()
        : null;
    final hasConnectedDevice = connectedDevice?.isNotEmpty == true;
    final outputName = hasConnectedDevice ? connectedDevice : _localAudioOutput;
    final hasOutputName = outputName?.isNotEmpty == true;
    return Container(
      key: const Key('pulse-player-dock-surface'),
      height: 88,
      width: double.infinity,
      decoration: frosted
          ? BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: const [Color(0x34252B30), Color(0x92252B30)],
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.16),
              ),
            )
          : BoxDecoration(color: palette.dock),
      clipBehavior: frosted ? Clip.antiAlias : Clip.none,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(children: [
        Expanded(
            flex: 3,
            child: PulseTrackNavigationSwipe(
              onPrevious: track == null ? null : playback.skipPrevious,
              onNext: track == null ? null : playback.skipNext,
              child: Row(children: [
                PulseTrackArtwork(
                  track: track,
                  title: track?.title ?? 'Pulse',
                  creator: '${track?.artist ?? ''}${track?.album ?? ''}',
                  size: 56,
                  borderRadius: 4,
                ),
                const SizedBox(width: 12),
                Flexible(
                    child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(track?.title ?? 'Nenhuma faixa selecionada',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    Row(children: [
                      Flexible(
                        child: PulseArtistLink(
                          artist: track?.artist,
                          fallback: track == null
                              ? 'Escolha uma faixa'
                              : 'Artista não informado',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: muted),
                          onOpenArtist: widget.onOpenArtist,
                        ),
                      ),
                      if (track?.source == AudioSource.jellyfin)
                        Text(' • Jellyfin',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: muted)),
                    ]),
                    if (hasOutputName)
                      Row(children: [
                        Icon(Icons.devices_rounded,
                            size: 13,
                            color: hasConnectedDevice ? palette.accent : muted),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(outputName!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                      color: hasConnectedDevice
                                          ? palette.accent
                                          : muted)),
                        ),
                      ]),
                  ],
                )),
                IconButton(
                  tooltip: track == null
                      ? 'Selecione uma faixa para adicionar aos Favoritos'
                      : widget.isFavorite
                          ? 'Remover dos Favoritos'
                          : 'Adicionar aos Favoritos',
                  onPressed: track == null ? null : widget.onToggleFavorite,
                  iconSize: 20,
                  icon: Icon(
                      widget.isFavorite
                          ? Icons.favorite_rounded
                          : Icons.favorite_border_rounded,
                      color: widget.isFavorite
                          ? PulsePaletteTheme.of(context).accent
                          : muted),
                ),
              ]),
            )),
        Expanded(
            flex: 4,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PulsePlaybackModeButtons(
                  playback: playback,
                  compact: true,
                  middle: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: 'Anterior',
                      onPressed: track == null ? null : playback.skipPrevious,
                      iconSize: 22,
                      icon: const Icon(Icons.skip_previous_rounded),
                    ),
                    Tooltip(
                      message: playback.isPlaying ? 'Pausar' : 'Reproduzir',
                      child: Material(
                        color: track == null ? Colors.white24 : Colors.white,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: track == null ? null : playback.togglePlayback,
                          child: SizedBox.square(
                              dimension: 34,
                              child: Icon(
                                  playback.isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded,
                                  color: Colors.black,
                                  size: 22)),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Próxima',
                      onPressed: track == null ? null : playback.skipNext,
                      iconSize: 22,
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                  ]),
                ),
                if (track != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: Row(children: [
                      SizedBox(
                          width: 34,
                          child: Text(_formatTime(playback.position),
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: muted))),
                      Expanded(
                          child: MouseRegion(
                        onEnter: (_) => setState(() => _isSeekHovered = true),
                        onExit: (_) => setState(() => _isSeekHovered = false),
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3,
                            activeTrackColor:
                                _isSeekHovered ? palette.accent : Colors.white,
                            inactiveTrackColor: _isSeekHovered
                                ? palette.accent.withValues(alpha: .38)
                                : Colors.white,
                            thumbColor:
                                _isSeekHovered ? palette.accent : Colors.white,
                            overlayColor: palette.accent.withValues(alpha: .16),
                            trackShape: const RoundedRectSliderTrackShape(),
                            thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 5,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 12,
                            ),
                          ),
                          child: Slider(
                            min: 0,
                            max: maxMs > 0 ? maxMs.toDouble() : 1,
                            value: sliderValue,
                            onChanged: maxMs <= 0
                                ? null
                                : (value) => setState(
                                      () => _draggingPosition = value,
                                    ),
                            onChangeEnd: maxMs <= 0
                                ? null
                                : (value) {
                                    setState(() => _draggingPosition = null);
                                    playback.seek(
                                        Duration(milliseconds: value.round()));
                                  },
                          ),
                        ),
                      )),
                      SizedBox(
                          width: 34,
                          child: Text(_formatTime(playback.duration),
                              textAlign: TextAlign.end,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(color: muted))),
                    ]),
                  ),
              ],
            )),
        Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (widget.onToggleLyrics != null)
                  IconButton(
                    tooltip: widget.lyricsOpen ? 'Fechar letra' : 'Letra',
                    onPressed: track == null ? null : widget.onToggleLyrics,
                    iconSize: 20,
                    icon: Icon(Icons.mic_external_on_rounded,
                        color: widget.lyricsOpen ? palette.accent : null),
                  ),
                IconButton(
                  tooltip: 'Fila de reprodução',
                  onPressed: widget.onShowQueue,
                  iconSize: 20,
                  icon: const Icon(Icons.queue_music_rounded),
                ),
                TapRegion(
                  groupId: widget.deviceTapRegionGroup,
                  child: IconButton(
                    tooltip: hasConnectedDevice
                        ? 'Conectado a $connectedDevice'
                        : hasOutputName
                            ? 'Saída de áudio: $outputName'
                            : 'Conectar a um dispositivo',
                    onPressed: widget.onToggleDevices,
                    iconSize: 20,
                    icon: Icon(
                      Icons.devices_rounded,
                      color: widget.devicesOpen ||
                              widget.connect?.selectedRemote == true
                          ? palette.accent
                          : null,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: playback.volume == 0 ? 'Ativar som' : 'Silenciar',
                  onPressed: () =>
                      playback.setVolume(playback.volume == 0 ? 1 : 0),
                  iconSize: 20,
                  icon: Icon(playback.volume == 0
                      ? Icons.volume_off_rounded
                      : Icons.volume_up_rounded),
                ),
                SizedBox(
                  width: MediaQuery.sizeOf(context).width < 1100 ? 76 : 120,
                  child: Listener(
                    onPointerSignal: (event) {
                      if (event is! PointerScrollEvent ||
                          event.scrollDelta.dy == 0) {
                        return;
                      }
                      final change =
                          (-event.scrollDelta.dy / 120 * 0.05).clamp(-0.2, 0.2);
                      unawaited(playback.setVolume(playback.volume + change));
                    },
                    child: MouseRegion(
                      onEnter: (_) => setState(() => _isVolumeHovered = true),
                      onExit: (_) => setState(() => _isVolumeHovered = false),
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4,
                          activeTrackColor:
                              _isVolumeHovered ? palette.accent : Colors.white,
                          inactiveTrackColor: _isVolumeHovered
                              ? palette.accent.withValues(alpha: .38)
                              : Colors.white,
                          thumbColor:
                              _isVolumeHovered ? palette.accent : Colors.white,
                          overlayColor: palette.accent.withValues(alpha: .16),
                          trackShape: const RoundedRectSliderTrackShape(),
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 6),
                          overlayShape:
                              const RoundSliderOverlayShape(overlayRadius: 13),
                        ),
                        child: Slider(
                          value: _draggingVolume ?? playback.volume,
                          onChanged: (value) {
                            setState(() => _draggingVolume = value);
                            unawaited(playback.setVolume(value));
                          },
                          onChangeEnd: (_) =>
                              setState(() => _draggingVolume = null),
                        ),
                      ),
                    ),
                  ),
                ),
                if (widget.onExpand case final expand?)
                  IconButton(
                    tooltip: widget.expanded
                        ? 'Sair da tela cheia'
                        : 'Entrar na tela cheia',
                    onPressed: expand,
                    iconSize: 19,
                    icon: Icon(widget.expanded
                        ? Icons.close_fullscreen_rounded
                        : Icons.open_in_full_rounded),
                  ),
              ],
            )),
      ]),
    );
  }
}

String _formatTime(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
