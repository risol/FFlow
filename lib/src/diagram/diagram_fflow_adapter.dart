import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../interactions/flow_layered_layout.dart';
import '../interactions/flow_orthogonal_edge_router.dart';
import '../geometry/flow_geometry.dart';
import '../models/flow_edge.dart';
import '../models/flow_graph_snapshot.dart';
import '../models/flow_handle.dart';
import '../models/flow_node.dart';
import '../models/flow_viewport.dart';
import 'diagram_document.dart';

/// A graph snapshot and its original application-level document.
class DiagramFlowGraph {
  const DiagramFlowGraph(this.document, this.snapshot);
  final DiagramDocument document;
  final FlowGraphSnapshot<Map<String, Object?>> snapshot;

  /// Preserve application semantics in a namespace separate from FFlow keys.
  Map<String, Object?> toSnapshotJson() => {
        ...snapshot.toJson(encodeNodeData: (data) => data),
        'fflowDiagram': {'document': document.toJson()},
      };
}

/// Adapts the supported Graph JSON model to FFlow and applies layered layout.
DiagramFlowGraph diagramToFlow(DiagramDocument document) {
  final nodes = <FlowNode<Map<String, Object?>>>[];
  final selfPorts = <String, (String?, String?)>{};
  final loopsByNode = <String, List<DiagramEdge>>{};
  for (final edge in document.edges) {
    if (edge.source == edge.target) {
      loopsByNode.putIfAbsent(edge.source, () => []).add(edge);
    }
  }
  for (final node in document.nodes) {
    final handles = [
      for (final port in node.ports)
        FlowHandle(
          id: port.id,
          type: port.kind == DiagramPortKind.source
              ? FlowHandleType.source
              : FlowHandleType.target,
          position: FlowHandlePosition.values.byName(port.side.name),
          offset: port.offset,
        ),
    ];
    // Supply collision-free implicit handles for missing endpoint kinds,
    // oriented along the chosen layout direction.
    for (final type in FlowHandleType.values) {
      if (handles.any((handle) => handle.type == type)) continue;
      var id = '__fflow_default_${type.name}';
      while (handles.any((handle) => handle.id == id)) {
        id = '_$id';
      }
      final sourceSide = switch (document.layout.direction) {
        DiagramDirection.lr => FlowHandlePosition.right,
        DiagramDirection.rl => FlowHandlePosition.left,
        DiagramDirection.tb => FlowHandlePosition.bottom,
        DiagramDirection.bt => FlowHandlePosition.top,
      };
      final targetSide = switch (document.layout.direction) {
        DiagramDirection.lr => FlowHandlePosition.left,
        DiagramDirection.rl => FlowHandlePosition.right,
        DiagramDirection.tb => FlowHandlePosition.top,
        DiagramDirection.bt => FlowHandlePosition.bottom,
      };
      handles.add(FlowHandle(
          id: id,
          type: type,
          position: type == FlowHandleType.source ? sourceSide : targetSide));
    }
    final loops = loopsByNode[node.id] ?? const <DiagramEdge>[];
    for (var index = 0; index < loops.length; index++) {
      final edge = loops[index];
      String addLoopHandle(FlowHandleType type, double offset) {
        var id = '__fflow_loop_${edge.id}_${type.name}';
        while (handles.any((handle) => handle.id == id)) {
          id = '_$id';
        }
        handles.add(FlowHandle(
            id: id,
            type: type,
            position: FlowHandlePosition.right,
            offset: offset));
        return id;
      }

      selfPorts[edge.id] = (
        edge.sourcePort ??
            addLoopHandle(FlowHandleType.source,
                (2 * index + 1) / (2 * loops.length + 1)),
        edge.targetPort ??
            addLoopHandle(FlowHandleType.target,
                (2 * index + 2) / (2 * loops.length + 1)),
      );
    }
    nodes.add(FlowNode<Map<String, Object?>>(
      id: node.id,
      type: node.type,
      position: node.position == null
          ? Offset.zero
          : Offset(node.position!.x, node.position!.y),
      width: node.size?.width ?? 220,
      height: node.size?.height ?? 96,
      parentId: node.parentId,
      handles: handles,
      data: {'label': node.label, 'diagram': node.toJson()},
    ));
  }
  final edges = <FlowEdge>[
    for (final edge in document.edges)
      FlowEdge(
        id: edge.id,
        sourceId: edge.source,
        targetId: edge.target,
        sourceHandleId: selfPorts[edge.id]?.$1 ?? edge.sourcePort,
        targetHandleId: selfPorts[edge.id]?.$2 ?? edge.targetPort,
        label: edge.label,
        markerStart: edge.type == 'erRelationship'
            ? (edge.data['sourceCardinality'] == 'zeroOrOne'
                ? FlowEdgeMarker.zeroOrOne
                : FlowEdgeMarker.crowFootZeroMany)
            : null,
        markerEnd: edge.type == 'erRelationship'
            ? (edge.data['nullable'] == true
                ? FlowEdgeMarker.zeroOrOne
                : FlowEdgeMarker.one)
            : edge.type == 'undirected'
                ? null
                : FlowEdgeMarker.arrowClosed,
        color: _color(edge.style['color']),
        strokeWidth: (edge.style['strokeWidth'] as num?)?.toDouble() ?? 2,
        data: edge.toJson(),
      ),
  ];
  var outputNodes = nodes;
  if (document.layout.mode == DiagramLayoutMode.auto) {
    final direction = switch (document.layout.direction) {
      DiagramDirection.lr => FlowLayoutDirection.leftToRight,
      DiagramDirection.rl => FlowLayoutDirection.rightToLeft,
      DiagramDirection.tb => FlowLayoutDirection.topToBottom,
      DiagramDirection.bt => FlowLayoutDirection.bottomToTop,
    };
    final layoutNodes = [...nodes];
    if (document.layout.nodeOrder != DiagramNodeOrder.input) {
      final labels = {for (final node in document.nodes) node.id: node.label};
      layoutNodes.sort((a, b) {
        final primary = document.layout.nodeOrder == DiagramNodeOrder.label
            ? labels[a.id]!.compareTo(labels[b.id]!)
            : a.id.compareTo(b.id);
        return primary != 0 ? primary : a.id.compareTo(b.id);
      });
    }
    final layout = FlowLayeredLayoutEngine<Map<String, Object?>>(
      direction: direction,
      nodeSpacing: document.layout.nodeSpacing,
      layerSpacing: document.layout.layerSpacing,
      groupPadding: document.layout.groupPadding,
    ).layout(nodes: layoutNodes, edges: edges);
    outputNodes = [
      for (final node in nodes)
        node.copyWith(
          position: (layout.positions[node.id] ?? node.position) -
              (node.parentId == null
                  ? Offset.zero
                  : layout.positions[node.parentId] ?? Offset.zero),
          width: layout.sizes[node.id]?.width ?? node.width,
          height: layout.sizes[node.id]?.height ?? node.height,
        ),
    ];
    if (document.type == DiagramType.flowchart) {
      outputNodes = _alignFlowSpine(document, outputNodes, edges);
    }
  }
  final byId = {for (final node in outputNodes) node.id: node};
  var outputEdges = [
    for (final edge in edges)
      if (edge.sourceId == edge.targetId)
        edge.copyWith(controlPoints: _selfLoop(edge, byId))
      else
        edge,
  ];
  if (document.type == DiagramType.flowchart &&
      document.layout.mode == DiagramLayoutMode.auto) {
    final feedback = _routeDecisionFeedback(document, outputNodes, outputEdges);
    final routed = _routeReciprocalEdges(document, feedback.$1, feedback.$2);
    final longCycles = _routeLongSameLayerEdges(document, routed.$1, routed.$2);
    outputNodes = longCycles.$1;
    outputEdges = longCycles.$2;
  }
  if (document.type == DiagramType.flowchart) {
    outputEdges = _routeOrthogonalFlowEdges(outputNodes, outputEdges);
  }
  return DiagramFlowGraph(
      document,
      FlowGraphSnapshot(
        nodes: outputNodes,
        edges: outputEdges,
        viewport: const FlowViewport(x: 0, y: 0, zoom: 1),
      ));
}

