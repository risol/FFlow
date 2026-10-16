part of 'flow_canvas.dart';

extension _FlowCanvasInteraction<T> on _FFlowCanvasState<T> {
  void _handleCanvasFocusChanged() {
    if (!_focusNode.hasFocus && _interactionSession != null) {
      _cancelActiveInteraction();
    }
  }

  Object _nodeGestureKey(String nodeId) => ('node', nodeId);

  Object _resizeGestureKey(String nodeId, _FlowResizeDirection direction) =>
      ('resize', nodeId, direction.index);

  Object _connectionGestureKey(String nodeId, String handleId) =>
      ('connection', nodeId, handleId);

  Object _reconnectGestureKey(String edgeId, bool sourceSide) =>
      ('reconnect', edgeId, sourceSide);

  void _trackGesturePointer(Object gestureKey, int pointerId) {
    (_gesturePointerIds[gestureKey] ??= <int>{}).add(pointerId);
  }

  int? _pointerForGesture(Object gestureKey) {
    final pointers = _gesturePointerIds[gestureKey];
    if (pointers == null) return null;
    for (final pointerId in pointers.toList().reversed) {
      if (_pointerCaptures.containsKey(pointerId)) return pointerId;
    }
    return null;
  }

  bool _ownsGesturePointer(Object gestureKey, int? pointerId) =>
      pointerId != null && _pointerForGesture(gestureKey) == pointerId;

  bool _claimCapturedInteraction(
    FlowInteractionKind kind,
    int pointerId, {
    required FlowHitTargetKind targetKind,
    String? nodeId,
    String? edgeId,
    String? handleId,
    bool? sourceSide,
    int? resizeDirection,
  }) {
    final capture = _pointerCaptures[pointerId];
    if (capture == null) return false;
    final target = capture.target;
    if (target.kind != targetKind ||
        (nodeId != null && target.nodeId != nodeId) ||
        (edgeId != null && target.edgeId != edgeId) ||
        (handleId != null && target.handleId != handleId) ||
        (sourceSide != null && target.sourceSide != sourceSide) ||
        (resizeDirection != null &&
            target.resizeDirection != resizeDirection)) {
      return false;
    }
    final current = _interactionSession;
    if (current != null &&
        (current.pointerId != pointerId ||
            (current.kind != FlowInteractionKind.pressed &&
                current.kind != kind))) {
      return false;
    }
    _interactionSession = FlowInteractionSession(
      pointerId: pointerId,
      kind: kind,
      target: target,
      downFlowPosition: capture.downFlowPosition,
      movingNodeIds: current?.movingNodeIds ?? const <String>{},
    );
    return true;
  }

  void _finishInteraction(int pointerId) {
    if (_interactionSession?.pointerId == pointerId) {
      _interactionSession = null;
    }
  }

  void _beginCanvasPanInteraction() {
    final current = _interactionSession;
    if (current == null || current.kind == FlowInteractionKind.canvasPanning) {
      return;
    }
    if (current.kind == FlowInteractionKind.pressed &&
        current.target.kind == FlowHitTargetKind.pane &&
        _selectionCandidatePointerId != current.pointerId) {
      _interactionSession = current.withKind(FlowInteractionKind.canvasPanning);
    }
  }

  void _endCanvasPanInteraction() {
    if (_interactionSession?.kind == FlowInteractionKind.canvasPanning) {
      _interactionSession = null;
    }
  }

  void _releasePointer(
    int pointerId, {
    required bool cancelled,
    Offset? globalPosition,
  }) {
    final session = _interactionSession;
    if (session?.pointerId == pointerId) {
      if (cancelled) {
        _cancelActiveInteraction();
      } else {
        switch (session!.kind) {
          case FlowInteractionKind.nodeDragging:
            _completeNodeDrag();
          case FlowInteractionKind.nodeResizing:
            _completeNodeResize();
          case FlowInteractionKind.connecting:
          case FlowInteractionKind.reconnecting:
            _completeConnection(globalPosition);
          case FlowInteractionKind.selectionDragging:
          case FlowInteractionKind.canvasPanning:
            _interactionSession = null;
          case FlowInteractionKind.pressed:
            _interactionSession = null;
            if (_pendingNodeDragPointerId == pointerId) {
              _pendingNodeDragId = null;
              _pendingNodeDragPointerId = null;
              _nodeDragStartGlobal = null;
              _lastDragFlowPosition = null;
            }
        }
      }
    }

    _pointerCaptures.remove(pointerId);
    _FlowInteractionLocks.noDrag.remove(pointerId);
    _FlowInteractionLocks.noPan.remove(pointerId);
    _FlowInteractionLocks.dragHandle.remove(pointerId);
    if (_pointerCaptures.isEmpty) {
      _pointerNoDrag = false;
      _pointerNoPan = false;
      _pointerDownPane = false;
      _paneDownPosition = null;
    }
    if (_selectionCandidatePointerId == pointerId) {
      _selectionCandidatePointerId = null;
      _selectionCandidateGlobalPosition = null;
      _selectionCandidateFlowPosition = null;
    }
    for (final entry in _gesturePointerIds.entries.toList()) {
      entry.value.remove(pointerId);
      if (entry.value.isEmpty) _gesturePointerIds.remove(entry.key);
    }
    if (_interactionSession?.pointerId == pointerId) {
      _interactionSession = null;
    }
  }

  void _cancelActiveInteraction() {
    final session = _interactionSession;
    if (session == null) return;
    _interactionSession = null;
    switch (session.kind) {
      case FlowInteractionKind.nodeDragging:
        _cancelNodeDrag();
      case FlowInteractionKind.nodeResizing:
        _cancelNodeResize();
      case FlowInteractionKind.connecting:
      case FlowInteractionKind.reconnecting:
        _cancelConnection();
      case FlowInteractionKind.selectionDragging:
        _stopAutoPan();
        _rebuild(() {
          _selectionBoxStart = null;
          _selectionBoxEnd = null;
          _selectionDragActive = false;
        });
      case FlowInteractionKind.canvasPanning:
        _stopAutoPan();
        _viewportInteractionActive = false;
      case FlowInteractionKind.pressed:
        _stopAutoPan();
        _pendingNodeDragId = null;
        _pendingNodeDragPointerId = null;
        _nodeDragStartGlobal = null;
        _lastDragFlowPosition = null;
        _pointerDownPane = false;
        _paneDownPosition = null;
        _selectionCandidatePointerId = null;
        _selectionCandidateGlobalPosition = null;
        _selectionCandidateFlowPosition = null;
        if (_selectionBoxStart != null) {
          _rebuild(() {
            _selectionBoxStart = null;
            _selectionBoxEnd = null;
            _selectionDragActive = false;
          });
        }
    }
    _releasePointer(session.pointerId, cancelled: false);
  }

  void _cancelInteractionIfTargetWasRemoved() {
    bool targetExists(FlowHitTestResult target) {
      if (target.nodeId != null &&
          !_graphIndex.nodesById.containsKey(target.nodeId)) {
        return false;
      }
      if (target.edgeId != null &&
          !_graphIndex.edgesById.containsKey(target.edgeId)) {
        return false;
      }
      return true;
    }

    if (_interactionSession case final session?
        when !targetExists(session.target)) {
      _cancelActiveInteraction();
    }
    final stalePointers = _pointerCaptures.entries
        .where((entry) => !targetExists(entry.value.target))
        .map((entry) => entry.key)
        .toList();
    for (final pointerId in stalePointers) {
      _releasePointer(pointerId, cancelled: false);
    }
  }
}
