import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../geometry/flow_geometry.dart';
import '../interactions/flow_graph_interaction.dart';
import '../models/flow_connection.dart';
import '../models/flow_edge.dart';
import '../models/flow_node.dart';
import '../models/flow_viewport.dart';

enum FlowNodeChangeType { add, remove, replace, position, dimensions, select }

/// A node state change consumed by [FlowGraphUtils.applyNodeChanges].
class FlowNodeChange<T> {
  const FlowNodeChange({
    required this.type,
    required this.id,
    this.node,
    this.position,
    this.size,
    this.selected,
    this.index,
  });

  final FlowNodeChangeType type;
  final String id;
  final FlowNode<T>? node;
  final Offset? position;
  final Size? size;
  final bool? selected;
  final int? index;
}

enum FlowEdgeChangeType { add, remove, replace, select }

/// An edge state change consumed by [FlowGraphUtils.applyEdgeChanges].
class FlowEdgeChange {
  const FlowEdgeChange({
    required this.type,
    required this.id,
    this.edge,
    this.selected,
    this.index,
  });

  final FlowEdgeChangeType type;
  final String id;
  final FlowEdge? edge;
  final bool? selected;
  final int? index;
}

/// Return value for deleting nodes and edges by id.
class FlowDeleteResult<T> {
  const FlowDeleteResult({required this.nodes, required this.edges});
  final List<FlowNode<T>> nodes;
  final List<FlowEdge> edges;
}

/// Immutable node and edge list operations for controlled graph state.
abstract final class FlowGraphUtils {
  static List<FlowEdge> addEdge(
    List<FlowEdge> edges,
    FlowEdge edge, {
    int? index,
  }) {
    final duplicate = edges.any((existing) =>
        existing.sourceId == edge.sourceId &&
        (existing.sourceHandleId ?? 'source') ==
            (edge.sourceHandleId ?? 'source') &&
        existing.targetId == edge.targetId &&
        (existing.targetHandleId ?? 'target') ==
            (edge.targetHandleId ?? 'target'));
    if (duplicate || edges.any((existing) => existing.id == edge.id)) {
      return edges;
    }
    final next = List<FlowEdge>.of(edges);
    next.insert(index?.clamp(0, next.length).toInt() ?? next.length, edge);
    return List.unmodifiable(next);
  }

  static List<FlowNode<T>> applyNodeChanges<T>(
    Iterable<FlowNodeChange<T>> changes,
    List<FlowNode<T>> nodes,
  ) {
    var next = List<FlowNode<T>>.of(nodes);
    for (final change in changes) {
      final currentIndex = next.indexWhere((node) => node.id == change.id);
      switch (change.type) {
        case FlowNodeChangeType.add:
          final node = change.node;
          if (node == null || currentIndex >= 0) continue;
          final index =
              change.index?.clamp(0, next.length).toInt() ?? next.length;
          next.insert(index, node);
        case FlowNodeChangeType.remove:
          if (currentIndex >= 0) next.removeAt(currentIndex);
        case FlowNodeChangeType.replace:
          final replacement = change.node;
          if (currentIndex >= 0 && replacement != null) {
            next[currentIndex] = replacement;
          }
        case FlowNodeChangeType.position:
          final position = change.position;
          if (currentIndex >= 0 && position != null) {
            next[currentIndex] =
                next[currentIndex].copyWith(position: position);
          }
        case FlowNodeChangeType.dimensions:
          final size = change.size;
          if (currentIndex >= 0 && size != null) {
            next[currentIndex] = next[currentIndex].copyWith(
              width: size.width,
              height: size.height,
            );
          }
        case FlowNodeChangeType.select:
          if (currentIndex >= 0 && change.selected != null) {
            next[currentIndex] = next[currentIndex].copyWith(
              selected: change.selected,
            );
          }
      }
    }
    return List.unmodifiable(next);
  }

  static List<FlowEdge> applyEdgeChanges(
    Iterable<FlowEdgeChange> changes,
    List<FlowEdge> edges,
  ) {
    var next = List<FlowEdge>.of(edges);
    for (final change in changes) {
      final currentIndex = next.indexWhere((edge) => edge.id == change.id);
      switch (change.type) {
        case FlowEdgeChangeType.add:
          final edge = change.edge;
          if (edge == null || currentIndex >= 0) continue;
          final index =
              change.index?.clamp(0, next.length).toInt() ?? next.length;
          next.insert(index, edge);
        case FlowEdgeChangeType.remove:
          if (currentIndex >= 0) next.removeAt(currentIndex);
        case FlowEdgeChangeType.replace:
          final replacement = change.edge;
          if (currentIndex >= 0 && replacement != null) {
            next[currentIndex] = replacement;
          }
        case FlowEdgeChangeType.select:
          if (currentIndex >= 0 && change.selected != null) {
            next[currentIndex] = next[currentIndex].copyWith(
              selected: change.selected,
            );
          }
      }
    }
    return List.unmodifiable(next);
  }