/// Route a simple decision/retry loop back into the incoming main line.
/// The merge point is explicit so the shared line cannot be mistaken for a
/// crossing. Other shapes and port configurations keep their original route.
(List<FlowNode<Map<String, Object?>>>, List<FlowEdge>) _routeDecisionFeedback(
    DiagramDocument document,
    List<FlowNode<Map<String, Object?>>> nodes,
    List<FlowEdge> edges) {
  if (nodes.length > 500 || edges.length > 1000) return (nodes, edges);
  final byId = {for (final node in nodes) node.id: node};
  final domainNodes = {for (final node in document.nodes) node.id: node};
  final horizontal = document.layout.direction == DiagramDirection.lr ||
      document.layout.direction == DiagramDirection.rl;
  final upstream = switch (document.layout.direction) {
    DiagramDirection.tb => const Offset(0, -1),
    DiagramDirection.bt => const Offset(0, 1),
    DiagramDirection.lr => const Offset(-1, 0),
    DiagramDirection.rl => const Offset(1, 0),
  };
  final upstreamSide = switch (document.layout.direction) {
    DiagramDirection.tb => FlowHandlePosition.top,
    DiagramDirection.bt => FlowHandlePosition.bottom,
    DiagramDirection.lr => FlowHandlePosition.left,
    DiagramDirection.rl => FlowHandlePosition.right,
  };
  final replacements = <String, FlowEdge>{};
  for (final forward in edges) {
    final decision = byId[forward.sourceId];
    final retry = byId[forward.targetId];
    if (decision == null ||
        retry == null ||
        decision.id == retry.id ||
        decision.parentId != null ||
        retry.parentId != null ||
        forward.sourceHandleId != null ||
        forward.targetHandleId != null) {
      continue;
    }
    final domainDecision = domainNodes[decision.id]!;
    final shape = domainDecision.style['shape'] ?? domainDecision.type;
    if ((shape != 'diamond' && shape != 'decision') ||
        domainDecision.ports.isNotEmpty ||
        domainNodes[retry.id]!.ports.isNotEmpty) {
      continue;
    }
    final backwards = edges
        .where(
            (edge) => edge.sourceId == retry.id && edge.targetId == decision.id)
        .toList();
    final incoming = edges
        .where((edge) =>
            edge.targetId == decision.id &&
            edge.sourceId != retry.id &&
            edge.sourceId != decision.id)
        .toList();
    if (backwards.length != 1 || incoming.length != 1) continue;
    final back = backwards.single, entry = incoming.single;
    if (back.sourceHandleId != null ||
        back.targetHandleId != null ||
        entry.targetHandleId != null ||
        forward.color != back.color ||
        entry.color != back.color ||
        forward.strokeWidth != back.strokeWidth ||
        entry.strokeWidth != back.strokeWidth) {
      continue;
    }
    final decisionRect = FlowGeometry.nodeRect(decision, byId);
    final retryRect = FlowGeometry.nodeRect(retry, byId);
    final entrySource = FlowGeometry.edgeSource(entry, byId);
    final entryTarget = FlowGeometry.edgeTarget(entry, byId);
    if (entrySource == null || entryTarget == null) continue;
    final incomingDelta = entrySource - entryTarget;
    final distance =
        incomingDelta.dx * upstream.dx + incomingDelta.dy * upstream.dy;
    final crossDifference =
        horizontal ? incomingDelta.dy.abs() : incomingDelta.dx.abs();
    if (distance < 64 || crossDifference > 0.01) continue;
    final join = entryTarget + upstream * (distance / 2);
    final delta = retryRect.center - decisionRect.center;
    final branchPositive = horizontal ? delta.dy > 0 : delta.dx > 0;
    final branchSide = horizontal
        ? (branchPositive ? FlowHandlePosition.bottom : FlowHandlePosition.top)
        : (branchPositive ? FlowHandlePosition.right : FlowHandlePosition.left);
    final targetSide = horizontal
        ? (branchPositive ? FlowHandlePosition.top : FlowHandlePosition.bottom)
        : (branchPositive ? FlowHandlePosition.left : FlowHandlePosition.right);
    final branchStart = switch (branchSide) {
      FlowHandlePosition.right => decisionRect.centerRight,
      FlowHandlePosition.left => decisionRect.centerLeft,
      FlowHandlePosition.top => decisionRect.topCenter,
      FlowHandlePosition.bottom => decisionRect.bottomCenter,
    };
    final offset = horizontal
        ? (branchStart.dx - retryRect.left) / retryRect.width
        : (branchStart.dy - retryRect.top) / retryRect.height;
    if (offset < 0.1 || offset > 0.9) continue;
    final branchEnd = switch (targetSide) {
      FlowHandlePosition.right =>
        Offset(retryRect.right, retryRect.top + retryRect.height * offset),
      FlowHandlePosition.left =>
        Offset(retryRect.left, retryRect.top + retryRect.height * offset),
      FlowHandlePosition.top =>
        Offset(retryRect.left + retryRect.width * offset, retryRect.top),
      FlowHandlePosition.bottom =>
        Offset(retryRect.left + retryRect.width * offset, retryRect.bottom),
    };
    final retryStart = switch (upstreamSide) {
      FlowHandlePosition.right => retryRect.centerRight,
      FlowHandlePosition.left => retryRect.centerLeft,
      FlowHandlePosition.top => retryRect.topCenter,
      FlowHandlePosition.bottom => retryRect.bottomCenter,
    };
    final bend = horizontal
        ? Offset(join.dx, retryStart.dy)
        : Offset(retryStart.dx, join.dy);
    bool clearSegment(Offset from, Offset to) {
      final segment = Rect.fromPoints(from, to).inflate(2);
      return byId.values.every((node) =>
          node.id == decision.id ||
          node.id == retry.id ||
          !FlowGeometry.nodeRect(node, byId).inflate(2).overlaps(segment));
    }

    if (!clearSegment(branchStart, branchEnd) ||
        !clearSegment(retryStart, bend) ||
        !clearSegment(bend, join) ||
        !clearSegment(join, entryTarget)) {
      continue;
    }
    String addHandle(String nodeId, FlowHandleType type,
        FlowHandlePosition side, String edgeId, double offset) {
      final node = byId[nodeId]!;
      var id = '__fflow_feedback_${edgeId}_${type.name}';
      while (node.handles.any((handle) => handle.id == id)) {
        id = '_$id';
      }
      byId[nodeId] = node.copyWith(handles: [
        ...node.handles,
        FlowHandle(id: id, type: type, position: side, offset: offset)
      ]);
      return id;
    }

    final branchSource = addHandle(
        decision.id, FlowHandleType.source, branchSide, forward.id, .5);
    final branchTarget = addHandle(
        retry.id, FlowHandleType.target, targetSide, forward.id, offset);
    final backSource =
        addHandle(retry.id, FlowHandleType.source, upstreamSide, back.id, .5);
    final midpoint = (branchStart + branchEnd) / 2;
    replacements[forward.id] = forward.copyWith(
        sourceHandleId: branchSource,
        targetHandleId: branchTarget,
        type: FlowEdgeType.straight,
        controlPoints: [midpoint]);
    replacements[back.id] = back.copyWith(
        sourceHandleId: backSource,
        targetHandleId: entry.targetHandleId,
        type: FlowEdgeType.straight,
        controlPoints: [bend, join],
        junctionPoints: [join]);
  }
  return (
    [for (final node in nodes) byId[node.id]!],
    [for (final edge in edges) replacements[edge.id] ?? edge]
  );
}

