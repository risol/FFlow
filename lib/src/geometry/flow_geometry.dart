import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/widgets.dart';

import '../models/flow_edge.dart';
import '../models/flow_handle.dart';
import '../models/flow_node.dart';

/// Coordinate helpers shared by canvas interactions and renderers.
abstract final class FlowGeometry {
  static Rect nodesBounds<T>(Iterable<FlowNode<T>> nodes) {
    final nodeList = nodes.toList(growable: false);
    final byId = {for (final node in nodeList) node.id: node};
    Rect? bounds;
    for (final node in nodeList) {
      if (!isVisible(node, byId)) continue;
      final position = absolutePosition(node, byId);
      final rect = Rect.fromLTWH(
        position.dx,
        position.dy,
        node.width,
        node.height,
      );
      bounds = bounds == null ? rect : bounds.expandToInclude(rect);
    }
    return bounds ?? Rect.zero;
  }

  /// Resolve a node's position into canvas coordinates, following its parents.
  static Offset absolutePosition<T>(
    FlowNode<T> node,
    Map<String, FlowNode<T>> nodes,
  ) {
    var position = _topLeft(node.position, node);
    var parentId = node.parentId;
    final visited = <String>{node.id};
    while (parentId != null && visited.add(parentId)) {
      final parent = nodes[parentId];
      if (parent == null) break;
      position += _topLeft(parent.position, parent);
      parentId = parent.parentId;
    }
    return position;
  }

  /// Absolute top-left of [node] in graph coordinates.
  static Offset nodeAbsoluteTopLeft<T>(
    FlowNode<T> node,
    Map<String, FlowNode<T>> nodes,
  ) =>
      absolutePosition(node, nodes);

  /// Absolute anchor point represented by [FlowNode.position].
  static Offset nodeAbsoluteAnchor<T>(
    FlowNode<T> node,
    Map<String, FlowNode<T>> nodes,
  ) =>
      nodeAbsoluteTopLeft(node, nodes) +
      Offset(node.width * node.origin.dx, node.height * node.origin.dy);

  static Offset _topLeft<T>(Offset anchor, FlowNode<T> node) => Offset(
        anchor.dx - node.width * node.origin.dx,
        anchor.dy - node.height * node.origin.dy,
      );

  /// Clamp [position] so the complete node remains inside its explicit extent
  /// and/or parent bounds. Position and extent use parent-local coordinates.
  static Offset constrainNodePosition<T>(
      FlowNode<T> node, Offset position, Map<String, FlowNode<T>> nodes,
      {Rect? globalExtent}) {
    final parent = node.parentId == null ? null : nodes[node.parentId];
    final useParent = node.extentToParent && parent != null;
    final extent = node.parentId == null && globalExtent != null
        ? _intersectExtents(node.extent, globalExtent)
        : node.extent;
    if (!useParent && extent == null) return position;

    final left = math.max(extent?.left ?? double.negativeInfinity,
        useParent ? 0 : double.negativeInfinity);
    final top = math.max(extent?.top ?? double.negativeInfinity,
        useParent ? 0 : double.negativeInfinity);
    final right = math.min(extent?.right ?? double.infinity,
        useParent ? parent.width : double.infinity);
    final bottom = math.min(extent?.bottom ?? double.infinity,
        useParent ? parent.height : double.infinity);
    final minX = left;
    final minY = top;
    final maxX = math.max(minX, right - node.width);
    final maxY = math.max(minY, bottom - node.height);
    final topLeft = _topLeft(position, node);
    return Offset(
      topLeft.dx.clamp(minX, maxX).toDouble() + node.width * node.origin.dx,
      topLeft.dy.clamp(minY, maxY).toDouble() + node.height * node.origin.dy,
    );
  }

  static Rect? _intersectExtents(Rect? first, Rect? second) {
    if (first == null) return second;
    if (second == null) return first;
    final left = math.max(first.left, second.left);
    final top = math.max(first.top, second.top);
    final right = math.max(left, math.min(first.right, second.right));
    final bottom = math.max(top, math.min(first.bottom, second.bottom));
    return Rect.fromLTRB(left, top, right, bottom);
  }

  static Rect nodeRect<T>(
    FlowNode<T> node,
    Map<String, FlowNode<T>> nodes,
  ) {
    final position = absolutePosition(node, nodes);
    return Rect.fromLTWH(position.dx, position.dy, node.width, node.height);
  }

