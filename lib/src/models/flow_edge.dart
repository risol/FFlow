import 'package:flutter/painting.dart';

enum FlowEdgeType { bezier, straight, step, smoothStep, simpleBezier }

enum FlowEdgeMarker { arrow, arrowClosed }

/// A directed connection between two nodes on an [FFlowCanvas].
class FlowEdge {
  const FlowEdge({
    required this.id,
    required this.sourceId,
    required this.targetId,
    this.color,
    this.strokeWidth = 2,
    this.sourceHandleId,
    this.targetHandleId,
    this.type = FlowEdgeType.bezier,
    this.customType,
    this.label,
    this.markerStart,
    this.markerEnd,
    this.selectable = true,
    this.deletable = true,
    this.reconnectable = true,
    this.hidden = false,
    this.selected = false,
    this.animated = false,
    this.interactionWidth = 20,
    this.data,
  });

  final String id;
  final String sourceId;
  final String targetId;
  final Color? color;
  final double strokeWidth;
  final String? sourceHandleId;
  final String? targetHandleId;
  final FlowEdgeType type;

  /// Optional application-defined renderer key, similar to React Flow's edge type registry.
  final String? customType;
  final String? label;
  final FlowEdgeMarker? markerStart;
  final FlowEdgeMarker? markerEnd;
  final bool selectable;
  final bool deletable;
  final bool reconnectable;
  final bool hidden;
  final bool selected;
  final bool animated;
  final double interactionWidth;
  final Object? data;

  FlowEdge copyWith({
    String? sourceId,
    String? targetId,
    String? sourceHandleId,
    String? targetHandleId,
    FlowEdgeType? type,
    String? customType,
    String? label,
    Color? color,
    double? strokeWidth,
    bool? selected,
  }) =>
      FlowEdge(
        id: id,
        sourceId: sourceId ?? this.sourceId,
        targetId: targetId ?? this.targetId,
        sourceHandleId: sourceHandleId ?? this.sourceHandleId,
        targetHandleId: targetHandleId ?? this.targetHandleId,
        type: type ?? this.type,
        customType: customType ?? this.customType,
        label: label ?? this.label,
        color: color ?? this.color,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        markerStart: markerStart,
        markerEnd: markerEnd,
        selectable: selectable,
        deletable: deletable,
        reconnectable: reconnectable,
        hidden: hidden,
        selected: selected ?? this.selected,
        animated: animated,
        interactionWidth: interactionWidth,
        data: data,
      );
}