/// Align a single-node layer to its sole neighbour in a multi-node layer.
/// This keeps common entry and exit paths on the decision's main axis.
List<FlowNode<Map<String, Object?>>> _alignFlowSpine(DiagramDocument document,
    List<FlowNode<Map<String, Object?>>> nodes, List<FlowEdge> edges) {
  final horizontal = document.layout.direction == DiagramDirection.lr ||
      document.layout.direction == DiagramDirection.rl;
  final reverse = document.layout.direction == DiagramDirection.rl ||
      document.layout.direction == DiagramDirection.bt;
  final byId = {for (final node in nodes) node.id: node};
  final parentIds = {
    for (final node in nodes)
      if (node.parentId != null) node.parentId!
  };
  double primary(Rect rect) => horizontal
      ? (reverse ? rect.right : rect.left)
      : (reverse ? rect.bottom : rect.top);
  double cross(Offset offset) => horizontal ? offset.dy : offset.dx;
  final layers = <int, List<String>>{};
  for (final node in nodes.where((node) => node.parentId == null)) {
    final key = (primary(FlowGeometry.nodeRect(node, byId)) * 100).round();
    layers.putIfAbsent(key, () => []).add(node.id);
  }
  final neighbours = <String, Set<String>>{};
  for (final edge in edges) {
    if (edge.sourceId == edge.targetId) continue;
    neighbours.putIfAbsent(edge.sourceId, () => {}).add(edge.targetId);
    neighbours.putIfAbsent(edge.targetId, () => {}).add(edge.sourceId);
  }
  final original = Map<String, FlowNode<Map<String, Object?>>>.from(byId);
  for (final layer in layers.values.where((layer) => layer.length == 1)) {
    final id = layer.single;
    final node = original[id]!;
    if (parentIds.contains(id)) continue;
    final candidates = (neighbours[id] ?? const <String>{}).where((otherId) {
      final other = original[otherId];
      if (other == null ||
          other.parentId != null ||
          parentIds.contains(otherId)) {
        return false;
      }
      final key =
          (primary(FlowGeometry.nodeRect(other, original)) * 100).round();
      return (layers[key]?.length ?? 0) > 1;
    }).toList();
    if (candidates.length != 1) continue;
    final ownRect = FlowGeometry.nodeRect(node, original);
    final neighborRect =
        FlowGeometry.nodeRect(original[candidates.single]!, original);
    final shift = cross(neighborRect.center) - cross(ownRect.center);
    final delta = horizontal ? Offset(0, shift) : Offset(shift, 0);
    final moved = ownRect.shift(delta);
    if (byId.values.any((other) =>
        other.id != id &&
        other.parentId == null &&
        moved.overlaps(FlowGeometry.nodeRect(other, byId)))) {
      continue;
    }
    byId[id] = node.copyWith(position: node.position + delta);
  }
  return [for (final node in nodes) byId[node.id]!];
}

