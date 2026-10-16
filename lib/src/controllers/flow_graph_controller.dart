import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../models/flow_edge.dart';
import '../models/flow_graph_snapshot.dart';
import '../models/flow_graph_index.dart';
import '../models/flow_diagnostic.dart';
import '../models/flow_handle.dart';
import '../models/flow_node.dart';
import '../models/flow_selection.dart';
import '../models/flow_viewport.dart';
import '../utils/flow_graph_utils.dart';

/// Observable graph state and query/update API for an FFlow editor.
///
/// Use the controller independently, or pass it to the FFlow canvas as its
/// state source. Mutations notify listeners after the graph has been updated.
class FlowGraphController<T> extends ChangeNotifier {
  FlowGraphController({
    Iterable<FlowNode<T>> nodes = const [],
    Iterable<FlowEdge> edges = const [],
  })  : _nodes = List.unmodifiable(nodes),
        _edges = List.unmodifiable(edges) {
    _index = FlowGraphIndex<T>(nodes: _nodes, edges: _edges);
  }

  List<FlowNode<T>> _nodes;
  List<FlowEdge> _edges;
  late FlowGraphIndex<T> _index;
  int _graphRevision = 0;
  int _geometryRevision = 0;

  List<FlowNode<T>> get nodes => _nodes;
  List<FlowEdge> get edges => _edges;
  FlowGraphIndex<T> get index => _index;
  int get graphRevision => _graphRevision;
  int get geometryRevision => _geometryRevision;

  FlowSelection get selection => FlowSelection(
        nodes: _nodes.where((node) => node.selected).map((node) => node.id),
        edges: _edges.where((edge) => edge.selected).map((edge) => edge.id),
      );

  List<FlowDiagnostic> validate({FlowViewport? viewport}) =>
      FlowGraphValidator.validate<T>(
        nodes: _nodes,
        edges: _edges,
        viewport: viewport,
      );

  FlowNode<T>? getNode(String id) => _index.nodesById[id];

  FlowEdge? getEdge(String id) => _index.edgesById[id];

  List<FlowNode<T>> getNodes({Iterable<String>? ids}) {
    if (ids == null) return _nodes;
    return List.unmodifiable([
      for (final id in ids)
        if (_index.nodesById[id] case final node?) node,
    ]);
  }

  List<FlowEdge> getEdges({Iterable<String>? ids}) {
    if (ids == null) return _edges;
    return List.unmodifiable([
      for (final id in ids)
        if (_index.edgesById[id] case final edge?) edge,
    ]);
  }

  List<FlowEdge> getNodeConnections(
    String nodeId, {
    String? handleId,
    FlowHandleType? type,
  }) =>
      List.unmodifiable([
        for (final entry in _index.edgeIdsByHandleKey.entries)
          if (entry.key.nodeId == nodeId &&
              (handleId == null || entry.key.handleId == handleId) &&
              (type == null || entry.key.type == type))
            for (final edgeId in entry.value)
              if (_index.edgesById[edgeId] case final edge?) edge,
      ]);

  List<FlowEdge> getHandleConnections(
    String nodeId, {
    String? handleId,
    FlowHandleType? type,
  }) =>
      getNodeConnections(nodeId, handleId: handleId, type: type);

  List<FlowNode<T>> getIncomers(String nodeId) {
    return _index.incomersOf(nodeId);
  }

  List<FlowNode<T>> getOutgoers(String nodeId) {
    return _index.outgoersOf(nodeId);
  }

  List<FlowEdge> getConnectedEdges(Iterable<String> nodeIds) {
    return _index.connectedEdgesOf(nodeIds);
  }

  Rect get nodesBounds => FlowGraphUtils.getNodesBounds(_nodes);

  List<FlowNode<T>> getNodesInside(
    Rect bounds, {
    bool partial = true,
    bool includeHidden = false,
  }) =>
      FlowGraphUtils.getNodesInside(
        bounds,
        _nodes,
        partial: partial,
        includeHidden: includeHidden,
      );

  bool isNodeIntersecting(
    String nodeId,
    Rect area, {
    bool partial = true,
    bool includeHidden = false,
  }) =>
      FlowGraphUtils.isNodeIntersecting(
        nodeId,
        area,
        _nodes,
        partial: partial,
        includeHidden: includeHidden,
      );

