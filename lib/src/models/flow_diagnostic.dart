import 'package:flutter/painting.dart';

import 'flow_edge.dart';
import 'flow_handle.dart';
import 'flow_node.dart';
import 'flow_viewport.dart';
import 'flow_events.dart';

enum FlowDiagnosticSeverity { warning, error }

/// A stable, machine-readable explanation of an invalid or suspicious graph.
class FlowDiagnostic {
  const FlowDiagnostic({
    required this.code,
    required this.message,
    this.severity = FlowDiagnosticSeverity.error,
    this.entityId,
  });

  final String code;
  final String message;
  final FlowDiagnosticSeverity severity;
  final String? entityId;

  @override
  String toString() =>
      'FlowDiagnostic($code${entityId == null ? '' : ', $entityId'}): $message';
}

/// Checks graph invariants without changing graph state.
abstract final class FlowGraphValidator {
  static List<FlowDiagnostic> validate<T>({
    required Iterable<FlowNode<T>> nodes,
    required Iterable<FlowEdge> edges,
    FlowViewport? viewport,
    double? minZoom,
    double? maxZoom,
    Rect? translateExtent,
    FlowConnectionMode? connectionMode,
  }) {
    final nodeList = nodes.toList(growable: false);
    final edgeList = edges.toList(growable: false);
    final diagnostics = <FlowDiagnostic>[];
    final nodesById = <String, FlowNode<T>>{};
    final edgesById = <String, FlowEdge>{};

    for (final node in nodeList) {
      if (nodesById.containsKey(node.id)) {
        diagnostics.add(FlowDiagnostic(
          code: 'duplicate-node-id',
          entityId: node.id,
          message: 'Node ids must be unique.',
        ));
      } else {
        nodesById[node.id] = node;
      }
      if (!_finite(node.position.dx) || !_finite(node.position.dy)) {
        diagnostics.add(FlowDiagnostic(
          code: 'invalid-node-position',
          entityId: node.id,
          message: 'Node position must contain finite coordinates.',
        ));
      }
      if (!_finite(node.width) ||
          !_finite(node.height) ||
          node.width <= 0 ||
          node.height <= 0 ||
          !_finite(node.minWidth) ||
          !_finite(node.minHeight) ||
          !_finite(node.maxWidth) ||
          !_finite(node.maxHeight) ||
          node.minWidth <= 0 ||
          node.minHeight <= 0 ||
          node.maxWidth < node.minWidth ||
          node.maxHeight < node.minHeight) {
        diagnostics.add(FlowDiagnostic(
          code: 'invalid-node-size',
          entityId: node.id,
          message: 'Node dimensions and size limits must be finite and valid.',
        ));
      }
      if (!_finite(node.origin.dx) || !_finite(node.origin.dy)) {
        diagnostics.add(FlowDiagnostic(
          code: 'invalid-node-origin',
          entityId: node.id,
          message: 'Node origin must contain finite coordinates.',
        ));
      }
      if (node.extent != null && !_validRect(node.extent!)) {
        diagnostics.add(FlowDiagnostic(
          code: 'invalid-node-extent',
          entityId: node.id,
          message: 'Node extent must have finite, ordered edges.',
        ));
      }
      final handleIds = <String>{};
      for (final handle in node.resolvedHandles) {
        if (!handleIds.add(handle.id)) {
          diagnostics.add(FlowDiagnostic(
            code: 'duplicate-handle-id',
            entityId: node.id,
            message: 'Handle id "${handle.id}" is duplicated on this node.',
          ));
        }
      }
    }

    for (final node in nodeList) {
      final parentId = node.parentId;
      if (parentId == node.id) {
        diagnostics.add(FlowDiagnostic(
          code: 'self-parent',
          entityId: node.id,
          message: 'A node cannot parent itself.',
        ));
      } else if (parentId != null && !nodesById.containsKey(parentId)) {
        diagnostics.add(FlowDiagnostic(
          code: 'missing-parent',
          entityId: node.id,
          message: 'Parent node "$parentId" does not exist.',
        ));
      }
      final visited = <String>{node.id};
      var current = parentId;
      while (current != null && nodesById[current] != null) {
        if (!visited.add(current)) {
          diagnostics.add(FlowDiagnostic(
            code: 'parent-cycle',
            entityId: node.id,
            message: 'Parent relationships must be acyclic.',
          ));
          break;
        }
        current = nodesById[current]?.parentId;
      }
    }

    for (final edge in edgeList) {
      if (edgesById.containsKey(edge.id)) {
        diagnostics.add(FlowDiagnostic(
          code: 'duplicate-edge-id',
          entityId: edge.id,
          message: 'Edge ids must be unique.',
        ));
      } else {
        edgesById[edge.id] = edge;
      }
      final source = nodesById[edge.sourceId];
      final target = nodesById[edge.targetId];
      if (source == null) {
        diagnostics.add(FlowDiagnostic(
          code: 'dangling-edge-source',
          entityId: edge.id,
          message: 'Source node "${edge.sourceId}" does not exist.',
        ));
      } else if (FlowGraphValidator._findHandle(
              source, edge.sourceHandleId, FlowHandleType.source) ==
          null) {
        diagnostics.add(FlowDiagnostic(
          code: 'missing-source-handle',
          entityId: edge.id,
          message: 'Source handle does not exist on "${edge.sourceId}".',
        ));
      }
      if (target == null) {
        diagnostics.add(FlowDiagnostic(
          code: 'dangling-edge-target',
          entityId: edge.id,
          message: 'Target node "${edge.targetId}" does not exist.',
        ));
      } else if (FlowGraphValidator._findHandle(
              target, edge.targetHandleId, edge.targetHandleType) ==
          null) {
        diagnostics.add(FlowDiagnostic(
          code: 'missing-target-handle',
          entityId: edge.id,
          message: 'Target handle does not exist on "${edge.targetId}".',
        ));
      }
      if (!_finite(edge.strokeWidth) ||
          edge.strokeWidth <= 0 ||
          !_finite(edge.interactionWidth) ||
          edge.interactionWidth < 0 ||
          !_finite(edge.curvature) ||
          !_finite(edge.stepPosition) ||
          !_finite(edge.cornerRadius) ||
          edge.controlPoints
              .any((point) => !_finite(point.dx) || !_finite(point.dy))) {
        diagnostics.add(FlowDiagnostic(
          code: 'invalid-edge-geometry',
          entityId: edge.id,
          message: 'Edge widths and path configuration must be finite.',
        ));
      }
      if (connectionMode == FlowConnectionMode.strict &&
          edge.targetHandleType == FlowHandleType.source) {
        diagnostics.add(FlowDiagnostic(
          code: 'loose-edge-in-strict-mode',
          severity: FlowDiagnosticSeverity.warning,
          entityId: edge.id,
          message: 'Source-to-source edges require loose connection mode.',
        ));
      }
    }

    if (viewport != null &&
        (!_finite(viewport.x) ||
            !_finite(viewport.y) ||
            !_finite(viewport.zoom) ||
            viewport.zoom <= 0)) {
      diagnostics.add(const FlowDiagnostic(
        code: 'invalid-viewport',
        message: 'Viewport translation must be finite and zoom must be > 0.',
      ));
    }
    if (minZoom != null && (!minZoom.isFinite || minZoom <= 0)) {
      diagnostics.add(const FlowDiagnostic(
        code: 'invalid-min-zoom',
        message: 'Minimum zoom must be finite and greater than zero.',
      ));
    }
    if (maxZoom != null && (!maxZoom.isFinite || maxZoom <= 0)) {
      diagnostics.add(const FlowDiagnostic(
        code: 'invalid-max-zoom',
        message: 'Maximum zoom must be finite and greater than zero.',
      ));
    }
    if (minZoom != null &&
        maxZoom != null &&
        minZoom.isFinite &&
        maxZoom.isFinite &&
        minZoom > maxZoom) {
      diagnostics.add(const FlowDiagnostic(
        code: 'inverted-zoom-range',
        message: 'Minimum zoom must not exceed maximum zoom.',
      ));
    }
    if (translateExtent != null && !_validRect(translateExtent)) {
      diagnostics.add(const FlowDiagnostic(
        code: 'invalid-translate-extent',
        message: 'Translate extent must have finite, ordered edges.',
      ));
    }
    return List.unmodifiable(diagnostics);
  }

  static FlowHandle? _findHandle<T>(
    FlowNode<T> node,
    String? handleId,
    FlowHandleType type,
  ) {
    for (final handle in node.resolvedHandles) {
      if (handle.type == type && (handleId == null || handle.id == handleId)) {
        return handle;
      }
    }
    return null;
  }

  static bool _finite(double value) => value.isFinite;

  static bool _validRect(Rect rect) =>
      rect.left.isFinite &&
      rect.top.isFinite &&
      rect.right.isFinite &&
      rect.bottom.isFinite &&
      rect.right >= rect.left &&
      rect.bottom >= rect.top;
}
