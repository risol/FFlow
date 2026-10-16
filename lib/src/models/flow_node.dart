import 'package:flutter/widgets.dart';

import 'flow_handle.dart';

const Object _flowNodeUnset = Object();

/// A node placed on an [FFlowCanvas].
///
/// [data] is owned by the application and can hold any immutable value used by
/// its node builder. [position] is in canvas coordinates for root nodes and
/// relative to the parent's top-left for child nodes. [origin] selects the
/// point on the node that is placed at [position].
class FlowNode<T> {
  const FlowNode({
    required this.id,
    required this.position,
    required this.data,
    this.type = 'default',
    this.width = 240,
    this.height = 126,
    this.hasInput = true,
    this.hasOutput = true,
    this.handles = const [],
    this.draggable = true,
    this.resizable = false,
    this.selectable = true,
    this.deletable = true,
    this.connectable = true,
    this.hidden = false,
    this.selected = false,
    this.parentId,
    this.origin = Offset.zero,
    this.extent,
    this.extentToParent = false,
    this.expandParent = false,
    this.minWidth = 80,
    this.minHeight = 48,
    this.maxWidth = 2000,
    this.maxHeight = 2000,
    this.ariaLabel,
    this.focusable = true,
    this.dragHandleOnly = false,
    this.autoMeasure = false,
    this.zIndex = 0,
    this.groupable = false,
  })  : assert(minWidth > 0 && maxWidth >= minWidth),
        assert(minHeight > 0 && maxHeight >= minHeight);

  final String id;
  final String type;
  final Offset position;
  final T data;
  final double width;
  final double height;
  final bool hasInput;
  final bool hasOutput;
  final List<FlowHandle> handles;
  final bool draggable;
  final bool resizable;
  final bool selectable;
  final bool deletable;
  final bool connectable;
  final bool hidden;
  final bool selected;
  final String? parentId;

  /// Normalized point on the node that [position] anchors to. Defaults to its
  /// top-left corner. For example, `Offset(.5, .5)` anchors the center.
  final Offset origin;

  /// Optional allowed bounds in the node's parent coordinate space. The node
  /// is kept inside this rectangle while dragged.
  final Rect? extent;

  /// Keep this node fully inside its parent node while it is dragged.
  final bool extentToParent;

  /// Grow parent nodes when this node is dragged beyond any of their edges.
  final bool expandParent;

  final double minWidth;
  final double minHeight;
  final double maxWidth;
  final double maxHeight;

  /// Accessible label exposed to keyboard and screen-reader users.
  final String? ariaLabel;
  final bool focusable;

  /// When true, only FFlowNodeDragHandle regions inside this node can start
  /// a drag. The node builder must wrap the desired drag region accordingly.
  final bool dragHandleOnly;

  /// Let the canvas size this node to its rendered content. [width] and
  /// [height] provide the initial size until the first layout measurement.
  final bool autoMeasure;

  /// Paint order within the same parent layer. Higher values paint on top.
  final int zIndex;

  /// Allow dynamic reparenting to place nodes inside this node when enabled
  /// on the canvas.
  final bool groupable;

  /// Returns explicitly declared handles, or the default left/right handles.
  List<FlowHandle> get resolvedHandles {
    if (handles.isNotEmpty) return handles;
    return [
      if (hasInput)
        const FlowHandle(
          id: 'target',
          type: FlowHandleType.target,
          position: FlowHandlePosition.left,
        ),
      if (hasOutput)
        const FlowHandle(
          id: 'source',
          type: FlowHandleType.source,
          position: FlowHandlePosition.right,
        ),
    ];
  }

  /// Creates a copy of this node with the supplied values replaced.
  FlowNode<T> copyWith({
    String? id,
    String? type,
    Offset? position,
    Object? data = _flowNodeUnset,
    double? width,
    double? height,
    bool? hasInput,
    bool? hasOutput,
    List<FlowHandle>? handles,
    bool? draggable,
    bool? resizable,
    bool? selectable,
    bool? deletable,
    bool? connectable,
    bool? hidden,
    bool? selected,
    Object? parentId = _flowNodeUnset,
    bool clearParentId = false,
    Offset? origin,
    Object? extent = _flowNodeUnset,
    bool clearExtent = false,
    bool? extentToParent,
    bool? expandParent,
    double? minWidth,
    double? minHeight,
    double? maxWidth,
    double? maxHeight,
    Object? ariaLabel = _flowNodeUnset,
    bool? focusable,
    bool? dragHandleOnly,
    bool? autoMeasure,
    int? zIndex,
    bool? groupable,
  }) =>
      FlowNode<T>(
        id: id ?? this.id,
        type: type ?? this.type,
        position: position ?? this.position,
        data: identical(data, _flowNodeUnset) ? this.data : data as T,
        width: width ?? this.width,
        height: height ?? this.height,
        hasInput: hasInput ?? this.hasInput,
        hasOutput: hasOutput ?? this.hasOutput,
        handles: handles ?? this.handles,
        draggable: draggable ?? this.draggable,
        resizable: resizable ?? this.resizable,
        selectable: selectable ?? this.selectable,
        deletable: deletable ?? this.deletable,
        connectable: connectable ?? this.connectable,
        hidden: hidden ?? this.hidden,
        selected: selected ?? this.selected,
        parentId: clearParentId
            ? null
            : identical(parentId, _flowNodeUnset)
                ? this.parentId
                : parentId as String?,
        origin: origin ?? this.origin,
        extent: clearExtent
            ? null
            : identical(extent, _flowNodeUnset)
                ? this.extent
                : extent as Rect?,
        extentToParent: extentToParent ?? this.extentToParent,
        expandParent: expandParent ?? this.expandParent,
        minWidth: minWidth ?? this.minWidth,
        minHeight: minHeight ?? this.minHeight,
        maxWidth: maxWidth ?? this.maxWidth,
        maxHeight: maxHeight ?? this.maxHeight,
        ariaLabel: identical(ariaLabel, _flowNodeUnset)
            ? this.ariaLabel
            : ariaLabel as String?,
        focusable: focusable ?? this.focusable,
        dragHandleOnly: dragHandleOnly ?? this.dragHandleOnly,
        autoMeasure: autoMeasure ?? this.autoMeasure,
        zIndex: zIndex ?? this.zIndex,
        groupable: groupable ?? this.groupable,
      );
}
