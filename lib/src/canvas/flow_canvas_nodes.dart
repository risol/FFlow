part of 'flow_canvas.dart';

extension _FlowCanvasNodes<T> on _FFlowCanvasState<T> {
  int _nodeDepth(FlowNode<T> node, Map<String, FlowNode<T>> nodesById) {
    var depth = 0;
    var parentId = node.parentId;
    final visited = <String>{node.id};
    while (parentId != null && visited.add(parentId)) {
      final parent = nodesById[parentId];
      if (parent == null) break;
      depth++;
      parentId = parent.parentId;
    }
    return depth;
  }

  List<FlowNode<T>> _orderedVisibleNodes(Map<String, FlowNode<T>> nodesById) {
    final order = {
      for (var index = 0; index < _nodes.length; index++)
        _nodes[index].id: index,
    };
    return _nodes
        .where((node) => FlowGeometry.isVisible(node, nodesById))
        .toList()
      ..sort((first, second) {
        final depth =
            _nodeDepth(first, nodesById) - _nodeDepth(second, nodesById);
        return depth != 0
            ? depth
            : first.zIndex != second.zIndex
                ? first.zIndex.compareTo(second.zIndex)
                : widget.elevateNodesOnSelect &&
                        _selectedNodes.contains(first.id) !=
                            _selectedNodes.contains(second.id)
                    ? _selectedNodes.contains(first.id)
                        ? 1
                        : -1
                    : order[first.id]!.compareTo(order[second.id]!);
      });
  }

  List<FlowEdge> _orderedVisibleEdges() {
    final order = {
      for (var index = 0; index < _edges.length; index++)
        _edges[index].id: index,
    };
    return List<FlowEdge>.of(_edges)
      ..sort((first, second) {
        if (first.zIndex != second.zIndex) {
          return first.zIndex.compareTo(second.zIndex);
        }
        if (widget.elevateEdgesOnSelect &&
            _selectedEdges.contains(first.id) !=
                _selectedEdges.contains(second.id)) {
          return _selectedEdges.contains(first.id) ? 1 : -1;
        }
        return order[first.id]!.compareTo(order[second.id]!);
      });
  }

