part of 'flow_canvas.dart';

extension _FlowCanvasChanges<T> on _FFlowCanvasState<T> {
  List<FlowNodeChange<T>> _diffNodes(
    List<FlowNode<T>> previous,
    List<FlowNode<T>> current,
  ) {
    final previousById = {for (final node in previous) node.id: node};
    final currentIds = current.map((node) => node.id).toSet();
    final changes = <FlowNodeChange<T>>[];

    for (var index = previous.length - 1; index >= 0; index--) {
      final node = previous[index];
      if (!currentIds.contains(node.id)) {
        changes.add(FlowNodeChange<T>(
          type: FlowNodeChangeType.remove,
          id: node.id,
          index: index,
        ));
      }
    }

    for (var index = 0; index < current.length; index++) {
      final node = current[index];
      final old = previousById[node.id];
      if (old == null) {
        changes.add(FlowNodeChange<T>(
          type: FlowNodeChangeType.add,
          id: node.id,
          node: node,
          index: index,
        ));
        continue;
      }

      if (!_sameNodeConfiguration(old, node)) {
        changes.add(FlowNodeChange<T>(
          type: FlowNodeChangeType.replace,
          id: node.id,
          node: node,
        ));
        continue;
      }
      if (old.position != node.position) {
        changes.add(FlowNodeChange<T>(
          type: FlowNodeChangeType.position,
          id: node.id,
          position: node.position,
        ));
      }
      if (old.width != node.width || old.height != node.height) {
        changes.add(FlowNodeChange<T>(
          type: FlowNodeChangeType.dimensions,
          id: node.id,
          size: Size(node.width, node.height),
        ));
      }
      if (old.selected != node.selected) {
        changes.add(FlowNodeChange<T>(
          type: FlowNodeChangeType.select,
          id: node.id,
          selected: node.selected,
        ));
      }
    }
    return changes;
  }

  List<FlowEdgeChange> _diffEdges(
    List<FlowEdge> previous,
    List<FlowEdge> current,
  ) {
    final previousById = {for (final edge in previous) edge.id: edge};
    final currentIds = current.map((edge) => edge.id).toSet();
    final changes = <FlowEdgeChange>[];

    for (var index = previous.length - 1; index >= 0; index--) {
      final edge = previous[index];
      if (!currentIds.contains(edge.id)) {
        changes.add(FlowEdgeChange(
          type: FlowEdgeChangeType.remove,
          id: edge.id,
          index: index,
        ));
      }
    }

    for (var index = 0; index < current.length; index++) {
      final edge = current[index];
      final old = previousById[edge.id];
      if (old == null) {
        changes.add(FlowEdgeChange(
          type: FlowEdgeChangeType.add,
          id: edge.id,
          edge: edge,
          index: index,
        ));
      } else if (!_sameEdgeConfiguration(old, edge)) {
        changes.add(FlowEdgeChange(
          type: FlowEdgeChangeType.replace,
          id: edge.id,
          edge: edge,
        ));
      } else if (old.selected != edge.selected) {
        changes.add(FlowEdgeChange(
          type: FlowEdgeChangeType.select,
          id: edge.id,
          selected: edge.selected,
        ));
      }
    }
    return changes;
  }

  bool _sameNodeConfiguration(FlowNode<T> a, FlowNode<T> b) =>
      a.id == b.id &&
      a.type == b.type &&
      a.data == b.data &&
      _sameHandles(a.handles, b.handles) &&
      a.hasInput == b.hasInput &&
      a.hasOutput == b.hasOutput &&
      a.draggable == b.draggable &&
      a.resizable == b.resizable &&
      a.selectable == b.selectable &&
      a.deletable == b.deletable &&
      a.connectable == b.connectable &&
      a.hidden == b.hidden &&
      a.parentId == b.parentId &&
      a.origin == b.origin &&
      a.extent == b.extent &&
      a.extentToParent == b.extentToParent &&
      a.expandParent == b.expandParent &&
      a.minWidth == b.minWidth &&
      a.minHeight == b.minHeight &&
      a.maxWidth == b.maxWidth &&
      a.maxHeight == b.maxHeight &&
      a.ariaLabel == b.ariaLabel &&
      a.focusable == b.focusable &&
      a.dragHandleOnly == b.dragHandleOnly &&
      a.autoMeasure == b.autoMeasure &&
      a.zIndex == b.zIndex;

  bool _sameHandles(List<FlowHandle> a, List<FlowHandle> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final left = a[i];
      final right = b[i];
      if (left.id != right.id ||
          left.type != right.type ||
          left.position != right.position ||
          left.offset != right.offset ||
          left.connectable != right.connectable ||
          left.connectableStart != right.connectableStart ||
          left.connectableEnd != right.connectableEnd ||
          left.maxConnections != right.maxConnections) {
        return false;
      }
    }
    return true;
  }

  bool _sameEdgeConfiguration(FlowEdge a, FlowEdge b) =>
      a.id == b.id &&
      a.sourceId == b.sourceId &&
      a.targetId == b.targetId &&
      a.color == b.color &&
      a.strokeWidth == b.strokeWidth &&
      a.sourceHandleId == b.sourceHandleId &&
      a.targetHandleId == b.targetHandleId &&
      a.targetHandleType == b.targetHandleType &&
      a.type == b.type &&
      a.customType == b.customType &&
      a.label == b.label &&
      a.markerStart == b.markerStart &&
      a.markerEnd == b.markerEnd &&
      a.selectable == b.selectable &&
      a.deletable == b.deletable &&
      a.reconnectable == b.reconnectable &&
      a.hidden == b.hidden &&
      a.animated == b.animated &&
      a.interactionWidth == b.interactionWidth &&
      a.data == b.data &&
      a.reconnectableSource == b.reconnectableSource &&
      a.reconnectableTarget == b.reconnectableTarget &&
      a.reconnectableEnds == b.reconnectableEnds &&
      a.curvature == b.curvature &&
      a.stepPosition == b.stepPosition &&
      a.cornerRadius == b.cornerRadius &&
      a.markerColor == b.markerColor &&
      a.ariaLabel == b.ariaLabel &&
      a.focusable == b.focusable &&
      a.floating == b.floating &&
      a.zIndex == b.zIndex;
}
