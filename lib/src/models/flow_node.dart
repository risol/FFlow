import 'package:flutter/widgets.dart';

import 'flow_handle.dart';

/// A node placed on an [FFlowCanvas].
///
/// [data] is owned by the application and can hold any immutable value used by
/// its node builder. [position] is in canvas coordinates for root nodes and
/// relative to [parentId] for child nodes.
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
  });

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
    T? data,
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
    String? parentId,
    bool clearParentId = false,
  }) =>
      FlowNode<T>(
        id: id ?? this.id,
        type: type ?? this.type,
        position: position ?? this.position,
        data: data ?? this.data,
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
        parentId: clearParentId ? null : parentId ?? this.parentId,
      );
}