/// Use straight or Manhattan segments for exported flowcharts. Existing
/// explicit routes and self-loops remain intact.
List<FlowEdge> _routeOrthogonalFlowEdges<T>(
    List<FlowNode<T>> nodes, List<FlowEdge> edges) {
  final byId = {for (final node in nodes) node.id: node};
  final bounded = nodes.length <= 500 && edges.length <= 1000;
  const router = FlowOrthogonalEdgeRouter();
  return [
    for (final edge in edges)
      if (edge.hidden ||
          edge.sourceId == edge.targetId ||
          edge.controlPoints.isNotEmpty)
        edge
      else if (!bounded)
        edge.copyWith(type: FlowEdgeType.step)
      else
        _routeOrthogonalFlowEdge(edge, byId, router),
  ];
}

FlowEdge _routeOrthogonalFlowEdge<T>(FlowEdge edge,
    Map<String, FlowNode<T>> nodes, FlowOrthogonalEdgeRouter router) {
  final source = nodes[edge.sourceId];
  final target = nodes[edge.targetId];
  if (source == null || target == null) return edge;
  final sourceAnchor = FlowGeometry.edgeSource(edge, nodes);
  final targetAnchor = FlowGeometry.edgeTarget(edge, nodes);
  if (sourceAnchor == null || targetAnchor == null) return edge;
  bool isAncestor(String id, FlowNode<T> node) {
    var parent = node.parentId;
    final seen = <String>{};
    while (parent != null && seen.add(parent)) {
      if (parent == id) return true;
      parent = nodes[parent]?.parentId;
    }
    return false;
  }

  final route = router.route(
    edge: edge,
    sourceBounds: FlowGeometry.nodeRect(source, nodes),
    targetBounds: FlowGeometry.nodeRect(target, nodes),
    sourceAnchor: sourceAnchor,
    targetAnchor: targetAnchor,
    obstacles: [
      for (final node in nodes.values)
        if (node.id != source.id &&
            node.id != target.id &&
            FlowGeometry.isVisible(node, nodes) &&
            !isAncestor(node.id, source) &&
            !isAncestor(node.id, target))
          FlowGeometry.nodeRect(node, nodes),
    ],
  );
  return edge.copyWith(
      type: FlowEdgeType.straight, controlPoints: route.controlPoints);
}

