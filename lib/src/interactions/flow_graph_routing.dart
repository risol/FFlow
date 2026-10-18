import 'package:flutter/painting.dart';

import '../geometry/flow_geometry.dart';
import '../models/flow_edge.dart';
import '../models/flow_node.dart';
import 'flow_extension_adapters.dart';

/// Helpers for applying an edge router to a complete graph.
abstract final class FlowGraphRouting {
  /// Routes each visible edge and returns a new immutable edge list.
  static Future<List<FlowEdge>> routeEdges<T>({
    required Iterable<FlowNode<T>> nodes,
    required Iterable<FlowEdge> edges,
    required FlowEdgeRouter router,
    Map<String, Object?> options = const {},
  }) async {
    final nodeList = nodes.toList(growable: false);
    final edgeList = edges.toList(growable: false);
    final nodesById = {for (final node in nodeList) node.id: node};
    final obstacles = <(String, Rect)>[
      for (final node in nodeList)
        if (FlowGeometry.isVisible(node, nodesById))
          (node.id, FlowGeometry.nodeRect(node, nodesById)),
    ];

    final routed = <FlowEdge>[];
    for (final edge in edgeList) {
      final source = nodesById[edge.sourceId];
      final target = nodesById[edge.targetId];
      if (edge.hidden ||
          source == null ||
          target == null ||
          !FlowGeometry.isVisible(source, nodesById) ||
          !FlowGeometry.isVisible(target, nodesById)) {
        routed.add(edge);
        continue;
      }
      final route = await router.route(
        edge: edge,
        sourceBounds: FlowGeometry.nodeRect(source, nodesById),
        targetBounds: FlowGeometry.nodeRect(target, nodesById),
        sourceAnchor: FlowGeometry.edgeSource(edge, nodesById),
        targetAnchor: FlowGeometry.edgeTarget(edge, nodesById),
        obstacles: [
          for (final (nodeId, rect) in obstacles)
            if (nodeId != source.id &&
                nodeId != target.id &&
                !_isAncestor(nodeId, source, nodesById) &&
                !_isAncestor(nodeId, target, nodesById))
              rect,
        ],
        options: options,
      );
      routed.add(route.applyTo(edge));
    }
    return List.unmodifiable(routed);
  }

  static bool _isAncestor<T>(
    String ancestorId,
    FlowNode<T> node,
    Map<String, FlowNode<T>> nodesById,
  ) {
    var parentId = node.parentId;
    final visited = <String>{node.id};
    while (parentId != null && visited.add(parentId)) {
      if (parentId == ancestorId) return true;
      parentId = nodesById[parentId]?.parentId;
    }
    return false;
  }
}
