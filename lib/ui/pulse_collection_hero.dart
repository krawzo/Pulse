import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../app/pulse_theme.dart';
import '../data/local_artwork_cache.dart';
import '../data/remote_artwork_cache.dart';
import '../domain/audio_track.dart';
import 'pulse_track_artwork.dart';

class PulseCollectionHero extends StatefulWidget {
  const PulseCollectionHero({
    super.key,
    required this.title,
    required this.type,
    required this.metadata,
    required this.tracks,
    required this.onBack,
    required this.onPlay,
    required this.backTooltip,
    required this.playTooltip,
    this.content,
    this.secondaryActions,
    this.onShuffle,
    this.shuffleActive = false,
    this.onAddToQueue,
    this.artworkBuilder,
    this.menuItems,
    this.onMenuAction,
    this.onMobileMenuPressed,
    this.trailingActionsBuilder,
    this.colorOverride,
  });

  final String title;
  final String type;
  final String metadata;
  final List<AudioTrack> tracks;
  final VoidCallback onBack;
  final VoidCallback? onPlay;
  final String backTooltip;
  final String playTooltip;
  final Widget? content;
  final Widget? secondaryActions;
  final VoidCallback? onShuffle;
  final bool shuffleActive;
  final VoidCallback? onAddToQueue;
  final Widget Function(double size)? artworkBuilder;
  final List<PopupMenuEntry<String>>? menuItems;
  final ValueChanged<String>? onMenuAction;
  final VoidCallback? onMobileMenuPressed;
  final Widget Function(bool compact)? trailingActionsBuilder;
  final Color? colorOverride;

  @override
  State<PulseCollectionHero> createState() => _PulseCollectionHeroState();
}

class _PulseCollectionHeroState extends State<PulseCollectionHero> {
  Future<Color?>? _coverColor;

  @override
  void initState() {
    super.initState();
    _loadColor();
  }

