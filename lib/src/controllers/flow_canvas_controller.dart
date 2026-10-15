import 'package:flutter/widgets.dart';

import '../geometry/flow_geometry.dart';
import '../models/flow_node.dart';
import '../models/flow_viewport.dart';
import '../utils/flow_graph_utils.dart';

/// Controls viewport movement and zoom for an [FFlowCanvas].
///
/// Pass the controller to the canvas and dispose it with the owning widget.
class FlowCanvasController extends TransformationController {
  Size? _viewportSize;

  FlowViewport get viewport => FlowViewport(
        x: value.entry(0, 3),
        y: value.entry(1, 3),
        zoom: value.getMaxScaleOnAxis(),
      );

  /// The canvas updates this size during layout so zoom helpers can keep the
  /// visible center fixed when no focal point is supplied.
  void updateViewportSize(Size size) => _viewportSize = size;

  /// Convert a point in canvas-local screen pixels to graph coordinates.
  Offset screenToFlowPosition(Offset position) => toScene(position);

  /// Convert a point in graph coordinates to canvas-local screen pixels.
  Offset flowToScreenPosition(Offset position) =>
      MatrixUtils.transformPoint(value, position);

  /// Set pan translation and zoom directly.
  void setViewport(FlowViewport viewport) {
    value = Matrix4.identity()
      ..translateByDouble(viewport.x, viewport.y, 0, 1)
      ..scaleByDouble(viewport.zoom, viewport.zoom, 1, 1);
  }

  void panBy(Offset delta) {
    value = Matrix4.translationValues(delta.dx, delta.dy, 0) * value;
  }

  void zoomBy(
    double factor, {
    Offset? focalPoint,
    double minZoom = 0.25,
    double maxZoom = 2,
  }) {
    final current = value.getMaxScaleOnAxis();
    zoomTo(
      current * factor,
      focalPoint: focalPoint,
      minZoom: minZoom,
      maxZoom: maxZoom,
    );
  }

  void zoomIn({double factor = 1.2, Offset? focalPoint}) =>
      zoomBy(factor, focalPoint: focalPoint);

  void zoomOut({double factor = 1.2, Offset? focalPoint}) =>
      zoomBy(1 / factor, focalPoint: focalPoint);

  void zoomTo(
    double zoom, {
    Offset? focalPoint,
    double minZoom = 0.25,
    double maxZoom = 2,
  }) {
    final current = value.getMaxScaleOnAxis();
    final next = zoom.clamp(minZoom, maxZoom).toDouble();
    final factor = next / current;
    final focal = focalPoint ??
        (_viewportSize == null
            ? null
            : Offset(_viewportSize!.width / 2, _viewportSize!.height / 2));
    if (focal == null) {
      value = Matrix4.diagonal3Values(factor, factor, 1) * value;
      return;
    }
    final aroundPoint = Matrix4.identity()
      ..translateByDouble(focal.dx, focal.dy, 0, 1)
      ..scaleByDouble(factor, factor, 1, 1)
      ..translateByDouble(-focal.dx, -focal.dy, 0, 1);
    value = aroundPoint * value;
  }

  void centerAt(Offset scenePoint, Size viewportSize, {double? zoom}) {
    final scale = zoom ?? value.getMaxScaleOnAxis();
    final center = Offset(viewportSize.width / 2, viewportSize.height / 2);
    final translation = center - scenePoint * scale;
    value = Matrix4.identity()
      ..translateByDouble(translation.dx, translation.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  /// Center [scenePoint] in the viewport, preserving zoom unless overridden.
  void panTo(Offset scenePoint, Size viewportSize, {double? zoom}) =>
      centerAt(scenePoint, viewportSize, zoom: zoom);

  /// Center graph coordinate ([x], [y]) in the attached canvas.
  ///
  /// The canvas supplies its viewport size during layout. This is a no-op
  /// until the controller is attached to a laid-out canvas.
  void setCenter(double x, double y, {double? zoom}) {
    final size = _viewportSize;
    if (size == null || size.isEmpty) return;
    centerAt(Offset(x, y), size, zoom: zoom);
  }

  /// Fit [bounds] inside [viewportSize] while preserving the requested padding.
  void fitBounds(
    Rect bounds,
    Size viewportSize, {
    double padding = 80,
    double minZoom = 0.25,
    double maxZoom = 2,
  }) {
    if (bounds.isEmpty || viewportSize.isEmpty) return;
    setViewport(FlowGraphUtils.getViewportForBounds(
      bounds,
      viewportSize,
      padding: padding,
      minZoom: minZoom,
      maxZoom: maxZoom,
    ));
  }

  void fitView<T>(
    Iterable<FlowNode<T>> nodes,
    Size viewportSize, {
    double padding = 80,
    double minZoom = 0.25,
    double maxZoom = 2,
  }) {
    final bounds = FlowGeometry.nodesBounds(nodes);
    fitBounds(
      bounds,
      viewportSize,
      padding: padding,
      minZoom: minZoom,
      maxZoom: maxZoom,
    );
  }
}
