import 'flow_edge.dart';
import 'flow_node.dart';
import 'flow_selection.dart';

/// Complete graph state used at transaction boundaries.
class FlowGraphState<T> {
  FlowGraphState({
    required Iterable<FlowNode<T>> nodes,
    required Iterable<FlowEdge> edges,
    FlowSelection? selection,
  })  : nodes = List.unmodifiable(nodes),
        edges = List.unmodifiable(edges),
        selection = selection ??
            FlowSelection(
              nodes:
                  nodes.where((node) => node.selected).map((node) => node.id),
              edges:
                  edges.where((edge) => edge.selected).map((edge) => edge.id),
            );

  final List<FlowNode<T>> nodes;
  final List<FlowEdge> edges;
  final FlowSelection selection;
}

enum FlowGraphOperationType {
  addNodes,
  removeNodes,
  moveNodes,
  resizeNodes,
  updateNode,
  reparentNodes,
  addEdges,
  removeEdges,
  reconnectEdge,
  updateEdge,
}

/// A typed graph operation and its before/after entities.
class FlowGraphOperation<T> {
  const FlowGraphOperation({
    required this.type,
    this.beforeNodes = const [],
    this.afterNodes = const [],
    this.beforeEdges = const [],
    this.afterEdges = const [],
  });

  final FlowGraphOperationType type;
  final List<FlowNode<T>> beforeNodes;
  final List<FlowNode<T>> afterNodes;
  final List<FlowEdge> beforeEdges;
  final List<FlowEdge> afterEdges;
}

/// One user-level edit. Pointer movement should be grouped into one instance.
class FlowGraphTransaction<T> {
  const FlowGraphTransaction({
    required this.id,
    required this.label,
    required this.operations,
    required this.before,
    required this.after,
  });

  final String id;
  final String label;
  final List<FlowGraphOperation<T>> operations;
  final FlowGraphState<T> before;
  final FlowGraphState<T> after;
  FlowSelection get beforeSelection => before.selection;
  FlowSelection get afterSelection => after.selection;

  static FlowGraphTransaction<T> between<T>({
    required String id,
    required String label,
    required FlowGraphState<T> before,
    required FlowGraphState<T> after,
  }) {
    final operations = <FlowGraphOperation<T>>[];
    final beforeNodes = {for (final node in before.nodes) node.id: node};
    final afterNodes = {for (final node in after.nodes) node.id: node};
    final beforeEdges = {for (final edge in before.edges) edge.id: edge};
    final afterEdges = {for (final edge in after.edges) edge.id: edge};

    final removedNodes = before.nodes
        .where((node) => !afterNodes.containsKey(node.id))
        .toList(growable: false);
    final addedNodes = after.nodes
        .where((node) => !beforeNodes.containsKey(node.id))
        .toList(growable: false);
    if (removedNodes.isNotEmpty) {
      operations.add(FlowGraphOperation(
          type: FlowGraphOperationType.removeNodes, beforeNodes: removedNodes));
    }
    if (addedNodes.isNotEmpty) {
      operations.add(FlowGraphOperation(
          type: FlowGraphOperationType.addNodes, afterNodes: addedNodes));
    }
    for (final node in before.nodes) {
      final updated = afterNodes[node.id];
      if (updated == null || identical(node, updated)) continue;
      final type = node.parentId != updated.parentId
          ? FlowGraphOperationType.reparentNodes
          : node.position != updated.position
              ? FlowGraphOperationType.moveNodes
              : node.width != updated.width || node.height != updated.height
                  ? FlowGraphOperationType.resizeNodes
                  : FlowGraphOperationType.updateNode;
      operations.add(FlowGraphOperation(
        type: type,
        beforeNodes: [node],
        afterNodes: [updated],
      ));
    }

    final removedEdges = before.edges
        .where((edge) => !afterEdges.containsKey(edge.id))
        .toList(growable: false);
    final addedEdges = after.edges
        .where((edge) => !beforeEdges.containsKey(edge.id))
        .toList(growable: false);
    if (removedEdges.isNotEmpty) {
      operations.add(FlowGraphOperation(
          type: FlowGraphOperationType.removeEdges, beforeEdges: removedEdges));
    }
    if (addedEdges.isNotEmpty) {
      operations.add(FlowGraphOperation(
          type: FlowGraphOperationType.addEdges, afterEdges: addedEdges));
    }
    for (final edge in before.edges) {
      final updated = afterEdges[edge.id];
      if (updated == null || identical(edge, updated)) continue;
      final reconnect = edge.sourceId != updated.sourceId ||
          edge.targetId != updated.targetId ||
          edge.sourceHandleId != updated.sourceHandleId ||
          edge.targetHandleId != updated.targetHandleId ||
          edge.targetHandleType != updated.targetHandleType;
      operations.add(FlowGraphOperation(
        type: reconnect
            ? FlowGraphOperationType.reconnectEdge
            : FlowGraphOperationType.updateEdge,
        beforeEdges: [edge],
        afterEdges: [updated],
      ));
    }
    return FlowGraphTransaction<T>(
      id: id,
      label: label,
      operations: List.unmodifiable(operations),
      before: before,
      after: after,
    );
  }
}
