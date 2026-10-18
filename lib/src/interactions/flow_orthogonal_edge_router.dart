import 'dart:math' as math;

import 'package:flutter/painting.dart';

import '../models/flow_edge.dart';
import 'flow_extension_adapters.dart';

/// A deterministic Manhattan router that searches around rectangular obstacles.
///
/// Pass the edge's resolved handle anchors when available. Without anchors, the
/// router chooses the facing side centers based on the relative node centers.
/// Obstacles should exclude the source and target nodes. Returned control points
/// are interior bends suitable for [FlowEdge.controlPoints].
class FlowOrthogonalEdgeRouter implements FlowEdgeRouter {
  const FlowOrthogonalEdgeRouter({
    this.clearance = 16,
    this.bendPenalty = 24,
    this.maxObstacles = 32,
  })  : assert(clearance >= 0),
        assert(bendPenalty >= 0),
        assert(maxObstacles > 0);

  final double clearance;
  final double bendPenalty;
  final int maxObstacles;

  @override
  FlowEdgeRoute route({
    required FlowEdge edge,
    required Rect sourceBounds,
    required Rect targetBounds,
    required List<Rect> obstacles,
    Offset? sourceAnchor,
    Offset? targetAnchor,
    Map<String, Object?> options = const {},
  }) {
    final routeClearance = _optionDouble('clearance', options, clearance);
    final routeBendPenalty = _optionDouble('bendPenalty', options, bendPenalty);
    final routeMaxObstacles = _optionInt('maxObstacles', options, maxObstacles);
    final source =
        sourceAnchor ?? _defaultAnchor(sourceBounds, targetBounds, true);
    final target =
        targetAnchor ?? _defaultAnchor(sourceBounds, targetBounds, false);
    if (source == target) return FlowEdgeRoute(const []);
    final escapeDistance = math.max(1.0, routeClearance);
    final start = _escapePoint(sourceBounds, source, escapeDistance);
    final end = _escapePoint(targetBounds, target, escapeDistance);

    final corridor = Rect.fromPoints(start, end).inflate(
      math.max(64.0, routeClearance * 4),
    );
    final relevant = obstacles
        .where((rect) => rect.isFinite && rect.overlaps(corridor))
        .toList()
      ..sort((a, b) => _distanceToSegment(a.center, start, end)
          .compareTo(_distanceToSegment(b.center, start, end)));
    final selected = relevant.take(routeMaxObstacles).toList(growable: false);
    final expanded = [
      for (final rect in [sourceBounds, targetBounds])
        Rect.fromLTRB(
          rect.left - routeClearance,
          rect.top - routeClearance,
          rect.right + routeClearance,
          rect.bottom + routeClearance,
        ),
      for (final rect in selected)
        Rect.fromLTRB(
          rect.left - routeClearance,
          rect.top - routeClearance,
          rect.right + routeClearance,
          rect.bottom + routeClearance,
        ),
    ];
    final xs = <double>{start.dx, end.dx, corridor.left, corridor.right};
    final ys = <double>{start.dy, end.dy, corridor.top, corridor.bottom};
    for (final rect in expanded) {
      xs
        ..add(rect.left)
        ..add(rect.right);
      ys
        ..add(rect.top)
        ..add(rect.bottom);
    }
    final xValues = xs.toList()..sort();
    final yValues = ys.toList()..sort();
    final startX = xValues.indexOf(start.dx);
    final endX = xValues.indexOf(end.dx);
    final startY = yValues.indexOf(start.dy);
    final endY = yValues.indexOf(end.dy);
    final width = xValues.length;
    final height = yValues.length;
    final pointCount = width * height;
    final stateCount = pointCount * 3;
    final distances = List<double>.filled(stateCount, double.infinity);
    final previous = List<int>.filled(stateCount, -1);
    final queue = _RouteMinHeap();
    final startVertex = startY * width + startX;
    final endVertex = endY * width + endX;
    final initialState = startVertex * 3;
    distances[initialState] = 0;
    queue.add(initialState, _heuristic(start, end));

    var endState = -1;
    while (queue.isNotEmpty) {
      final item = queue.removeFirst();
      if (item.priority >
          distances[item.state] +
              _heuristic(
                  _pointForState(item.state, width, xValues, yValues), end) +
              0.0001) {
        continue;
      }
      final vertex = item.state ~/ 3;
      final direction = item.state % 3;
      if (vertex == endVertex) {
        endState = item.state;
        break;
      }
      final xIndex = vertex % width;
      final yIndex = vertex ~/ width;
      final current = Offset(xValues[xIndex], yValues[yIndex]);
      for (final (nextX, nextY, nextDirection) in <(int, int, int)>[
        if (xIndex > 0) (xIndex - 1, yIndex, 1),
        if (xIndex + 1 < width) (xIndex + 1, yIndex, 1),
        if (yIndex > 0) (xIndex, yIndex - 1, 2),
        if (yIndex + 1 < height) (xIndex, yIndex + 1, 2),
      ]) {
        final next = Offset(xValues[nextX], yValues[nextY]);
        if (!_segmentIsClear(current, next, expanded)) continue;
        final nextVertex = nextY * width + nextX;
        final nextState = nextVertex * 3 + nextDirection;
        final length = (next - current).distance;
        final turnCost = direction != 0 && direction != nextDirection
            ? routeBendPenalty
            : 0.0;
        final candidate = distances[item.state] + length + turnCost;
        if (candidate >= distances[nextState]) continue;
        distances[nextState] = candidate;
        previous[nextState] = item.state;
        queue.add(nextState, candidate + _heuristic(next, end));
      }
    }

    if (endState < 0) {
      final fallback = _fallbackRoute(start, end, expanded);
      return FlowEdgeRoute(_removeCollinear(
        source,
        [start, ...fallback, end],
        target,
      ));
    }
    final points = <Offset>[];
    var state = endState;
    while (state != initialState && state >= 0) {
      final vertex = state ~/ 3;
      points.add(Offset(xValues[vertex % width], yValues[vertex ~/ width]));
      state = previous[state];
    }
    final route = points.reversed.toList();
    if (route.isNotEmpty) route.removeLast(); // Drop the target anchor.
    final inner = _removeCollinear(start, route, end);
    return FlowEdgeRoute(
        _removeCollinear(source, [start, ...inner, end], target));
  }

