import 'dart:io';

import 'package:flutter/material.dart';

import '../domain/audio_track.dart';
import '../domain/pulse_preferences.dart';
import '../app/pulse_theme.dart';
import 'pulse_mobile_track_swipe.dart';
import 'pulse_track_artwork.dart';

class PulseTrackRow extends StatefulWidget {
  const PulseTrackRow({
    super.key,
    required this.track,
    required this.selected,
    required this.favorite,
    required this.playlists,
    required this.onSelect,
    required this.onFavorite,
    required this.onAddToPlaylist,
    required this.onAddToQueue,
    required this.onPlayNext,
    required this.onSetSleepTimer,
    required this.onShare,
    required this.sleepTimerActive,
    required this.canStopAfterCurrentTrack,
    this.onOpenAlbum,
    this.onOpenArtist,
    this.onDownload,
    this.downloaded = false,
    this.downloading = false,
    this.density = PulseDensity.compact,
  });

  final AudioTrack track;
  final bool selected;
  final bool favorite;
  final List<PulsePlaylist> playlists;
  final VoidCallback onSelect;
  final VoidCallback onFavorite;
  final ValueChanged<String> onAddToPlaylist;
  final VoidCallback onAddToQueue;
  final VoidCallback onPlayNext;
  final ValueChanged<Duration?> onSetSleepTimer;
  final Future<void> Function() onShare;
  final bool sleepTimerActive;
  final bool canStopAfterCurrentTrack;
  final VoidCallback? onOpenAlbum;
  final VoidCallback? onOpenArtist;
  final Future<void> Function()? onDownload;
  final bool downloaded;
  final bool downloading;
  final PulseDensity density;

  @override
  State<PulseTrackRow> createState() => _PulseTrackRowState();
}

class _PulseTrackRowState extends State<PulseTrackRow> {
  bool _hovered = false;
  final GlobalKey _menuButtonKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showAlbumColumn = constraints.maxWidth >= 720;
        final desktop = Platform.isWindows;
        final rowHeight = switch (widget.density) {
              PulseDensity.compact => 56.0,
              PulseDensity.standard => 64.0,
              PulseDensity.comfortable => 72.0,
            } +
            (desktop ? 10.0 : 0.0);
        final artworkSize = switch (widget.density) {
              PulseDensity.compact => 40.0,
              PulseDensity.standard => 44.0,
              PulseDensity.comfortable => 48.0,
            } +
            (desktop ? 4.0 : 0.0);
        final colors = Theme.of(context).colorScheme;
        final palette = PulsePaletteTheme.of(context);
        final dark = Theme.of(context).brightness == Brightness.dark;
        final onGradient = widget.selected &&
            !desktop &&
            palette.functionalReverseGradient != null;
        final selectedFill = desktop
            ? (dark ? const Color(0xB344494F) : const Color(0xFFE2E2E2))
            : colors.secondaryContainer;
        final hoverFill = desktop
            ? (dark ? const Color(0xA8000000) : const Color(0xFFE8E8E8))
            : colors.surfaceContainerHighest;
        final restingFill =
            desktop && dark ? const Color(0x26000000) : Colors.transparent;
        final artist = widget.track.artist?.trim();
        final album = widget.track.album?.trim();
        final genre = widget.track.genre?.trim();
        final subtitle = [
          if (artist != null && artist.isNotEmpty) artist,
          if (genre != null && genre.isNotEmpty) genre,
          if (widget.track.source == AudioSource.jellyfin) 'Jellyfin',
        ].join(' • ');
        final accessibleLabel = [
          widget.track.title,
          if (artist != null && artist.isNotEmpty) artist,
          if (album != null && album.isNotEmpty) album,
          if (genre != null && genre.isNotEmpty) 'Gênero: $genre',
        ].join(', ');