  static Offset inputAnchor<T>(FlowNode<T> node,
      {Map<String, FlowNode<T>>? nodes}) {
    final rect = nodes == null
        ? Rect.fromLTWH(
            node.position.dx - node.width * node.origin.dx,
            node.position.dy - node.height * node.origin.dy,
            node.width,
            node.height,
          )
        : nodeRect(node, nodes);
    return Offset(rect.left, rect.center.dy);
  }

  static Offset outputAnchor<T>(FlowNode<T> node,
      {Map<String, FlowNode<T>>? nodes}) {
    final rect = nodes == null
        ? Rect.fromLTWH(
            node.position.dx - node.width * node.origin.dx,
            node.position.dy - node.height * node.origin.dy,
            node.width,
            node.height,
          )
        : nodeRect(node, nodes);
    return Offset(rect.right, rect.center.dy);
  }

  static Offset handleAnchor<T>(FlowNode<T> node, FlowHandle handle,
      {Map<String, FlowNode<T>>? nodes}) {
    final rect = nodes == null
        ? Rect.fromLTWH(
            node.position.dx - node.width * node.origin.dx,
            node.position.dy - node.height * node.origin.dy,
            node.width,
            node.height,
          )
        : nodeRect(node, nodes);
    final offset = handle.offset.clamp(0.0, 1.0).toDouble();
    return switch (handle.position) {
      FlowHandlePosition.left =>
        Offset(rect.left, rect.top + rect.height * offset),
      FlowHandlePosition.right =>
        Offset(rect.right, rect.top + rect.height * offset),
      FlowHandlePosition.top =>
        Offset(rect.left + rect.width * offset, rect.top),
      FlowHandlePosition.bottom =>
        Offset(rect.left + rect.width * offset, rect.bottom),
    };
  }

  static bool isVisible<T>(
    FlowNode<T> node,
    Map<String, FlowNode<T>> nodes,
  ) {
    if (node.hidden) return false;
    var parentId = node.parentId;
    final visited = <String>{node.id};
    while (parentId != null && visited.add(parentId)) {
      final parent = nodes[parentId];
      if (parent == null) break;
      if (parent.hidden || parent.collapsed) return false;
      parentId = parent.parentId;
    }
    return true;
  }

  static FlowHandle? handleFor<T>(
      FlowNode<T> node, String? handleId, FlowHandleType type) {
    for (final handle in node.resolvedHandles) {
      if (handle.type == type && (handleId == null || handle.id == handleId)) {
        return handle;
      }
    }
    return null;
  }

  static Offset? edgeSource<T>(FlowEdge edge, Map<String, FlowNode<T>> nodes) {
    final node = nodes[edge.sourceId];
    final handle = node == null
        ? null
        : handleFor(node, edge.sourceHandleId, FlowHandleType.source);
    return node == null || !isVisible(node, nodes) || handle == null
        ? null
        : edge.floating && nodes[edge.targetId] != null
            ? floatingAnchor(node, nodes[edge.targetId]!, nodes: nodes)
            : handleAnchor(node, handle, nodes: nodes);
  }

  static Offset? edgeTarget<T>(FlowEdge edge, Map<String, FlowNode<T>> nodes) {
    final node = nodes[edge.targetId];
    final handle = node == null
        ? null
        : handleFor(node, edge.targetHandleId, edge.targetHandleType);
    return node == null || !isVisible(node, nodes) || handle == null
        ? null
        : edge.floating && nodes[edge.sourceId] != null
            ? floatingAnchor(node, nodes[edge.sourceId]!, nodes: nodes)
            : handleAnchor(node, handle, nodes: nodes);
  }

  /// Returns the point where the ray from a node's center toward [other]
  /// intersects its rectangular boundary.
  static Offset floatingAnchor<T>(
    FlowNode<T> node,
    FlowNode<T> other, {
    required Map<String, FlowNode<T>> nodes,
  }) {
    final rect = nodeRect(node, nodes);
    final delta = nodeRect(other, nodes).center - rect.center;
    if (delta == Offset.zero) return rect.centerRight;
    final halfWidth = math.max(rect.width / 2, 1e-9);
    final halfHeight = math.max(rect.height / 2, 1e-9);
    final scale = 1 /
        math.max(
          delta.dx.abs() / halfWidth,
          delta.dy.abs() / halfHeight,
        );
    return rect.center + delta * scale;
  }

