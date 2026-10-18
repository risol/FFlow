import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../models/flow_edge.dart';
import '../models/flow_node.dart';
import 'flow_extension_adapters.dart';

/// Deterministic force-directed layout for root-level nodes.
///
/// Existing nodes can be pinned through [fixedNodeIds] or the `fixedNodeIds`
/// layout option. This supports incremental placement: keep the current node
/// ids fixed and pass newly added nodes in the graph to arrange them around the
/// existing layout. Nodes inside parent groups are left unchanged.
class FlowForceLayoutEngine<T> implements FlowLayoutEngine<T> {
  const FlowForceLayoutEngine({
    this.iterations = 180,
    this.nodeSpacing = 36,
    this.edgeLength = 190,
    this.repulsion = 9000,
    this.gravity = 0.012,
    this.maxStep = 22,
    this.fixedNodeIds = const {},
  })  : assert(iterations > 0),
        assert(nodeSpacing >= 0),
        assert(edgeLength > 0),
        assert(repulsion >= 0),
        assert(gravity >= 0),
        assert(maxStep > 0);

  final int iterations;
  final double nodeSpacing;
  final double edgeLength;
  final double repulsion;
  final double gravity;
  final double maxStep;
  final Set<String> fixedNodeIds;

  @override
  FlowLayoutResult layout({
    required List<FlowNode<T>> nodes,
    required List<FlowEdge> edges,
    Map<String, Object?> options = const {},
  }) {
    final movableNodes = nodes
        .where((node) => !node.hidden && node.parentId == null)
        .toList(growable: false);
    if (movableNodes.length < 2) {
      return FlowLayoutResult({
        for (final node in movableNodes) node.id: node.position,
      });
    }

    final resolvedIterations = _positiveInt(
      'iterations',
      options['iterations'],
      iterations,
    );
    final resolvedNodeSpacing = _nonNegativeDouble(
      'nodeSpacing',
      options['nodeSpacing'],
      nodeSpacing,
    );
    final resolvedEdgeLength = _positiveDouble(
      'edgeLength',
      options['edgeLength'],
      edgeLength,
    );
    final resolvedRepulsion = _nonNegativeDouble(
      'repulsion',
      options['repulsion'],
      repulsion,
    );
    final resolvedGravity = _nonNegativeDouble(
      'gravity',
      options['gravity'],
      gravity,
    );
    final resolvedMaxStep =
        _positiveDouble('maxStep', options['maxStep'], maxStep);
    final fixedIds = <String>{
      ...fixedNodeIds,
      if (options['fixedNodeIds'] case final Iterable<Object?> ids)
        for (final id in ids)
          if (id is String) id,
    };
    final positions = <Offset>[];
    final velocities = List<Offset>.filled(movableNodes.length, Offset.zero);
    for (final node in movableNodes) {
      final topLeft = Offset(
        node.position.dx - node.width * node.origin.dx,
        node.position.dy - node.height * node.origin.dy,
      );
      positions.add(topLeft + Offset(node.width / 2, node.height / 2));
    }

    if (_allCoincident(positions)) {
      for (var index = 0; index < movableNodes.length; index++) {
        final node = movableNodes[index];
        if (fixedIds.contains(node.id)) continue;
        final angle = _stableHash(node.id) * math.pi * 2;
        final radius = math.max(
          resolvedEdgeLength / 2,
          resolvedNodeSpacing + math.max(node.width, node.height),
        );
        positions[index] += Offset(math.cos(angle), math.sin(angle)) * radius;
      }
    }

    final center = _mean(positions);
    final indexById = {
      for (var index = 0; index < movableNodes.length; index++)
        movableNodes[index].id: index,
    };
    final forceEdges = <(int, int)>{};
    for (final edge in edges) {
      final source = indexById[edge.sourceId];
      final target = indexById[edge.targetId];
      if (source != null && target != null && source != target) {
        forceEdges.add((source, target));
      }
    }

    final pairCount = movableNodes.length * (movableNodes.length - 1) ~/ 2;
    final iterationCount = math.min(
      resolvedIterations,
      math.max(12, 4000000 ~/ math.max(1, pairCount)),
    );
    for (var iteration = 0; iteration < iterationCount; iteration++) {
      final forces = List<Offset>.filled(movableNodes.length, Offset.zero);
      for (var first = 0; first < movableNodes.length; first++) {
        for (var second = first + 1; second < movableNodes.length; second++) {
          if (fixedIds.contains(movableNodes[first].id) &&
              fixedIds.contains(movableNodes[second].id)) {
            continue;
          }
          final delta = positions[second] - positions[first];
          final distance = math.max(1.0, delta.distance);
          final direction = delta.distanceSquared == 0
              ? _pairDirection(movableNodes[first].id, movableNodes[second].id)
              : delta / distance;
          final firstNode = movableNodes[first];
          final secondNode = movableNodes[second];
          final requiredX =
              (firstNode.width + secondNode.width) / 2 + resolvedNodeSpacing;
          final requiredY =
              (firstNode.height + secondNode.height) / 2 + resolvedNodeSpacing;
          final overlapX = requiredX - delta.dx.abs();
          final overlapY = requiredY - delta.dy.abs();
          final collisionForce = overlapX > 0 && overlapY > 0
              ? math.min(overlapX, overlapY) * 0.16 + resolvedRepulsion / 1000
              : resolvedRepulsion / (distance * distance);
          final force = direction * collisionForce;
          forces[first] -= force;
          forces[second] += force;
        }
      }
      for (final (source, target) in forceEdges) {
        final delta = positions[target] - positions[source];
        final distance = math.max(1.0, delta.distance);
        final spring =
            delta / distance * ((distance - resolvedEdgeLength) * 0.018);
        forces[source] += spring;
        forces[target] -= spring;
      }

      final cooling = 1 - iteration / iterationCount;
      for (var index = 0; index < movableNodes.length; index++) {
        if (fixedIds.contains(movableNodes[index].id)) {
          velocities[index] = Offset.zero;
          continue;
        }
        final gravityForce = (center - positions[index]) * resolvedGravity;
        final velocity =
            (velocities[index] * 0.72 + forces[index] + gravityForce) * cooling;
        final length = velocity.distance;
        velocities[index] = length > resolvedMaxStep
            ? velocity / length * resolvedMaxStep
            : velocity;
        positions[index] += velocities[index];
      }
    }
    _resolveOverlaps(
      movableNodes,
      positions,
      fixedIds,
      resolvedNodeSpacing,
    );

    return FlowLayoutResult({
      for (var index = 0; index < movableNodes.length; index++)
        movableNodes[index].id: Offset(
          positions[index].dx -
              movableNodes[index].width / 2 +
              movableNodes[index].width * movableNodes[index].origin.dx,
          positions[index].dy -
              movableNodes[index].height / 2 +
              movableNodes[index].height * movableNodes[index].origin.dy,
        ),
    });
  }

