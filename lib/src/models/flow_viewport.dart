import 'package:flutter/animation.dart';

/// Options shared by fit-to-view helpers and initial viewport fitting.
class FlowFitViewOptions {
  const FlowFitViewOptions({
    this.padding = 80,
    this.minZoom = 0.25,
    this.maxZoom = 2,
    this.duration = Duration.zero,
    this.curve = Curves.easeInOut,
  });

  final double padding;
  final double minZoom;
  final double maxZoom;
  final Duration duration;
  final Curve curve;
}

/// The translation and zoom of a flow canvas.
class FlowViewport {
  const FlowViewport({required this.x, required this.y, required this.zoom});

  final double x;
  final double y;
  final double zoom;

  FlowViewport copyWith({double? x, double? y, double? zoom}) => FlowViewport(
        x: x ?? this.x,
        y: y ?? this.y,
        zoom: zoom ?? this.zoom,
      );

  Map<String, double> toJson() => {'x': x, 'y': y, 'zoom': zoom};

  factory FlowViewport.fromJson(Map<String, Object?> json) => FlowViewport(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        zoom: (json['zoom'] as num).toDouble(),
      );

  @override
  bool operator ==(Object other) =>
      other is FlowViewport &&
      other.x == x &&
      other.y == y &&
      other.zoom == zoom;

  @override
  int get hashCode => Object.hash(x, y, zoom);
}
