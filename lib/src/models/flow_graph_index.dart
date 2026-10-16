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
    final children = <String, List<String>>{};
    for (final node in nodesById.values) {
      final parentId = node.parentId;
      if (parentId != null) (children[parentId] ??= []).add(node.id);
    }
    childrenByParentId = _freezeLists(children);

    final incoming = <String, List<String>>{};
    final outgoing = <String, List<String>>{};
    final handles = <FlowHandleKey, List<String>>{};
    for (final edge in edgesById.values) {
      (outgoing[edge.sourceId] ??= []).add(edge.id);
      (incoming[edge.targetId] ??= []).add(edge.id);
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
    edgeIdsByHandleKey = Map.unmodifiable({
      for (final entry in handles.entries)
        entry.key: List<String>.unmodifiable(entry.value),
    });
  }

  final Map<String, FlowNode<T>> nodesById;
  final Map<String, FlowEdge> edgesById;
  late final Map<String, List<String>> childrenByParentId;
  late final Map<String, List<String>> incomingByNodeId;
  late final Map<String, List<String>> outgoingByNodeId;
  late final Map<FlowHandleKey, List<String>> edgeIdsByHandleKey;
  final int graphRevision;
  final int geometryRevision;

  List<FlowNode<T>> childrenOf(String parentId) => List.unmodifiable([
        for (final id in childrenByParentId[parentId] ?? const <String>[])
          if (nodesById[id] case final node?) node,
      ]);

  List<FlowNode<T>> incomersOf(String nodeId) {
    final sourceIds = {
      for (final id in incomingByNodeId[nodeId] ?? const <String>[])
        if (edgesById[id] case final edge?) edge.sourceId,
    };
    return List.unmodifiable(
        nodesById.values.where((node) => sourceIds.contains(node.id)));
  }

  List<FlowNode<T>> outgoersOf(String nodeId) {
    final targetIds = {
      for (final id in outgoingByNodeId[nodeId] ?? const <String>[])
        if (edgesById[id] case final edge?) edge.targetId,
    };
    return List.unmodifiable(
        nodesById.values.where((node) => targetIds.contains(node.id)));
  }

  List<FlowEdge> connectedEdgesOf(Iterable<String> nodeIds) {
    final result = <String>{};
    for (final nodeId in nodeIds) {
      result
        ..addAll(incomingByNodeId[nodeId] ?? const <String>[])
        ..addAll(outgoingByNodeId[nodeId] ?? const <String>[]);
    }
    return List.unmodifiable([
      for (final edge in edgesById.values)
        if (result.contains(edge.id)) edge,
    ]);
  }

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