        final row = MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: Tooltip(
            message: accessibleLabel,
            child: Material(
              color: onGradient
                  ? Colors.transparent
                  : widget.selected
                      ? selectedFill
                      : _hovered
                          ? hoverFill
                          : restingFill,
              borderRadius: BorderRadius.circular(8),
              child: Ink(
                decoration: BoxDecoration(
                  gradient:
                      onGradient ? palette.functionalReverseGradient : null,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: InkWell(
                  onTap: widget.onSelect,
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: rowHeight,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          if (desktop)
                            SizedBox(
                              width: 16,
                              child: widget.selected || _hovered
                                  ? Icon(Icons.play_arrow_rounded,
                                      size: 16,
                                      color:
                                          dark ? Colors.white : Colors.black87)
                                  : null,
                            )
                          else
                            Container(
                              width: 2,
                              height: 36,
                              decoration: BoxDecoration(
                                color: widget.selected
                                    ? palette.selectedMarker
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          const SizedBox(width: 6),
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              PulseTrackArtwork(
                                track: widget.track,
                                title: widget.track.title,
                                creator:
                                    '${widget.track.artist ?? ''}${widget.track.album ?? ''}',
                                size: artworkSize,
                                borderRadius: 7,
                              ),
                              if (!desktop && (_hovered || widget.selected))
                                const Icon(Icons.play_arrow_rounded,
                                    color: Colors.white, size: 26),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  widget.track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: widget.selected
                                            ? desktop
                                                ? dark
                                                    ? palette.emphasisInk
                                                    : pulseLightAccent
                                                : onGradient
                                                    ? Colors.white
                                                    : colors
                                                        .onSecondaryContainer
                                            : Theme.of(context)
                                                .colorScheme
                                                .onSurface,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                Text(
                                  subtitle.isEmpty
                                      ? 'Artista não informado'
                                      : subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: widget.selected
                                              ? onGradient
                                                  ? Colors.white
                                                  : colors.onSecondaryContainer
                                              : colors.onSurface.withValues(
                                                  alpha: 0.68,
                                                )),
                                ),
                              ],
                            ),
                          ),
                          if (showAlbumColumn &&
                              album != null &&
                              album.isNotEmpty)
                            SizedBox(
                              width: 176,
                              child: Text(
                                album,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                        color: onGradient
                                            ? Colors.white
                                            : Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                                .withValues(alpha: 0.68)),
                              ),
                            ),
                          Tooltip(
                            message: widget.favorite
                                ? 'Remover dos favoritos'
                                : 'Adicionar aos favoritos',
                            child: SizedBox(
                              width: 48,
                              height: 48,
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: widget.onFavorite,
                                  customBorder: const CircleBorder(),
                                  child: Center(
                                    child: Icon(
                                      widget.favorite
                                          ? Icons.favorite_rounded
                                          : Icons.favorite_border_rounded,
                                      size: 20,
                                      color: onGradient
                                          ? Colors.white
                                          : widget.favorite
                                              ? palette.emphasisInk
                                              : colors.onSurface
                                                  .withValues(alpha: 0.6),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Tooltip(
                            message: 'Mais opções',
                            child: SizedBox(
                              width: 48,
                              height: 48,
                              child: PopupMenuButton<String>(
                                key: _menuButtonKey,
                                tooltip: null,
                                constraints: const BoxConstraints(
                                  minWidth: 240,
                                  maxWidth: 300,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 12,
                                padding: EdgeInsets.zero,
                                onSelected: _onMenuSelected,
                                itemBuilder: _buildMenuItems,
                                child: SizedBox.expand(
                                  child: Center(
                                    child: Icon(Icons.more_vert_rounded,
                                        color:
                                            onGradient ? Colors.white : null),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        return desktop || constraints.maxWidth >= 600
            ? row
            : PulseMobileTrackSwipe(
                onPlayNext: widget.onPlayNext,
                child: row,
              );
      },
    );
  }

  List<PopupMenuEntry<String>> _buildMenuItems(BuildContext context) {
    final items = <PopupMenuEntry<String>>[
      _menuItem(
          'playlist_menu', Icons.playlist_add_rounded, 'Adicionar à playlist',
          hasSubmenu: true),
      _menuItem(
        'favorite',
        widget.favorite ? Icons.favorite_rounded : Icons.favorite_border,
        widget.favorite
            ? 'Remover de músicas curtidas'
            : 'Adicionar a músicas curtidas',
      ),
      _menuItem('add_queue', Icons.queue_music_rounded, 'Adicionar à fila'),
      _menuItem('play_next', Icons.playlist_play_rounded, 'Tocar a seguir'),
      if (widget.onDownload != null)
        _menuItem(
            'download',
            widget.downloaded
                ? Icons.download_done_rounded
                : Icons.download_outlined,
            widget.downloading
                ? 'Baixando…'
                : widget.downloaded
                    ? 'Remover download'
                    : 'Baixar'),
      _menuItem('timer_menu', Icons.timer_outlined, 'Timer', hasSubmenu: true),
    ];

    items.add(const PopupMenuDivider(height: 8));
    if (widget.onOpenArtist != null || widget.onOpenAlbum != null) {
      if (widget.onOpenArtist != null) {
        items.add(_menuItem(
            'artist', Icons.person_outline_rounded, 'Ir para o artista'));
      }
      if (widget.onOpenAlbum != null) {
        items.add(_menuItem(
          'album',
          Icons.album_outlined,
          'Ir para o álbum',
        ));
      }
    }
    items.add(_menuItem('share', Icons.share_outlined, 'Compartilhar'));

    return items;
  }

  PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label, {
    bool hasSubmenu = false,
  }) =>
      PopupMenuItem<String>(
        value: value,
        height: 46,
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (hasSubmenu) ...[
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right_rounded, size: 20),
            ],
          ],
        ),
      );

  Future<void> _onMenuSelected(String value) async {
    switch (value) {
      case 'add_queue':
        widget.onAddToQueue();
      case 'play_next':
        widget.onPlayNext();
      case 'download':
        if (!widget.downloading) await widget.onDownload?.call();
      case 'favorite':
        widget.onFavorite();
      case 'playlist_menu':
        final playlistId = await _showSubmenu<String>(
          _playlistMenuItems(),
        );
        if (playlistId != null) {
          widget.onAddToPlaylist(playlistId);
        }
      case 'timer_menu':
        final timer = await _showSubmenu<String>(_timerMenuItems());
        if (timer == null) return;
        if (timer == 'end_of_track') {
          widget.onSetSleepTimer(null);
        } else if (timer == 'cancel') {
          widget.onSetSleepTimer(Duration.zero);
        } else {
          final minutes = int.tryParse(timer);
          if (minutes != null) {
            widget.onSetSleepTimer(Duration(minutes: minutes));
          }
        }
      case 'artist':
        widget.onOpenArtist?.call();
      case 'album':
        widget.onOpenAlbum?.call();
      case 'share':
        await widget.onShare();
      default:
        return;
    }
  }

  List<PopupMenuEntry<String>> _playlistMenuItems() => widget.playlists.isEmpty
      ? const [
          PopupMenuItem<String>(
            enabled: false,
            child: Text('Nenhuma playlist criada'),
          ),
        ]
      : widget.playlists
          .map((playlist) => _menuItem(
                playlist.id,
                Icons.queue_music_rounded,
                playlist.name,
              ))
          .toList(growable: false);

  List<PopupMenuEntry<String>> _timerMenuItems() => [
        _menuItem('5', Icons.schedule_rounded, '5 minutos'),
        _menuItem('10', Icons.schedule_rounded, '10 minutos'),
        _menuItem('15', Icons.schedule_rounded, '15 minutos'),
        _menuItem('30', Icons.schedule_rounded, '30 minutos'),
        _menuItem('45', Icons.schedule_rounded, '45 minutos'),
        _menuItem('60', Icons.schedule_rounded, '1 hora'),
        const PopupMenuDivider(height: 8),
        PopupMenuItem<String>(
          value: 'end_of_track',
          enabled: widget.canStopAfterCurrentTrack,
          height: 46,
          child: Row(
            children: [
              const Icon(Icons.stop_circle_outlined, size: 20),
              const SizedBox(width: 12),
              const Expanded(
                child: Text('Quando a faixa acabar',
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
        if (widget.sleepTimerActive)
          _menuItem('cancel', Icons.timer_off_outlined, 'Cancelar timer'),
      ];

  Future<T?> _showSubmenu<T>(List<PopupMenuEntry<T>> items) async {
    final buttonContext = _menuButtonKey.currentContext;
    if (buttonContext == null) return null;
    final button = buttonContext.findRenderObject();
    final overlay = Overlay.of(buttonContext).context.findRenderObject();
    if (button is! RenderBox || overlay is! RenderBox) return null;
    final topLeft = button.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight = button.localToGlobal(
      button.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    return showMenu<T>(
      context: buttonContext,
      position: RelativeRect.fromRect(
        Rect.fromPoints(topLeft, bottomRight),
        Offset.zero & overlay.size,
      ),
      constraints: const BoxConstraints(minWidth: 240, maxWidth: 300),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 12,
      items: items,
    );
  }
}
