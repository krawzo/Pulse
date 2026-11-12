import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/local_artwork_cache.dart';
import '../data/remote_artwork_cache.dart';
import '../domain/audio_track.dart';
import '../state/mobile_audio_output.dart';
import '../state/pulse_connect_controller.dart';
import 'pulse_track_artwork.dart';
import 'pulse_track_navigation_swipe.dart';

class CompactMiniPlayer extends StatefulWidget {
  const CompactMiniPlayer({
    super.key,
    required this.track,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.onToggle,
    required this.onSeek,
    required this.onOpenNowPlaying,
    this.onPrevious,
    this.onNext,
    this.mobile = false,
    this.connect,
    this.onShowDevices,
    this.onToggleFavorite,
    this.isFavorite = false,
  });

  final AudioTrack? track;
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final VoidCallback onToggle;
  final ValueChanged<Duration> onSeek;
  final VoidCallback onOpenNowPlaying;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final bool mobile;
  final PulseConnectController? connect;
  final VoidCallback? onShowDevices;
  final VoidCallback? onToggleFavorite;
  final bool isFavorite;

  @override
  State<CompactMiniPlayer> createState() => _CompactMiniPlayerState();
}

class _CompactMiniPlayerState extends State<CompactMiniPlayer> {
  double? _draggingPosition;
  Future<Color?>? _coverColor;
  String? _artworkSignature;

  @override
  void initState() {
    super.initState();
    _loadColor();
    if (widget.mobile) {
      MobileAudioOutput.instance.start();
      MobileAudioOutput.instance.addListener(_onOutputChanged);
      widget.connect?.addListener(_onOutputChanged);
    }
  }

