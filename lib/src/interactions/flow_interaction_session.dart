import 'package:flutter/widgets.dart';

import 'flow_hit_test.dart';

/// The single graph interaction currently owned by the canvas.
enum FlowInteractionKind {
  pressed,
  nodeDragging,
  nodeResizing,
  connecting,
  reconnecting,
  selectionDragging,
  canvasPanning,
}

class FlowInteractionSession {
  FlowInteractionSession({
    required this.pointerId,
    required this.kind,
    required this.target,
    required this.downFlowPosition,
    Iterable<String> movingNodeIds = const {},
  }) : movingNodeIds = Set.unmodifiable(movingNodeIds);

  final int pointerId;
  final FlowInteractionKind kind;
  final FlowHitTestResult target;
  final Offset downFlowPosition;
  final Set<String> movingNodeIds;

  FlowInteractionSession withKind(
    FlowInteractionKind next, {
    Iterable<String>? movingNodeIds,
  }) =>
      FlowInteractionSession(
        pointerId: pointerId,
        kind: next,
        target: target,
        downFlowPosition: downFlowPosition,
        movingNodeIds: movingNodeIds ?? this.movingNodeIds,
      );
}
