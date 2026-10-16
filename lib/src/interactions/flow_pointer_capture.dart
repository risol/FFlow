import 'package:flutter/gestures.dart';

import 'flow_hit_test.dart';

/// Captures the target and coordinates chosen at pointer-down until release.
class FlowPointerCapture {
  FlowPointerCapture({
    required this.pointerId,
    required this.target,
    required this.downGlobalPosition,
    required this.downViewportPosition,
    required this.downFlowPosition,
    required this.deviceKind,
    required this.startedAt,
    required Set<String> selectedNodeIds,
  }) : selectedNodeIds = Set.unmodifiable(selectedNodeIds);

  final int pointerId;
  final FlowHitTestResult target;
  final Offset downGlobalPosition;
  final Offset downViewportPosition;
  final Offset downFlowPosition;
  final PointerDeviceKind deviceKind;
  final Duration startedAt;
  final Set<String> selectedNodeIds;
}
