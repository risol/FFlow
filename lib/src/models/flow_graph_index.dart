import 'flow_edge.dart';
import 'flow_handle.dart';
import 'flow_node.dart';

/// Identifies one handle endpoint in a graph index.
class FlowHandleKey {
  const FlowHandleKey(this.nodeId, this.handleId, this.type);

  final String nodeId;
  final String? handleId;
  final FlowHandleType type;

  @override
  bool operator ==(Object other) =>
      other is FlowHandleKey &&
      other.nodeId == nodeId &&
      other.handleId == handleId &&
      other.type == type;

  @override
  int get hashCode => Object.hash(nodeId, handleId, type);
}

/// A read-optimized snapshot of the graph's identity and adjacency data.
///
/// Rebuild this value when graph state changes. Collections exposed by the
/// index are immutable, so it is safe to share with renderers and tools.
class FlowGraphIndex<T> {
  FlowGraphIndex({
    required Iterable<FlowNode<T>> nodes,
    required Iterable<FlowEdge> edges,
    this.graphRevision = 0,
    this.geometryRevision = 0,
  })  : nodesById = Map.unmodifiable({for (final node in nodes) node.id: node}),
        edgesById =
            Map.unmodifiable({for (final edge in edges) edge.id: edge}) {
    final nodeOrder = <String, int>{};
    var order = 0;
    for (final id in nodesById.keys) {
      nodeOrder[id] = order++;
    }
    _nodeOrderById = Map.unmodifiable(nodeOrder);
    final edgeOrder = <String, int>{};
    order = 0;
    for (final id in edgesById.keys) {
      edgeOrder[id] = order++;
    }
    _edgeOrderById = Map.unmodifiable(edgeOrder);
    final children = <String, List<String>>{};
    for (final node in nodesById.values) {
      final parentId = node.parentId;
      if (parentId != null) (children[parentId] ??= []).add(node.id);
    }
    childrenByParentId = _freezeLists(children);

    final incoming = <String, List<String>>{};
    final outgoing = <String, List<String>>{};
    final incident = <String, List<String>>{};
    final handles = <FlowHandleKey, List<String>>{};
    for (final edge in edgesById.values) {
      (outgoing[edge.sourceId] ??= []).add(edge.id);
      (incoming[edge.targetId] ??= []).add(edge.id);
      (incident[edge.sourceId] ??= []).add(edge.id);
      if (edge.targetId != edge.sourceId) {
        (incident[edge.targetId] ??= []).add(edge.id);
      }
      final sourceHandle = nodesById[edge.sourceId]
          ?.resolvedHandles
          .where((handle) =>
              handle.type == FlowHandleType.source &&
              (edge.sourceHandleId == null || handle.id == edge.sourceHandleId))
          .firstOrNull;
      final targetHandle = nodesById[edge.targetId]
          ?.resolvedHandles
          .where((handle) =>
              handle.type == edge.targetHandleType &&
              (edge.targetHandleId == null || handle.id == edge.targetHandleId))
          .firstOrNull;
      (handles[FlowHandleKey(
              edge.sourceId,
              sourceHandle?.id ?? edge.sourceHandleId,
              FlowHandleType.source)] ??= [])
          .add(edge.id);
      (handles[FlowHandleKey(
              edge.targetId,
              targetHandle?.id ?? edge.targetHandleId,
              edge.targetHandleType)] ??= [])
          .add(edge.id);
    }
    incomingByNodeId = _freezeLists(incoming);
    outgoingByNodeId = _freezeLists(outgoing);
    edgeIdsByNodeId = _freezeLists(incident);
    edgeIdsByHandleKey = Map.unmodifiable({
      for (final entry in handles.entries)
        entry.key: List<String>.unmodifiable(entry.value),
    });
  }

  final Map<String, FlowNode<T>> nodesById;
  final Map<String, FlowEdge> edgesById;
  late final Map<String, int> _nodeOrderById;
  late final Map<String, int> _edgeOrderById;
  late final Map<String, List<String>> childrenByParentId;
  late final Map<String, List<String>> incomingByNodeId;
  late final Map<String, List<String>> outgoingByNodeId;
  late final Map<String, List<String>> edgeIdsByNodeId;
  late final Map<FlowHandleKey, List<String>> edgeIdsByHandleKey;
  final int graphRevision;
  final int geometryRevision;

