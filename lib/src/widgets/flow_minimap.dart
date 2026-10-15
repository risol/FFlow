import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../controllers/flow_canvas_controller.dart';
import '../geometry/flow_geometry.dart';
import '../models/flow_edge.dart';
import '../models/flow_node.dart';

/// A compact graph overview that can be clicked or dragged to navigate.
class FFlowMiniMap<T> extends StatelessWidget {
  const FFlowMiniMap({
    super.key,
    required this.nodes,
    this.edges = const [],
    required this.controller,
    required this.viewportSize,
    this.width = 190,
    this.height = 130,
    this.padding = 9,
    this.backgroundColor = const Color(0xF0191D27),
    this.nodeColor = const Color(0xFF7569C8),
    this.viewportColor = const Color(0xFFAFA4FF),
    this.nodeColorFor,
    this.nodeBorderColorFor,
    this.nodeBorderWidth = 0,
    this.edgeColor = const Color(0xFF657083),
    this.showNodes = true,
    this.showViewport = true,
  });

  final List<FlowNode<T>> nodes;
  final List<FlowEdge> edges;
  final FlowCanvasController controller;
  final Size viewportSize;
  final double width;
  final double height;
  final double padding;
  final Color backgroundColor;
  final Color nodeColor;
  final Color viewportColor;
  final Color Function(FlowNode<T> node)? nodeColorFor;
  final Color Function(FlowNode<T> node)? nodeBorderColorFor;
  final double nodeBorderWidth;
  final Color edgeColor;
  final bool showNodes;
  final bool showViewport;

  @override
  Widget build(BuildContext context) {
    final bounds = FlowGeometry.nodesBounds(nodes);
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: const Color(0xFF333A49)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LayoutBuilder(builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            final map = _MiniMapTransform(bounds, size, padding);
            void navigate(Offset position) {
              if (bounds.isEmpty || viewportSize.isEmpty) return;
              final point = map.toScene(position);
              controller.centerAt(point, viewportSize);
            }

            return AnimatedBuilder(
              animation: controller,
              builder: (context, child) {
                final viewportTopLeft = controller.toScene(Offset.zero);
                final viewportBottomRight = controller.toScene(
                  Offset(viewportSize.width, viewportSize.height),
                );
                final viewportRect = Rect.fromPoints(
                  viewportTopLeft,
                  viewportBottomRight,
                );
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (details) => navigate(details.localPosition),
                  onPanStart: (details) => navigate(details.localPosition),
                  onPanUpdate: (details) => navigate(details.localPosition),
                  child: CustomPaint(
                    painter: _MiniMapPainter<T>(
                      nodes: nodes,
                      edges: edges,
                      bounds: bounds,
                      viewportRect: viewportRect,
                      transform: map,
                      nodeColor: nodeColor,
                      nodeColorFor: nodeColorFor,
                      nodeBorderColorFor: nodeBorderColorFor,
                      nodeBorderWidth: nodeBorderWidth,
                      edgeColor: edgeColor,
                      showNodes: showNodes,
                      showViewport: showViewport,
                      viewportColor: viewportColor,
                    ),
                    size: Size.infinite,
                  ),
                );
              },
            );
          }),
        ),
      ),
    );
  }
}

class _MiniMapTransform {
  _MiniMapTransform(this.bounds, this.size, this.padding) {
    final width = math.max(bounds.width, 1.0);
    final height = math.max(bounds.height, 1.0);
    scale = math.min(
      (size.width - padding * 2).clamp(1, double.infinity) / width,
      (size.height - padding * 2).clamp(1, double.infinity) / height,
    );
    left = (size.width - bounds.width * scale) / 2;
    top = (size.height - bounds.height * scale) / 2;
  }

  final Rect bounds;
  final Size size;
  final double padding;
  late final double scale;
  late final double left;
  late final double top;

