import 'package:flutter/widgets.dart';

import '../geometry/flow_geometry.dart';
import '../models/flow_edge.dart';
import '../models/flow_node.dart';
import '../utils/flow_graph_utils.dart';

enum FlowClipboardParentPolicy { preserveCopiedParents, detachAllToRoot }

class FlowClipboardPayload<T> {
  const FlowClipboardPayload({
    required this.schemaVersion,
    required this.nodes,
    required this.edges,
  });

  static const currentSchemaVersion = 1;
  final int schemaVersion;
  final List<FlowNode<T>> nodes;
  final List<FlowEdge> edges;
}

class FlowClipboardResult<T> {
  const FlowClipboardResult({
    required this.nodes,
    required this.edges,
    required this.pastedNodes,
    required this.pastedEdges,
  });

  final List<FlowNode<T>> nodes;
  final List<FlowEdge> edges;
  final List<FlowNode<T>> pastedNodes;
  final List<FlowEdge> pastedEdges;
}

/// In-memory copy/cut/paste helper. Payloads retain typed application data.
class FlowClipboard<T> {
  FlowClipboardPayload<T>? _payload;
  int _pasteCount = 0;

  FlowClipboardPayload<T>? get payload => _payload;
  bool get isNotEmpty => _payload?.nodes.isNotEmpty ?? false;

  FlowClipboardPayload<T> copy({
    required Iterable<FlowNode<T>> nodes,
    required Iterable<FlowEdge> edges,
    required Iterable<String> selectedNodeIds,
  }) {
    final nodeList = nodes.toList(growable: false);
    final edgeList = edges.toList(growable: false);
    final selected = selectedNodeIds.toSet();
    final copiedNodes = nodeList
        .where((node) => selected.contains(node.id))
        .toList(growable: false);
    final copiedIds = copiedNodes.map((node) => node.id).toSet();
    final copiedEdges = edgeList
        .where((edge) =>
            copiedIds.contains(edge.sourceId) &&
            copiedIds.contains(edge.targetId))
        .toList(growable: false);
    _payload = FlowClipboardPayload<T>(
      schemaVersion: FlowClipboardPayload.currentSchemaVersion,
      nodes: List.unmodifiable(copiedNodes),
      edges: List.unmodifiable(copiedEdges),
    );
    _pasteCount = 0;
    return _payload!;
  }

  FlowDeleteResult<T> cut({
    required List<FlowNode<T>> nodes,
    required List<FlowEdge> edges,
    required Iterable<String> selectedNodeIds,
  }) {
    copy(nodes: nodes, edges: edges, selectedNodeIds: selectedNodeIds);
    return FlowGraphUtils.deleteElements(
      nodes: nodes,
      edges: edges,
      nodeIds: selectedNodeIds,
    );
  }

  FlowClipboardResult<T> paste({
    required List<FlowNode<T>> nodes,
    required List<FlowEdge> edges,
    required String Function() createId,
    Offset? offset,
    FlowClipboardParentPolicy parentPolicy =
        FlowClipboardParentPolicy.preserveCopiedParents,
  }) {
    final payload = _payload;
    if (payload == null || payload.nodes.isEmpty) {
      return FlowClipboardResult<T>(
        nodes: List.unmodifiable(nodes),
        edges: List.unmodifiable(edges),
        pastedNodes: const [],
        pastedEdges: const [],
      );
    }
    if (payload.schemaVersion > FlowClipboardPayload.currentSchemaVersion) {
      throw FormatException(
          'Unsupported FFlow clipboard schema ${payload.schemaVersion}.');
    }
    final delta =
        offset ?? Offset(24 * (_pasteCount + 1), 24 * (_pasteCount + 1));
    _pasteCount++;
    final nodeIds = <String, String>{};
    final edgeIds = <String, String>{};
    final usedIds = <String>{
      ...nodes.map((node) => node.id),
      ...edges.map((edge) => edge.id),
    };
    String allocateId() {
      for (var attempt = 0; attempt < 1000; attempt++) {
        final id = createId();
        if (id.isNotEmpty && usedIds.add(id)) return id;
      }
      throw StateError('Could not allocate a unique FFlow clipboard id.');
    }

    for (final node in payload.nodes) {
      nodeIds[node.id] = allocateId();
    }
    for (final edge in payload.edges) {
      edgeIds[edge.id] = allocateId();
    }
    final copiedIds = payload.nodes.map((node) => node.id).toSet();
    final nodesById = {for (final node in payload.nodes) node.id: node};
    final pastedNodes = <FlowNode<T>>[];
    for (final node in payload.nodes) {
      final copiedParent = node.parentId != null &&
          copiedIds.contains(node.parentId) &&
          parentPolicy == FlowClipboardParentPolicy.preserveCopiedParents;
      final absoluteAnchor = FlowGeometry.nodeAbsoluteAnchor(node, nodesById);
      pastedNodes.add(node.copyWith(
        id: nodeIds[node.id],
        parentId: copiedParent ? nodeIds[node.parentId] : null,
        position: copiedParent ? node.position : absoluteAnchor + delta,
        selected: true,
      ));
    }
    final pastedEdges = <FlowEdge>[
      for (final edge in payload.edges)
        edge.copyWith(
          id: edgeIds[edge.id],
          sourceId: nodeIds[edge.sourceId],
          targetId: nodeIds[edge.targetId],
          selected: true,
        ),
    ];
    return FlowClipboardResult<T>(
      nodes: List.unmodifiable([...nodes, ...pastedNodes]),
      edges: List.unmodifiable([...edges, ...pastedEdges]),
      pastedNodes: List.unmodifiable(pastedNodes),
      pastedEdges: List.unmodifiable(pastedEdges),
    );
  }
}
