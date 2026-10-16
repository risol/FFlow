part of 'flow_canvas.dart';

extension _FlowCanvasConnections<T> on _FFlowCanvasState<T> {
  void _startConnection(
      FlowNode<T> node, FlowHandle handle, DragStartDetails details) {
    final pointerId =
        _pointerForGesture(_connectionGestureKey(node.id, handle.id));
    if (pointerId == null ||
        !_claimCapturedInteraction(
          FlowInteractionKind.connecting,
          pointerId,
          targetKind: FlowHitTargetKind.connectionHandle,
          nodeId: node.id,
          handleId: handle.id,
        )) {
      return;
    }
    _connectingNodeId = node.id;
    _connectingHandleId = handle.id;
    _connectingHandleType = handle.type;
    _connectionGestureStart = FlowConnectionStart(
      nodeId: node.id,
      handleId: handle.id,
      handleType: handle.type,
    );
    _connectionStartGlobal = details.globalPosition;
    _connectionPointerId = pointerId;
    _connectionThresholdMet = widget.connectionDragThreshold <= 0;
    if (_connectionThresholdMet) {
      widget.onConnectStart?.call(_connectionGestureStart!);
    }
    final renderObject = context.findRenderObject();
    final local = renderObject is RenderBox
        ? renderObject.globalToLocal(details.globalPosition)
        : details.localPosition;
    _connectionStart = FlowGeometry.handleAnchor(
      node,
      handle,
      nodes: {for (final item in _nodes) item.id: item},
    );
    _connectionPoint = _screenToFlow(local);
    _syncConnectionPreview();
    _rebuild(() {});
    _updateConnectionAt(
      _lastPointerGlobalPositions[pointerId] ?? details.globalPosition,
    );
  }

  void _syncConnectionPreview() {
    final start = _connectionStart;
    final point = _connectionPoint;
    final next = start == null || point == null ? null : (start, point);
    if (_connectionPreview.value != next) _connectionPreview.value = next;
  }

