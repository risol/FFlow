import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';

import '../geometry/flow_edge_geometry_cache.dart';
import '../geometry/flow_geometry.dart';
import '../models/flow_edge.dart';
import '../models/flow_node.dart';

class FlowEdgesPainter<T> extends CustomPainter {
  FlowEdgesPainter({
    required this.nodes,
    required this.edges,
    required this.selectedEdgeIds,
    required this.defaultColor,
    required this.previewStart,
    required this.previewTarget,
    required this.previewColor,
    required this.animation,
    this.geometryCache,
    this.sceneOffset = Offset.zero,
    this.repaintOnAnimation = true,
  }) : super(repaint: repaintOnAnimation ? animation : null);

  final List<FlowNode<T>> nodes;
  final List<FlowEdge> edges;
  final Set<String> selectedEdgeIds;
  final Color defaultColor;
  final Offset? previewStart;
  final Offset? previewTarget;
  final Color previewColor;
  final Animation<double> animation;
  final FlowEdgeGeometryCache? geometryCache;
  final Offset sceneOffset;
  final bool repaintOnAnimation;

  late final Map<String, FlowNode<T>> _nodesById = {
    for (final node in nodes) node.id: node,
  };

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(sceneOffset.dx, sceneOffset.dy);
    for (final edge in edges) {
      if (edge.hidden) continue;
      final geometry = geometryCache?.result(edge, _nodesById) ??
          FlowGeometry.edgePathResult(edge, _nodesById);
      if (geometry == null) continue;
      _drawPath(
        canvas,
        geometry.path,
        geometry.metrics,
        edge,
        color: selectedEdgeIds.contains(edge.id)
            ? const Color(0xFFB4A9FF)
            : edge.color ?? defaultColor,
        strokeWidth:
            edge.strokeWidth + (selectedEdgeIds.contains(edge.id) ? 1 : 0),
      );
    }