/// Routes an implicit same-layer edge around an intervening root node when a
/// clear side corridor exists. It is intentionally bounded for large graphs.
(List<FlowNode<Map<String, Object?>>>, List<FlowEdge>) _routeLongSameLayerEdges(
    DiagramDocument document,
    List<FlowNode<Map<String, Object?>>> nodes,
    List<FlowEdge> edges) {
  if (nodes.length > 1000 || edges.length > 2000) return (nodes, edges);
  final byId = {for (final node in nodes) node.id: node};
  final domainNodes = {for (final node in document.nodes) node.id: node};
  final horizontal = document.layout.direction == DiagramDirection.lr ||
      document.layout.direction == DiagramDirection.rl;
  final reverse = document.layout.direction == DiagramDirection.rl ||
      document.layout.direction == DiagramDirection.bt;
  double primary(Rect r) =>
      horizontal ? (reverse ? r.right : r.left) : (reverse ? r.bottom : r.top);
  double cross(Offset p) => horizontal ? p.dy : p.dx;
  final replacements = <String, FlowEdge>{};
  var laneIndex = 0;
  Offset anchor(Rect r, FlowHandlePosition side) => switch (side) {
        FlowHandlePosition.right => Offset(r.right, r.center.dy),
        FlowHandlePosition.left => Offset(r.left, r.center.dy),
        FlowHandlePosition.bottom => Offset(r.center.dx, r.bottom),
        FlowHandlePosition.top => Offset(r.center.dx, r.top),
      };
  String addHandle(String nodeId, FlowHandleType type, FlowHandlePosition side,
      String edgeId) {
    final node = byId[nodeId]!;
    var id = '__fflow_layer_cycle_${edgeId}_${type.name}';
    while (node.handles.any((handle) => handle.id == id)) {
      id = '_$id';
    }
    byId[nodeId] = node.copyWith(handles: [
      ...node.handles,
      FlowHandle(id: id, type: type, position: side)
    ]);
    return id;
  }

  for (final edge in edges) {
    if (edge.sourceId == edge.targetId ||
        edge.controlPoints.isNotEmpty ||
        edge.sourceHandleId != null ||
        edge.targetHandleId != null) {
      continue;
    }
    final source = byId[edge.sourceId]!;
    final target = byId[edge.targetId]!;
    if (source.parentId != null ||
        target.parentId != null ||
        domainNodes[source.id]!.ports.isNotEmpty ||
        domainNodes[target.id]!.ports.isNotEmpty) {
      continue;
    }
    final sourceRect = FlowGeometry.nodeRect(source, byId);
    final targetRect = FlowGeometry.nodeRect(target, byId);
    if ((primary(sourceRect) - primary(targetRect)).abs() > 0.01) continue;
    final low = math.min(cross(sourceRect.center), cross(targetRect.center));
    final high = math.max(cross(sourceRect.center), cross(targetRect.center));
    final sameLayer = nodes
        .where((node) =>
            node.parentId == null &&
            (primary(FlowGeometry.nodeRect(node, byId)) - primary(sourceRect))
                    .abs() <=
                0.01)
        .toList();
    final hasInterveningNode = sameLayer.any((node) =>
        node.id != source.id &&
        node.id != target.id &&
        cross(FlowGeometry.nodeRect(node, byId).center) > low &&
        cross(FlowGeometry.nodeRect(node, byId).center) < high);
    final rects = [
      for (final node in sameLayer) FlowGeometry.nodeRect(node, byId)
    ];
    bool segmentClear(Offset a, Offset b) {
      final segment = Rect.fromPoints(a, b).inflate(4);
      return byId.values.every((node) =>
          node.id == source.id ||
          node.id == target.id ||
          !FlowGeometry.nodeRect(node, byId).inflate(4).overlaps(segment));
    }

    if (!hasInterveningNode) {
      final forward = cross(targetRect.center) > cross(sourceRect.center);
      final sourceSide = horizontal
          ? (forward ? FlowHandlePosition.bottom : FlowHandlePosition.top)
          : (forward ? FlowHandlePosition.right : FlowHandlePosition.left);
      final targetSide = horizontal
          ? (forward ? FlowHandlePosition.top : FlowHandlePosition.bottom)
          : (forward ? FlowHandlePosition.left : FlowHandlePosition.right);
      if (!segmentClear(
          anchor(sourceRect, sourceSide), anchor(targetRect, targetSide))) {
        continue;
      }
      replacements[edge.id] = edge.copyWith(
        sourceHandleId:
            addHandle(source.id, FlowHandleType.source, sourceSide, edge.id),
        targetHandleId:
            addHandle(target.id, FlowHandleType.target, targetSide, edge.id),
      );
      continue;
    }

    for (final positive in [true, false]) {
      final margin = 48.0 + (laneIndex % 8) * 16;
      final side = horizontal
          ? (positive ? FlowHandlePosition.right : FlowHandlePosition.left)
          : (positive ? FlowHandlePosition.bottom : FlowHandlePosition.top);
      final primaryLane = horizontal
          ? (positive
              ? rects.map((r) => r.right).reduce(math.max) + margin
              : rects.map((r) => r.left).reduce(math.min) - margin)
          : (positive
              ? rects.map((r) => r.bottom).reduce(math.max) + margin
              : rects.map((r) => r.top).reduce(math.min) - margin);
      final start = anchor(sourceRect, side), end = anchor(targetRect, side);
      final a = horizontal
          ? Offset(primaryLane, start.dy)
          : Offset(start.dx, primaryLane);
      final b = horizontal
          ? Offset(primaryLane, end.dy)
          : Offset(end.dx, primaryLane);
      if (!segmentClear(start, a) ||
          !segmentClear(a, b) ||
          !segmentClear(b, end)) {
        continue;
      }
      final sourceHandle =
          addHandle(source.id, FlowHandleType.source, side, edge.id);
      final targetHandle =
          addHandle(target.id, FlowHandleType.target, side, edge.id);
      replacements[edge.id] = edge.copyWith(
          sourceHandleId: sourceHandle,
          targetHandleId: targetHandle,
          controlPoints: [a, b]);
      laneIndex++;
      break;
    }
  }
  return (
    [for (final node in nodes) byId[node.id]!],
    [for (final edge in edges) replacements[edge.id] ?? edge]
  );
}

