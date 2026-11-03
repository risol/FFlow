import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../canvas/flow_canvas.dart';
import '../geometry/flow_geometry.dart';
import '../models/flow_diagnostic.dart';
import '../models/flow_edge.dart';
import '../models/flow_graph_snapshot.dart';
import '../models/flow_viewport.dart';
import 'flow_offscreen_capture.dart';
import 'flow_png_capture.dart';

/// Result of rendering a static FFlow snapshot at its natural scale.
class FlowGraphPng {
  const FlowGraphPng(
      {required this.bytes,
      required this.graphBounds,
      required this.logicalSize,
      required this.pixelRatio,
      this.preparation = Duration.zero,
      this.timings});
  final Uint8List bytes;

  /// Bounds in graph coordinates, before the requested padding is added.
  final Rect graphBounds;
  final Size logicalSize;
  final double pixelRatio;
  final Duration preparation;
  final FlowCaptureTimings? timings;
}

/// Renders an FFlow snapshot to an offscreen PNG, independent of its saved
/// viewport. Node builders must paint within their declared node dimensions.
/// Asynchronous resources, auto-measured nodes and custom edge renderers are
/// not supported by this experimental static export. A custom edge label must
/// fit within the default measured label bounds expanded by [edgeLabelOutset].
/// Default labels are moved away from nodes and earlier labels when a bounded
/// nearby search finds a clear position; custom label builders are not moved.
Future<FlowGraphPng> renderFlowSnapshot<T>({
  required ui.FlutterView view,
  required FlowGraphSnapshot<T> snapshot,
  required FlowNodeBuilder<T> nodeBuilder,
  double padding = 32,
  double pixelRatio = 2,
  Color backgroundColor = Colors.white,
  Color? titleColor,
  String fontFamily = 'Roboto',
  Color edgeColor = const Color(0xff727c90),
  double gridSpacing = 0,
  TextDirection textDirection = TextDirection.ltr,
  String? title,
  Widget Function(BuildContext, FlowEdge)? edgeLabelBuilder,
  double edgeLabelOutset = 0,
  int maxNodes = 5000,
  int maxEdges = 10000,
  int maxDimension = 8192,
  int? maxWidth,
  int? maxHeight,
  int maxPixels = 32000000,
  int maxBytes = 64000000,
}) async {
  final preparationClock = Stopwatch()..start();
  if (!padding.isFinite ||
      padding < 0 ||
      !gridSpacing.isFinite ||
      gridSpacing < 0 ||
      !edgeLabelOutset.isFinite ||
      edgeLabelOutset < 0 ||
      maxNodes < 0 ||
      maxEdges < 0) {
    throw ArgumentError('Invalid graph export options');
  }
  if (snapshot.nodes.length > maxNodes || snapshot.edges.length > maxEdges) {
    throw StateError('IMAGE_TOO_LARGE: graph exceeds node or edge limits');
  }
  final errors = FlowGraphValidator.validate(
    nodes: snapshot.nodes,
    edges: snapshot.edges,
  ).where((d) => d.severity == FlowDiagnosticSeverity.error).toList();
  if (errors.isNotEmpty) {
    final referenceError = errors.any((d) =>
        d.code.startsWith('dangling-edge-') ||
        d.code == 'missing-parent' ||
        d.code == 'missing-source-handle' ||
        d.code == 'missing-target-handle');
    throw StateError(
        '${referenceError ? 'GRAPH_REFERENCE_ERROR' : 'SCHEMA_ERROR'}: ${errors.join('; ')}');
  }
  if (snapshot.nodes.any((node) => node.autoMeasure)) {
    throw StateError('RENDER_INIT_ERROR: auto-measured nodes are unsupported');
  }
  final byId = {for (final node in snapshot.nodes) node.id: node};
  final parentIds = {
    for (final node in snapshot.nodes)
      if (node.parentId != null) node.parentId!
  };
  final labelObstacles = <Rect>[
    for (final node in snapshot.nodes)
      if (!parentIds.contains(node.id) && FlowGeometry.isVisible(node, byId))
        FlowGeometry.nodeRect(node, byId).inflate(2),
  ];
  final occupiedLabels = <Rect>[];
  final labelOffsets = <String, Offset>{};
  final placeLabels = edgeLabelBuilder == null &&
      snapshot.nodes.length <= 1000 &&
      snapshot.edges.length <= 2000;
  Rect? bounds;
  void include(Rect rect) {
    if (!rect.left.isFinite ||
        !rect.top.isFinite ||
        !rect.right.isFinite ||
        !rect.bottom.isFinite) {
      throw StateError('IMAGE_TOO_LARGE: graph bounds are not finite');
    }
    bounds = bounds == null ? rect : bounds!.expandToInclude(rect);
  }

  for (final node in snapshot.nodes) {
    if (FlowGeometry.isVisible(node, byId)) {
      // Allow for FFlow's handles, selection borders and their shadows.
      final nodeBounds = FlowGeometry.nodeRect(node, byId);
      if (nodeBounds.width <= 0 || nodeBounds.height <= 0) {
        throw StateError(
            'IMAGE_TOO_LARGE: node ${node.id} exceeds coordinate precision');
      }
      include(nodeBounds.inflate(16));
    }
  }
  for (final edge in snapshot.edges) {
    if (edge.hidden ||
        !FlowGeometry.isVisible(byId[edge.sourceId]!, byId) ||
        !FlowGeometry.isVisible(byId[edge.targetId]!, byId)) {
      continue;
    }
    final geometry = FlowGeometry.edgePathResult(edge, byId);
    if (geometry == null) continue;
    include(geometry.bounds.inflate(math.max(24, edge.strokeWidth / 2 + 2)));
    if (edge.label != null) {
      if (edge.label!.length > 10000) {
        throw StateError('IMAGE_TOO_LARGE: edge label ${edge.id} is too long');
      }
      final painter = TextPainter(
        text: TextSpan(
            text: edge.label,
            style: TextStyle(fontFamily: fontFamily, fontSize: 10)),
        textDirection: textDirection,
      )..layout();
      final labelSize = Size(painter.width + 16, painter.height + 8);
      painter.dispose();
      final originalLabel = Rect.fromCenter(
          center: geometry.labelPosition,
          width: labelSize.width,
          height: labelSize.height);
      var labelRect = originalLabel;
      if (placeLabels) {
        bool clear(Rect candidate) =>
            !labelObstacles.any(candidate.overlaps) &&
            !occupiedLabels.any(candidate.overlaps);
        if (!clear(labelRect)) {
          for (var ring = 1; ring <= 8; ring++) {
            final vertical = ring * (labelSize.height + 8);
            final horizontal = ring * (labelSize.width + 8);
            final offsets = [
              Offset(0, -vertical),
              Offset(0, vertical),
              Offset(-horizontal, 0),
              Offset(horizontal, 0)
            ];
            final offset = offsets
                .where((value) => clear(originalLabel.shift(value)))
                .firstOrNull;
            if (offset != null) {
              labelOffsets[edge.id] = offset;
              labelRect = originalLabel.shift(offset);
              break;
            }
          }
        }
        occupiedLabels.add(labelRect.inflate(2));
      }
      include(labelRect.inflate(edgeLabelOutset));
    }
  }
  final graphBounds = bounds ?? Rect.zero;
  if (!(graphBounds.width + 2 * padding).isFinite ||
      !(graphBounds.height + 2 * padding).isFinite) {
    throw StateError('IMAGE_TOO_LARGE: graph dimensions are not finite');
  }
  var titleHeight = 0.0;
  var titleWidth = 0.0;
  if (title != null && title.isNotEmpty) {
    if (title.length > 10000) {
      throw StateError('IMAGE_TOO_LARGE: title is too long');
    }
    final painter = TextPainter(
      text: TextSpan(
          text: title,
          style: TextStyle(
              fontFamily: fontFamily,
              fontSize: 18,
              fontWeight: FontWeight.w600)),
      textDirection: textDirection,
    )..layout();
    titleWidth = painter.width + 2 * padding;
    titleHeight = painter.height + 24;
    painter.dispose();
  }
  final graphWidth = graphBounds.width + 2 * padding;
  final logicalSize = Size(
    math.max(1, math.max(graphWidth, titleWidth).ceilToDouble()),
    math.max(
        1, (graphBounds.height + 2 * padding + titleHeight).ceilToDouble()),
  );
  // FFlow's scene includes the graph coordinates as well as the viewport.
  // Translate roots to a local origin so a small graph at a very large global
  // coordinate does not create an enormous intermediate scene. Child positions
  // stay parent-relative and edge control points are absolute.
  final shift = Offset(-graphBounds.left, -graphBounds.top);
  final localNodes = [
    for (final node in snapshot.nodes)
      if (node.parentId == null)
        node.copyWith(
          position: node.position + shift,
          extent: node.extent?.shift(shift),
        )
      else
        node,
  ];
  final localEdges = [
    for (final edge in snapshot.edges)
      edge.copyWith(
          controlPoints: [for (final p in edge.controlPoints) p + shift]),
  ];
  if (gridSpacing > 0 &&
      ((logicalSize.width + 512) / gridSpacing) *
              ((logicalSize.height + 512) / gridSpacing) >
          1000000) {
    throw StateError('IMAGE_TOO_LARGE: background grid exceeds drawing limit');
  }
  final preparation = preparationClock.elapsed;
  final timings = FlowCaptureTimings();
  final bytes = await captureFlowOffscreen(
    view: view,
    size: logicalSize,
    pixelRatio: pixelRatio,
    maxDimension: maxDimension,
    maxWidth: maxWidth,
    maxHeight: maxHeight,
    maxPixels: maxPixels,
    maxBytes: maxBytes,
    timings: timings,
    child: Directionality(
      textDirection: textDirection,
      child: MediaQuery(
        data: const MediaQueryData(),
        child: DefaultTextStyle(
          style: TextStyle(fontFamily: fontFamily, fontSize: 14),
          child: ColoredBox(
              color: backgroundColor,
              child: Column(children: [
                if (titleHeight > 0)
                  SizedBox(
                      height: titleHeight,
                      child: Center(
                          child: Text(title!,
                              style: TextStyle(
                                  fontFamily: fontFamily,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: titleColor ??
                                      (backgroundColor.computeLuminance() < 0.4
                                          ? Colors.white
                                          : Colors.black))))),
                Expanded(
                    child: FFlowCanvas<T>(
                  nodes: localNodes,
                  edges: localEdges,
                  nodeBuilder: (context, node, selected) =>
                      nodeBuilder(context, byId[node.id]!, selected),
                  backgroundColor: backgroundColor,
                  edgeColor: edgeColor,
                  edgeLabelBuilder: edgeLabelBuilder ??
                      (labelOffsets.isEmpty
                          ? null
                          : (context, edge) => Transform.translate(
                                offset: labelOffsets[edge.id] ?? Offset.zero,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: const Color(0xff202633),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                        color: const Color(0xff394151)),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 3),
                                    child: Text(edge.label!,
                                        style: const TextStyle(
                                            color: Colors.white, fontSize: 10)),
                                  ),
                                ),
                              )),
                  gridSpacing: gridSpacing,
                  defaultViewport: FlowViewport(
                      x: padding + (logicalSize.width - graphWidth) / 2,
                      y: padding,
                      zoom: 1),
                  onlyRenderVisibleElements: false,
                  showHandles: false,
                  panEnabled: false,
                  zoomEnabled: false,
                )),
              ])),
        ),
      ),
    ),
  );
  return FlowGraphPng(
      bytes: bytes,
      graphBounds: graphBounds,
      logicalSize: logicalSize,
      pixelRatio: pixelRatio,
      preparation: preparation,
      timings: timings);
}
