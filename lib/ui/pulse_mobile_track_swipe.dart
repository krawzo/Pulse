import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Reveals the mobile queue action without removing the track from its list.
class PulseMobileTrackSwipe extends StatefulWidget {
  const PulseMobileTrackSwipe({
    super.key,
    required this.child,
    required this.onPlayNext,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback onPlayNext;
  final bool enabled;

  @override
  State<PulseMobileTrackSwipe> createState() => _PulseMobileTrackSwipeState();
}

class _PulseMobileTrackSwipeState extends State<PulseMobileTrackSwipe> {
  static const _triggerDistance = 72.0;
  double _dragOffset = 0;
  bool _dragging = false;

  void _reset() {
    if (!mounted) return;
    setState(() {
      _dragOffset = 0;
      _dragging = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;

    return LayoutBuilder(builder: (context, constraints) {
      final maxOffset = math.min(136.0, constraints.maxWidth * .42);
      return ClipRect(
        child: Stack(children: [
          Positioned.fill(
            child: ColoredBox(
              color: const Color(0xFF1ED760),
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: maxOffset,
                  child: const Center(
                    child: Icon(Icons.playlist_add_rounded,
                        color: Colors.black, size: 30),
                  ),
                ),
              ),
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: (_) => setState(() => _dragging = true),
            onHorizontalDragUpdate: (details) => setState(() {
              _dragOffset =
                  (_dragOffset + details.delta.dx).clamp(0.0, maxOffset);
            }),
            onHorizontalDragEnd: (details) {
              final triggered = _dragOffset >= _triggerDistance ||
                  (_dragOffset >= 24 &&
                      details.primaryVelocity != null &&
                      details.primaryVelocity! > 700);
              _reset();
              if (triggered) widget.onPlayNext();
            },
            onHorizontalDragCancel: _reset,
            child: AnimatedContainer(
              duration:
                  _dragging ? Duration.zero : const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              transform: Matrix4.translationValues(_dragOffset, 0, 0),
              child: ColoredBox(
                color: Theme.of(context).scaffoldBackgroundColor,
                child: widget.child,
              ),
            ),
          ),
        ]),
      );
    });
  }
}
