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
  FlowLayoutResult(
    Map<String, Offset> positions, {
    Map<String, Size> sizes = const {},
  })  : positions = Map.unmodifiable(positions),
        sizes = Map.unmodifiable(sizes);

  final Map<String, Offset> positions;
  final Map<String, Size> sizes;

  List<FlowNode<T>> applyTo<T>(Iterable<FlowNode<T>> nodes) =>
      List.unmodifiable([
        for (final node in nodes)
          node.copyWith(
            position: positions[node.id] ?? node.position,
            width: sizes[node.id]?.width ?? node.width,
            height: sizes[node.id]?.height ?? node.height,
          ),
      ]);

  /// Interpolates node positions and sizes from [nodes] toward this result.
  ///
  /// Pass a value in the range 0–1, typically from a Flutter animation. Nodes
  /// without a result entry remain unchanged.
  List<FlowNode<T>> interpolate<T>(
    Iterable<FlowNode<T>> nodes,
    double progress,
  ) {
    final t = progress.clamp(0.0, 1.0).toDouble();
    return List.unmodifiable([
      for (final node in nodes)
        node.copyWith(
          position: positions.containsKey(node.id)
              ? Offset.lerp(node.position, positions[node.id]!, t)
              : node.position,
          width: sizes.containsKey(node.id)
              ? node.width + (sizes[node.id]!.width - node.width) * t
              : node.width,
          height: sizes.containsKey(node.id)
              ? node.height + (sizes[node.id]!.height - node.height) * t
              : node.height,
        ),
    ]);
  }
}

/// Routing output shared by automatic routers and editable edge points.
class FlowEdgeRoute {
  FlowEdgeRoute(Iterable<Offset> controlPoints)
      : controlPoints = List.unmodifiable(controlPoints);

  final List<Offset> controlPoints;

  FlowEdge applyTo(FlowEdge edge) =>
      edge.copyWith(controlPoints: controlPoints);
}

/// Dependency-free contract for optional orthogonal or obstacle-aware routers.
abstract interface class FlowEdgeRouter {
  FutureOr<FlowEdgeRoute> route({
    required FlowEdge edge,
    required Rect sourceBounds,
    required Rect targetBounds,
    required List<Rect> obstacles,
    Offset? sourceAnchor,
    Offset? targetAnchor,
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
