import 'package:flutter/material.dart';

import '../state/playback_controller.dart';

class PulsePlaybackModeButtons extends StatelessWidget {
  const PulsePlaybackModeButtons({
    super.key,
    required this.playback,
    this.compact = false,
    this.showLabels = false,
    this.middle,
  });

  final PlaybackController playback;
  final bool compact;
  final bool showLabels;
  final Widget? middle;

  @override
  Widget build(BuildContext context) {
    final repeatTooltip = switch (playback.repeatMode) {
      PulseRepeatMode.off => 'Repetir desativado',
      PulseRepeatMode.queue => 'Repetir fila',
      PulseRepeatMode.track => 'Repetir faixa',
    };
    final repeatIcon = playback.repeatMode == PulseRepeatMode.track
        ? const Icon(Icons.repeat_one_rounded)
        : const Icon(Icons.repeat_rounded);
    final activeColor = Theme.of(context).colorScheme.onSecondaryContainer;
    final repeatLabel = switch (playback.repeatMode) {
      PulseRepeatMode.off => null,
      PulseRepeatMode.queue => 'Fila',
      PulseRepeatMode.track => 'Faixa',
    };
    final repeatGlyph = repeatLabel != null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconTheme(data: const IconThemeData(size: 18), child: repeatIcon),
              const SizedBox(width: 4),
              Text(
                repeatLabel,
                style: TextStyle(
                  color: activeColor,
                  fontSize: 10,
                  height: 1,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          )
        : repeatIcon;
    final enabled = playback.currentTrack != null;
    if (showLabels) {
      return Row(
        children: [
          Expanded(
            child: _ModeTile(
              title: 'Aleatório',
              state: playback.shuffleEnabled ? 'Ativado' : 'Desligado',
              tooltip: playback.shuffleEnabled
                  ? 'Aleatório ativado'
                  : 'Aleatório desativado',
              icon: const Icon(Icons.shuffle_rounded),
              active: playback.shuffleEnabled,
              enabled: enabled,
              onPressed: playback.toggleShuffle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _ModeTile(
              title: 'Repetir',
              state: switch (playback.repeatMode) {
                PulseRepeatMode.off => 'Desligado',
                PulseRepeatMode.queue => 'Fila',
                PulseRepeatMode.track => 'Faixa',
              },
              tooltip: repeatTooltip,
              icon: repeatIcon,
              active: playback.repeatMode != PulseRepeatMode.off,
              enabled: enabled,
              onPressed: playback.cycleRepeatMode,
            ),
          ),
        ],
      );
    }

    final secondaryContainer = Theme.of(context).colorScheme.secondaryContainer;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _iconButton(
          tooltip: playback.shuffleEnabled
              ? 'Aleatório ativado'
              : 'Aleatório desativado',
          semanticLabel: playback.shuffleEnabled
              ? 'Aleatório, ativado'
              : 'Aleatório, desativado',
          active: playback.shuffleEnabled,
          enabled: enabled,
          visualDensity:
              compact ? VisualDensity.compact : VisualDensity.standard,
          activeColor: activeColor,
          onSurface: onSurface,
          secondaryContainer: secondaryContainer,
          icon: const Icon(Icons.shuffle_rounded),
          onPressed: playback.toggleShuffle,
        ),
        if (middle != null) middle!,
        _iconButton(
          tooltip: repeatTooltip,
          semanticLabel:
              'Repetir, ${repeatTooltip.replaceFirst('Repetir ', '')}',
          active: playback.repeatMode != PulseRepeatMode.off,
          enabled: enabled,
          visualDensity:
              compact ? VisualDensity.compact : VisualDensity.standard,
          activeColor: activeColor,
          onSurface: onSurface,
          secondaryContainer: secondaryContainer,
          icon: repeatGlyph,
          onPressed: playback.cycleRepeatMode,
        ),
      ],
    );
  }

  Widget _iconButton({
    required String tooltip,
    required String semanticLabel,
    required bool active,
    required bool enabled,
    required VisualDensity visualDensity,
    required Color activeColor,
    required Color onSurface,
    required Color secondaryContainer,
    required Widget icon,
    required VoidCallback onPressed,
  }) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        toggled: active,
        label: semanticLabel,
        onTap: enabled ? onPressed : null,
        child: ExcludeSemantics(
          child: Material(
            color: active ? secondaryContainer : Colors.transparent,
            shape: const CircleBorder(),
            child: IconButton(
              visualDensity: visualDensity,
              onPressed: enabled ? onPressed : null,
              color: active ? activeColor : onSurface,
              disabledColor: onSurface.withValues(alpha: 0.54),
              icon: icon,
            ),
          ),
        ),
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    required this.title,
    required this.state,
    required this.tooltip,
    required this.icon,
    required this.active,
    required this.enabled,
    required this.onPressed,
  });

  final String title;
  final String state;
  final String tooltip;
  final Widget icon;
  final bool active;
  final bool enabled;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final activeIconColor = colors.onSecondaryContainer;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        toggled: active,
        label: '$title, $state',
        onTap: enabled ? onPressed : null,
        child: ExcludeSemantics(
          child: OutlinedButton(
            onPressed: enabled ? onPressed : null,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.centerLeft,
              backgroundColor:
                  active ? colors.secondaryContainer : colors.surface,
              foregroundColor:
                  active ? colors.onSecondaryContainer : colors.onSurface,
              side: BorderSide(color: colors.outlineVariant),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Row(
              children: [
                IconTheme(
                  data: IconThemeData(
                    size: 20,
                    color: active ? activeIconColor : null,
                  ),
                  child: icon,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, maxLines: 1),
                      Text(
                        state,
                        maxLines: 1,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: active
                                  ? colors.onSecondaryContainer.withValues(
                                      alpha: 0.72,
                                    )
                                  : colors.onSurface.withValues(alpha: 0.68),
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
    );
  }
}