  static Path edgePath(
    FlowEdge edge,
    Offset start,
    Offset end, {
    FlowHandlePosition sourcePosition = FlowHandlePosition.right,
    FlowHandlePosition targetPosition = FlowHandlePosition.left,
  }) {
    final path = Path()..moveTo(start.dx, start.dy);
    final stepPosition = edge.stepPosition.clamp(0.05, 0.95).toDouble();
    switch (edge.type) {
      case FlowEdgeType.straight:
        path.lineTo(end.dx, end.dy);
      case FlowEdgeType.step:
      case FlowEdgeType.smoothStep:
        final sourceDirection = _direction(sourcePosition);
        final targetDirection = _direction(targetPosition);
        final controlDistance =
            ((end - start).distance * 0.25).clamp(32.0, 120.0).toDouble();
        final sourceLead = start + sourceDirection * controlDistance;
        final targetLead = end + targetDirection * controlDistance;
        final sourceIsHorizontal = sourceDirection.dx != 0;
        final targetIsHorizontal = targetDirection.dx != 0;
        final points = <Offset>[start, sourceLead];
        if (sourceIsHorizontal && targetIsHorizontal) {
          final middleX =
              sourceLead.dx + (targetLead.dx - sourceLead.dx) * stepPosition;
          points
            ..add(Offset(middleX, sourceLead.dy))
            ..add(Offset(middleX, targetLead.dy));
        } else if (!sourceIsHorizontal && !targetIsHorizontal) {
          final middleY =
              sourceLead.dy + (targetLead.dy - sourceLead.dy) * stepPosition;
          points
            ..add(Offset(sourceLead.dx, middleY))
            ..add(Offset(targetLead.dx, middleY));
        } else if (sourceIsHorizontal) {
          points.add(Offset(targetLead.dx, sourceLead.dy));
        } else {
          points.add(Offset(sourceLead.dx, targetLead.dy));
        }
        points
          ..add(targetLead)
          ..add(end);
        if (edge.type == FlowEdgeType.step) {
          for (final point in points.skip(1)) {
            path.lineTo(point.dx, point.dy);
          }
        } else {
          _appendRoundedPolyline(path, points, edge.cornerRadius);
        }
      case FlowEdgeType.bezier:
      case FlowEdgeType.simpleBezier:
        final distance = ((end - start).distance * edge.curvature)
            .clamp(36.0, 190.0)
            .toDouble();
        final sourceControl = start + _direction(sourcePosition) * distance;
        final targetControl = end + _direction(targetPosition) * distance;
        path.cubicTo(
          sourceControl.dx,
          sourceControl.dy,
          targetControl.dx,
          targetControl.dy,
          end.dx,
          end.dy,
        );
    }
    return path;
  }

  static Path edgePathFor<T>(FlowEdge edge, Map<String, FlowNode<T>> nodes) {
    final source = nodes[edge.sourceId];
    final target = nodes[edge.targetId];
    if (source == null || target == null) return Path();
    final sourceHandle =
        handleFor(source, edge.sourceHandleId, FlowHandleType.source);
    final targetHandle =
        handleFor(target, edge.targetHandleId, edge.targetHandleType);
    if (sourceHandle == null || targetHandle == null) return Path();
    final start = edgeSource(edge, nodes);
    final end = edgeTarget(edge, nodes);
    if (start == null || end == null) return Path();
    final sourcePosition = edge.floating
        ? _boundarySide(nodeRect(source, nodes), start)
        : sourceHandle.position;
    final targetPosition = edge.floating
        ? _boundarySide(nodeRect(target, nodes), end)
        : targetHandle.position;
    return edgePath(
      edge,
      start,
      end,
      sourcePosition: sourcePosition,
      targetPosition: targetPosition,
    );
  }

