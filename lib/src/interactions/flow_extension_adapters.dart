import 'dart:async';

import 'package:flutter/painting.dart';

import '../models/flow_edge.dart';
import '../models/flow_graph_transaction.dart';
import '../models/flow_node.dart';

/// Dependency-free adapter for optional layout engines such as Dagre or ELK.
abstract interface class FlowLayoutEngine<T> {
  FutureOr<FlowLayoutResult> layout({
    required List<FlowNode<T>> nodes,
    required List<FlowEdge> edges,
    Map<String, Object?> options = const {},
  });
}

class FlowLayoutResult {
  FlowLayoutResult(Map<String, Offset> positions)
      : positions = Map.unmodifiable(positions);

  final Map<String, Offset> positions;

  List<FlowNode<T>> applyTo<T>(Iterable<FlowNode<T>> nodes) =>
      List.unmodifiable([
        for (final node in nodes)
          node.copyWith(position: positions[node.id] ?? node.position),
      ]);
}

/// Routing output shared by automatic routers and editable edge points.
class FlowEdgeRoute {
  FlowEdgeRoute(Iterable<Offset> controlPoints)
      : controlPoints = List.unmodifiable(controlPoints);

  final List<Offset> controlPoints;
}

/// Dependency-free contract for optional orthogonal or obstacle-aware routers.
abstract interface class FlowEdgeRouter {
  FutureOr<FlowEdgeRoute> route({
    required FlowEdge edge,
    required Rect sourceBounds,
    required Rect targetBounds,
    required List<Rect> obstacles,
    Map<String, Object?> options = const {},
  });
}

/// Collaboration boundary for applications that exchange graph operations.
///
/// The SDK defines transactions and their operation types but leaves transport,
/// conflict resolution, persistence, and CRDT choice to the adapter package.
abstract interface class FlowCollaborationOperationAdapter<T> {
  Stream<FlowGraphTransaction<T>> get remoteTransactions;

  FutureOr<void> publish(FlowGraphTransaction<T> transaction);
}