  void _updateConnectionAt(Offset globalPosition) {
    if (_connectingNodeId == null && _reconnectingEdgeId == null) return;
    if (!_connectionThresholdMet) {
      final start = _connectionStartGlobal;
      if (start == null ||
          (globalPosition - start).distance < widget.connectionDragThreshold) {
        return;
      }
      _connectionThresholdMet = true;
      final gesture = _connectionGestureStart;
      if (gesture != null) {
        if (gesture.reconnecting) {
          widget.onReconnectStart?.call(gesture);
        } else {
          widget.onConnectStart?.call(gesture);
        }
      }
    }
    _autoPanForGesture(
      globalPosition,
      interaction: FlowAutoPanInteraction.connect,
    );
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) return;
    final local = renderObject.globalToLocal(globalPosition);
    final point = _screenToFlow(local);
    if (_reconnectingEdgeId != null && _reconnectingSource) {
      _connectionStart = point;
    } else {
      _connectionPoint = point;
    }
    _syncConnectionPreview();
  }

  void _endConnection(DragEndDetails details, {Object? gestureKey}) {
    if (gestureKey != null &&
        !_ownsGesturePointer(gestureKey, _connectionPointerId)) {
      return;
    }
    _stopAutoPan();
    if (!_connectionThresholdMet) {
      _rebuild(() {
        _reconnectingEdgeId = null;
        _connectingNodeId = null;
        _connectingHandleId = null;
        _connectingHandleType = null;
        _connectionStart = null;
        _connectionPoint = null;
        _connectionGestureStart = null;
        _connectionStartGlobal = null;
        _connectionThresholdMet = false;
        _syncConnectionPreview();
      });
      final pointerId = _connectionPointerId;
      _connectionPointerId = null;
      if (pointerId != null) _finishInteraction(pointerId);
      return;
    }
    final dropPoint = _scenePointFromGlobal(details.globalPosition);
    final reconnectEdgeId = _reconnectingEdgeId;
    if (reconnectEdgeId != null) {
      final edge =
          _edges.where((item) => item.id == reconnectEdgeId).firstOrNull;
      final point = dropPoint ??
          (_reconnectingSource ? _connectionStart : _connectionPoint);
      FlowConnection? completedConnection;
      if (edge != null && point != null) {
        final nodeMap = {for (final node in _nodes) node.id: node};
        final targetHandle = nodeMap[edge.targetId] == null
            ? null
            : FlowGeometry.handleFor(
                nodeMap[edge.targetId]!,
                edge.targetHandleId,
                edge.targetHandleType,
              );
        final sourceHandle = nodeMap[edge.sourceId] == null
            ? null
            : FlowGeometry.handleFor(
                nodeMap[edge.sourceId]!,
                edge.sourceHandleId,
                FlowHandleType.source,
              );
        final connection = _reconnectingSource
            ? FlowGraphInteraction.sourceConnectionAt(
                nodes: _nodes,
                edges: _edges,
                targetId: edge.targetId,
                targetHandleId: targetHandle?.id,
                point: point,
                excludedEdgeId: edge.id,
                isValidConnection: widget.isValidConnection,
                snapRadius: _sceneSnapRadius,
                targetHandleType: edge.targetHandleType,
                connectionMode: widget.connectionMode,
              )
            : FlowGraphInteraction.connectionAt(
                nodes: _nodes,
                edges: _edges,
                sourceId: edge.sourceId,
                sourceHandleId: sourceHandle?.id,
                point: point,
                excludedEdgeId: edge.id,
                isValidConnection: widget.isValidConnection,
                snapRadius: _sceneSnapRadius,
                connectionMode: widget.connectionMode,
              );
        if (connection != null) {
          completedConnection = connection;
          _edges = FlowGraphInteraction.reconnectEdge(
            edges: _edges,
            edgeId: edge.id,
            connection: connection,
          );
          final updatedEdge = _edges.firstWhere((item) => item.id == edge.id);
          widget.onReconnect?.call(updatedEdge);
          _publishEdges();
        }
      }
      final gesture = _connectionGestureStart;
      if (gesture != null) {
        widget.onReconnectEnd?.call(FlowConnectionEnd(
          start: gesture,
          point: point ?? Offset.zero,
          connection: completedConnection,
          cancelled: completedConnection == null,
        ));
        if (completedConnection == null &&
            point != null &&
            _nodeAt(point) == null) {
          widget.onConnectionDrop
              ?.call(FlowConnectionDrop(start: gesture, point: point));
        }
      }
      _rebuild(() {
        _reconnectingEdgeId = null;
        _connectingNodeId = null;
        _connectingHandleId = null;
        _connectingHandleType = null;
        _connectionStart = null;
        _connectionPoint = null;
        _connectionGestureStart = null;
        _connectionStartGlobal = null;
        _connectionThresholdMet = false;
        _syncConnectionPreview();
      });
      final pointerId = _connectionPointerId;
      _connectionPointerId = null;
      if (pointerId != null) _finishInteraction(pointerId);
      return;
    }

    final sourceId = _connectingNodeId;
    final handleId = _connectingHandleId;
    final point = dropPoint ?? _connectionPoint;
    FlowConnection? completedConnection;
    if (sourceId != null && handleId != null && point != null) {
      final connection = _connectingHandleType == FlowHandleType.target
          ? FlowGraphInteraction.sourceConnectionAt(
              nodes: _nodes,
              edges: _edges,
              targetId: sourceId,
              targetHandleId: handleId,
              point: point,
              isValidConnection: widget.isValidConnection,
              snapRadius: _sceneSnapRadius,
              connectionMode: widget.connectionMode,
            )
          : FlowGraphInteraction.connectionAt(
              nodes: _nodes,
              edges: _edges,
              sourceId: sourceId,
              sourceHandleId: handleId,
              point: point,
              isValidConnection: widget.isValidConnection,
              snapRadius: _sceneSnapRadius,
              connectionMode: widget.connectionMode,
            );
      completedConnection = connection;
      if (connection != null) widget.onConnect?.call(connection);
    }
    final gesture = _connectionGestureStart;
    if (gesture != null) {
      widget.onConnectEnd?.call(FlowConnectionEnd(
        start: gesture,
        point: point ?? Offset.zero,
        connection: completedConnection,
        cancelled: completedConnection == null,
      ));
      if (completedConnection == null &&
          point != null &&
          _nodeAt(point) == null) {
        widget.onConnectionDrop
            ?.call(FlowConnectionDrop(start: gesture, point: point));
      }
    }
    _rebuild(() {
      _connectingNodeId = null;
      _connectingHandleId = null;
      _connectingHandleType = null;
      _connectionStart = null;
      _connectionPoint = null;
      _connectionGestureStart = null;
      _connectionStartGlobal = null;
      _connectionThresholdMet = false;
      _syncConnectionPreview();
    });
    final pointerId = _connectionPointerId;
    _connectionPointerId = null;
    if (pointerId != null) _finishInteraction(pointerId);
  }

  void _completeConnection(Offset? globalPosition) {
    _endConnection(DragEndDetails(
      globalPosition: globalPosition ?? Offset.zero,
      velocity: Velocity.zero,
    ));
  }

  void _cancelConnection([Object? gestureKey]) {
    if (gestureKey != null &&
        !_ownsGesturePointer(gestureKey, _connectionPointerId)) {
      return;
    }
    _stopAutoPan();
    final gesture = _connectionGestureStart;
    final point = _connectionPoint ?? _connectionStart ?? Offset.zero;
    if (gesture != null && _connectionThresholdMet) {
      final event = FlowConnectionEnd(
        start: gesture,
        point: point,
        cancelled: true,
      );
      if (gesture.reconnecting) {
        widget.onReconnectEnd?.call(event);
      } else {
        widget.onConnectEnd?.call(event);
      }
    }
    _rebuild(() {
      _reconnectingEdgeId = null;
      _connectingNodeId = null;
      _connectingHandleId = null;
      _connectingHandleType = null;
      _connectionGestureStart = null;
      _connectionStartGlobal = null;
      _connectionThresholdMet = false;
      _connectionStart = null;
      _connectionPoint = null;
      _syncConnectionPreview();
    });
    final pointerId = _connectionPointerId;
    _connectionPointerId = null;
    if (pointerId != null) _finishInteraction(pointerId);
  }

  double get _sceneSnapRadius =>
      widget.snapRadius / _transformController.value.getMaxScaleOnAxis();

  Offset? _scenePointFromGlobal(Offset globalPosition) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) return null;
    return _screenToFlow(renderObject.globalToLocal(globalPosition));
  }

  void _startReconnect(
      FlowEdge edge, bool sourceSide, DragStartDetails details) {
    final pointerId = _pointerForGesture(
      _reconnectGestureKey(edge.id, sourceSide),
    );
    if (pointerId == null ||
        !_claimCapturedInteraction(
          FlowInteractionKind.reconnecting,
          pointerId,
          targetKind: FlowHitTargetKind.reconnectHandle,
          edgeId: edge.id,
          sourceSide: sourceSide,
        )) {
      return;
    }
    final nodeMap = {for (final node in _nodes) node.id: node};
    final source = FlowGeometry.edgeSource(edge, nodeMap);
    final target = FlowGeometry.edgeTarget(edge, nodeMap);
    if (source == null || target == null) return;
    _reconnectingEdgeId = edge.id;
    _reconnectingSource = sourceSide;
    final nodeId = sourceSide ? edge.sourceId : edge.targetId;
    final handleId = sourceSide ? edge.sourceHandleId : edge.targetHandleId;
    _connectionGestureStart = FlowConnectionStart(
      nodeId: nodeId,
      handleId: handleId,
      handleType: sourceSide ? FlowHandleType.source : edge.targetHandleType,
      edgeId: edge.id,
      reconnecting: true,
    );
    _connectionStartGlobal = details.globalPosition;
    _connectionPointerId = pointerId;
    _connectionThresholdMet = widget.connectionDragThreshold <= 0;
    if (_connectionThresholdMet) {
      widget.onReconnectStart?.call(_connectionGestureStart!);
    }
    _connectionStart = source;
    _connectionPoint = target;
    _syncConnectionPreview();
    _rebuild(() {});
    _updateConnectionAt(
      _lastPointerGlobalPositions[pointerId] ?? details.globalPosition,
    );
  }

  Widget _buildReconnectHandle(FlowEdge edge, bool sourceSide, Offset point) =>
      Positioned(
        left: point.dx + _sceneOffset.dx - 11,
        top: point.dy + _sceneOffset.dy - 11,
        width: 22,
        height: 22,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (event) => _trackGesturePointer(
            _reconnectGestureKey(edge.id, sourceSide),
            event.pointer,
          ),
          child: FlowPort(
            isOutput:
                sourceSide || edge.targetHandleType == FlowHandleType.source,
            enabled: true,
            onPanStart: (details) => _startReconnect(edge, sourceSide, details),
            onPanEnd: (details) => _endConnection(
              details,
              gestureKey: _reconnectGestureKey(edge.id, sourceSide),
            ),
            onPanCancel: () => _cancelConnection(
              _reconnectGestureKey(edge.id, sourceSide),
            ),
          ),
        ),
      );
}
