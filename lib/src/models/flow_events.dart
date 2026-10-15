import 'package:flutter/widgets.dart';
import 'package:flutter/gestures.dart';

import 'flow_connection.dart';
import 'flow_edge.dart';
import 'flow_handle.dart';
import 'flow_node.dart';

/// Whether a selection rectangle must contain a complete node or only overlap
/// it to include it in the selection.
enum FlowSelectionMode { full, partial }

enum FlowConnectionMode { strict, loose }

enum FlowToolbarPlacement { top, right, bottom, left }

/// Pointer coordinates reported by canvas, node, and edge callbacks.
class FlowPointerPosition {
  const FlowPointerPosition({
    required this.viewportPosition,
    required this.flowPosition,
    required this.deviceKind,
  });

  /// Position relative to the FFlow canvas viewport.
  final Offset viewportPosition;

  /// Position in graph coordinates after applying the viewport transform.
  final Offset flowPosition;

  final PointerDeviceKind deviceKind;
}

typedef FlowNodePointerCallback<T> = void Function(
  FlowNode<T> node,
  FlowPointerPosition position,
);

typedef FlowEdgePointerCallback = void Function(
  FlowEdge edge,
  FlowPointerPosition position,
);

class FlowConnectionStart {
  const FlowConnectionStart({
    required this.nodeId,
    required this.handleId,
    required this.handleType,
    this.edgeId,
    this.reconnecting = false,
  });

  final String nodeId;
  final String handleId;
  final FlowHandleType handleType;
  final String? edgeId;
  final bool reconnecting;
}

class FlowConnectionEnd {
  const FlowConnectionEnd({
    required this.start,
    required this.point,
    this.connection,
    this.cancelled = false,
  });

  final FlowConnectionStart start;
  final Offset point;
  final FlowConnection? connection;
  final bool cancelled;
}

typedef FlowConnectionLineBuilder = Widget Function(
  BuildContext context,
  Offset source,
  Offset target,
);
