import 'package:flutter/painting.dart';

import '../models/flow_edge.dart';
import '../models/flow_handle.dart';
import '../models/flow_node.dart';
import 'flow_geometry.dart';

/// Revision-aware cache for resolved edge anchors, paths, bounds and labels.
///
/// Its key deliberately excludes paint-only fields such as color, selection,
/// and animation. Parent movement is included through absolute node bounds.
class FlowEdgeGeometryCache {
  final Map<String, _Entry> _entries = {};
  int hits = 0;
  int misses = 0;

  int get length => _entries.length;

  FlowEdgePathResult? result<T>(
    FlowEdge edge,
    Map<String, FlowNode<T>> nodes,
  ) {
    final key = _geometryKey(edge, nodes);
    final cached = _entries[edge.id];
    if (cached != null && cached.key == key) {
      hits++;
      return cached.result;
    }
    misses++;
    final value = FlowGeometry.edgePathResult(edge, nodes);
    _entries[edge.id] = _Entry(key, value);
    return value;
  }

  void retainEdges(Iterable<FlowEdge> edges) {
    final ids = edges.map((edge) => edge.id).toSet();
    _entries.removeWhere((id, _) => !ids.contains(id));
  }

  void invalidateEdges(Iterable<String> edgeIds) {
    for (final id in edgeIds) {
      _entries.remove(id);
    }
  }

  void invalidateNode<T>(String nodeId, Iterable<FlowEdge> edges) {
    invalidateEdges(edges
        .where((edge) => edge.sourceId == nodeId || edge.targetId == nodeId)
        .map((edge) => edge.id));
  }

  void clear() {
    _entries.clear();
    hits = 0;
    misses = 0;
  }

  int _geometryKey<T>(FlowEdge edge, Map<String, FlowNode<T>> nodes) {
    final source = nodes[edge.sourceId];
    final target = nodes[edge.targetId];
    final sourceRect =
        source == null ? null : FlowGeometry.nodeRect(source, nodes);
    final targetRect =
        target == null ? null : FlowGeometry.nodeRect(target, nodes);
    final sourceHandle = source == null
        ? null
        : FlowGeometry.handleFor(
            source, edge.sourceHandleId, FlowHandleType.source);
    final targetHandle = target == null
        ? null
        : FlowGeometry.handleFor(
            target, edge.targetHandleId, edge.targetHandleType);
    return Object.hash(
      sourceRect,
      targetRect,
      sourceHandle?.id,
      sourceHandle?.position,
      sourceHandle?.offset,
      targetHandle?.id,
      targetHandle?.position,
      targetHandle?.offset,
      edge.sourceId,
      edge.targetId,
      edge.sourceHandleId,
      edge.targetHandleId,
      edge.targetHandleType,
      edge.type,
      edge.floating,
      edge.curvature,
      edge.stepPosition,
      edge.cornerRadius,
      Object.hashAll(edge.controlPoints),
    );
  }
}

class _Entry {
  const _Entry(this.key, this.result);
  final int key;
  final FlowEdgePathResult? result;
}

/// Uniform-grid broad phase for node and edge pointer queries.
class FlowHitTestIndex {
  FlowHitTestIndex({this.cellSize = 256}) : assert(cellSize > 0);

  final double cellSize;
  final Map<String, Set<String>> _nodeCells = {};
  final Map<String, Set<String>> _edgeCells = {};
  final Map<String, Rect> _nodeBounds = {};
  final Map<String, Rect> _edgeBounds = {};
  final Set<String> _largeNodeIds = {};
  final Set<String> _largeEdgeIds = {};

  void rebuild<T>({
    required Iterable<FlowNode<T>> nodes,
    required Iterable<FlowEdge> edges,
    required Map<String, FlowNode<T>> nodesById,
    required FlowEdgeGeometryCache geometryCache,
    double nodeHitTestTolerance = 0,
    double edgeHitTestScale = 1,
  }) {
    _nodeCells.clear();
    _edgeCells.clear();
    _nodeBounds.clear();
    _edgeBounds.clear();
    _largeNodeIds.clear();
    _largeEdgeIds.clear();
    for (final node in nodes) {
      final bounds =
          FlowGeometry.nodeRect(node, nodesById).inflate(nodeHitTestTolerance);
      _nodeBounds[node.id] = bounds;
      _insert(_nodeCells, _largeNodeIds, node.id, bounds);
    }
    for (final edge in edges) {
      final result = geometryCache.result(edge, nodesById);
      if (result == null) continue;
      final bounds =
          result.bounds.inflate(edge.interactionWidth * edgeHitTestScale);
      _edgeBounds[edge.id] = bounds;
      _insert(_edgeCells, _largeEdgeIds, edge.id, bounds);
    }
  }

  List<String> nodeCandidates(Offset point) =>
      _query(_nodeCells, _largeNodeIds, _nodeBounds, point);

  List<String> edgeCandidates(Offset point) =>
      _query(_edgeCells, _largeEdgeIds, _edgeBounds, point);

  List<String> edgeCandidatesIn(Rect rect) =>
      _queryRect(_edgeCells, _largeEdgeIds, _edgeBounds, rect);

  void _insert(Map<String, Set<String>> cells, Set<String> large, String id,
      Rect bounds) {
    if (!bounds.isFinite || bounds.isEmpty) return;
    final left = (bounds.left / cellSize).floor();
    final top = (bounds.top / cellSize).floor();
    final right = (bounds.right / cellSize).floor();
    final bottom = (bounds.bottom / cellSize).floor();
    final cellCount = (right - left + 1) * (bottom - top + 1);
    if (cellCount > 256) {
      large.add(id);
      return;
    }
    for (var x = left; x <= right; x++) {
      for (var y = top; y <= bottom; y++) {
        (cells['$x:$y'] ??= <String>{}).add(id);
      }
    }
  }

  List<String> _query(Map<String, Set<String>> cells, Set<String> large,
      Map<String, Rect> boundsById, Offset point) {
    final ids = <String>{
      ...large,
      ...?cells[
          '${(point.dx / cellSize).floor()}:${(point.dy / cellSize).floor()}'],
    };
    ids.removeWhere((id) => !(boundsById[id]?.contains(point) ?? false));
    return List.unmodifiable(ids);
  }

  List<String> _queryRect(Map<String, Set<String>> cells, Set<String> large,
      Map<String, Rect> boundsById, Rect rect) {
    if (!rect.isFinite || rect.isEmpty) return const [];
    final left = (rect.left / cellSize).floor();
    final top = (rect.top / cellSize).floor();
    final right = (rect.right / cellSize).floor();
    final bottom = (rect.bottom / cellSize).floor();
    final ids = <String>{...large};
    for (var x = left; x <= right; x++) {
      for (var y = top; y <= bottom; y++) {
        ids.addAll(cells['$x:$y'] ?? const <String>{});
      }
    }
    ids.removeWhere((id) => !(boundsById[id]?.overlaps(rect) ?? false));
    return List.unmodifiable(ids);
  }
}
