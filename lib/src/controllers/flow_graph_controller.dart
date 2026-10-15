import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../models/flow_edge.dart';
import '../models/flow_graph_snapshot.dart';
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
        _edges = List.unmodifiable(edges);

  List<FlowNode<T>> _nodes;
  List<FlowEdge> _edges;

  List<FlowNode<T>> get nodes => _nodes;
  List<FlowEdge> get edges => _edges;

  FlowSelection get selection => FlowSelection(
        nodes: _nodes.where((node) => node.selected).map((node) => node.id),
        edges: _edges.where((edge) => edge.selected).map((edge) => edge.id),
      );

  FlowNode<T>? getNode(String id) =>
      _nodes.where((node) => node.id == id).firstOrNull;

  FlowEdge? getEdge(String id) =>
      _edges.where((edge) => edge.id == id).firstOrNull;

  List<FlowNode<T>> getNodes({Iterable<String>? ids}) {
    if (ids == null) return _nodes;
    final requested = ids.toSet();
    return List.unmodifiable(
        _nodes.where((node) => requested.contains(node.id)));
  }

  List<FlowEdge> getEdges({Iterable<String>? ids}) {
    if (ids == null) return _edges;
    final requested = ids.toSet();
    return List.unmodifiable(
        _edges.where((edge) => requested.contains(edge.id)));
  }

  List<FlowEdge> getNodeConnections(
    String nodeId, {
    String? handleId,
    FlowHandleType? type,
  }) =>
      FlowGraphUtils.getHandleConnections(
        nodeId,
        _edges,
        handleId: handleId,
        type: type,
      );

  List<FlowEdge> getHandleConnections(
    String nodeId, {
    String? handleId,
    FlowHandleType? type,
  }) =>
      FlowGraphUtils.getHandleConnections(
        nodeId,
        _edges,
        handleId: handleId,
        type: type,
      );

  List<FlowNode<T>> getIncomers(String nodeId) {
    final node = getNode(nodeId);
    return node == null
        ? const []
        : FlowGraphUtils.getIncomers(node, _nodes, _edges);
  }

  List<FlowNode<T>> getOutgoers(String nodeId) {
    final node = getNode(nodeId);
    return node == null
        ? const []
        : FlowGraphUtils.getOutgoers(node, _nodes, _edges);
  }

  List<FlowEdge> getConnectedEdges(Iterable<String> nodeIds) {
    final ids = nodeIds.toSet();
    return List.unmodifiable(_edges.where(
        (edge) => ids.contains(edge.sourceId) || ids.contains(edge.targetId)));
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
    _nodes = nextNodes;
    _edges = nextEdges;
    notifyListeners();
  }

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