  List<FlowNode<T>> getIntersectingNodes(
    String nodeId, {
    bool partial = true,
    bool includeHidden = false,
  }) =>
      FlowGraphUtils.getIntersectingNodes(
        nodeId,
        _nodes,
        partial: partial,
        includeHidden: includeHidden,
      );

  void setGraph({
    required Iterable<FlowNode<T>> nodes,
    required Iterable<FlowEdge> edges,
  }) {
    final nextNodes = List<FlowNode<T>>.unmodifiable(nodes);
    final nextEdges = List<FlowEdge>.unmodifiable(edges);
    if (listEquals(_nodes, nextNodes) && listEquals(_edges, nextEdges)) return;
    final geometryChanged = _geometrySignature(_nodes, _edges) !=
        _geometrySignature(nextNodes, nextEdges);
    _nodes = nextNodes;
    _edges = nextEdges;
    _graphRevision++;
    if (geometryChanged) _geometryRevision++;
    _index = FlowGraphIndex<T>(
      nodes: _nodes,
      edges: _edges,
      graphRevision: _graphRevision,
      geometryRevision: _geometryRevision,
    );
    notifyListeners();
  }

  int _geometrySignature(
    Iterable<FlowNode<T>> nodes,
    Iterable<FlowEdge> edges,
  ) =>
      Object.hashAll([
        for (final node in nodes)
          Object.hash(
            node.id,
            node.position,
            node.width,
            node.height,
            node.origin,
            node.parentId,
            Object.hashAll(node.resolvedHandles.map((handle) => Object.hash(
                  handle.id,
                  handle.type,
                  handle.position,
                  handle.offset,
                ))),
          ),
        for (final edge in edges)
          Object.hash(
            edge.id,
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
          ),
      ]);

  void setNodes(Iterable<FlowNode<T>> nodes) =>
      setGraph(nodes: nodes, edges: _edges);

  void setEdges(Iterable<FlowEdge> edges) =>
      setGraph(nodes: _nodes, edges: edges);

  void setSelection({
    Iterable<String> nodeIds = const [],
    Iterable<String> edgeIds = const [],
  }) {
    final selectedNodes = nodeIds.toSet();
    final selectedEdges = edgeIds.toSet();
    setGraph(
      nodes: [
        for (final node in _nodes)
          node.copyWith(selected: selectedNodes.contains(node.id)),
      ],
      edges: [
        for (final edge in _edges)
          edge.copyWith(selected: selectedEdges.contains(edge.id)),
      ],
    );
  }

  void addNodes(Iterable<FlowNode<T>> nodes) {
    final ids = _nodes.map((node) => node.id).toSet();
    setNodes([
      ..._nodes,
      for (final node in nodes)
        if (ids.add(node.id)) node,
    ]);
  }

  void updateNode(String id, FlowNode<T> Function(FlowNode<T>) update) {
    final index = _nodes.indexWhere((node) => node.id == id);
    if (index < 0) return;
    final next = List<FlowNode<T>>.of(_nodes);
    next[index] = update(next[index]);
    setNodes(next);
  }

  void addEdges(Iterable<FlowEdge> edges) {
    var next = _edges;
    for (final edge in edges) {
      next = FlowGraphUtils.addEdge(next, edge);
    }
    setEdges(next);
  }

  void updateEdge(String id, FlowEdge Function(FlowEdge) update) {
    final index = _edges.indexWhere((edge) => edge.id == id);
    if (index < 0) return;
    final next = List<FlowEdge>.of(_edges);
    next[index] = update(next[index]);
    setEdges(next);
  }

  FlowDeleteResult<T> deleteElements({
    Iterable<String> nodeIds = const [],
    Iterable<String> edgeIds = const [],
  }) {
    final result = FlowGraphUtils.deleteElements(
      nodes: _nodes,
      edges: _edges,
      nodeIds: nodeIds,
      edgeIds: edgeIds,
    );
    setGraph(nodes: result.nodes, edges: result.edges);
    return result;
  }

  FlowGraphSnapshot<T> toSnapshot(FlowViewport viewport) =>
      FlowGraphSnapshot<T>(
        nodes: _nodes,
        edges: _edges,
        viewport: viewport,
      );
}