  @override
  void didUpdateWidget(covariant PulseCollectionHero oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_artworkSignature(oldWidget.tracks) !=
        _artworkSignature(widget.tracks)) {
      _loadColor();
    }
  }

  String _artworkSignature(List<AudioTrack> tracks) => tracks
      .take(8)
      .map((track) =>
          '${track.id}\u0000${track.path}\u0000${track.modifiedAtMillis}\u0000${track.artworkUrl ?? ''}')
      .join('\u0001');

  void _loadColor() {
    final remoteTrack = widget.tracks
        .where((track) =>
            track.source == AudioSource.jellyfin &&
            track.artworkUrl?.isNotEmpty == true)
        .firstOrNull;
    if (remoteTrack != null) {
      _coverColor = _extractRemoteColor(remoteTrack);
      return;
    }
    final local = widget.tracks
        .where((track) => track.source == AudioSource.local)
        .take(8);
    if (local.isEmpty) {
      _coverColor = Future.value(null);
      return;
    }
    _coverColor = _extractColor(local.toList(growable: false));
  }

  Future<Color?> _extractRemoteColor(AudioTrack track) async {
    try {
      final cached = await RemoteArtworkCache.instance.imageFor(track);
      final scheme = await ColorScheme.fromImageProvider(
        provider: cached == null
            ? NetworkImage(track.artworkUrl!)
            : FileImage(cached),
        brightness: Brightness.dark,
      );
      return scheme.primary;
    } on Object {
      return null;
    }
  }

  Future<void> _showMobileMenu() async {
    final items = widget.menuItems ??
        [
          PopupMenuItem<String>(
            value: 'play',
            child: Text(widget.playTooltip),
          ),
        ];
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: const Color(0xFF242424),
      builder: (sheetContext) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final entry in items)
              if (entry is PopupMenuItem<String>)
                ListTile(
                  enabled: entry.enabled,
                  title: entry.child,
                  onTap: entry.enabled && entry.value != null
                      ? () => Navigator.of(sheetContext).pop(entry.value)
                      : null,
                )
              else if (entry is PopupMenuDivider)
                const Divider(height: 1),
          ],
        ),
      ),
    );
    if (!mounted || selected == null) return;
    if (widget.onMenuAction case final action?) {
      action(selected);
    } else if (selected == 'play') {
      widget.onPlay?.call();
    }
  }

  Future<Color?> _extractColor(List<AudioTrack> tracks) async {
    try {
      final Uint8List? bytes = await LocalArtworkCache.instance.imageForTracks(
        tracks.map((track) => (
              path: track.path,
              size: track.sizeBytes,
              modifiedAtMillis: track.modifiedAtMillis,
            )),
      );
      if (bytes == null) return null;
      final scheme = await ColorScheme.fromImageProvider(
        provider: MemoryImage(bytes),
        brightness: Brightness.dark,
      );
      return scheme.primary;
    } on Object {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 600;
          final mobile = Platform.isAndroid && narrow;
          final toolbarOnSecondLine = widget.trailingActionsBuilder != null &&
              constraints.maxWidth < 500;
          final light = Theme.of(context).brightness == Brightness.light;
          final coverSize = narrow
              ? mobile
                  ? (constraints.maxWidth * .55).clamp(150.0, 220.0).toDouble()
                  : 112.0
              : constraints.maxWidth < 720
                  ? 168.0
                  : 232.0;
          final surface = Theme.of(context).scaffoldBackgroundColor;
          final frosted = PulsePaletteTheme.of(context).isFrosted;
          return FutureBuilder<Color?>(
            future: _coverColor,
            builder: (context, snapshot) {
              final base = widget.colorOverride ??
                  snapshot.data ??
                  (mobile
                      ? PulsePaletteTheme.of(context).accent
                      : const Color(0xFF494949));
              const ink = Colors.white;
              final middle = Color.lerp(base, Colors.black, .42)!;
              final lower = Color.lerp(base, surface, light ? .72 : .86)!;
              final pageGradient = LinearGradient(
                begin: mobile ? Alignment.topCenter : Alignment.topLeft,
                end: mobile ? Alignment.bottomCenter : Alignment.bottomRight,
                stops: const [0, .34, .70, 1],
                colors: frosted
                    ? const [
                        Color(0x35232A30),
                        Color(0x2A20262B),
                        Color(0x20252B30),
                        Color(0x1020262A),
                      ]
                    : light
                        ? [
                            Color.lerp(Colors.white, base, .35)!,
                            Color.lerp(Colors.white, base, .20)!,
                            Color.lerp(Colors.white, base, .06)!,
                            surface,
                          ]
                        : [base, middle, lower, surface],
              );
              final header = <Widget>[
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.fromLTRB(
                    narrow ? 14 : 24,
                    8,
                    narrow ? 14 : 24,
                    22,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      IconButton(
                        tooltip: widget.backTooltip,
                        onPressed: widget.onBack,
                        icon: Icon(Icons.arrow_back_rounded, color: ink),
                      ),
                      const SizedBox(height: 10),
                      if (mobile) ...[
                        Center(
                          child: widget.artworkBuilder?.call(coverSize) ??
                              PulseTrackArtwork(
                                artworkTracks: widget.tracks,
                                title: widget.title,
                                creator: widget.metadata,
                                size: coverSize,
                                borderRadius: 5,
                              ),
                        ),
                        const SizedBox(height: 22),
                        Text(widget.type.toUpperCase(),
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: .6)),
                        const SizedBox(height: 7),
                        Text(widget.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                height: 1.06,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        Text(widget.metadata,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                      ],
                      if (!mobile)
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            widget.artworkBuilder?.call(coverSize) ??
                                PulseTrackArtwork(
                                  artworkTracks: widget.tracks,
                                  title: widget.title,
                                  creator: widget.metadata,
                                  size: coverSize,
                                  borderRadius: 4,
                                ),
                            const SizedBox(width: 20),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text(
                                    widget.type.toUpperCase(),
                                    style: TextStyle(
                                      color: ink,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: .6,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    widget.title,
                                    maxLines: narrow ? 2 : 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: ink,
                                      fontWeight: FontWeight.w800,
                                      height: 1.05,
                                      fontSize: narrow
                                          ? 30
                                          : constraints.maxWidth < 800
                                              ? 44
                                              : 60,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    widget.metadata,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: ink.withValues(alpha: .84),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                SizedBox(
                  height: toolbarOnSecondLine ? 120 : 72,
                  width: double.infinity,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(children: [
                      SizedBox(
                          height: 72,
                          child: Row(
                            children: [
                              Tooltip(
                                message: widget.playTooltip,
                                child: Material(
                                  color: widget.onPlay == null
                                      ? Colors.grey
                                      : PulsePaletteTheme.of(context).accent,
                                  shape: const CircleBorder(),
                                  child: InkWell(
                                    customBorder: const CircleBorder(),
                                    onTap: widget.onPlay,
                                    child: SizedBox.square(
                                      dimension: 56,
                                      child: Icon(
                                        Icons.play_arrow_rounded,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onPrimary,
                                        size: 34,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              if (widget.onShuffle != null)
                                IconButton(
                                  tooltip: widget.shuffleActive
                                      ? 'Desativar reprodução aleatória'
                                      : 'Reprodução aleatória',
                                  onPressed: widget.onShuffle,
                                  color: widget.shuffleActive
                                      ? PulsePaletteTheme.of(context).accent
                                      : ink.withValues(alpha: .78),
                                  icon: const Icon(Icons.shuffle_rounded),
                                ),
                              if (widget.onAddToQueue != null)
                                IconButton(
                                  tooltip: 'Adicionar playlist à fila',
                                  onPressed: widget.onAddToQueue,
                                  color: ink.withValues(alpha: .78),
                                  icon: const Icon(Icons.queue_music_rounded),
                                ),
                              if (widget.trailingActionsBuilder == null ||
                                  toolbarOnSecondLine)
                                const Spacer(),
                              if (mobile)
                                IconButton(
                                  tooltip: 'Mais opções',
                                  onPressed: widget.onPlay != null ||
                                          widget.menuItems?.isNotEmpty == true
                                      ? widget.onMobileMenuPressed ??
                                          _showMobileMenu
                                      : null,
                                  icon: const Icon(Icons.more_horiz_rounded,
                                      color: Colors.white),
                                )
                              else
                                PopupMenuButton<String>(
                                  tooltip: 'Mais opções',
                                  constraints: widget.menuItems == null
                                      ? null
                                      : const BoxConstraints(
                                          minWidth: 280,
                                          maxWidth: 320,
                                        ),
                                  enabled: widget.onPlay != null ||
                                      widget.menuItems?.isNotEmpty == true,
                                  onSelected: widget.onMenuAction ??
                                      (value) {
                                        if (value == 'play') {
                                          widget.onPlay?.call();
                                        }
                                      },
                                  itemBuilder: (context) =>
                                      widget.menuItems ??
                                      [
                                        PopupMenuItem(
                                          value: 'play',
                                          child: Text(widget.playTooltip),
                                        ),
                                      ],
                                  icon: Icon(Icons.more_horiz_rounded,
                                      color: ink),
                                ),
                              if (widget.trailingActionsBuilder != null &&
                                  !toolbarOnSecondLine) ...[
                                const Spacer(),
                                widget.trailingActionsBuilder!(
                                  constraints.maxWidth < 760,
                                ),
                              ],
                            ],
                          )),
                      if (toolbarOnSecondLine)
                        Align(
                          alignment: Alignment.centerRight,
                          child: widget.trailingActionsBuilder!(true),
                        ),
                    ]),
                  ),
                ),
                if (widget.secondaryActions != null)
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      narrow ? 16 : 24,
                      0,
                      narrow ? 16 : 24,
                      12,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: widget.secondaryActions!,
                    ),
                  ),
              ];
              return Container(
                decoration: BoxDecoration(gradient: pageGradient),
                child: mobile
                    ? NestedScrollView(
                        headerSliverBuilder: (context, innerBoxIsScrolled) => [
                          SliverToBoxAdapter(
                            child: Column(children: header),
                          ),
                        ],
                        body: widget.content ?? const SizedBox.shrink(),
                      )
                    : Column(
                        children: [
                          ...header,
                          Expanded(
                            child: widget.content ?? const SizedBox.shrink(),
                          ),
                        ],
                      ),
              );
            },
          );
        },
      );
}