  void _onOutputChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    MobileAudioOutput.instance.removeListener(_onOutputChanged);
    widget.connect?.removeListener(_onOutputChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant CompactMiniPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mobile != widget.mobile ||
        oldWidget.connect != widget.connect) {
      if (oldWidget.mobile) {
        MobileAudioOutput.instance.removeListener(_onOutputChanged);
        oldWidget.connect?.removeListener(_onOutputChanged);
      }
      if (widget.mobile) {
        MobileAudioOutput.instance.start();
        MobileAudioOutput.instance.addListener(_onOutputChanged);
        widget.connect?.addListener(_onOutputChanged);
      }
    }
    final track = widget.track;
    final signature = track == null
        ? null
        : '${track.id}\u0000${track.path}\u0000${track.modifiedAtMillis}\u0000${track.artworkUrl ?? ''}';
    if (signature != _artworkSignature) _loadColor();
  }

  void _loadColor() {
    final track = widget.track;
    _artworkSignature = track == null
        ? null
        : '${track.id}\u0000${track.path}\u0000${track.modifiedAtMillis}\u0000${track.artworkUrl ?? ''}';
    _coverColor = track == null ? Future.value(null) : _extractColor(track);
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
        final Uint8List? bytes =
            await LocalArtworkCache.instance.imageForTracks([
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

  @override
  Widget build(BuildContext context) {
    final maxMs = widget.duration.inMilliseconds;
    final positionMs = widget.position.inMilliseconds.clamp(
      0,
      maxMs > 0 ? maxMs : 1,
    );
    final value = (_draggingPosition ?? positionMs.toDouble())
        .clamp(0, maxMs > 0 ? maxMs.toDouble() : 1)
        .toDouble();
    if (widget.mobile) {
      final progress = maxMs > 0 ? (value / maxMs).clamp(0.0, 1.0) : 0.0;
      final remoteName = widget.connect?.connected == true
          ? widget.connect?.deviceName?.trim()
          : null;
      final deviceName = remoteName?.isNotEmpty == true
          ? remoteName
          : MobileAudioOutput.instance.deviceName;
      final namedDevice = deviceName?.isNotEmpty == true;
      final artist = widget.track?.artist?.trim() ?? '';
      return FutureBuilder<Color?>(
        future: _coverColor,
        builder: (context, snapshot) {
          final hsv =
              HSVColor.fromColor(snapshot.data ?? const Color(0xFF327F70));
          final color = hsv
              .withSaturation(hsv.saturation < .68 ? .68 : hsv.saturation)
              .withValue(hsv.value < .56 ? .56 : hsv.value)
              .toColor();
          return Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 4),
            child: PulseTrackNavigationSwipe(
              onPrevious: widget.track == null ? null : widget.onPrevious,
              onNext: widget.track == null ? null : widget.onNext,
              child: Material(
                color: color,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.all(7),
                          child: PulseTrackArtwork(
                            track: widget.track,
                            title: widget.track?.title ?? 'Pulse',
                            creator: widget.track?.artist ?? '',
                            size: 42,
                            borderRadius: 6,
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            onTap: widget.onOpenNowPlaying,
                            child: SizedBox(
                              height: 56,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                      namedDevice && artist.isNotEmpty
                                          ? '${widget.track?.title ?? ''} · $artist'
                                          : widget.track?.title ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700)),
                                  if (namedDevice)
                                    Row(children: [
                                      Icon(
                                        remoteName?.isNotEmpty == true
                                            ? Icons.devices_rounded
                                            : Icons.headphones_rounded,
                                        size: 12,
                                        color: const Color(0xFF1ED760),
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(deviceName!,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                color: Color(0xFF1ED760),
                                                fontSize: 11)),
                                      ),
                                    ])
                                  else
                                    Text(
                                        widget.track?.artist ??
                                            'Artista não informado',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12)),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (widget.onShowDevices != null)
                          IconButton(
                            tooltip: namedDevice
                                ? 'Conectado a $deviceName'
                                : 'Conectar a um dispositivo',
                            onPressed: widget.onShowDevices,
                            icon: Icon(remoteName?.isNotEmpty == true
                                ? Icons.devices_rounded
                                : namedDevice
                                    ? Icons.headphones_rounded
                                    : Icons.devices_rounded),
                            color: namedDevice
                                ? const Color(0xFF1ED760)
                                : Colors.white,
                            iconSize: 19,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                                width: 34, height: 48),
                          ),
                        if (widget.onToggleFavorite != null)
                          IconButton(
                            tooltip: widget.isFavorite
                                ? 'Remover de músicas curtidas'
                                : 'Adicionar a músicas curtidas',
                            onPressed: widget.track == null
                                ? null
                                : widget.onToggleFavorite,
                            icon: Icon(widget.isFavorite
                                ? Icons.check_circle_rounded
                                : Icons.favorite_border_rounded),
                            color: widget.isFavorite
                                ? const Color(0xFF1ED760)
                                : Colors.white,
                            iconSize: 21,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                                width: 34, height: 48),
                          ),
                        IconButton(
                          tooltip: widget.isPlaying ? 'Pausar' : 'Reproduzir',
                          onPressed:
                              widget.track == null ? null : widget.onToggle,
                          icon: Icon(widget.isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded),
                          color: Colors.white,
                          iconSize: 26,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                              width: 38, height: 48),
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 2,
                      backgroundColor: Colors.white24,
                      valueColor:
                          const AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
        decoration: BoxDecoration(
          border:
              Border(top: BorderSide(color: Theme.of(context).dividerColor)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                PulseTrackArtwork(
                  track: widget.track,
                  title: widget.track?.title ?? 'Pulse',
                  creator:
                      '${widget.track?.artist ?? ''}${widget.track?.album ?? ''}',
                  size: 40,
                  borderRadius: 7,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PulseTrackNavigationSwipe(
                    onPrevious: widget.track == null ? null : widget.onPrevious,
                    onNext: widget.track == null ? null : widget.onNext,
                    child: InkWell(
                      onTap: widget.onOpenNowPlaying,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.track?.title ?? 'Escolha uma faixa',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                          Text(
                            widget.track?.artist ?? 'Player local',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withValues(alpha: 0.68),
                                    ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: widget.isPlaying ? 'Pausar' : 'Reproduzir',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.track == null ? null : widget.onToggle,
                  icon: Icon(
                    widget.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
                IconButton(
                  tooltip: 'Mostrar a tela Tocando agora',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onOpenNowPlaying,
                  icon: const Icon(Icons.open_in_full_rounded, size: 18),
                ),
              ],
            ),
            if (widget.track != null)
              Row(
                children: [
                  SizedBox(
                    width: 36,
                    child: Text(
                      _formatTime(widget.position),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      min: 0,
                      max: maxMs > 0 ? maxMs.toDouble() : 1,
                      value: value,
                      onChanged: maxMs <= 0
                          ? null
                          : (next) => setState(() => _draggingPosition = next),
                      onChangeEnd: maxMs <= 0
                          ? null
                          : (next) {
                              setState(() => _draggingPosition = null);
                              widget
                                  .onSeek(Duration(milliseconds: next.round()));
                            },
                    ),
                  ),
                  SizedBox(
                    width: 36,
                    child: Text(
                      _formatTime(widget.duration),
                      textAlign: TextAlign.end,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

String _formatTime(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
