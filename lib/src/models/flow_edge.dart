import 'package:flutter/painting.dart';

import 'flow_handle.dart';

enum FlowEdgeType { bezier, straight, step, smoothStep, simpleBezier }

enum FlowEdgeMarker { arrow, arrowClosed }

/// Which side of an edge may be moved during reconnection.
enum FlowReconnectable { none, source, target, both }

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
    this.targetHandleType = FlowHandleType.target,
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
    this.reconnectableSource = true,
    this.reconnectableTarget = true,
    this.reconnectableEnds,
    this.curvature = 0.5,
    this.stepPosition = 0.5,
    this.cornerRadius = 8,
    this.markerColor,
    this.ariaLabel,
    this.focusable = true,
    this.floating = false,
    this.zIndex = 0,
  });

  final String id;
  final String sourceId;
  final String targetId;
  final Color? color;
  final double strokeWidth;
  final String? sourceHandleId;
  final String? targetHandleId;

  /// Type of handle at the target endpoint; loose connections may use a source
  /// handle here.
  final FlowHandleType targetHandleType;
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

  /// Fine-grained reconnection permissions. [reconnectable] remains as a
  /// compatibility switch that disables both ends when false.
  final bool reconnectableSource;
  final bool reconnectableTarget;
  final FlowReconnectable? reconnectableEnds;

  /// Bezier control distance as a fraction of the endpoint distance.
  final double curvature;

  /// Position of the central bend for step edges, from 0 to 1.
  final double stepPosition;

  /// Corner radius used by smooth-step edges.
  final double cornerRadius;
  final Color? markerColor;
  final String? ariaLabel;
  final bool focusable;

  /// Resolve endpoints to the nearest point on each node boundary instead of
  /// using the fixed anchors of the selected handles.
  final bool floating;

  /// Paint order. Higher values paint on top of lower-valued edges.
  final int zIndex;

  bool get canReconnectSource =>
      reconnectable &&
      reconnectableSource &&
      (reconnectableEnds == null ||
          reconnectableEnds == FlowReconnectable.source ||
          reconnectableEnds == FlowReconnectable.both);
  bool get canReconnectTarget =>
      reconnectable &&
      reconnectableTarget &&
      (reconnectableEnds == null ||
          reconnectableEnds == FlowReconnectable.target ||
          reconnectableEnds == FlowReconnectable.both);

  FlowEdge copyWith({
    String? sourceId,
    String? targetId,
    String? sourceHandleId,
    String? targetHandleId,
    FlowHandleType? targetHandleType,
    FlowEdgeType? type,
    String? customType,
    String? label,
    Color? color,
    double? strokeWidth,
    bool? selected,
    bool? reconnectable,
    bool? reconnectableSource,
    bool? reconnectableTarget,
    FlowReconnectable? reconnectableEnds,
    double? curvature,
    double? stepPosition,
    double? cornerRadius,
    Color? markerColor,
    String? ariaLabel,
    bool? focusable,
    bool? floating,
    int? zIndex,
  }) =>
      FlowEdge(
        id: id,
        sourceId: sourceId ?? this.sourceId,
        targetId: targetId ?? this.targetId,
        sourceHandleId: sourceHandleId ?? this.sourceHandleId,
        targetHandleId: targetHandleId ?? this.targetHandleId,
        targetHandleType: targetHandleType ?? this.targetHandleType,
        type: type ?? this.type,
        customType: customType ?? this.customType,
        label: label ?? this.label,
        color: color ?? this.color,
        strokeWidth: strokeWidth ?? this.strokeWidth,
        markerStart: markerStart,
        markerEnd: markerEnd,
        selectable: selectable,
        deletable: deletable,
        reconnectable: reconnectable ?? this.reconnectable,
        hidden: hidden,
        selected: selected ?? this.selected,
        animated: animated,
        interactionWidth: interactionWidth,
        data: data,
        reconnectableSource: reconnectableSource ?? this.reconnectableSource,
        reconnectableTarget: reconnectableTarget ?? this.reconnectableTarget,
        reconnectableEnds: reconnectableEnds ?? this.reconnectableEnds,
        curvature: curvature ?? this.curvature,
        stepPosition: stepPosition ?? this.stepPosition,
        cornerRadius: cornerRadius ?? this.cornerRadius,
        markerColor: markerColor ?? this.markerColor,
        ariaLabel: ariaLabel ?? this.ariaLabel,
        focusable: focusable ?? this.focusable,
        floating: floating ?? this.floating,
        zIndex: zIndex ?? this.zIndex,
      );
}
