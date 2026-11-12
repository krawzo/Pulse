import 'package:flutter/material.dart';

/// Horizontal gesture on the miniplayer's track area.
/// Left goes to the previous track; right advances to the next track.
class PulseTrackNavigationSwipe extends StatefulWidget {
  const PulseTrackNavigationSwipe({
    super.key,
    required this.child,
    required this.onPrevious,
    required this.onNext,
  });

  final Widget child;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  State<PulseTrackNavigationSwipe> createState() =>
      _PulseTrackNavigationSwipeState();
}

class _PulseTrackNavigationSwipeState extends State<PulseTrackNavigationSwipe> {
  double _distance = 0;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => _distance = 0,
        onHorizontalDragUpdate: (details) => _distance += details.delta.dx,
        onHorizontalDragCancel: () => _distance = 0,
        onHorizontalDragEnd: (details) {
          final distance = _distance;
          _distance = 0;
          final velocity = details.primaryVelocity ?? 0;
          if (distance <= -60 || (distance <= -24 && velocity < -650)) {
            widget.onPrevious?.call();
          } else if (distance >= 60 || (distance >= 24 && velocity > 650)) {
            widget.onNext?.call();
          }
        },
        child: widget.child,
      );
}
