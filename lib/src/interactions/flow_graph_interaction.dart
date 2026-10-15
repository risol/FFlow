import 'package:flutter/widgets.dart';

import '../geometry/flow_geometry.dart';
import '../models/flow_connection.dart';
import '../models/flow_edge.dart';
import '../models/flow_events.dart';
import '../models/flow_handle.dart';
import '../models/flow_node.dart';

/// Stateless graph operations used by the canvas interaction layer.
abstract final class FlowGraphInteraction {
  static List<FlowNode<T>> moveNode<T>({
    required List<FlowNode<T>> nodes,
    required String nodeId,
    required Offset delta,
  }) =>
      List.unmodifiable([
        for (final node in nodes)
          if (node.id == nodeId)
            node.copyWith(position: node.position + delta)
          else
            node,
      ]);

  static FlowConnection? connectionAt<T>({
    required List<FlowNode<T>> nodes,
    required List<FlowEdge> edges,
    required String sourceId,
    required String sourceHandleId,
    required Offset point,
    bool Function(FlowConnection connection)? isValidConnection,
    double snapRadius = 38,
    String? excludedEdgeId,
    FlowConnectionMode connectionMode = FlowConnectionMode.strict,
  }) {
    final nodesById = {for (final node in nodes) node.id: node};
    FlowNode<T>? source;
    for (final node in nodes) {
      if (node.id == sourceId) {
        source = node;
        break;
      }
    }
    if (source == null ||
        !FlowGeometry.isVisible(source, nodesById) ||
        !source.connectable) {
      return null;
    }
    final sourceHandle = FlowGeometry.handleFor(
      source,
      sourceHandleId,
      FlowHandleType.source,
    );
    if (sourceHandle == null ||
        !sourceHandle.connectable ||
        !sourceHandle.connectableStart ||
        _connectionCount(
                nodes, edges, sourceId, sourceHandleId, FlowHandleType.source,
                excludedEdgeId: excludedEdgeId) >=
            (sourceHandle.maxConnections ?? 1 << 30)) {
      return null;
    }

    FlowConnection? closest;
    var closestDistance = snapRadius;
    for (final node in nodes) {
      if (!FlowGeometry.isVisible(node, nodesById) || !node.connectable) {
        continue;
      }
      for (final handle in node.resolvedHandles) {
        if ((handle.type != FlowHandleType.target &&
                !(connectionMode == FlowConnectionMode.loose &&
                    handle.type == FlowHandleType.source)) ||
            !handle.connectable ||
            !handle.connectableEnd ||
            _connectionCount(nodes, edges, node.id, handle.id, handle.type,
                    excludedEdgeId: excludedEdgeId) >=
                (handle.maxConnections ?? 1 << 30)) {
          continue;
        }
        if (node.id == sourceId &&
            handle.id == sourceHandleId &&
            handle.type == FlowHandleType.source) {
          continue;
        }
        final candidateDistance =
            (FlowGeometry.handleAnchor(node, handle, nodes: nodesById) - point)
                .distance;
        if (candidateDistance >= closestDistance) continue;
        final candidate = FlowConnection(
          sourceId: sourceId,
          sourceHandleId: sourceHandleId,
          targetId: node.id,
          targetHandleId: handle.id,
          targetHandleType: handle.type,
        );
        if (isValidConnection != null && !isValidConnection(candidate)) {
          continue;
        }
        closest = candidate;
        closestDistance = candidateDistance;
      }
    }
    if (closest == null ||
        _containsConnection(nodes, edges, closest,
            excludedEdgeId: excludedEdgeId)) {
      return null;
    }
    return closest;
  }

  /// Finds a compatible source handle near [point] for reconnecting an edge's
  /// source endpoint while keeping its target endpoint fixed. The fixed target
  /// may itself be a source handle when [connectionMode] is loose.
  static FlowConnection? sourceConnectionAt<T>({
    required List<FlowNode<T>> nodes,
    required List<FlowEdge> edges,
    required String targetId,
    required String targetHandleId,
    required Offset point,
    bool Function(FlowConnection connection)? isValidConnection,
    double snapRadius = 38,
    String? excludedEdgeId,
    FlowHandleType targetHandleType = FlowHandleType.target,
    FlowConnectionMode connectionMode = FlowConnectionMode.strict,
  }) {
    final nodesById = {for (final node in nodes) node.id: node};
    final targetNode = nodes.where((node) => node.id == targetId).firstOrNull;
    final targetHandle = targetNode == null
        ? null
        : FlowGeometry.handleFor(targetNode, targetHandleId, targetHandleType);
    if (targetNode == null ||
        !FlowGeometry.isVisible(targetNode, nodesById) ||
        !targetNode.connectable ||
        (targetHandleType == FlowHandleType.source &&
            connectionMode != FlowConnectionMode.loose) ||
        targetHandle == null ||
        !targetHandle.connectable ||
        !targetHandle.connectableEnd ||
        _connectionCount(
                nodes, edges, targetId, targetHandleId, targetHandleType,
                excludedEdgeId: excludedEdgeId) >=
            (targetHandle.maxConnections ?? 1 << 30)) {
      return null;
    }
    FlowConnection? closest;
    var closestDistance = snapRadius;
    for (final node in nodes) {
      if (!FlowGeometry.isVisible(node, nodesById) || !node.connectable) {
        continue;
      }
      for (final handle in node.resolvedHandles) {
        if (handle.type != FlowHandleType.source ||
            !handle.connectable ||
            !handle.connectableStart ||
            _connectionCount(
                    nodes, edges, node.id, handle.id, FlowHandleType.source,
                    excludedEdgeId: excludedEdgeId) >=
                (handle.maxConnections ?? 1 << 30)) {
          continue;
        }
        if (node.id == targetId &&
            handle.id == targetHandleId &&
            targetHandleType == FlowHandleType.source) {
          continue;
        }
        final distance =
            (FlowGeometry.handleAnchor(node, handle, nodes: nodesById) - point)
                .distance;
        if (distance >= closestDistance) continue;
        final candidate = FlowConnection(
          sourceId: node.id,
          sourceHandleId: handle.id,
          targetId: targetId,
          targetHandleId: targetHandleId,
          targetHandleType: targetHandleType,
        );
        if (isValidConnection != null && !isValidConnection(candidate)) {
          continue;
        }
        closest = candidate;
        closestDistance = distance;
      }
    }
    if (closest == null ||
        _containsConnection(nodes, edges, closest,
            excludedEdgeId: excludedEdgeId)) {
      return null;
    }
    return closest;
  }