  Offset _escapePoint(Rect bounds, Offset anchor, double distance) {
    const tolerance = 0.001;
    if ((anchor.dx - bounds.left).abs() <= tolerance) {
      return anchor + Offset(-distance, 0);
    }
    if ((anchor.dx - bounds.right).abs() <= tolerance) {
      return anchor + Offset(distance, 0);
    }
    if ((anchor.dy - bounds.top).abs() <= tolerance) {
      return anchor + Offset(0, -distance);
    }
    if ((anchor.dy - bounds.bottom).abs() <= tolerance) {
      return anchor + Offset(0, distance);
    }
    final distances = [
      (anchor.dx - bounds.left).abs(),
      (anchor.dx - bounds.right).abs(),
      (anchor.dy - bounds.top).abs(),
      (anchor.dy - bounds.bottom).abs(),
    ];
    final side = distances.indexOf(distances.reduce(math.min));
    return switch (side) {
      0 => anchor + Offset(-distance, 0),
      1 => anchor + Offset(distance, 0),
      2 => anchor + Offset(0, -distance),
      _ => anchor + Offset(0, distance),
    };
  }

  Offset _defaultAnchor(Rect source, Rect target, bool isSource) {
    final delta = target.center - source.center;
    final horizontal = delta.dx.abs() >= delta.dy.abs();
    if (horizontal) {
      final sourceOnRight = delta.dx >= 0;
      final useRight = isSource ? sourceOnRight : !sourceOnRight;
      final rect = isSource ? source : target;
      return Offset(useRight ? rect.right : rect.left, rect.center.dy);
    }
    final sourceOnBottom = delta.dy >= 0;
    final useBottom = isSource ? sourceOnBottom : !sourceOnBottom;
    final rect = isSource ? source : target;
    return Offset(rect.center.dx, useBottom ? rect.bottom : rect.top);
  }

  double _optionDouble(
    String key,
    Map<String, Object?> options,
    double fallback,
  ) {
    final value = options[key];
    if (value == null) return fallback;
    if (value is num && value.isFinite && value >= 0) return value.toDouble();
    throw ArgumentError.value(value, 'options[$key]');
  }

  int _optionInt(String key, Map<String, Object?> options, int fallback) {
    final value = options[key];
    if (value == null) return fallback;
    if (value is int && value > 0) return value;
    throw ArgumentError.value(value, 'options[$key]');
  }

  double _heuristic(Offset point, Offset end) =>
      (point.dx - end.dx).abs() + (point.dy - end.dy).abs();

  Offset _pointForState(
    int state,
    int width,
    List<double> xs,
    List<double> ys,
  ) {
    final vertex = state ~/ 3;
    return Offset(xs[vertex % width], ys[vertex ~/ width]);
  }

