import 'dart:async';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

/// Window controls drawn inside the Pulse header when Windows hides its caption.
class PulseWindowControls extends StatefulWidget {
  const PulseWindowControls({super.key, this.compact = false});

  final bool compact;

  @override
  State<PulseWindowControls> createState() => _PulseWindowControlsState();
}

class _PulseWindowControlsState extends State<PulseWindowControls>
    with WindowListener {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(_refreshMaximized());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _refreshMaximized() async {
    final maximized = await windowManager.isMaximized();
    if (mounted) setState(() => _maximized = maximized);
  }

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);

  @override
  void onWindowRestore() => unawaited(_refreshMaximized());

  @override
  Widget build(BuildContext context) {
    final width = widget.compact ? 40.0 : 46.0;
    final foreground = Theme.of(context).colorScheme.onSurface;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _WindowButton(
          width: width,
          tooltip: 'Minimizar',
          icon: Icons.remove_rounded,
          foreground: foreground,
          onTap: () => windowManager.minimize(),
        ),
        _WindowButton(
          width: width,
          tooltip: _maximized ? 'Restaurar' : 'Maximizar',
          icon: _maximized
              ? Icons.filter_none_rounded
              : Icons.crop_square_rounded,
          foreground: foreground,
          onTap: _toggleMaximize,
        ),
        _WindowButton(
          width: width,
          tooltip: 'Fechar Pulse',
          icon: Icons.close_rounded,
          foreground: foreground,
          close: true,
          onTap: () => windowManager.close(),
        ),
      ],
    );
  }
}

class _WindowButton extends StatelessWidget {
  const _WindowButton({
    required this.width,
    required this.tooltip,
    required this.icon,
    required this.foreground,
    required this.onTap,
    this.close = false,
  });

  final double width;
  final String tooltip;
  final IconData icon;
  final Color foreground;
  final VoidCallback onTap;
  final bool close;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: SizedBox(
          width: width,
          height: 52,
          child: InkWell(
            onTap: onTap,
            hoverColor: close
                ? const Color(0xFFC42B31)
                : foreground.withValues(alpha: .12),
            child: Center(
              child: Icon(icon, size: 18, color: foreground),
            ),
          ),
        ),
      );
}
