import 'dart:math' as math;

import 'package:flutter/material.dart';

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
  }) : super(repaint: animation);

  final List<FlowNode<T>> nodes;
  final List<FlowEdge> edges;
  final Set<String> selectedEdgeIds;
  final Color defaultColor;
  final Offset? previewStart;
  final Offset? previewTarget;
  final Color previewColor;
  final Animation<double> animation;

  @override
  void paint(Canvas canvas, Size size) {
    final byId = {for (final node in nodes) node.id: node};
    for (final edge in edges) {
      if (edge.hidden) continue;
      final start = FlowGeometry.edgeSource(edge, byId);
      final end = FlowGeometry.edgeTarget(edge, byId);
      if (start == null || end == null) continue;
      _drawEdge(
        canvas,
        start,
        end,
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
      _drawEdge(
        canvas,
        source,
        target,
        null,
        color: previewColor,
        strokeWidth: 2,
      );
    }
  }

  void _drawEdge(
    Canvas canvas,
    Offset start,
    Offset end,
    FlowEdge? edge, {
    required Color color,
    required double strokeWidth,
  }) {
    final path = edge == null
        ? Path()
        : FlowGeometry.edgePathFor(
            edge, {for (final node in nodes) node.id: node});
    if (edge == null) {
      final bend = (end.dx - start.dx).abs() * 0.48;
      final control = bend.clamp(48.0, 190.0).toDouble();
      path
        ..moveTo(start.dx, start.dy)
        ..cubicTo(start.dx + control, start.dy, end.dx - control, end.dy,
            end.dx, end.dy);
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0x99000000)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth + 5
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round,
    );

    if (edge?.animated ?? false) {
      _drawAnimatedDashes(canvas, path, color, strokeWidth, animation.value);
    }
    if (edge?.markerStart != null) {
      _drawMarker(canvas, path, edge?.markerColor ?? color,
          atStart: true,
          closed: edge!.markerStart == FlowEdgeMarker.arrowClosed);
    }
    if (edge?.markerEnd != null) {
      _drawMarker(canvas, path, edge?.markerColor ?? color,
          atStart: false,
          closed: edge!.markerEnd == FlowEdgeMarker.arrowClosed);
    }
  }

  void _drawAnimatedDashes(
    Canvas canvas,
    Path path,
    Color color,
    double strokeWidth,
    double progress,
  ) {
    final dashLength = math.max(8.0, strokeWidth * 4).toDouble();
    const gapLength = 8.0;
    final cycleLength = dashLength + gapLength;
    final phase = progress * cycleLength;
    final dashPath = Path();
    for (final metric in path.computeMetrics()) {
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

  void _drawMarker(Canvas canvas, Path path, Color color,
      {required bool atStart, required bool closed}) {
    final metrics = path.computeMetrics().toList(growable: false);
    if (metrics.isEmpty || metrics.first.length == 0) return;
    final metric = metrics.first;
    final tangent = metric.getTangentForOffset(atStart ? 0 : metric.length);
    if (tangent == null) return;
    final direction = tangent.vector;
    final tip = tangent.position;
    final sign = atStart ? -1.0 : 1.0;
    final base = tip - direction * (9 * sign);
    final normal = Offset(-direction.dy, direction.dx) * 4;
    final marker = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(base.dx + normal.dx, base.dy + normal.dy)
      ..lineTo(base.dx - normal.dx, base.dy - normal.dy);
    if (closed) {
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
      oldDelegate.animation != animation;
}
