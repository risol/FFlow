import 'package:flutter/widgets.dart';

/// The graph element or control selected by the canvas hit-test.
enum FlowHitTargetKind {
  pane,
  node,
  connectionHandle,
  resizeHandle,
  reconnectHandle,
  edge,
}

/// Immutable result shared by pointer-down, hover, context-menu, and gestures.
class FlowHitTestResult {
  const FlowHitTestResult({
    required this.kind,
    this.nodeId,
    this.edgeId,
    this.handleId,
    this.sourceSide,
    this.resizeDirection,
  });

  const FlowHitTestResult.pane() : this(kind: FlowHitTargetKind.pane);

  final FlowHitTargetKind kind;
  final String? nodeId;
  final String? edgeId;
  final String? handleId;
  final bool? sourceSide;

  /// Ordinal of the canvas resize direction, kept independent of its widget
  /// implementation so this result can be safely retained by pointer capture.
  final int? resizeDirection;

  bool get hasNode => nodeId != null;
}

/// A rectangular broad-phase region with an optional precise geometry check.
class FlowHitTestRegion {
  const FlowHitTestRegion({
    required this.result,
    required this.bounds,
    required this.priority,
    this.paintOrder = 0,
    this.containsPoint,
  });

  final FlowHitTestResult result;
  final Rect bounds;

  /// Higher values are tested first. The canvas uses this for hit layers that
  /// paint above one another (for example reconnect handles above nodes).
  final int priority;
  final int paintOrder;
  final bool Function(Offset point)? containsPoint;

  bool contains(Offset point) =>
      bounds.contains(point) && (containsPoint?.call(point) ?? true);
}

/// Resolves overlapping graph regions in a stable, explicit paint order.
class FlowHitTestEngine {
  const FlowHitTestEngine();

  FlowHitTestResult hitTest(
    Offset point, {
    required Iterable<FlowHitTestRegion> regions,
  }) {
    final ordered = regions.toList()
      ..sort((a, b) {
        final priority = b.priority.compareTo(a.priority);
        return priority != 0 ? priority : b.paintOrder.compareTo(a.paintOrder);
      });
    for (final region in ordered) {
      if (region.contains(point)) return region.result;
    }
    return const FlowHitTestResult.pane();
  }
}
