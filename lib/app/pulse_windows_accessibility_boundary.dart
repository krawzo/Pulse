import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Temporary Windows engine workaround for flutter/flutter#175041.
///
/// The native accessibility bridge can crash while the semantics tree changes
/// near startup. This boundary keeps pointer, keyboard and visual behavior,
/// but screen readers cannot inspect the app unless explicitly enabled.
class PulseWindowsAccessibilityBoundary extends StatelessWidget {
  const PulseWindowsAccessibilityBoundary({
    super.key,
    required this.enabled,
    required this.child,
  });

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.windows || enabled) {
      return child;
    }
    return ExcludeSemantics(
      key: const ValueKey('pulse-windows-accessibility-workaround'),
      child: child,
    );
  }
}
