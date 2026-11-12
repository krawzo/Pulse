import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/local_artwork_cache.dart';
import '../data/remote_artwork_cache.dart';
import '../domain/audio_track.dart';
import 'pulse_local_artwork.dart';

class PulseTrackArtwork extends StatefulWidget {
  const PulseTrackArtwork({
    super.key,
    this.track,
    required this.title,
    this.artworkTracks,
    this.creator = '',
    this.fallbackIcon,
    this.size = 48,
    this.borderRadius = 10,
  });

  final AudioTrack? track;
  final List<AudioTrack>? artworkTracks;
  final String title;
  final String creator;
  final IconData? fallbackIcon;
  final double size;
  final double borderRadius;

  @override
  State<PulseTrackArtwork> createState() => _PulseTrackArtworkState();
}

class _PulseTrackArtworkState extends State<PulseTrackArtwork> {
  Future<Uint8List?>? _image;
  Future<File?>? _remoteFile;

  @override
  void initState() {
    super.initState();
    _startLoad();
  }

  @override
  void didUpdateWidget(covariant PulseTrackArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_trackSignature(oldWidget) != _trackSignature(widget)) {
      _startLoad();
    }
  }

  String _trackSignature(PulseTrackArtwork artwork) => [
        if (artwork.artworkTracks != null)
          ...artwork.artworkTracks!.map(
            (track) =>
                '${track.path}\u0000${track.sizeBytes}\u0000${track.modifiedAtMillis}\u0000${track.artworkUrl ?? ''}',
          ),
        if (artwork.artworkTracks == null && artwork.track != null)
          '${artwork.track!.path}\u0000${artwork.track!.sizeBytes}\u0000${artwork.track!.modifiedAtMillis}\u0000${artwork.track!.artworkUrl ?? ''}',
      ].join('\u0001');

  void _startLoad() {
    final track = widget.track;
    final candidates = widget.artworkTracks ??
        (track == null ? const <AudioTrack>[] : <AudioTrack>[track]);
    final localCandidates = candidates
        .where((item) => item.source == AudioSource.local)
        .toList(growable: false);
    _image = localCandidates.isEmpty
        ? null
        : LocalArtworkCache.instance.imageForTracks(
            localCandidates.map((item) => (
                  path: item.path,
                  size: item.sizeBytes,
                  modifiedAtMillis: item.modifiedAtMillis,
                )),
          );
    final remoteTrack = widget.track?.source == AudioSource.jellyfin
        ? widget.track
        : candidates
            .where((item) =>
                item.source == AudioSource.jellyfin && item.artworkUrl != null)
            .firstOrNull;
    _remoteFile =
        (Platform.isAndroid || Platform.isWindows) && remoteTrack != null
            ? RemoteArtworkCache.instance.imageFor(remoteTrack)
            : null;
  }

  Widget _fallback() => PulseLocalArtwork(
        key: ValueKey('fallback-${widget.title}-${widget.creator}'),
        title: widget.title,
        creator: widget.creator,
        icon: widget.fallbackIcon,
        size: widget.size,
        borderRadius: widget.borderRadius,
      );

  @override
  Widget build(BuildContext context) {
    final decodeWidth =
        (widget.size * MediaQuery.devicePixelRatioOf(context)).ceil();
    final remoteTrack = widget.track?.source == AudioSource.jellyfin
        ? widget.track
        : widget.artworkTracks
            ?.where((track) =>
                track.source == AudioSource.jellyfin &&
                track.artworkUrl != null)
            .firstOrNull;
    final remoteUrl = remoteTrack?.artworkUrl;
    if (remoteUrl != null) {
      final imageUri = Uri.tryParse(remoteUrl);
      final ready = remoteTrack == null
          ? null
          : RemoteArtworkCache.instance.readyImageFor(remoteTrack);
      if (ready != null) {
        return ExcludeSemantics(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: Image.file(ready,
                width: widget.size,
                height: widget.size,
                cacheWidth: decodeWidth,
                gaplessPlayback: true,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _fallback()),
          ),
        );
      }
      if (_remoteFile case final future?) {
        return FutureBuilder<File?>(
          future: future,
          builder: (context, snapshot) => ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              child: snapshot.data == null
                  ? _fallback()
                  : Image.file(snapshot.data!,
                      width: widget.size,
                      height: widget.size,
                      cacheWidth: decodeWidth,
                      gaplessPlayback: true,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          _fallback()),
            ),
          ),
        );
      }
      final image = imageUri?.scheme == 'file'
          ? Image.file(File.fromUri(imageUri!),
              width: widget.size,
              height: widget.size,
              cacheWidth: decodeWidth,
              gaplessPlayback: true,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => _fallback())
          : Image.network(remoteUrl,
              width: widget.size,
              height: widget.size,
              cacheWidth: decodeWidth,
              gaplessPlayback: true,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => _fallback());
      return ExcludeSemantics(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          child: image,
        ),
      );
    }
    final future = _image;
    if (future == null) return _fallback();
    return ExcludeSemantics(
      child: FutureBuilder<Uint8List?>(
        future: future,
        builder: (context, snapshot) {
          final bytes = snapshot.data;
          final child = bytes == null
              ? _fallback()
              : ClipRRect(
                  key: ValueKey('image-${bytes.hashCode}'),
                  borderRadius: BorderRadius.circular(widget.borderRadius),
                  child: SizedBox.square(
                    dimension: widget.size,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.memory(
                          bytes,
                          width: widget.size,
                          height: widget.size,
                          cacheWidth: decodeWidth,
                          gaplessPlayback: true,
                          fit: BoxFit.cover,
                          frameBuilder:
                              (context, child, frame, wasSynchronouslyLoaded) =>
                                  AnimatedSwitcher(
                            duration: const Duration(milliseconds: 160),
                            child: frame == null && !wasSynchronouslyLoaded
                                ? _fallback()
                                : child,
                          ),
                          errorBuilder: (context, error, stackTrace) =>
                              _fallback(),
                        ),
                      ],
                    ),
                  ),
                );
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 160),
            child: child,
          );
        },
      ),
    );
  }
}