/// Route an unambiguous pair of opposite implicit edges on separate lanes.
/// Other cycles and explicitly positioned ports retain their original paths.
(List<FlowNode<Map<String, Object?>>>, List<FlowEdge>) _routeReciprocalEdges(
    DiagramDocument document,
    List<FlowNode<Map<String, Object?>>> nodes,
    List<FlowEdge> edges) {
  final byId = {for (final node in nodes) node.id: node};
  final domainNodes = {for (final node in document.nodes) node.id: node};
  final pairs = <(String, String), List<FlowEdge>>{};
  for (final edge in edges) {
    if (edge.sourceId == edge.targetId) continue;
    final ordered = edge.sourceId.compareTo(edge.targetId) < 0
        ? (edge.sourceId, edge.targetId)
        : (edge.targetId, edge.sourceId);
    pairs.putIfAbsent(ordered, () => []).add(edge);
  }
  final replacements = <String, FlowEdge>{};
  for (final entry in pairs.entries) {
    final pair = entry.value;
    if (pair.length != 2 ||
        pair[0].sourceId != pair[1].targetId ||
        pair.any((edge) =>
            edge.sourceHandleId != null || edge.targetHandleId != null)) {
      continue;
    }
    final first = byId[entry.key.$1]!;
    final second = byId[entry.key.$2]!;
    if (first.parentId != null ||
        second.parentId != null ||
        domainNodes[first.id]!.ports.isNotEmpty ||
        domainNodes[second.id]!.ports.isNotEmpty) {
      continue;
    }
    final a = FlowGeometry.nodeRect(first, byId);
    final b = FlowGeometry.nodeRect(second, byId);
    final delta = b.center - a.center;
    final horizontal = delta.dx.abs() >= delta.dy.abs();
    final gap = horizontal
        ? math.max(a.left, b.left) - math.min(a.right, b.right)
        : math.max(a.top, b.top) - math.min(a.bottom, b.bottom);
    if (gap < 24) continue;
    final crossLow =
        horizontal ? math.max(a.top, b.top) : math.max(a.left, b.left);
    final crossHigh =
        horizontal ? math.min(a.bottom, b.bottom) : math.min(a.right, b.right);
    if (crossHigh - crossLow < 40) continue;
    final corridor = Rect.fromPoints(a.center, b.center).inflate(24);
    if (byId.values.any((node) =>
        node.id != first.id &&
        node.id != second.id &&
        FlowGeometry.nodeRect(node, byId).overlaps(corridor))) {
      continue;
    }

    FlowHandlePosition side(bool fromFirst) {
      if (horizontal) {
        return (delta.dx > 0) == fromFirst
            ? FlowHandlePosition.right
            : FlowHandlePosition.left;
      }
      return (delta.dy > 0) == fromFirst
          ? FlowHandlePosition.bottom
          : FlowHandlePosition.top;
    }

    String addHandle(String nodeId, FlowHandleType type,
        FlowHandlePosition position, String edgeId, double crossCoordinate) {
      final node = byId[nodeId]!;
      final rect = FlowGeometry.nodeRect(node, byId);
      final domainNode = domainNodes[nodeId]!;
      final shape = domainNode.style['shape'] ?? domainNode.type;
      final offset = (horizontal
              ? (crossCoordinate - rect.top) / rect.height
              : (crossCoordinate - rect.left) / rect.width)
          .clamp(0.0, 1.0)
          .toDouble();
      final diamond = shape == 'diamond' || shape == 'decision';
      final ellipse = shape == 'circle' || shape == 'ellipse';
      Offset? anchor;
      if (diamond || ellipse) {
        final extent = diamond
            ? 0.5 - (offset - 0.5).abs()
            : 0.5 * math.sqrt(math.max(0, 1 - math.pow(2 * offset - 1, 2)));
        anchor = switch (position) {
          FlowHandlePosition.right => Offset(0.5 + extent, offset),
          FlowHandlePosition.left => Offset(0.5 - extent, offset),
          FlowHandlePosition.bottom => Offset(offset, 0.5 + extent),
          FlowHandlePosition.top => Offset(offset, 0.5 - extent),
        };
      }
      var id = '__fflow_cycle_${edgeId}_${type.name}';
      while (node.handles.any((handle) => handle.id == id)) {
        id = '_$id';
      }
      byId[nodeId] = node.copyWith(handles: [
        ...node.handles,
        FlowHandle(
            id: id,
            type: type,
            position: position,
            offset: offset,
            anchor: anchor)
      ]);
      return id;
    }

    for (final edge in pair) {
      final fromFirst = edge.sourceId == first.id;
      final crossCoordinate =
          crossLow + (crossHigh - crossLow) * (fromFirst ? 0.28 : 0.72);
      final sourceId = addHandle(edge.sourceId, FlowHandleType.source,
          side(fromFirst), edge.id, crossCoordinate);
      final targetId = addHandle(edge.targetId, FlowHandleType.target,
          side(!fromFirst), edge.id, crossCoordinate);
      final routed =
          edge.copyWith(sourceHandleId: sourceId, targetHandleId: targetId);
      final start = FlowGeometry.edgeSource(routed, byId)!;
      final end = FlowGeometry.edgeTarget(routed, byId)!;
      final midpoint =
          horizontal ? (start.dx + end.dx) / 2 : (start.dy + end.dy) / 2;
      replacements[edge.id] = routed.copyWith(
        type: FlowEdgeType.straight,
        controlPoints: horizontal
            ? [Offset(midpoint, start.dy), Offset(midpoint, end.dy)]
            : [Offset(start.dx, midpoint), Offset(end.dx, midpoint)],
      );
    }
  }
  return (
    [for (final node in nodes) byId[node.id]!],
    [for (final edge in edges) replacements[edge.id] ?? edge]
  );
}