  /// Resolves an edge's complete geometry once for paint, labels and hit tests.
  static FlowEdgePathResult? edgePathResult<T>(
    FlowEdge edge,
    Map<String, FlowNode<T>> nodes,
  ) {
    final source = nodes[edge.sourceId];
    final target = nodes[edge.targetId];
    final start = edgeSource(edge, nodes);
    final end = edgeTarget(edge, nodes);
    if (source == null || target == null || start == null || end == null) {
      return null;
    }
    final sourceHandle =
        handleFor(source, edge.sourceHandleId, FlowHandleType.source);
    final targetHandle =
        handleFor(target, edge.targetHandleId, edge.targetHandleType);
    if (sourceHandle == null || targetHandle == null) return null;
    final sourceSide = edge.floating
        ? _boundarySide(nodeRect(source, nodes), start)
        : sourceHandle.position;
    final targetSide = edge.floating
        ? _boundarySide(nodeRect(target, nodes), end)
        : targetHandle.position;
    final path = edge.controlPoints.isEmpty
        ? edgePath(
            edge,
            start,
            end,
            sourcePosition: sourceSide,
            targetPosition: targetSide,
          )
        : Path()
      ..moveTo(start.dx, start.dy)
      ..addPolygon(
        [for (final point in edge.controlPoints) point, end],
        false,
      );
    final metrics = path.computeMetrics().toList(growable: false);
    final labelPosition = metrics.isEmpty || metrics.first.length == 0
        ? start
        : metrics.first
                .getTangentForOffset(metrics.first.length / 2)
                ?.position ??
            start;
    return FlowEdgePathResult(
      path: path,
      bounds: path.getBounds(),
      labelPosition: labelPosition,
      sourceAnchor: start,
      targetAnchor: end,
      sourceSide: sourceSide,
      targetSide: targetSide,
      metrics: metrics,
    );
  }

  static FlowHandlePosition _boundarySide(Rect rect, Offset point) {
    final delta = point - rect.center;
    final horizontalDistance = delta.dx.abs() / math.max(rect.width, 1);
    final verticalDistance = delta.dy.abs() / math.max(rect.height, 1);
    if (horizontalDistance >= verticalDistance) {
      return delta.dx < 0 ? FlowHandlePosition.left : FlowHandlePosition.right;
    }
    return delta.dy < 0 ? FlowHandlePosition.top : FlowHandlePosition.bottom;
  }

  static Offset _direction(FlowHandlePosition position) => switch (position) {
        FlowHandlePosition.left => const Offset(-1, 0),
        FlowHandlePosition.right => const Offset(1, 0),
        FlowHandlePosition.top => const Offset(0, -1),
        FlowHandlePosition.bottom => const Offset(0, 1),
      };

  static void _appendRoundedPolyline(
      Path path, List<Offset> points, double cornerRadius) {
    if (points.length < 2) return;
    for (var index = 1; index < points.length - 1; index++) {
      final previous = points[index - 1];
      final corner = points[index];
      final next = points[index + 1];
      final incomingLength = (corner - previous).distance;
      final outgoingLength = (next - corner).distance;
      final radius =
          math.min(cornerRadius, math.min(incomingLength, outgoingLength) / 2);
      if (radius <= 0.01) {
        path.lineTo(corner.dx, corner.dy);
        continue;
      }
      final before = corner - (corner - previous) / incomingLength * radius;
      final after = corner + (next - corner) / outgoingLength * radius;
      path
        ..lineTo(before.dx, before.dy)
        ..quadraticBezierTo(corner.dx, corner.dy, after.dx, after.dy);
    }
    path.lineTo(points.last.dx, points.last.dy);
  }

  static Offset pointAlongPath(Path path, double t) {
    final metrics = path.computeMetrics().toList(growable: false);
    if (metrics.isEmpty) return Offset.zero;
    final metric = metrics.first;
    final tangent =
        metric.getTangentForOffset(metric.length * t.clamp(0.0, 1.0));
    return tangent?.position ?? Offset.zero;
  }

  static double distanceToPath(Path path, Offset point) {
    var distance = double.infinity;
    for (final metric in path.computeMetrics()) {
      final steps = (metric.length / 8).ceil().clamp(1, 400);
      for (var index = 0; index <= steps; index++) {
        final tangent =
            metric.getTangentForOffset(metric.length * index / steps);
        if (tangent != null) {
          distance = (tangent.position - point).distance < distance
              ? (tangent.position - point).distance
              : distance;
        }
      }
    }
    return distance;
  }

