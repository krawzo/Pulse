import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/pulse_theme.dart';

class PulsePanelResizeHandle extends StatefulWidget {
  const PulsePanelResizeHandle({
    super.key,
    required this.panelWidth,
    required this.onResize,
    this.increaseTowardsRight = false,
    this.semanticLabel = 'Redimensionar painel Tocando agora',
    this.tooltip = 'Redimensionar Tocando agora',
  });

  final double panelWidth;
  final ValueChanged<double> onResize;
  final bool increaseTowardsRight;
  final String semanticLabel;
  final String tooltip;

  @override
  State<PulsePanelResizeHandle> createState() => _PulsePanelResizeHandleState();
}

class _PulsePanelResizeHandleState extends State<PulsePanelResizeHandle> {
  final _focusNode = FocusNode();
  bool _hovered = false;
  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final highlighted = _hovered || _focused;
    return Semantics(
      label: widget.semanticLabel,
      value: '${widget.panelWidth.round()} pixels',
      increasedValue: 'Mais largo',
      decreasedValue: 'Mais estreito',
      onIncrease: () => widget.onResize(16),
      onDecrease: () => widget.onResize(-16),
      child: Focus(
        focusNode: _focusNode,
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            widget.onResize(widget.increaseTowardsRight ? -16 : 16);
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            widget.onResize(widget.increaseTowardsRight ? 16 : -16);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => _focusNode.requestFocus(),
            onHorizontalDragStart: (_) => _focusNode.requestFocus(),
            onHorizontalDragUpdate: (details) => widget.onResize(
                details.delta.dx * (widget.increaseTowardsRight ? 1 : -1)),
            child: SizedBox.expand(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      width: highlighted ? 3 : 2,
                      height: highlighted ? 72 : 48,
                      decoration: BoxDecoration(
                        color: highlighted
                            ? PulsePaletteTheme.of(context).emphasisInk
                            : colors.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 8,
                    left: 0,
                    right: 0,
                    height: 24,
                    child: Tooltip(
                      message: widget.tooltip,
                      preferBelow: false,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