  List<FlowNode<T>> childrenOf(String parentId) => List.unmodifiable([
        for (final id in childrenByParentId[parentId] ?? const <String>[])
          if (nodesById[id] case final node?) node,
      ]);

  List<FlowNode<T>> incomersOf(String nodeId) {
    final seen = <String>{};
    final result = <FlowNode<T>>[];
    for (final edgeId in incomingByNodeId[nodeId] ?? const <String>[]) {
      final edge = edgesById[edgeId];
      final sourceId = edge?.sourceId;
      final node = sourceId == null ? null : nodesById[sourceId];
      if (node != null && seen.add(sourceId!)) result.add(node);
    }
    result.sort((first, second) =>
        _nodeOrderById[first.id]!.compareTo(_nodeOrderById[second.id]!));
    return List.unmodifiable(result);
  }

  List<FlowNode<T>> outgoersOf(String nodeId) {
    final seen = <String>{};
    final result = <FlowNode<T>>[];
    for (final edgeId in outgoingByNodeId[nodeId] ?? const <String>[]) {
      final edge = edgesById[edgeId];
      final targetId = edge?.targetId;
      final node = targetId == null ? null : nodesById[targetId];
      if (node != null && seen.add(targetId!)) result.add(node);
    }
    result.sort((first, second) =>
        _nodeOrderById[first.id]!.compareTo(_nodeOrderById[second.id]!));
    return List.unmodifiable(result);
  }

  List<FlowEdge> connectedEdgesOf(Iterable<String> nodeIds) {
    final seen = <String>{};
    final result = <FlowEdge>[];
    for (final nodeId in nodeIds) {
      for (final edgeId in edgeIdsByNodeId[nodeId] ?? const <String>[]) {
        final edge = edgesById[edgeId];
        if (edge != null && seen.add(edgeId)) result.add(edge);
      }
    }
    result.sort((first, second) =>
        _edgeOrderById[first.id]!.compareTo(_edgeOrderById[second.id]!));
    return List.unmodifiable(result);
  }

  List<FlowEdge> connectionsForNode(
    String nodeId, {
    String? handleId,
    FlowHandleType? type,
  }) {
    final node = nodesById[nodeId];
    if (node == null) return const [];
    if (handleId != null && type != null) {
      return List.unmodifiable([
        for (final edgeId
            in edgeIdsByHandleKey[FlowHandleKey(nodeId, handleId, type)] ??
                const <String>[])
          if (edgesById[edgeId] case final edge?) edge,
      ]);
    }
    final result = <FlowEdge>[];
    for (final edgeId in edgeIdsByNodeId[nodeId] ?? const <String>[]) {
      final edge = edgesById[edgeId];
      if (edge == null) continue;
      final sourceMatch = edge.sourceId == nodeId &&
          (type == null || type == FlowHandleType.source) &&
          (handleId == null ||
              _resolvedHandleId(
                    node,
                    edge.sourceHandleId,
                    FlowHandleType.source,
                  ) ==
                  handleId);
      final targetMatch = edge.targetId == nodeId &&
          (type == null || type == edge.targetHandleType) &&
          (handleId == null ||
              _resolvedHandleId(
                    node,
                    edge.targetHandleId,
                    edge.targetHandleType,
                  ) ==
                  handleId);
      if (sourceMatch || targetMatch) result.add(edge);
    }
    return List.unmodifiable(result);
  }

  String? _resolvedHandleId(
    FlowNode<T> node,
    String? handleId,
    FlowHandleType type,
  ) =>
      node.resolvedHandles
          .where((handle) =>
              handle.type == type &&
              (handleId == null || handle.id == handleId))
          .firstOrNull
          ?.id ??
      handleId;

  List<FlowEdge> connectionsFor(FlowHandleKey key) => List.unmodifiable([
        for (final id in edgeIdsByHandleKey[key] ?? const <String>[])
          if (edgesById[id] case final edge?) edge,
      ]);

  static Map<K, List<V>> _freezeLists<K, V>(Map<K, List<V>> values) =>
      Map.unmodifiable({
        for (final entry in values.entries)
          entry.key: List<V>.unmodifiable(entry.value),
      });
}