List<Offset> _selfLoop<T>(FlowEdge edge, Map<String, FlowNode<T>> byId) {
  final node = byId[edge.sourceId]!;
  final rect = FlowGeometry.nodeRect(node, byId);
  const margin = 56.0;
  final outer = rect.inflate(margin);
  final source = FlowGeometry.edgeSource(edge, byId)!;
  final target = FlowGeometry.edgeTarget(edge, byId)!;
  final start =
      FlowGeometry.handleFor(node, edge.sourceHandleId, FlowHandleType.source)!
          .position;
  final end =
      FlowGeometry.handleFor(node, edge.targetHandleId, edge.targetHandleType)!
          .position;
  const sides = [
    FlowHandlePosition.top,
    FlowHandlePosition.right,
    FlowHandlePosition.bottom,
    FlowHandlePosition.left
  ];
  Offset project(Offset point, FlowHandlePosition side) => switch (side) {
        FlowHandlePosition.top => Offset(point.dx, outer.top),
        FlowHandlePosition.right => Offset(outer.right, point.dy),
        FlowHandlePosition.bottom => Offset(point.dx, outer.bottom),
        FlowHandlePosition.left => Offset(outer.left, point.dy),
      };
  final corners = [
    outer.topRight,
    outer.bottomRight,
    outer.bottomLeft,
    outer.topLeft
  ];
  if (start == end && (source - target).distance > 0.01) {
    return [project(source, start), project(target, end)];
  }
  var current = sides.indexOf(start);
  final finish = sides.indexOf(end);
  var steps = (finish - current + 4) % 4;
  if (steps == 0) steps = 4;
  final points = <Offset>[project(source, start)];
  for (var i = 0; i < steps; i++) {
    points.add(corners[current]);
    current = (current + 1) % 4;
  }
  points.add(project(target, end));
  return points;
}

Color? _color(Object? value) {
  if (value == null) return null;
  final hex = (value as String).substring(1);
  return Color(int.parse(hex.length == 6 ? 'ff$hex' : hex, radix: 16));
}
