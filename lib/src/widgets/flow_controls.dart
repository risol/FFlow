import 'package:flutter/material.dart';

import '../controllers/flow_canvas_controller.dart';
import '../models/flow_node.dart';

/// Built-in viewport controls similar to React Flow's Controls component.
class FFlowControls<T> extends StatelessWidget {
  const FFlowControls({
    super.key,
    required this.controller,
    required this.nodes,
    required this.viewportSize,
    this.padding = 72,
    this.backgroundColor = const Color(0xF0191D27),
    this.foregroundColor = const Color(0xFFADB4C3),
    this.locked,
    this.onLockChanged,
    this.additionalControls = const [],
  });

  final FlowCanvasController controller;
  final List<FlowNode<T>> nodes;
  final Size viewportSize;
  final double padding;
  final Color backgroundColor;
  final Color foregroundColor;
  final bool? locked;

  /// Called with the new lock value. The host should pass the corresponding
  /// `panEnabled` and `zoomEnabled` values back to FFlowCanvas.
  final ValueChanged<bool>? onLockChanged;

  /// App-provided buttons appended to the built-in viewport controls.
  final List<Widget> additionalControls;

  @override
  Widget build(BuildContext context) {
    final center = Offset(viewportSize.width / 2, viewportSize.height / 2);
    return Material(
      color: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Color(0xFF333A49)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _ControlButton(
          icon: Icons.add_rounded,
          tooltip: 'Zoom in',
          color: foregroundColor,
          onPressed: () => controller.zoomBy(1.2, focalPoint: center),
        ),
        _ControlButton(
          icon: Icons.remove_rounded,
          tooltip: 'Zoom out',
          color: foregroundColor,
          onPressed: () => controller.zoomBy(1 / 1.2, focalPoint: center),
        ),
        const Divider(height: 1, color: Color(0xFF333A49)),
        _ControlButton(
          icon: Icons.center_focus_strong_rounded,
          tooltip: 'Fit graph to view',
          color: foregroundColor,
          onPressed: () => controller.fitView(
            nodes,
            viewportSize,
            padding: padding,
          ),
        ),
        if (onLockChanged != null) ...[
          const Divider(height: 1, color: Color(0xFF333A49)),
          _ControlButton(
            icon: locked == true ? Icons.lock_rounded : Icons.lock_open_rounded,
            tooltip: locked == true ? 'Unlock canvas' : 'Lock canvas',
            color: foregroundColor,
            onPressed: () => onLockChanged!(locked != true),
          ),
        ],
        if (additionalControls.isNotEmpty) ...[
          const Divider(height: 1, color: Color(0xFF333A49)),
          ...additionalControls,
        ],
      ]),
    );
  }
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, size: 17),
          color: color,
          constraints: const BoxConstraints.tightFor(width: 38, height: 36),
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
        ),
      );
}