  static FlowDeleteResult<T> deleteElements<T>({
    required List<FlowNode<T>> nodes,
    required List<FlowEdge> edges,
    Iterable<String> nodeIds = const [],
    Iterable<String> edgeIds = const [],
  }) {
    final requestedNodeIds = nodeIds.toSet();
    final requestedEdgeIds = edgeIds.toSet();
    final deletableNodeIds = nodes
        .where((node) => requestedNodeIds.contains(node.id) && node.deletable)
        .map((node) => node.id)
        .toSet();
    final deletableEdgeIds = edges
        .where((edge) => requestedEdgeIds.contains(edge.id) && edge.deletable)
        .map((edge) => edge.id)
        .toSet();
    final nodesById = {for (final node in nodes) node.id: node};
    return FlowDeleteResult<T>(
      nodes: List.unmodifiable([
        for (final node in nodes)
          if (!deletableNodeIds.contains(node.id))
            if (node.parentId != null &&
                deletableNodeIds.contains(node.parentId))
              node.copyWith(
                position: FlowGeometry.absolutePosition(node, nodesById),
                clearParentId: true,
              )
            else
              node,
      ]),
      edges: List.unmodifiable(edges.where((edge) =>
          !deletableEdgeIds.contains(edge.id) &&
          !deletableNodeIds.contains(edge.sourceId) &&
          !deletableNodeIds.contains(edge.targetId))),
    );
  }

  static List<FlowEdge> getConnectedEdges<T>(
    Iterable<FlowNode<T>> nodes,
    List<FlowEdge> edges,
  ) {
    final ids = nodes.map((node) => node.id).toSet();
    return List.unmodifiable(edges.where(
      (edge) => ids.contains(edge.sourceId) || ids.contains(edge.targetId),
    ));
  }

  static List<FlowNode<T>> getIncomers<T>(
    FlowNode<T> node,
    List<FlowNode<T>> nodes,
    List<FlowEdge> edges,
  ) {
    final ids = edges
        .where((edge) => edge.targetId == node.id)
        .map((edge) => edge.sourceId)
        .toSet();
    return List.unmodifiable(
        nodes.where((candidate) => ids.contains(candidate.id)));
  }

  static List<FlowNode<T>> getOutgoers<T>(
    FlowNode<T> node,
    List<FlowNode<T>> nodes,
    List<FlowEdge> edges,
  ) {
    final ids = edges
        .where((edge) => edge.sourceId == node.id)
        .map((edge) => edge.targetId)
        .toSet();
    return List.unmodifiable(
        nodes.where((candidate) => ids.contains(candidate.id)));
  }

  static Rect getNodesBounds<T>(Iterable<FlowNode<T>> nodes) =>
      FlowGeometry.nodesBounds(nodes);

  static FlowViewport getViewportForBounds(
    Rect bounds,
    Size viewportSize, {
    double padding = 80,
    double minZoom = 0.25,
    double maxZoom = 2,
  }) {
    if (bounds.isEmpty || viewportSize.isEmpty) {
      return const FlowViewport(x: 0, y: 0, zoom: 1);
    }
    final availableWidth =
        (viewportSize.width - padding * 2).clamp(1, double.infinity);
    final availableHeight =
        (viewportSize.height - padding * 2).clamp(1, double.infinity);
    final zoom = math
        .min(availableWidth / bounds.width, availableHeight / bounds.height)
        .clamp(minZoom, maxZoom)
        .toDouble();
    final center = Offset(viewportSize.width / 2, viewportSize.height / 2);
    final translation = center - bounds.center * zoom;
    return FlowViewport(x: translation.dx, y: translation.dy, zoom: zoom);
  }

  static List<FlowNode<T>> moveNode<T>({
    required List<FlowNode<T>> nodes,
    required String nodeId,
    required Offset delta,
  }) =>
      FlowGraphInteraction.moveNode(nodes: nodes, nodeId: nodeId, delta: delta);

  static List<FlowEdge> reconnectEdge({
    required List<FlowEdge> edges,
    required String edgeId,
    required FlowConnection connection,
  }) =>
      FlowGraphInteraction.reconnectEdge(
        edges: edges,
        edgeId: edgeId,
        connection: connection,
      );
}