  Widget _buildNode(
      FlowNode<T> node, Map<String, FlowNode<T>> nodesById, int order) {
    final selected = _selectedNodes.contains(node.id);
    final position = FlowGeometry.absolutePosition(node, nodesById);
    final focusNode = _nodeFocusNode(node.id);
    final content = MouseRegion(
      onEnter: (event) => widget.onNodeMouseEnter?.call(
        node,
        _pointerPosition(event.position, event.kind),
      ),
      onHover: (event) => widget.onNodeMouseMove?.call(
        node,
        _pointerPosition(event.position, event.kind),
      ),
      onExit: (event) => widget.onNodeMouseLeave?.call(
        node,
        _pointerPosition(event.position, event.kind),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_pointerDownNodeId == node.id &&
              !_nodeWasSelectedOnPointerDown &&
              _selectedNodes.contains(node.id)) {
            widget.onNodeClick?.call(node.id);
            _pointerDownNodeId = null;
            return;
          }
          _selectNode(node.id, toggle: _multiSelectPressed);
          widget.onNodeClick?.call(node.id);
          _pointerDownNodeId = null;
        },
        onDoubleTap: () => widget.onNodeDoubleClick?.call(node),
        onPanStart: node.draggable && !node.dragHandleOnly
            ? (details) => _startNodeDrag(node, details)
            : null,
        onPanUpdate:
            node.draggable && !node.dragHandleOnly ? _updateNodeDrag : null,
        onPanEnd: node.draggable && !node.dragHandleOnly ? _endNodeDrag : null,
        onPanCancel:
            node.draggable && !node.dragHandleOnly ? _cancelNodeDrag : null,
        child: _FlowNodeDragScope(
          onPanStart: node.draggable
              ? (details) => _startNodeDrag(node, details)
              : null,
          onPanUpdate: node.draggable ? _updateNodeDrag : null,
          onPanEnd: node.draggable ? _endNodeDrag : null,
          onPanCancel: node.draggable ? _cancelNodeDrag : null,
          child: widget.nodeBuilder(context, node, selected),
        ),
      ),
    );
    final nodeStack = Stack(
      clipBehavior: Clip.none,
      children: [
        if (node.autoMeasure) content else Positioned.fill(child: content),
        for (final handle in node.resolvedHandles)
          _buildHandle(node, handle, nodesById, position),
        if (selected && node.resizable)
          for (final direction in _FlowResizeDirection.values)
            _buildNodeResizeHandle(node, direction),
      ],
    );
    final sizedStack = node.autoMeasure
        ? ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: node.minWidth,
              maxWidth: node.maxWidth,
              minHeight: node.minHeight,
              maxHeight: node.maxHeight,
            ),
            child: nodeStack,
          )
        : nodeStack;
    final semantics = FocusTraversalOrder(
      order: NumericFocusOrder(order.toDouble()),
      child: Focus(
        focusNode: focusNode,
        canRequestFocus: node.focusable,
        skipTraversal: !node.focusable,
        onFocusChange: (focused) {
          if (focused) _keepNodeInView(node.id);
          if (mounted) _rebuild(() {});
        },
        onKeyEvent: (focus, event) => _handleNodeKey(node, event),
        child: Semantics(
          container: true,
          explicitChildNodes: true,
          label: node.ariaLabel ?? '${node.type} node ${node.id}',
          button: true,
          focusable: node.focusable,
          focused: focusNode.hasFocus,
          selected: selected,
          onTap: node.selectable
              ? () {
                  _selectNode(node.id, toggle: false);
                  widget.onNodeClick?.call(node.id);
                }
              : null,
          child: sizedStack,
        ),
      ),
    );
    return Positioned(
      left: position.dx,
      top: position.dy,
      width: node.autoMeasure ? null : node.width,
      height: node.autoMeasure ? null : node.height,
      child: node.autoMeasure
          ? _FlowMeasureSize(
              onChange: (size) => _handleNodeMeasured(node.id, size),
              child: semantics,
            )
          : semantics,
    );
  }

  void _handleNodeMeasured(String nodeId, Size size) {
    if (!mounted) return;
    final index = _nodes.indexWhere((node) => node.id == nodeId);
    if (index < 0 || !_nodes[index].autoMeasure) return;
    final node = _nodes[index];
    final width = size.width.clamp(node.minWidth, node.maxWidth).toDouble();
    final height = size.height.clamp(node.minHeight, node.maxHeight).toDouble();
    if ((node.width - width).abs() < 0.5 &&
        (node.height - height).abs() < 0.5) {
      return;
    }
    final next = List<FlowNode<T>>.of(_nodes);
    next[index] = node.copyWith(width: width, height: height);
    _nodes = List.unmodifiable(next);
    _expandParentsForNode(nodeId);
    _publishNodes();
    _rebuild(() {});
  }

  Widget _buildNodeResizeHandle(
    FlowNode<T> node,
    _FlowResizeDirection direction,
  ) {
    const cornerSize = 12.0;
    const sideSize = 18.0;
    final width = direction.x == 0 ? sideSize : cornerSize;
    final height = direction.y == 0 ? sideSize : cornerSize;
    return Positioned(
      left: direction.x < 0
          ? -cornerSize / 2
          : direction.x == 0
              ? node.width / 2 - width / 2
              : null,
      right: direction.x > 0 ? -cornerSize / 2 : null,
      top: direction.y < 0
          ? -cornerSize / 2
          : direction.y == 0
              ? node.height / 2 - height / 2
              : null,
      bottom: direction.y > 0 ? -cornerSize / 2 : null,
      width: width,
      height: height,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanStart: (details) => _startNodeResize(node, direction, details),
        onPanUpdate: _updateNodeResize,
        onPanEnd: _endNodeResize,
        onPanCancel: _cancelNodeResize,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: widget.connectionColor,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: Colors.white, width: 1.5),
          ),
        ),
      ),
    );
  }

  bool _canStartConnection(FlowNode<T> node, FlowHandle handle) {
    if (!node.connectable ||
        !handle.connectable ||
        !handle.connectableStart ||
        (handle.type == FlowHandleType.target &&
            widget.connectionMode != FlowConnectionMode.loose)) {
      return false;
    }
    final count = FlowGraphInteraction.getHandleConnectionCount(
      nodes: _nodes,
      edges: _edges,
      nodeId: node.id,
      handleId: handle.id,
      type: handle.type,
    );
    return count < (handle.maxConnections ?? 1 << 30);
  }

  bool _canCompleteConnection(FlowNode<T> node, FlowHandle handle) {
    final startingType = _connectingHandleType;
    final compatibleTypes = startingType != handle.type ||
        (widget.connectionMode == FlowConnectionMode.loose &&
            startingType == FlowHandleType.source &&
            handle.type == FlowHandleType.source);
    final connectionCount = FlowGraphInteraction.getHandleConnectionCount(
      nodes: _nodes,
      edges: _edges,
      nodeId: node.id,
      handleId: handle.id,
      type: handle.type,
    );
    return _connectingNodeId != null &&
        compatibleTypes &&
        node.connectable &&
        handle.connectable &&
        handle.connectableEnd &&
        connectionCount < (handle.maxConnections ?? 1 << 30);
  }

  void _handleHandleTap(FlowNode<T> node, FlowHandle handle) {
    if (!widget.connectOnClick) return;
    if (_connectingNodeId == null) {
      if (!_canStartConnection(node, handle)) return;
      _connectingNodeId = node.id;
      _connectingHandleId = handle.id;
      _connectingHandleType = handle.type;
      _connectionGestureStart = FlowConnectionStart(
        nodeId: node.id,
        handleId: handle.id,
        handleType: handle.type,
      );
      widget.onConnectStart?.call(_connectionGestureStart!);
      final anchor = FlowGeometry.handleAnchor(
        node,
        handle,
        nodes: {for (final item in _nodes) item.id: item},
      );
      _connectionStart = anchor;
      _connectionPoint = anchor;
      _rebuild(() {});
      return;
    }

    if (!_canCompleteConnection(node, handle)) {
      if (_canStartConnection(node, handle)) {
        final oldStart = _connectionGestureStart;
        if (oldStart != null) {
          widget.onConnectEnd?.call(FlowConnectionEnd(
            start: oldStart,
            point: _connectionPoint ?? Offset.zero,
            cancelled: true,
          ));
        }
        _connectingNodeId = null;
        _connectingHandleId = null;
        _connectingHandleType = null;
        _connectionStart = null;
        _connectionPoint = null;
        _connectionGestureStart = null;
        _handleHandleTap(node, handle);
      }
      return;
    }

    final nodesById = {for (final item in _nodes) item.id: item};
    final point = FlowGeometry.handleAnchor(node, handle, nodes: nodesById);
    final start = _connectionGestureStart;
    FlowConnection? connection;
    if (start != null && _connectingNodeId != node.id) {
      connection = start.handleType == FlowHandleType.source
          ? FlowGraphInteraction.connectionAt(
              nodes: _nodes,
              edges: _edges,
              sourceId: start.nodeId,
              sourceHandleId: start.handleId,
              point: point,
              isValidConnection: widget.isValidConnection,
              snapRadius: 2,
              connectionMode: widget.connectionMode,
            )
          : FlowGraphInteraction.sourceConnectionAt(
              nodes: _nodes,
              edges: _edges,
              targetId: start.nodeId,
              targetHandleId: start.handleId,
              point: point,
              isValidConnection: widget.isValidConnection,
              snapRadius: 2,
              connectionMode: widget.connectionMode,
            );
    }
    if (connection != null) widget.onConnect?.call(connection);
    if (start != null) {
      widget.onConnectEnd?.call(FlowConnectionEnd(
        start: start,
        point: point,
        connection: connection,
        cancelled: connection == null,
      ));
    }
    _rebuild(() {
      _connectingNodeId = null;
      _connectingHandleId = null;
      _connectingHandleType = null;
      _connectionStart = null;
      _connectionPoint = null;
      _connectionGestureStart = null;
    });
  }

  Widget _buildHandle(
    FlowNode<T> node,
    FlowHandle handle,
    Map<String, FlowNode<T>> nodesById,
    Offset nodePosition,
  ) {
    final anchor = FlowGeometry.handleAnchor(node, handle, nodes: nodesById);
    final canStart = _canStartConnection(node, handle);
    final canFinish = _canCompleteConnection(node, handle);
    return Positioned(
      left: anchor.dx - nodePosition.dx - 11,
      top: anchor.dy - nodePosition.dy - 11,
      width: 22,
      height: 22,
      child: FlowPort(
        isOutput: handle.type == FlowHandleType.source,
        enabled: canStart || canFinish,
        onTap:
            widget.connectOnClick ? () => _handleHandleTap(node, handle) : null,
        onPanStart: canStart
            ? (details) => _startConnection(node, handle, details)
            : null,
        onPanUpdate: canStart ? _updateConnection : null,
        onPanEnd: canStart ? _endConnection : null,
        onPanCancel: canStart ? _cancelConnection : null,
      ),
    );
  }
}
