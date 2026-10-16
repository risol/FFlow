import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../geometry/flow_geometry.dart';
import '../interactions/flow_graph_interaction.dart';
import '../models/flow_connection.dart';
import '../models/flow_edge.dart';
import '../models/flow_handle.dart';
import '../models/flow_node.dart';
import '../models/flow_selection.dart';
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
  const FlowDeleteResult({
    required this.nodes,
    required this.edges,
    this.deletedNodes = const [],
    this.deletedEdges = const [],
  });

  /// Graph state after deletion.
  final List<FlowNode<T>> nodes;
  final List<FlowEdge> edges;

  /// The actual deleted entities, including edges removed by node cascade.
  final List<FlowNode<T>> deletedNodes;
  final List<FlowEdge> deletedEdges;
}

/// Immutable node and edge list operations for controlled graph state.
abstract final class FlowGraphUtils {
  /// Returns ids eligible for select-all. Hidden nodes and edges attached to
  /// hidden nodes are excluded unless [includeHidden] is explicitly enabled.
  static FlowSelection selectAll<T>({
    required Iterable<FlowNode<T>> nodes,
    required Iterable<FlowEdge> edges,
    bool includeHidden = false,
  }) {
    final nodeList = nodes.toList(growable: false);
    final edgeList = edges.toList(growable: false);
    final nodesById = {for (final node in nodeList) node.id: node};
    return FlowSelection(
      nodes: nodeList
          .where((node) =>
              node.selectable &&
              (includeHidden || FlowGeometry.isVisible(node, nodesById)))
          .map((n) => n.id),
      edges: edgeList.where((edge) {
        if (!edge.selectable) return false;
        if (includeHidden) return true;
        final source = nodesById[edge.sourceId];
        final target = nodesById[edge.targetId];
        return !edge.hidden &&
            source != null &&
            target != null &&
            FlowGeometry.isVisible(source, nodesById) &&
            FlowGeometry.isVisible(target, nodesById);
      }).map((edge) => edge.id),
    );
  }

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
            (edge.targetHandleId ?? 'target') &&
        existing.targetHandleType == edge.targetHandleType);
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
    final deletedNodes = List<FlowNode<T>>.unmodifiable(
      nodes.where((node) => deletableNodeIds.contains(node.id)),
    );
    final deletedEdgeIds = <String>{
      ...deletableEdgeIds,
      for (final edge in edges)
        if (deletableNodeIds.contains(edge.sourceId) ||
            deletableNodeIds.contains(edge.targetId))
          edge.id,
    };
    final deletedEdges = List<FlowEdge>.unmodifiable(
      edges.where((edge) => deletedEdgeIds.contains(edge.id)),
    );
    return FlowDeleteResult<T>(
      nodes: List.unmodifiable([
        for (final node in nodes)
          if (!deletableNodeIds.contains(node.id))
            if (node.parentId != null &&
                deletableNodeIds.contains(node.parentId))
              node.copyWith(
                position: FlowGeometry.absolutePosition(node, nodesById) +
                    Offset(node.width * node.origin.dx,
                        node.height * node.origin.dy),
                clearParentId: true,
              )
            else
              node,
      ]),
      edges: List.unmodifiable(
          edges.where((edge) => !deletedEdgeIds.contains(edge.id))),
      deletedNodes: deletedNodes,
      deletedEdges: deletedEdges,
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

  static FlowNode<T>? getNode<T>(String id, Iterable<FlowNode<T>> nodes) =>
      nodes.where((node) => node.id == id).firstOrNull;

  /// Returns the nodes fully contained by, or overlapping, [bounds].
  static List<FlowNode<T>> getNodesInside<T>(
    Rect bounds,
    Iterable<FlowNode<T>> nodes, {
    bool partial = true,
    bool includeHidden = false,
  }) {
    final nodeList = nodes.toList(growable: false);
    final nodesById = {for (final node in nodeList) node.id: node};
    return List.unmodifiable(nodeList.where((node) {
      if (!includeHidden && !FlowGeometry.isVisible(node, nodesById)) {
        return false;
      }
      final rect = FlowGeometry.nodeRect(node, nodesById);
      if (partial) return rect.overlaps(bounds);
      return bounds.left <= rect.left &&
          bounds.top <= rect.top &&
          bounds.right >= rect.right &&
          bounds.bottom >= rect.bottom;
    }));
  }

  /// Finds visible nodes that overlap the node identified by [nodeId].
  static List<FlowNode<T>> getIntersectingNodes<T>(
    String nodeId,
    Iterable<FlowNode<T>> nodes, {
    bool partial = true,
    bool includeHidden = false,
  }) {
    final nodeList = nodes.toList(growable: false);
    final nodesById = {for (final node in nodeList) node.id: node};
    final source = nodesById[nodeId];
    if (source == null ||
        (!includeHidden && !FlowGeometry.isVisible(source, nodesById))) {
      return const [];
    }
    final sourceRect = FlowGeometry.nodeRect(source, nodesById);
    return List.unmodifiable(nodeList.where((node) {
      if (node.id == nodeId ||
          (!includeHidden && !FlowGeometry.isVisible(node, nodesById))) {
        return false;
      }
      final rect = FlowGeometry.nodeRect(node, nodesById);
      return partial
          ? sourceRect.overlaps(rect)
          : sourceRect.left <= rect.left &&
              sourceRect.top <= rect.top &&
              sourceRect.right >= rect.right &&
              sourceRect.bottom >= rect.bottom;
    }));
  }

  /// Returns whether a node overlaps or is fully contained by [area].
  static bool isNodeIntersecting<T>(
    String nodeId,
    Rect area,
    Iterable<FlowNode<T>> nodes, {
    bool partial = true,
    bool includeHidden = false,
  }) {
    final nodeList = nodes.toList(growable: false);
    final nodesById = {for (final node in nodeList) node.id: node};
    final node = nodesById[nodeId];
    if (node == null ||
        (!includeHidden && !FlowGeometry.isVisible(node, nodesById))) {
      return false;
    }
    final rect = FlowGeometry.nodeRect(node, nodesById);
    if (partial) return rect.overlaps(area);
    return area.left <= rect.left &&
        area.top <= rect.top &&
        area.right >= rect.right &&
        area.bottom >= rect.bottom;
  }

  static List<FlowEdge> getHandleConnections(
    String nodeId,
    List<FlowEdge> edges, {
    String? handleId,
    FlowHandleType? type,
  }) =>
      List.unmodifiable(edges.where((edge) {
        final isSource = edge.sourceId == nodeId &&
            (type == null || type == FlowHandleType.source) &&
            (handleId == null || edge.sourceHandleId == handleId);
        final isTarget = edge.targetId == nodeId &&
            (type == null || type == edge.targetHandleType) &&
            (handleId == null || edge.targetHandleId == handleId);
        return isSource || isTarget;
      }));

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
