import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Per-task timing collector. Do not reuse it concurrently across captures.
class FlowCaptureTimings {
  Duration layoutPaint = Duration.zero;
  Duration raster = Duration.zero;
  Duration pngEncode = Duration.zero;
}

/// Captures an already painted boundary. The host owns mounting, sizing and
/// frame scheduling; an offstage or otherwise unpainted widget cannot be used.
Future<Uint8List> captureFlowPng(
  GlobalKey boundaryKey, {
  double pixelRatio = 2,
  int maxDimension = 8192,
  int? maxWidth,
  int? maxHeight,
  int maxPixels = 32000000,
  int maxBytes = 64000000,
  FlowCaptureTimings? timings,
}) async {
  final renderObject = boundaryKey.currentContext?.findRenderObject();
  if (renderObject is! RenderRepaintBoundary) {
    throw StateError('RENDER_INIT_ERROR: boundary is not ready for capture');
  }
  return captureFlowBoundary(renderObject,
      pixelRatio: pixelRatio,
      maxDimension: maxDimension,
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      maxPixels: maxPixels,
      maxBytes: maxBytes,
      timings: timings);
}

/// Captures a boundary belonging to either the host or a detached pipeline.
Future<Uint8List> captureFlowBoundary(
  RenderRepaintBoundary renderObject, {
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
  if (!pixelRatio.isFinite ||
      pixelRatio <= 0 ||
      maxDimension <= 0 ||
      widthLimit <= 0 ||
      heightLimit <= 0 ||
      maxPixels <= 0 ||
      maxBytes <= 0) {
    throw ArgumentError('Invalid PNG capture limits or pixel ratio');
  }
  if (!renderObject.attached ||
      !renderObject.hasSize ||
      renderObject.debugNeedsPaint) {
    throw StateError('RENDER_INIT_ERROR: boundary is not ready for capture');
  }
  final size = renderObject.size;
  if (!size.width.isFinite ||
      !size.height.isFinite ||
      size.width * pixelRatio > widthLimit ||
      size.height * pixelRatio > heightLimit) {
    throw StateError('IMAGE_TOO_LARGE: invalid or excessive image dimensions');
  }
  final width = (size.width * pixelRatio).ceil();
  final height = (size.height * pixelRatio).ceil();
  if (width <= 0 ||
      height <= 0 ||
      width > widthLimit ||
      height > heightLimit ||
      width * height > maxPixels) {
    throw StateError('IMAGE_TOO_LARGE: invalid or excessive image dimensions');
  }
  final rasterClock = Stopwatch()..start();
  final image = await renderObject.toImage(pixelRatio: pixelRatio);
  timings?.raster = rasterClock.elapsed;
  try {
    final encodeClock = Stopwatch()..start();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    timings?.pngEncode = encodeClock.elapsed;
    if (bytes == null) {
      throw StateError('PNG_ENCODE_ERROR: encoder returned no data');
    }
    if (bytes.lengthInBytes > maxBytes) {
      throw StateError('IMAGE_TOO_LARGE: encoded PNG exceeds byte limit');
    }
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } finally {
    image.dispose();
  }
}
