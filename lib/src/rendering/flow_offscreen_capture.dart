import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'flow_png_capture.dart';

/// Experimental detached render tree for static, self-contained widgets.
///
/// The tree is laid out and painted by a separate pipeline, but is never
/// submitted to the window. Widgets that depend on later frames, network
/// resources or inherited state from the host are not supported. The caller
/// must provide a live Flutter view and any required inherited widgets.
Future<Uint8List> captureFlowOffscreen({
  required ui.FlutterView view,
  required Size size,
  required Widget child,
  double pixelRatio = 2,
  int maxDimension = 8192,
  int? maxWidth,
  int? maxHeight,
  int maxPixels = 32000000,
  int maxBytes = 64000000,
  FlowCaptureTimings? timings,
}) async {
  final widthLimit = maxWidth ?? maxDimension;
  final heightLimit = maxHeight ?? maxDimension;
  if (!size.width.isFinite ||
      !size.height.isFinite ||
      size.width <= 0 ||
      size.height <= 0 ||
      !pixelRatio.isFinite ||
      pixelRatio <= 0 ||
      maxDimension <= 0 ||
      widthLimit <= 0 ||
      heightLimit <= 0 ||
      maxPixels <= 0 ||
      maxBytes <= 0) {
    throw ArgumentError('Invalid render size or capture limits');
  }
  if (size.width * pixelRatio > widthLimit ||
      size.height * pixelRatio > heightLimit) {
    throw StateError('IMAGE_TOO_LARGE: excessive image dimensions');
  }
  final width = (size.width * pixelRatio).ceil();
  final height = (size.height * pixelRatio).ceil();
  if (width > widthLimit ||
      height > heightLimit ||
      width * height > maxPixels) {
    throw StateError('IMAGE_TOO_LARGE: excessive image dimensions');
  }

  final constraints = BoxConstraints.tight(size);
  final renderView = RenderView(
    view: view,
    configuration: ViewConfiguration(
      logicalConstraints: constraints,
      physicalConstraints: constraints,
    ),
  );
  final pipeline = PipelineOwner()..rootNode = renderView;
  final owner = BuildOwner(focusManager: FocusManager());
  RenderObjectToWidgetElement<RenderBox>? element;
  final layoutClock = Stopwatch()..start();
  try {
    // Flutter catches many build, layout and paint exceptions internally and
    // can otherwise produce a partial image. The pipeline below is entirely
    // synchronous, so temporarily intercept its errors without keeping a
    // process-wide handler installed across an await.
    final previousHandler = FlutterError.onError;
    FlutterErrorDetails? failure;
    FlutterError.onError = (details) => failure ??= details;
    try {
      renderView.prepareInitialFrame();
      element = RenderObjectToWidgetAdapter<RenderBox>(
        container: renderView,
        child: RepaintBoundary(child: child),
      ).attachToRenderTree(owner);
      void checkFailure() {
        if (failure != null) {
          throw StateError(
              'RENDER_INIT_ERROR: ${failure!.exceptionAsString()}');
        }
      }

      checkFailure();
      void rejectErrorWidgets(Element current) {
        if (current.widget is ErrorWidget) {
          throw StateError('RENDER_INIT_ERROR: widget build failed');
        }
        current.visitChildren(rejectErrorWidgets);
      }

      owner.buildScope(element);
      pipeline.flushLayout();
      pipeline.flushCompositingBits();
      pipeline.flushPaint();
      checkFailure();
      rejectErrorWidgets(element);
      // FFlow updates its scene origin during layout. Its edge painters are
      // constructed earlier in build, so rebuild after the first layout to use
      // the new origin before taking the image. This is not a substitute for
      // asynchronous resource loading or arbitrary animation frames.
      void markDirty(Element child) {
        child.markNeedsBuild();
        child.visitChildren(markDirty);
      }

      element.visitChildren(markDirty);
      owner.buildScope(element);
      pipeline.flushLayout();
      pipeline.flushCompositingBits();
      pipeline.flushPaint();
      checkFailure();
      rejectErrorWidgets(element);
    } finally {
      FlutterError.onError = previousHandler;
    }
    timings?.layoutPaint = layoutClock.elapsed;
    return await captureFlowBoundary(renderView.child! as RenderRepaintBoundary,
        pixelRatio: pixelRatio,
        maxDimension: maxDimension,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        maxPixels: maxPixels,
        maxBytes: maxBytes,
        timings: timings);
  } finally {
    try {
      if (element != null) {
        RenderObjectToWidgetAdapter<RenderBox>(container: renderView)
            .attachToRenderTree(owner, element);
        owner.buildScope(element);
        owner.finalizeTree();
      }
    } finally {
      pipeline.rootNode = null;
      // The adapter owns only the child element. Its root RenderView is
      // created manually and must release its retained layer explicitly.
      renderView.dispose();
      pipeline.dispose();
      owner.focusManager.dispose();
    }
  }
}