  /// Tests a path against a rectangle using sampled segments after a bounds
  /// broad phase. This also catches a long edge that crosses the box with both
  /// endpoints outside it.
  static bool pathIntersectsRect(Path path, Rect rect, {double step = 4}) {
    if (!path.getBounds().overlaps(rect)) return false;
    for (final metric in path.computeMetrics()) {
      final count = (metric.length / math.max(step, 0.5)).ceil().clamp(1, 2048);
      Offset? previous;
      for (var index = 0; index <= count; index++) {
        final point =
            metric.getTangentForOffset(metric.length * index / count)?.position;
        if (point == null) continue;
        if (rect.contains(point) ||
            (previous != null &&
                _segmentIntersectsRect(previous, point, rect))) {
          return true;
        }
        previous = point;
      }
    }
    return false;
  }

  /// Finds the closest x/y alignment between [movingBounds] and target node
  /// rectangles. Corrections are returned in graph coordinates.
  static FlowAlignmentGuides findAlignmentGuides(
    Rect movingBounds,
    Iterable<Rect> targets, {
    required double threshold,
  }) {
    double? bestX;
    double? bestY;
    double? vertical;
    double? horizontal;
    final movingX = [
      movingBounds.left,
      movingBounds.center.dx,
      movingBounds.right
    ];
    final movingY = [
      movingBounds.top,
      movingBounds.center.dy,
      movingBounds.bottom
    ];
    for (final target in targets) {
      final targetX = [target.left, target.center.dx, target.right];
      final targetY = [target.top, target.center.dy, target.bottom];
      for (final from in movingX) {
        for (final to in targetX) {
          final delta = to - from;
          if (delta.abs() <= threshold &&
              (bestX == null || delta.abs() < bestX.abs())) {
            bestX = delta;
            vertical = to;
          }
        }
      }
      for (final from in movingY) {
        for (final to in targetY) {
          final delta = to - from;
          if (delta.abs() <= threshold &&
              (bestY == null || delta.abs() < bestY.abs())) {
            bestY = delta;
            horizontal = to;
          }
        }
      }
    }
    return FlowAlignmentGuides(
      correction: Offset(bestX ?? 0, bestY ?? 0),
      vertical: vertical,
      horizontal: horizontal,
    );
  }

  static bool _segmentIntersectsRect(Offset a, Offset b, Rect rect) {
    var t0 = 0.0;
    var t1 = 1.0;
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final p = [-dx, dx, -dy, dy];
    final q = [
      a.dx - rect.left,
      rect.right - a.dx,
      a.dy - rect.top,
      rect.bottom - a.dy
    ];
    for (var index = 0; index < 4; index++) {
      if (p[index] == 0) {
        if (q[index] < 0) return false;
        continue;
      }
      final ratio = q[index] / p[index];
      if (p[index] < 0) {
        t0 = math.max(t0, ratio);
      } else {
        t1 = math.min(t1, ratio);
      }
      if (t0 > t1) return false;
    }
    return true;
  }

  static FlowNode<T>? closestInputNode<T>({
    required Iterable<FlowNode<T>> nodes,
    required String sourceId,
    required Offset point,
    double maxDistance = double.infinity,
  }) {
    final nodeList = nodes.toList(growable: false);
    final nodesById = {for (final node in nodeList) node.id: node};
    FlowNode<T>? closest;
    var closestDistance = maxDistance;
    for (final node in nodeList) {
      if (node.id == sourceId ||
          !isVisible(node, nodesById) ||
          !node.hasInput) {
        continue;
      }
      final distance = (inputAnchor(node, nodes: nodesById) - point).distance;
      if (distance < closestDistance) {
        closest = node;
        closestDistance = distance;
      }
    }
    return closest;
  }
}

/// Cached-ready edge geometry consumed by the painter and interaction layer.
class FlowEdgePathResult {
  const FlowEdgePathResult({
    required this.path,
    required this.bounds,
    required this.labelPosition,
    required this.sourceAnchor,
    required this.targetAnchor,
    required this.sourceSide,
    required this.targetSide,
    required this.metrics,
  });

  final Path path;
  final Rect bounds;
  final Offset labelPosition;
  final Offset sourceAnchor;
  final Offset targetAnchor;
  final FlowHandlePosition sourceSide;
  final FlowHandlePosition targetSide;
  final List<PathMetric> metrics;
}

class FlowAlignmentGuides {
  const FlowAlignmentGuides({
    required this.correction,
    this.vertical,
    this.horizontal,
  });

  final Offset correction;
  final double? vertical;
  final double? horizontal;
}
