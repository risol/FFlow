import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart';

import 'flow_edge.dart';
import 'flow_handle.dart';
import 'flow_node.dart';
import 'flow_viewport.dart';

/// Serializable graph state, including the current viewport.
///
/// Node data stays application-defined. Supply [encodeNodeData] and
/// [decodeNodeData] when converting snapshots to or from JSON.
class FlowGraphSnapshot<T> {
  FlowGraphSnapshot({
    required Iterable<FlowNode<T>> nodes,
    required Iterable<FlowEdge> edges,
    required this.viewport,
  })  : nodes = List.unmodifiable(nodes),
        edges = List.unmodifiable(edges);

  final List<FlowNode<T>> nodes;
  final List<FlowEdge> edges;
  final FlowViewport viewport;

  Map<String, Object?> toJson({
    required Object? Function(T data) encodeNodeData,
    Object? Function(Object? data)? encodeEdgeData,
  }) =>
      {
        'nodes': [
          for (final node in nodes)
            {
              'id': node.id,
              'type': node.type,
              'position': {'x': node.position.dx, 'y': node.position.dy},
              'data': encodeNodeData(node.data),
              'width': node.width,
              'height': node.height,
              'hasInput': node.hasInput,
              'hasOutput': node.hasOutput,
              'handles': [
                for (final handle in node.handles)
                  {
                    'id': handle.id,
                    'type': handle.type.name,
                    'position': handle.position.name,
                    'offset': handle.offset,
                    'connectable': handle.connectable,
                    'connectableStart': handle.connectableStart,
                    'connectableEnd': handle.connectableEnd,
                    'maxConnections': handle.maxConnections,
                  },
              ],
              'draggable': node.draggable,
              'resizable': node.resizable,
              'selectable': node.selectable,
              'deletable': node.deletable,
              'connectable': node.connectable,
              'hidden': node.hidden,
              'selected': node.selected,
              'parentId': node.parentId,
              'origin': {'x': node.origin.dx, 'y': node.origin.dy},
              'extent': node.extent == null
                  ? null
                  : {
                      'left': node.extent!.left,
                      'top': node.extent!.top,
                      'right': node.extent!.right,
                      'bottom': node.extent!.bottom,
                    },
              'extentToParent': node.extentToParent,
              'expandParent': node.expandParent,
              'minWidth': node.minWidth,
              'minHeight': node.minHeight,
              'maxWidth': node.maxWidth,
              'maxHeight': node.maxHeight,
              'ariaLabel': node.ariaLabel,
              'focusable': node.focusable,
              'dragHandleOnly': node.dragHandleOnly,
              'autoMeasure': node.autoMeasure,
              'zIndex': node.zIndex,
            },
        ],
        'edges': [
          for (final edge in edges)
            {
              'id': edge.id,
              'source': edge.sourceId,
              'target': edge.targetId,
              'sourceHandle': edge.sourceHandleId,
              'targetHandle': edge.targetHandleId,
              'targetHandleType': edge.targetHandleType.name,
              'type': edge.type.name,
              'customType': edge.customType,
              'label': edge.label,
              'color': edge.color?.toARGB32(),
              'strokeWidth': edge.strokeWidth,
              'markerStart': edge.markerStart?.name,
              'markerEnd': edge.markerEnd?.name,
              'selectable': edge.selectable,
              'selected': edge.selected,
              'deletable': edge.deletable,
              'reconnectable': edge.reconnectable,
              'reconnectableSource': edge.reconnectableSource,
              'reconnectableTarget': edge.reconnectableTarget,
              'reconnectableEnds': edge.reconnectableEnds?.name,
              'curvature': edge.curvature,
              'stepPosition': edge.stepPosition,
              'cornerRadius': edge.cornerRadius,
              'markerColor': edge.markerColor?.toARGB32(),
              'ariaLabel': edge.ariaLabel,
              'focusable': edge.focusable,
              'hidden': edge.hidden,
              'animated': edge.animated,
              'interactionWidth': edge.interactionWidth,
              'floating': edge.floating,
              'zIndex': edge.zIndex,
              'data': encodeEdgeData == null
                  ? edge.data
                  : encodeEdgeData(edge.data),
            },
        ],
        'viewport': viewport.toJson(),
      };