  Rect toMap(Rect sceneRect) => Rect.fromLTWH(
        left + (sceneRect.left - bounds.left) * scale,
        top + (sceneRect.top - bounds.top) * scale,
        sceneRect.width * scale,
        sceneRect.height * scale,
      );

  Offset toScene(Offset mapPosition) => Offset(
        bounds.left + (mapPosition.dx - left) / scale,
        bounds.top + (mapPosition.dy - top) / scale,
      );
}

class _MiniMapPainter<T> extends CustomPainter {
  const _MiniMapPainter({
    required this.nodes,
    required this.edges,
    required this.bounds,
    required this.viewportRect,
    required this.transform,
    required this.nodeColor,
    required this.nodeColorFor,
    required this.nodeBorderColorFor,
    required this.nodeBorderWidth,
    required this.edgeColor,
    required this.showNodes,
    required this.showViewport,
    required this.viewportColor,
  });

  final List<FlowNode<T>> nodes;
  final List<FlowEdge> edges;
  final Rect bounds;
  final Rect viewportRect;
  final _MiniMapTransform transform;
  final Color nodeColor;
  final Color Function(FlowNode<T> node)? nodeColorFor;
  final Color Function(FlowNode<T> node)? nodeBorderColorFor;
  final double nodeBorderWidth;
  final Color edgeColor;
  final bool showNodes;
  final bool showViewport;
  final Color viewportColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (bounds.isEmpty) return;
    final nodesById = {for (final node in nodes) node.id: node};
    canvas.save();
    canvas.translate(
      transform.left - bounds.left * transform.scale,
      transform.top - bounds.top * transform.scale,
    );
    canvas.scale(transform.scale);
    for (final edge in edges) {
      if (edge.hidden) continue;
      final path = FlowGeometry.edgePathFor(edge, nodesById);
      canvas.drawPath(
        path,
        Paint()
          ..color = edge.color ?? edgeColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.0, edge.strokeWidth * 2)
          ..strokeCap = StrokeCap.round,
      );
    }
    canvas.restore();
    for (final node in showNodes ? nodes : <FlowNode<T>>[]) {
      if (!FlowGeometry.isVisible(node, nodesById)) continue;
      final position = FlowGeometry.absolutePosition(node, nodesById);
      final rect = transform.toMap(Rect.fromLTWH(
        position.dx,
        position.dy,
        node.width,
        node.height,
      ));
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, const Radius.circular(2)),
        Paint()..color = nodeColorFor?.call(node) ?? nodeColor,
      );
      final border = nodeBorderColorFor?.call(node);
      if (border != null && nodeBorderWidth > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(2)),
          Paint()
            ..color = border
            ..style = PaintingStyle.stroke
            ..strokeWidth = nodeBorderWidth,
        );
      }
    }
    if (!showViewport) return;
    final view = transform.toMap(viewportRect).intersect(Offset.zero & size);
    if (!view.isEmpty) {
      canvas.drawRect(
        view,
        Paint()
          ..color = viewportColor.withValues(alpha: 0.08)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        view,
        Paint()
          ..color = viewportColor.withValues(alpha: 0.8)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniMapPainter<T> oldDelegate) =>
      oldDelegate.nodes != nodes ||
      oldDelegate.edges != edges ||
      oldDelegate.bounds != bounds ||
      oldDelegate.viewportRect != viewportRect ||
      oldDelegate.transform.scale != transform.scale ||
      oldDelegate.transform.left != transform.left ||
      oldDelegate.transform.top != transform.top ||
      oldDelegate.nodeColor != nodeColor ||
      oldDelegate.nodeColorFor != nodeColorFor ||
      oldDelegate.nodeBorderColorFor != nodeBorderColorFor ||
      oldDelegate.nodeBorderWidth != nodeBorderWidth ||
      oldDelegate.edgeColor != edgeColor ||
      oldDelegate.showNodes != showNodes ||
      oldDelegate.showViewport != showViewport ||
      oldDelegate.viewportColor != viewportColor;
}