    final source = previewStart;
    final target = previewTarget;
    if (source != null && target != null) {
      final bend = (target.dx - source.dx).abs() * 0.48;
      final control = bend.clamp(48.0, 190.0).toDouble();
      final preview = Path()
        ..moveTo(source.dx, source.dy)
        ..cubicTo(source.dx + control, source.dy, target.dx - control,
            target.dy, target.dx, target.dy);
      _drawPath(canvas, preview,
          preview.computeMetrics().toList(growable: false), null,
          color: previewColor, strokeWidth: 2);
    }
    canvas.restore();
  }

  void _drawPath(
    Canvas canvas,
    Path path,
    List<PathMetric> resolvedMetrics,
    FlowEdge? edge, {
    required Color color,
    required double strokeWidth,
  }) {
    final metrics = resolvedMetrics;
    if (metrics.isEmpty) return;
    final strokePath = _withMarkerGaps(path, metrics, edge);
    canvas.drawPath(
      strokePath,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );

    if (edge?.animated ?? false) {
      _drawAnimatedDashes(canvas, metrics, color, strokeWidth, animation.value);
    }
    if (edge?.markerStart != null) {
      _drawMarker(canvas, metrics, edge?.markerColor ?? color,
          atStart: true, markerType: edge!.markerStart!);
    }
    if (edge?.markerEnd != null) {
      _drawMarker(canvas, metrics, edge?.markerColor ?? color,
          atStart: false, markerType: edge!.markerEnd!);
    }
  }

  Path _withMarkerGaps(
      Path original, List<PathMetric> metrics, FlowEdge? edge) {
    double? gapCenter(FlowEdgeMarker? marker) => switch (marker) {
          FlowEdgeMarker.crowFootZeroMany => 18,
          FlowEdgeMarker.zeroOrOne => 13,
          _ => null,
        };
    final start = gapCenter(edge?.markerStart);
    final end = gapCenter(edge?.markerEnd);
    if (start == null && end == null) return original;
    final result = Path();
    for (var i = 0; i < metrics.length; i++) {
      final metric = metrics[i];
      final gaps = <(double, double)>[
        if (i == 0 && start != null) (start - 4, start + 4),
        if (i == metrics.length - 1 && end != null)
          (metric.length - end - 4, metric.length - end + 4),
      ]..sort((a, b) => a.$1.compareTo(b.$1));
      var cursor = 0.0;
      for (final gap in gaps) {
        final from = gap.$1.clamp(0.0, metric.length).toDouble();
        final to = gap.$2.clamp(0.0, metric.length).toDouble();
        if (from > cursor) {
          result.addPath(metric.extractPath(cursor, from), Offset.zero);
        }
        cursor = math.max(cursor, to);
      }
      if (cursor < metric.length) {
        result.addPath(metric.extractPath(cursor, metric.length), Offset.zero);
      }
    }
    return result;
  }

  void _drawAnimatedDashes(
    Canvas canvas,
    List<PathMetric> metrics,
    Color color,
    double strokeWidth,
    double progress,
  ) {
    final dashLength = math.max(8.0, strokeWidth * 4).toDouble();
    const gapLength = 8.0;
    final cycleLength = dashLength + gapLength;
    final phase = progress * cycleLength;
    final dashPath = Path();
    for (final metric in metrics) {
      for (var start = -phase; start < metric.length; start += cycleLength) {
        final from = start.clamp(0.0, metric.length).toDouble();
        final to = (start + dashLength).clamp(0.0, metric.length).toDouble();
        if (to > from) {
          dashPath.addPath(metric.extractPath(from, to), Offset.zero);
        }
      }
    }
    canvas.drawPath(
      dashPath,
      Paint()
        ..color = Color.lerp(color, Colors.white, 0.28) ?? color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawMarker(
    Canvas canvas,
    List<PathMetric> metrics,
    Color color, {
    required bool atStart,
    required FlowEdgeMarker markerType,
  }) {
    if (metrics.first.length == 0) return;
    final metric = metrics.first;
    final tangent = metric.getTangentForOffset(atStart ? 0 : metric.length);
    if (tangent == null) return;
    final direction = tangent.vector;
    final tip = tangent.position;
    final sign = atStart ? -1.0 : 1.0;
    final normalUnit = Offset(-direction.dy, direction.dx);
    final inward = direction * -sign;
    if (markerType == FlowEdgeMarker.crowFootZeroMany ||
        markerType == FlowEdgeMarker.one ||
        markerType == FlowEdgeMarker.zeroOrOne) {
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      void line(Offset a, Offset b) => canvas.drawLine(a, b, paint);
      if (markerType == FlowEdgeMarker.crowFootZeroMany) {
        final junction = tip + inward * 12;
        line(junction, tip + normalUnit * 5);
        line(junction, tip - normalUnit * 5);
        line(junction, tip);
        canvas.drawCircle(tip + inward * 18, 3, paint);
      } else {
        final bar = tip + inward * 5;
        line(bar + normalUnit * 5, bar - normalUnit * 5);
        if (markerType == FlowEdgeMarker.zeroOrOne) {
          canvas.drawCircle(tip + inward * 13, 3, paint);
        } else {
          final second = tip + inward * 10;
          line(second + normalUnit * 5, second - normalUnit * 5);
        }
      }
      return;
    }
    final base = tip - direction * (9 * sign);
    final normal = Offset(-direction.dy, direction.dx) * 4;
    final marker = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(base.dx + normal.dx, base.dy + normal.dy)
      ..lineTo(base.dx - normal.dx, base.dy - normal.dy);
    if (markerType == FlowEdgeMarker.arrowClosed) {
      marker.close();
      canvas.drawPath(marker, Paint()..color = color);
    } else {
      canvas.drawPath(
        marker,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant FlowEdgesPainter<T> oldDelegate) =>
      oldDelegate.nodes != nodes ||
      oldDelegate.edges != edges ||
      oldDelegate.selectedEdgeIds != selectedEdgeIds ||
      oldDelegate.defaultColor != defaultColor ||
      oldDelegate.previewStart != previewStart ||
      oldDelegate.previewTarget != previewTarget ||
      oldDelegate.previewColor != previewColor ||
      oldDelegate.geometryCache != geometryCache ||
      oldDelegate.sceneOffset != sceneOffset ||
      oldDelegate.repaintOnAnimation != repaintOnAnimation ||
      (repaintOnAnimation && oldDelegate.animation != animation);
}