  factory FlowGraphSnapshot.fromJson(
    Map<String, Object?> json, {
    required T Function(Object? value) decodeNodeData,
    Object? Function(Object? value)? decodeEdgeData,
  }) {
    final nodes = (json['nodes'] as List<Object?>).map((entry) {
      final map = entry! as Map<String, Object?>;
      final position = map['position']! as Map<String, Object?>;
      final origin = map['origin'] as Map<String, Object?>?;
      final extent = map['extent'] as Map<String, Object?>?;
      final handles =
          (map['handles'] as List<Object?>? ?? const []).map((entry) {
        final handle = entry! as Map<String, Object?>;
        return FlowHandle(
          id: handle['id']! as String,
          type: FlowHandleType.values.byName(handle['type']! as String),
          position:
              FlowHandlePosition.values.byName(handle['position']! as String),
          offset: (handle['offset'] as num? ?? 0.5).toDouble(),
          connectable: handle['connectable'] as bool? ?? true,
          connectableStart: handle['connectableStart'] as bool? ?? true,
          connectableEnd: handle['connectableEnd'] as bool? ?? true,
          maxConnections: (handle['maxConnections'] as num?)?.toInt(),
        );
      }).toList(growable: false);
      return FlowNode<T>(
        id: map['id']! as String,
        type: map['type'] as String? ?? 'default',
        position: Offset(
          (position['x']! as num).toDouble(),
          (position['y']! as num).toDouble(),
        ),
        data: decodeNodeData(map['data']),
        width: (map['width'] as num? ?? 240).toDouble(),
        height: (map['height'] as num? ?? 126).toDouble(),
        hasInput: map['hasInput'] as bool? ?? true,
        hasOutput: map['hasOutput'] as bool? ?? true,
        handles: handles,
        draggable: map['draggable'] as bool? ?? true,
        resizable: map['resizable'] as bool? ?? false,
        selectable: map['selectable'] as bool? ?? true,
        deletable: map['deletable'] as bool? ?? true,
        connectable: map['connectable'] as bool? ?? true,
        hidden: map['hidden'] as bool? ?? false,
        selected: map['selected'] as bool? ?? false,
        parentId: map['parentId'] as String?,
        origin: origin == null
            ? Offset.zero
            : Offset((origin['x'] as num? ?? 0).toDouble(),
                (origin['y'] as num? ?? 0).toDouble()),
        extent: extent == null
            ? null
            : Rect.fromLTRB(
                (extent['left'] as num).toDouble(),
                (extent['top'] as num).toDouble(),
                (extent['right'] as num).toDouble(),
                (extent['bottom'] as num).toDouble(),
              ),
        extentToParent: map['extentToParent'] as bool? ?? false,
        expandParent: map['expandParent'] as bool? ?? false,
        minWidth: (map['minWidth'] as num? ?? 80).toDouble(),
        minHeight: (map['minHeight'] as num? ?? 48).toDouble(),
        maxWidth: (map['maxWidth'] as num? ?? 2000).toDouble(),
        maxHeight: (map['maxHeight'] as num? ?? 2000).toDouble(),
        ariaLabel: map['ariaLabel'] as String?,
        focusable: map['focusable'] as bool? ?? true,
        dragHandleOnly: map['dragHandleOnly'] as bool? ?? false,
        autoMeasure: map['autoMeasure'] as bool? ?? false,
        zIndex: (map['zIndex'] as num? ?? 0).toInt(),
      );
    }).toList(growable: false);

    final edges = (json['edges'] as List<Object?>).map((entry) {
      final map = entry! as Map<String, Object?>;
      return FlowEdge(
        id: map['id']! as String,
        sourceId: map['source']! as String,
        targetId: map['target']! as String,
        sourceHandleId: map['sourceHandle'] as String?,
        targetHandleId: map['targetHandle'] as String?,
        targetHandleType: FlowHandleType.values.byName(
          map['targetHandleType'] as String? ?? FlowHandleType.target.name,
        ),
        type: FlowEdgeType.values.byName(map['type'] as String? ?? 'bezier'),
        customType: map['customType'] as String?,
        label: map['label'] as String?,
        color:
            map['color'] == null ? null : Color((map['color'] as num).toInt()),
        strokeWidth: (map['strokeWidth'] as num? ?? 2).toDouble(),
        markerStart: _marker(map['markerStart'] as String?),
        markerEnd: _marker(map['markerEnd'] as String?),
        selectable: map['selectable'] as bool? ?? true,
        selected: map['selected'] as bool? ?? false,
        deletable: map['deletable'] as bool? ?? true,
        reconnectable: map['reconnectable'] as bool? ?? true,
        reconnectableSource: map['reconnectableSource'] as bool? ?? true,
        reconnectableTarget: map['reconnectableTarget'] as bool? ?? true,
        reconnectableEnds: map['reconnectableEnds'] == null
            ? null
            : FlowReconnectable.values
                .byName(map['reconnectableEnds'] as String),
        curvature: (map['curvature'] as num? ?? 0.5).toDouble(),
        stepPosition: (map['stepPosition'] as num? ?? 0.5).toDouble(),
        cornerRadius: (map['cornerRadius'] as num? ?? 8).toDouble(),
        markerColor: map['markerColor'] == null
            ? null
            : Color((map['markerColor'] as num).toInt()),
        ariaLabel: map['ariaLabel'] as String?,
        focusable: map['focusable'] as bool? ?? true,
        hidden: map['hidden'] as bool? ?? false,
        animated: map['animated'] as bool? ?? false,
        interactionWidth: (map['interactionWidth'] as num? ?? 20).toDouble(),
        floating: map['floating'] as bool? ?? false,
        zIndex: (map['zIndex'] as num? ?? 0).toInt(),
        data:
            decodeEdgeData == null ? map['data'] : decodeEdgeData(map['data']),
      );
    }).toList(growable: false);

    return FlowGraphSnapshot<T>(
      nodes: nodes,
      edges: edges,
      viewport:
          FlowViewport.fromJson(json['viewport']! as Map<String, Object?>),
    );
  }

  static FlowEdgeMarker? _marker(String? name) =>
      name == null ? null : FlowEdgeMarker.values.byName(name);
}