  void _resolveOverlaps(
    List<FlowNode<T>> nodes,
    List<Offset> positions,
    Set<String> fixedIds,
    double spacing,
  ) {
    for (var pass = 0; pass < 12; pass++) {
      var moved = false;
      for (var first = 0; first < nodes.length; first++) {
        for (var second = first + 1; second < nodes.length; second++) {
          final delta = positions[second] - positions[first];
          final requiredX =
              (nodes[first].width + nodes[second].width) / 2 + spacing;
          final requiredY =
              (nodes[first].height + nodes[second].height) / 2 + spacing;
          final overlapX = requiredX - delta.dx.abs();
          final overlapY = requiredY - delta.dy.abs();
          if (overlapX <= 0 || overlapY <= 0) continue;
          final firstFixed = fixedIds.contains(nodes[first].id);
          final secondFixed = fixedIds.contains(nodes[second].id);
          if (firstFixed && secondFixed) continue;
          final axisX = overlapX <= overlapY;
          final sign = axisX
              ? (delta.dx == 0 ? 1.0 : delta.dx.sign)
              : (delta.dy == 0 ? 1.0 : delta.dy.sign);
          final separation = (axisX ? overlapX : overlapY) + 0.5;
          final offset = axisX
              ? Offset(sign * separation, 0)
              : Offset(0, sign * separation);
          if (firstFixed) {
            positions[second] += offset;
          } else if (secondFixed) {
            positions[first] -= offset;
          } else {
            positions[first] -= offset / 2;
            positions[second] += offset / 2;
          }
          moved = true;
        }
      }
      if (!moved) break;
    }
  }

  bool _allCoincident(List<Offset> positions) =>
      positions.every((point) => point == positions.first);

  Offset _mean(List<Offset> positions) {
    final total = positions.fold(Offset.zero, (sum, point) => sum + point);
    return total / positions.length.toDouble();
  }

  double _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0x7fffffff;
    }
    return hash / 0x7fffffff;
  }

  Offset _pairDirection(String firstId, String secondId) {
    final angle = _stableHash('$firstId\u0000$secondId') * math.pi * 2;
    return Offset(math.cos(angle), math.sin(angle));
  }

  int _positiveInt(String name, Object? value, int fallback) {
    if (value == null) return fallback;
    if (value is int && value > 0) return value;
    throw ArgumentError.value(value, 'options[$name]');
  }

  double _positiveDouble(String name, Object? value, double fallback) {
    if (value == null) return fallback;
    if (value is num && value.isFinite && value > 0) return value.toDouble();
    throw ArgumentError.value(value, 'options[$name]');
  }

  double _nonNegativeDouble(String name, Object? value, double fallback) {
    if (value == null) return fallback;
    if (value is num && value.isFinite && value >= 0) return value.toDouble();
    throw ArgumentError.value(value, 'options[$name]');
  }
}