  bool _segmentIsClear(Offset a, Offset b, List<Rect> obstacles) {
    if (a.dx == b.dx) {
      final top = math.min(a.dy, b.dy);
      final bottom = math.max(a.dy, b.dy);
      for (final rect in obstacles) {
        if (a.dx > rect.left &&
            a.dx < rect.right &&
            top < rect.bottom &&
            bottom > rect.top) {
          return false;
        }
      }
      return true;
    }
    final left = math.min(a.dx, b.dx);
    final right = math.max(a.dx, b.dx);
    for (final rect in obstacles) {
      if (a.dy > rect.top &&
          a.dy < rect.bottom &&
          left < rect.right &&
          right > rect.left) {
        return false;
      }
    }
    return true;
  }

  List<Offset> _fallbackRoute(Offset start, Offset end, List<Rect> obstacles) {
    final horizontalFirst = [start, Offset(end.dx, start.dy), end];
    final verticalFirst = [start, Offset(start.dx, end.dy), end];
    final horizontalClear = _pathIsClear(horizontalFirst, obstacles);
    final verticalClear = _pathIsClear(verticalFirst, obstacles);
    if (horizontalClear && verticalClear) {
      final firstLength = _pathLength(horizontalFirst);
      final secondLength = _pathLength(verticalFirst);
      return firstLength <= secondLength
          ? horizontalFirst.skip(1).take(1).toList()
          : verticalFirst.skip(1).take(1).toList();
    }
    if (horizontalClear) return horizontalFirst.skip(1).take(1).toList();
    if (verticalClear) return verticalFirst.skip(1).take(1).toList();
    return [
      Offset((start.dx + end.dx) / 2, start.dy),
      Offset((start.dx + end.dx) / 2, end.dy)
    ];
  }

  bool _pathIsClear(List<Offset> points, List<Rect> obstacles) {
    for (var index = 1; index < points.length; index++) {
      if (!_segmentIsClear(points[index - 1], points[index], obstacles)) {
        return false;
      }
    }
    return true;
  }

  double _pathLength(List<Offset> points) {
    var length = 0.0;
    for (var index = 1; index < points.length; index++) {
      length += (points[index] - points[index - 1]).distance;
    }
    return length;
  }

  List<Offset> _removeCollinear(
    Offset start,
    List<Offset> route,
    Offset end,
  ) {
    final points = <Offset>[start, ...route, end];
    if (points.length <= 2) return const [];
    final simplified = <Offset>[points.first];
    for (var i = 1; i < points.length - 1; i++) {
      final before = simplified.last;
      final point = points[i];
      final after = points[i + 1];
      if (before.dx == point.dx && point.dx == after.dx ||
          before.dy == point.dy && point.dy == after.dy) {
        continue;
      }
      simplified.add(point);
    }
    simplified.add(points.last);
    return simplified.skip(1).take(simplified.length - 2).toList();
  }

  double _distanceToSegment(Offset point, Offset start, Offset end) {
    final delta = end - start;
    final lengthSquared = delta.distanceSquared;
    if (lengthSquared == 0) return (point - start).distance;
    final projection =
        (((point - start).dx * delta.dx + (point - start).dy * delta.dy) /
                lengthSquared)
            .clamp(0.0, 1.0);
    return (point - (start + delta * projection)).distance;
  }
}

class _RouteQueueEntry {
  const _RouteQueueEntry(this.state, this.priority);

  final int state;
  final double priority;
}

class _RouteMinHeap {
  final List<_RouteQueueEntry> _values = [];

  bool get isNotEmpty => _values.isNotEmpty;

  void add(int state, double priority) {
    final entry = _RouteQueueEntry(state, priority);
    _values.add(entry);
    var index = _values.length - 1;
    while (index > 0) {
      final parent = (index - 1) ~/ 2;
      if (_values[parent].priority <= entry.priority) break;
      _values[index] = _values[parent];
      index = parent;
    }
    _values[index] = entry;
  }

  _RouteQueueEntry removeFirst() {
    final first = _values.first;
    final last = _values.removeLast();
    if (_values.isEmpty) return first;
    var index = 0;
    while (true) {
      final left = index * 2 + 1;
      if (left >= _values.length) break;
      final right = left + 1;
      final child = right < _values.length &&
              _values[right].priority < _values[left].priority
          ? right
          : left;
      if (_values[child].priority >= last.priority) break;
      _values[index] = _values[child];
      index = child;
    }
    _values[index] = last;
    return first;
  }
}