  static FlowEdge createEdge(FlowConnection connection, String edgeId) =>
      FlowEdge(
        id: edgeId,
        sourceId: connection.sourceId,
        sourceHandleId: connection.sourceHandleId,
        targetId: connection.targetId,
        targetHandleId: connection.targetHandleId,
        targetHandleType: connection.targetHandleType,
      );

  static List<FlowEdge> reconnectEdge({
    required List<FlowEdge> edges,
    required String edgeId,
    required FlowConnection connection,
  }) {
    FlowEdge? oldEdge;
    for (final edge in edges) {
      if (edge.id == edgeId) {
        oldEdge = edge;
        break;
      }
    }
    if (oldEdge == null) return edges;
    return List.unmodifiable([
      for (final edge in edges)
        if (edge.id == edgeId)
          edge.copyWith(
            sourceId: connection.sourceId,
            sourceHandleId: connection.sourceHandleId,
            targetId: connection.targetId,
            targetHandleId: connection.targetHandleId,
            targetHandleType: connection.targetHandleType,
          )
        else
          edge,
    ]);
  }

  static int getHandleConnectionCount<T>({
    required List<FlowNode<T>> nodes,
    required List<FlowEdge> edges,
    required String nodeId,
    required String handleId,
    required FlowHandleType type,
    String? excludedEdgeId,
  }) =>
      _connectionCount(
        nodes,
        edges,
        nodeId,
        handleId,
        type,
        excludedEdgeId: excludedEdgeId,
      );

  static int _connectionCount<T>(
    List<FlowNode<T>> nodes,
    List<FlowEdge> edges,
    String nodeId,
    String handleId,
    FlowHandleType type, {
    String? excludedEdgeId,
  }) {
    final node = nodes.where((item) => item.id == nodeId).firstOrNull;
    if (node == null) return 0;
    var count = 0;
    for (final edge in edges) {
      if (edge.id == excludedEdgeId) continue;
      if (type == FlowHandleType.source && edge.sourceId == nodeId) {
        final endpoint = FlowGeometry.handleFor(
          node,
          edge.sourceHandleId,
          FlowHandleType.source,
        );
        if (endpoint?.id == handleId) count++;
      }
      if (edge.targetId == nodeId && edge.targetHandleType == type) {
        final endpoint = FlowGeometry.handleFor(
          node,
          edge.targetHandleId,
          edge.targetHandleType,
        );
        if (endpoint?.id == handleId) count++;
      }
    }
    return count;
  }

  static bool _containsConnection<T>(
    List<FlowNode<T>> nodes,
    List<FlowEdge> edges,
    FlowConnection connection, {
    String? excludedEdgeId,
  }) {
    final nodeMap = {for (final node in nodes) node.id: node};
    final source = nodeMap[connection.sourceId];
    final target = nodeMap[connection.targetId];
    final expectedSourceHandle = source == null
        ? null
        : FlowGeometry.handleFor(
            source, connection.sourceHandleId, FlowHandleType.source);
    final expectedTargetHandle = target == null
        ? null
        : FlowGeometry.handleFor(
            target, connection.targetHandleId, connection.targetHandleType);
    return edges.any((edge) {
      if (edge.id == excludedEdgeId ||
          edge.sourceId != connection.sourceId ||
          edge.targetId != connection.targetId ||
          expectedSourceHandle == null ||
          expectedTargetHandle == null) {
        return false;
      }
      final edgeSourceHandle = source == null
          ? null
          : FlowGeometry.handleFor(
              source, edge.sourceHandleId, FlowHandleType.source);
      final edgeTargetHandle = target == null
          ? null
          : FlowGeometry.handleFor(
              target, edge.targetHandleId, edge.targetHandleType);
      return edgeSourceHandle?.id == expectedSourceHandle.id &&
          edgeTargetHandle?.id == expectedTargetHandle.id &&
          edge.targetHandleType == connection.targetHandleType;
    });
  }
}
