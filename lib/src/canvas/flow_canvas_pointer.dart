part of 'flow_canvas.dart';

extension _FlowCanvasPointer<T> on _FFlowCanvasState<T> {
  void _handlePointerDown(PointerDownEvent event) {
    _pendingNodeDragId = null;
    _nodeDragStartGlobal = null;
    _pointerNoDrag = _FlowInteractionLocks.noDrag.contains(event.pointer);
    _pointerNoPan = _FlowInteractionLocks.noPan.contains(event.pointer);
    if (_pointerNoPan || _pointerNoDrag) _rebuild(() {});
    if (event.kind == PointerDeviceKind.mouse &&
        (event.buttons & kSecondaryButton) != 0) {
      _dispatchContextMenu(event);
      return;
    }
    if (event.kind == PointerDeviceKind.mouse &&
        (event.buttons & kPrimaryButton) == 0) {
      return;
    }
    _focusNode.requestFocus();
    _pointerDownPane = false;
    _paneDownPosition = null;
    final scenePoint = _screenToFlow(event.localPosition);
    final hit = _hitTestAt(scenePoint);
    final capture = FlowPointerCapture(
      pointerId: event.pointer,
      target: hit,
      downGlobalPosition: event.position,
      downViewportPosition: event.localPosition,
      downFlowPosition: scenePoint,
      deviceKind: event.kind,
      startedAt: event.timeStamp,
      selectedNodeIds: _selectedNodes,
    );
    _pointerCaptures[event.pointer] = capture;
    _lastPointerGlobalPositions[event.pointer] = event.position;
    _interactionSession ??= FlowInteractionSession(
      pointerId: event.pointer,
      kind: FlowInteractionKind.pressed,
      target: hit,
      downFlowPosition: scenePoint,
    );
    final wantsSelectionDrag =
        _selectionKeyPressed || _isSelectionKeyDown || widget.selectionOnDrag;
    _pointerNoPan = _FlowInteractionLocks.noPan.contains(event.pointer) ||
        hit.kind != FlowHitTargetKind.pane ||
        wantsSelectionDrag;
    if (_pointerNoPan) _rebuild(() {});
    if (hit.nodeId != null ||
        hit.kind == FlowHitTargetKind.connectionHandle ||
        hit.kind == FlowHitTargetKind.resizeHandle ||
        hit.kind == FlowHitTargetKind.reconnectHandle) {
      _lastBlankPointerDown = null;
      _lastBlankPointerPosition = null;
      return;
    }
    if (wantsSelectionDrag) {
      _selectionCandidatePointerId = event.pointer;
      _selectionCandidateGlobalPosition = event.position;
      _selectionCandidateFlowPosition = scenePoint;
      _lastBlankPointerDown = null;
      _lastBlankPointerPosition = null;
      if (widget.selectionDragThreshold <= 0) {
        _beginSelectionDrag(event.pointer, event.position);
      }
      return;
    }
    final hitEdge = hit.kind == FlowHitTargetKind.edge && hit.edgeId != null
        ? _graphIndex.edgesById[hit.edgeId]
        : null;
    if (hitEdge != null && hitEdge.selectable) {
      _selectEdge(hitEdge.id, toggle: _multiSelectPressed);
      widget.onEdgeClick?.call(hitEdge.id);
      final previousId = _lastEdgeClickId;
      final previousTime = _lastEdgeClickAt;
      final previousPosition = _lastEdgeClickPosition;
      if (previousId == hitEdge.id &&
          previousTime != null &&
          previousPosition != null &&
          event.timeStamp - previousTime <= kDoubleTapTimeout &&
          (event.localPosition - previousPosition).distance <= kDoubleTapSlop) {
        widget.onEdgeDoubleClick?.call(
          hitEdge,
          _pointerPosition(event.position, event.kind),
        );
        _lastEdgeClickId = null;
        _lastEdgeClickAt = null;
        _lastEdgeClickPosition = null;
      } else {
        _lastEdgeClickId = hitEdge.id;
        _lastEdgeClickAt = event.timeStamp;
        _lastEdgeClickPosition = event.localPosition;
      }
      _lastBlankPointerDown = null;
      _lastBlankPointerPosition = null;
      return;
    }
    _pointerDownPane = true;
    _paneDownPosition = event.position;
    if (!_multiSelectPressed) _clearSelection();
    if (widget.zoomOnDoubleClick) {
      final previousTime = _lastBlankPointerDown;
      final previousPosition = _lastBlankPointerPosition;
      if (previousTime != null &&
          previousPosition != null &&
          event.timeStamp - previousTime <= kDoubleTapTimeout &&
          (event.localPosition - previousPosition).distance <= kDoubleTapSlop) {
        _zoomAt(event.localPosition, 1.2);
        _lastBlankPointerDown = null;
        _lastBlankPointerPosition = null;
      } else {
        _lastBlankPointerDown = event.timeStamp;
        _lastBlankPointerPosition = event.localPosition;
      }
    }
  }

  bool get _isShiftDown => HardwareKeyboard.instance.logicalKeysPressed.any(
        (key) =>
            key == LogicalKeyboardKey.shiftLeft ||
            key == LogicalKeyboardKey.shiftRight,
      );

  bool get _isSelectionKeyDown => HardwareKeyboard.instance.logicalKeysPressed
      .any(widget.selectionKeyCodes.contains);

  void _handleNodeTap(FlowNode<T> node) {
    _selectNode(node.id, toggle: _multiSelectPressed);
    widget.onNodeClick?.call(node.id);

    final pointerId = _pointerForGesture(_nodeGestureKey(node.id));
    final capture = pointerId == null ? null : _pointerCaptures[pointerId];
    if (capture == null || capture.target.nodeId != node.id) return;
    final previousTime = _lastNodeClickAt;
    final previousPosition = _lastNodeClickPosition;
    final previousId = _lastNodeClickId;
    if (previousId == node.id &&
        previousTime != null &&
        previousPosition != null &&
        capture.startedAt - previousTime <= kDoubleTapTimeout &&
        (capture.downViewportPosition - previousPosition).distance <=
            kDoubleTapSlop) {
      widget.onNodeDoubleClick?.call(node);
      _lastNodeClickId = null;
      _lastNodeClickAt = null;
      _lastNodeClickPosition = null;
    } else {
      _lastNodeClickId = node.id;
      _lastNodeClickAt = capture.startedAt;
      _lastNodeClickPosition = capture.downViewportPosition;
    }
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (_pointerCaptures.containsKey(event.pointer)) {
      _lastPointerGlobalPositions[event.pointer] = event.position;
    }
    _updateHover(event);
    _updateCapturedNodeDrag(event);
    final interaction = _interactionSession;
    if (interaction?.pointerId == event.pointer &&
        (interaction?.kind == FlowInteractionKind.connecting ||
            interaction?.kind == FlowInteractionKind.reconnecting)) {
      _updateConnectionAt(event.position);
    }
    if (_selectionCandidatePointerId == event.pointer &&
        _interactionSession?.kind == FlowInteractionKind.pressed &&
        _interactionSession?.pointerId == event.pointer) {
      final down = _selectionCandidateGlobalPosition;
      if (down != null &&
          (event.position - down).distance >= widget.selectionDragThreshold) {
        _beginSelectionDrag(event.pointer, event.position);
      }
    }
    if (_selectionBoxStart == null ||
        _interactionSession?.pointerId != event.pointer ||
        _interactionSession?.kind != FlowInteractionKind.selectionDragging) {
      final paneDown = _paneDownPosition;
      if (paneDown != null &&
          (event.position - paneDown).distance > kTouchSlop) {
        _pointerDownPane = false;
      }
      if (_lastBlankPointerDown != null && event.delta.distance > kTouchSlop) {
        _lastBlankPointerDown = null;
        _lastBlankPointerPosition = null;
      }
      return;
    }
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) return;
    final local = renderObject.globalToLocal(event.position);
    _autoPanForGesture(
      event.position,
      interaction: FlowAutoPanInteraction.selection,
    );
    final end = _screenToFlow(local);
    _rebuild(() => _selectionBoxEnd = end);
    widget.onSelectionDrag?.call(Rect.fromPoints(_selectionBoxStart!, end));
  }

  void _beginSelectionDrag(int pointerId, Offset globalPosition) {
    final current = _interactionSession;
    final capture = _pointerCaptures[pointerId];
    final start = _selectionCandidateFlowPosition;
    final renderObject = context.findRenderObject();
    if (current == null ||
        current.pointerId != pointerId ||
        current.kind != FlowInteractionKind.pressed ||
        capture == null ||
        start == null ||
        renderObject is! RenderBox) {
      return;
    }
    if (!_multiSelectPressed) _clearSelection();
    final end = _screenToFlow(renderObject.globalToLocal(globalPosition));
    _selectionBoxStart = start;
    _selectionBoxEnd = end;
    _selectionDragActive = true;
    _selectionCandidatePointerId = null;
    _selectionCandidateGlobalPosition = null;
    _selectionCandidateFlowPosition = null;
    _lastBlankPointerDown = null;
    _lastBlankPointerPosition = null;
    _interactionSession = FlowInteractionSession(
      pointerId: pointerId,
      kind: FlowInteractionKind.selectionDragging,
      target: capture.target,
      downFlowPosition: capture.downFlowPosition,
    );
    final selectionRect = Rect.fromPoints(start, end);
    widget.onSelectionDragStart?.call(selectionRect);
    widget.onSelectionDrag?.call(selectionRect);
    _rebuild(() {});
  }

  FlowPointerPosition _pointerPosition(
    Offset globalPosition,
    PointerDeviceKind deviceKind,
  ) {
    final renderObject = context.findRenderObject();
    final local = renderObject is RenderBox
        ? renderObject.globalToLocal(globalPosition)
        : globalPosition;
    return FlowPointerPosition(
      viewportPosition: local,
      flowPosition: _screenToFlow(local),
      deviceKind: deviceKind,
    );
  }

  FlowNode<T>? _nodeAt(Offset flowPosition) {
    final result = _hitTestAt(flowPosition);
    final id = result.nodeId;
    return id == null ? null : _graphIndex.nodesById[id];
  }

  FlowHitTestResult _hitTestAt(Offset flowPosition) {
    final nodesById = _graphIndex.nodesById;
    final regions = <FlowHitTestRegion>[];
    final scale = _transformController.value.getMaxScaleOnAxis();

    // Reconnect handles paint after every node, so they are the topmost graph
    // targets even where their endpoint overlaps node content. Query only edge
    // bounds near the pointer rather than scanning every edge during hover.
    final reconnectCandidates = _hitTestIndex
        .edgeCandidatesIn(Rect.fromCenter(
          center: flowPosition,
          width: 22 / scale,
          height: 22 / scale,
        ))
        .toSet();
    for (final edgeId in reconnectCandidates) {
      final edge = _graphIndex.edgesById[edgeId];
      if (edge == null) continue;
      if (!edge.reconnectable ||
          !_selectedEdges.contains(edge.id) ||
          edge.hidden ||
          !_edgeInViewport(edge, nodesById)) {
        continue;
      }
      final rank = _edgePaintRanks[edge.id];
      if (rank == null) continue;
      final geometry = _edgeGeometryCache.result(edge, nodesById);
      if (geometry == null) continue;
      final endpoints = <(bool, Offset?)>[
        if (edge.canReconnectSource) (true, geometry.sourceAnchor),
        if (edge.canReconnectTarget) (false, geometry.targetAnchor),
      ];
      for (final (sourceSide, point) in endpoints) {
        if (point == null) continue;
        regions.add(FlowHitTestRegion(
          result: FlowHitTestResult(
            kind: FlowHitTargetKind.reconnectHandle,
            edgeId: edge.id,
            sourceSide: sourceSide,
          ),
          bounds: Rect.fromCenter(center: point, width: 22, height: 22),
          priority: 1000000,
          paintOrder: rank * 2 + (sourceSide ? 0 : 1),
        ));
      }
    }

    final nodeCandidates = _hitTestIndex
        .nodeCandidates(flowPosition)
        .where(_nodePaintRanks.containsKey)
        .map((id) => nodesById[id])
        .whereType<FlowNode<T>>()
        .where((node) => FlowGeometry.isVisible(node, nodesById))
        .toList()
      ..sort((a, b) =>
          (_nodePaintRanks[a.id] ?? -1).compareTo(_nodePaintRanks[b.id] ?? -1));
    for (final node in nodeCandidates) {
      final rank = _nodePaintRanks[node.id]!;
      final layerPriority = 1000 + rank * 10;
      final nodeRect = FlowGeometry.nodeRect(node, nodesById);
      if (_selectedNodes.contains(node.id) && node.resizable) {
        for (var index = 0;
            index < _FlowResizeDirection.values.length;
            index++) {
          final direction = _FlowResizeDirection.values[index];
          const cornerSize = 12.0;
          const sideSize = 18.0;
          final width = direction.x == 0 ? sideSize : cornerSize;
          final height = direction.y == 0 ? sideSize : cornerSize;
          final center = Offset(
            direction.x < 0
                ? nodeRect.left
                : direction.x > 0
                    ? nodeRect.right
                    : nodeRect.center.dx,
            direction.y < 0
                ? nodeRect.top
                : direction.y > 0
                    ? nodeRect.bottom
                    : nodeRect.center.dy,
          );
          regions.add(FlowHitTestRegion(
            result: FlowHitTestResult(
              kind: FlowHitTargetKind.resizeHandle,
              nodeId: node.id,
              resizeDirection: index,
            ),
            bounds: Rect.fromCenter(
              center: center,
              width: width,
              height: height,
            ),
            priority: layerPriority + 2,
            paintOrder: index,
          ));
        }
      }
      for (final handle in node.resolvedHandles) {
        final canStart = _canStartConnection(node, handle);
        final canFinish = _canCompleteConnection(node, handle);
        if (!canStart && !canFinish) continue;
        final anchor =
            FlowGeometry.handleAnchor(node, handle, nodes: nodesById);
        regions.add(FlowHitTestRegion(
          result: FlowHitTestResult(
            kind: FlowHitTargetKind.connectionHandle,
            nodeId: node.id,
            handleId: handle.id,
          ),
          bounds: Rect.fromCenter(center: anchor, width: 22, height: 22),
          priority: layerPriority + 1,
          paintOrder: node.resolvedHandles.indexOf(handle),
        ));
      }
      regions.add(FlowHitTestRegion(
        result: FlowHitTestResult(
          kind: FlowHitTargetKind.node,
          nodeId: node.id,
        ),
        bounds: nodeRect.inflate(widget.nodeHitTestTolerance),
        priority: layerPriority,
      ));
    }

    final candidateIds = _hitTestIndex.edgeCandidates(flowPosition).toSet();
    for (final edgeId in candidateIds) {
      final edge = _graphIndex.edgesById[edgeId];
      final rank = _edgePaintRanks[edgeId];
      if (edge == null ||
          rank == null ||
          edge.hidden ||
          !_edgeInViewport(edge, nodesById)) {
        continue;
      }
      final geometry = _edgeGeometryCache.result(edge, nodesById);
      if (geometry == null) continue;
      regions.add(FlowHitTestRegion(
        result: FlowHitTestResult(
          kind: FlowHitTargetKind.edge,
          edgeId: edge.id,
        ),
        bounds: geometry.bounds.inflate(edge.interactionWidth / scale),
        priority: 0,
        paintOrder: rank,
        containsPoint: (point) =>
            FlowGeometry.distanceToPath(geometry.path, point) <=
            edge.interactionWidth / scale,
      ));
    }
    return _flowHitTestEngine.hitTest(flowPosition, regions: regions);
  }

  void _dispatchContextMenu(PointerDownEvent event) {
    final position = _pointerPosition(event.position, event.kind);
    final hit = _hitTestAt(position.flowPosition);
    final node = hit.nodeId == null ? null : _graphIndex.nodesById[hit.nodeId];
    if (node != null) {
      widget.onNodeContextMenu?.call(node, position);
      return;
    }
    final edge = hit.edgeId != null ? _graphIndex.edgesById[hit.edgeId] : null;
    if (edge != null) {
      widget.onEdgeContextMenu?.call(edge, position);
      return;
    }
    widget.onPaneContextMenu?.call(position);
  }

  void _updateHover(PointerMoveEvent event) {
    if (event.kind != PointerDeviceKind.mouse) return;
    final position = _pointerPosition(event.position, event.kind);
    final hit = _hitTestAt(position.flowPosition);
    final node = hit.nodeId == null ? null : _graphIndex.nodesById[hit.nodeId];
    final edge = hit.edgeId != null ? _graphIndex.edgesById[hit.edgeId] : null;
    if (edge?.id != _hoveredEdgeId) {
      final previous =
          _edges.where((item) => item.id == _hoveredEdgeId).firstOrNull;
      if (previous != null) widget.onEdgeMouseLeave?.call(previous, position);
      _hoveredEdgeId = edge?.id;
      if (edge != null) widget.onEdgeMouseEnter?.call(edge, position);
    }
    if (edge != null) widget.onEdgeMouseMove?.call(edge, position);
    final overPane = node == null && edge == null;
    if (overPane != _pointerOverPane) {
      _pointerOverPane = overPane;
      if (overPane) {
        widget.onPaneMouseEnter?.call(position);
      } else {
        widget.onPaneMouseLeave?.call(position);
      }
    }
    if (overPane) widget.onPaneMouseMove?.call(position);
  }

  void _handleCanvasMouseExit(PointerExitEvent event) {
    if (event.kind != PointerDeviceKind.mouse) return;
    final position = _pointerPosition(event.position, event.kind);
    final hoveredEdge =
        _edges.where((edge) => edge.id == _hoveredEdgeId).firstOrNull;
    if (hoveredEdge != null) {
      widget.onEdgeMouseLeave?.call(hoveredEdge, position);
    }
    _hoveredEdgeId = null;
    if (_pointerOverPane) widget.onPaneMouseLeave?.call(position);
    _pointerOverPane = false;
  }

  void _handlePointerUp(PointerEvent event) {
    final terminal = event is PointerUpEvent || event is PointerCancelEvent;
    try {
      _handlePointerUpBody(event);
    } finally {
      if (terminal) {
        final pointerId = event.pointer;
        final cancelled = event is PointerCancelEvent;
        scheduleMicrotask(() {
          if (!mounted) return;
          _releasePointer(
            pointerId,
            cancelled: cancelled,
            globalPosition: event.position,
          );
          _pointerNoDrag = false;
          _pointerNoPan = false;
          _pointerDownPane = false;
          _paneDownPosition = null;
          _stopAutoPan();
          _rebuild(() {});
        });
      }
    }
  }

  void _handlePointerUpBody(PointerEvent event) {
    final start = _selectionBoxStart;
    final end = _selectionBoxEnd;
    if (start == null || end == null) {
      if (event is PointerUpEvent &&
          _pointerDownPane &&
          _interactionSession?.pointerId == event.pointer) {
        widget.onPaneClick?.call();
      }
      return;
    }
    if (event is! PointerUpEvent) {
      _rebuild(() {
        _selectionBoxStart = null;
        _selectionBoxEnd = null;
        _selectionDragActive = false;
      });
      return;
    }
    final box = Rect.fromPoints(start, end);
    final nodesById = _graphIndex.nodesById;
    final selection = <String>{};
    final selectedEdges = <String>{};
    _rebuild(() {
      selection.addAll(_nodes.where((node) {
        if (!node.selectable || !FlowGeometry.isVisible(node, nodesById)) {
          return false;
        }
        final rect = FlowGeometry.nodeRect(node, nodesById);
        return widget.selectionMode == FlowSelectionMode.full
            ? box.left <= rect.left &&
                box.top <= rect.top &&
                box.right >= rect.right &&
                box.bottom >= rect.bottom
            : box.overlaps(rect);
      }).map((node) => node.id));
      selectedEdges.addAll(_edges.where((edge) {
        if (!edge.selectable || edge.hidden) return false;
        final geometry = _edgeGeometryCache.result(edge, nodesById);
        if (geometry == null) return false;
        if (widget.edgeSelectionMode == FlowSelectionMode.full) {
          return box.left <= geometry.bounds.left &&
              box.top <= geometry.bounds.top &&
              box.right >= geometry.bounds.right &&
              box.bottom >= geometry.bounds.bottom;
        }
        return FlowGeometry.pathIntersectsRect(geometry.path, box);
      }).map((edge) => edge.id));
      _selectedNodes.addAll(selection);
      _selectedEdges.addAll(selectedEdges);
      _selectionBoxStart = null;
      _selectionBoxEnd = null;
      _selectionDragActive = false;
    });
    _emitSelection();
    widget.onSelectionDragEnd?.call(_selection);
  }

  void _startNodeDrag(FlowNode<T> node, DragStartDetails _) {
    final pointerId = _pointerForGesture(_nodeGestureKey(node.id));
    final capture = pointerId == null ? null : _pointerCaptures[pointerId];
    final targetId = capture?.target.nodeId;
    final target = targetId == null ? null : _graphIndex.nodesById[targetId];
    if (pointerId == null ||
        capture == null ||
        capture.target.kind != FlowHitTargetKind.node ||
        target == null ||
        !target.draggable ||
        _FlowInteractionLocks.noDrag.contains(pointerId) ||
        (target.dragHandleOnly &&
            !_FlowInteractionLocks.dragHandle.contains(pointerId))) {
      return;
    }
    _prepareNodeDrag(target, capture);
  }

  void _prepareNodeDrag(
    FlowNode<T> target,
    FlowPointerCapture capture,
  ) {
    final pointerId = capture.pointerId;
    if (_pendingNodeDragPointerId == pointerId &&
        _pendingNodeDragId == target.id) {
      return;
    }
    _nodeFocusNode(target.id).requestFocus();
    if (!_selectedNodes.contains(target.id)) {
      _selectNode(target.id, toggle: _multiSelectPressed);
    }
    _pendingNodeDragId = target.id;
    _pendingNodeDragPointerId = pointerId;
    _nodeDragStartGlobal = capture.downGlobalPosition;
    _lastDragFlowPosition = capture.downFlowPosition;
    if (widget.nodeDragThreshold <= 0) _activateNodeDrag(target.id);
  }

  void _updateNodeDrag(DragUpdateDetails details, String gestureNodeId) {
    if (!_ownsGesturePointer(
      _nodeGestureKey(gestureNodeId),
      _pendingNodeDragPointerId,
    )) {
      return;
    }
    if (_draggingNodeId == null) {
      final pendingId = _pendingNodeDragId;
      final start = _nodeDragStartGlobal;
      if (pendingId == null ||
          start == null ||
          (details.globalPosition - start).distance <
              widget.nodeDragThreshold) {
        return;
      }
      _activateNodeDrag(pendingId);
    }
    final pointerId = _pendingNodeDragPointerId;
    if (pointerId != null) {
      _updateNodeDragAt(pointerId, details.globalPosition);
    }
  }

  void _updateCapturedNodeDrag(PointerMoveEvent event) {
    final capture = _pointerCaptures[event.pointer];
    if (capture == null ||
        capture.target.kind != FlowHitTargetKind.node ||
        _FlowInteractionLocks.noDrag.contains(event.pointer) ||
        (_interactionSession != null &&
            _interactionSession!.pointerId != event.pointer)) {
      return;
    }
    final targetId = capture.target.nodeId;
    final node = targetId == null ? null : _graphIndex.nodesById[targetId];
    if (node == null ||
        !node.draggable ||
        (node.dragHandleOnly &&
            !_FlowInteractionLocks.dragHandle.contains(event.pointer))) {
      return;
    }
    _prepareNodeDrag(node, capture);
    if ((event.position - capture.downGlobalPosition).distance <
        widget.nodeDragThreshold) {
      return;
    }
    if (_draggingNodeId == null) _activateNodeDrag(node.id);
    _updateNodeDragAt(event.pointer, event.position);
  }

  void _updateNodeDragAt(int pointerId, Offset globalPosition) {
    final session = _interactionSession;
    if (session == null ||
        session.kind != FlowInteractionKind.nodeDragging ||
        session.pointerId != pointerId) {
      return;
    }
    _autoPanForGesture(
      globalPosition,
      interaction: FlowAutoPanInteraction.nodeDrag,
    );
    final previous = _lastDragFlowPosition;
    final current = _scenePointFromGlobal(globalPosition);
    if (previous == null || current == null) return;
    _lastDragFlowPosition = current;
    _applyNodeDragDelta(current - previous, session.movingNodeIds);
  }

  void _applyNodeDragDelta(Offset delta, Set<String> movingIds) {
    if (delta == Offset.zero || movingIds.isEmpty) return;
    final nodesById = {for (final node in _nodes) node.id: node};
    final grid = widget.snapGrid;
    _nodes = List.unmodifiable([
      for (final node in _nodes)
        if (movingIds.contains(node.id) && node.draggable)
          node.copyWith(
              position: FlowGeometry.constrainNodePosition(
            node,
            _snapPosition(node.position + delta, grid),
            nodesById,
            globalExtent: widget.nodeExtent,
          ))
        else
          node,
    ]);
    for (final id in movingIds) {
      _expandParentsForNode(id);
    }
    if (widget.helperLinesEnabled && movingIds.isNotEmpty) {
      final currentById = {for (final node in _nodes) node.id: node};
      Rect? movingBounds;
      for (final id in movingIds) {
        final moved = currentById[id];
        if (moved == null) continue;
        final rect = FlowGeometry.nodeRect(moved, currentById);
        movingBounds =
            movingBounds == null ? rect : movingBounds.expandToInclude(rect);
      }
      if (movingBounds != null) {
        final targetBounds = _nodes
            .where((node) =>
                !movingIds.contains(node.id) &&
                FlowGeometry.isVisible(node, currentById))
            .map((node) => FlowGeometry.nodeRect(node, currentById));
        final guides = FlowGeometry.findAlignmentGuides(
          movingBounds,
          targetBounds,
          threshold: widget.helperLineThreshold /
              _transformController.value.getMaxScaleOnAxis(),
        );
        _alignmentGuides = guides;
        if (widget.helperLineSnap && guides.correction != Offset.zero) {
          final boundsById = {for (final node in _nodes) node.id: node};
          _nodes = List.unmodifiable([
            for (final node in _nodes)
              if (movingIds.contains(node.id) && node.draggable)
                node.copyWith(
                  position: FlowGeometry.constrainNodePosition(
                    node,
                    node.position + guides.correction,
                    boundsById,
                    globalExtent: widget.nodeExtent,
                  ),
                )
              else
                node,
          ]);
          for (final id in movingIds) {
            _expandParentsForNode(id);
          }
        }
      }
    } else {
      _alignmentGuides = null;
    }
    for (final id in movingIds) {
      final moved = _nodes.where((node) => node.id == id).firstOrNull;
      if (moved != null) widget.onNodeDrag?.call(moved);
    }
    _publishNodes();
    _rebuild(() {});
  }

  void _activateNodeDrag(String nodeId) {
    final node = _nodes.where((item) => item.id == nodeId).firstOrNull;
    if (node == null || _draggingNodeId == nodeId) return;
    final pointerId = _pendingNodeDragPointerId;
    final capture = pointerId == null ? null : _pointerCaptures[pointerId];
    if (pointerId == null ||
        capture == null ||
        !_claimCapturedInteraction(
          FlowInteractionKind.nodeDragging,
          pointerId,
          targetKind: FlowHitTargetKind.node,
          nodeId: nodeId,
        )) {
      return;
    }
    final wasSelectedAtDown = capture.selectedNodeIds.contains(nodeId);
    final candidates =
        wasSelectedAtDown ? capture.selectedNodeIds : <String>{nodeId};
    final nodesById = {for (final item in _nodes) item.id: item};
    final movingIds = candidates.where((id) {
      final candidate = nodesById[id];
      if (candidate == null || !candidate.draggable) return false;
      var parentId = candidate.parentId;
      final visited = <String>{};
      while (parentId != null && visited.add(parentId)) {
        if (candidates.contains(parentId) &&
            nodesById[parentId]?.draggable == true) {
          return false;
        }
        parentId = nodesById[parentId]?.parentId;
      }
      return true;
    }).toSet();
    _interactionSession = FlowInteractionSession(
      pointerId: pointerId,
      kind: FlowInteractionKind.nodeDragging,
      target: capture.target,
      downFlowPosition: capture.downFlowPosition,
      movingNodeIds: movingIds,
    );
    _draggingNodeId = nodeId;
    _lastDragFlowPosition = capture.downFlowPosition;
    widget.historyController?.beginTransaction(
      'Move nodes',
      _captureGraphState(),
    );
    widget.onNodeDragStart?.call(node);
  }

  void _endNodeDrag(DragEndDetails details, String gestureNodeId) {
    if (!_ownsGesturePointer(
      _nodeGestureKey(gestureNodeId),
      _pendingNodeDragPointerId,
    )) {
      return;
    }
    _completeNodeDrag();
  }

  void _completeNodeDrag() {
    _stopAutoPan();
    final id = _draggingNodeId;
    if (id != null) {
      if (widget.dynamicReparenting) _applyDynamicReparenting(id);
      final node = _nodes.where((item) => item.id == id).firstOrNull;
      if (node != null) widget.onNodeDragEnd?.call(node);
      if (widget.proximityConnect && node != null) {
        _emitProximityConnection(node);
      }
    }
    _draggingNodeId = null;
    final pointerId = _pendingNodeDragPointerId;
    _pendingNodeDragId = null;
    _pendingNodeDragPointerId = null;
    _nodeDragStartGlobal = null;
    _lastDragFlowPosition = null;
    _alignmentGuides = null;
    _rebuild(() {});
    final history = widget.historyController;
    if (history?.isRecording ?? false) {
      history!.commitTransaction(_captureGraphState());
    }
    if (pointerId != null) _finishInteraction(pointerId);
  }

  void _applyDynamicReparenting(String nodeId) {
    final nodesById = {for (final node in _nodes) node.id: node};
    final node = nodesById[nodeId];
    if (node == null) return;
    final anchor = FlowGeometry.nodeAbsoluteAnchor(node, nodesById);
    final center = FlowGeometry.nodeRect(node, nodesById).center;
    FlowNode<T>? nextParent;
    for (final candidate in _orderedVisibleNodes(nodesById).reversed) {
      if (!candidate.groupable ||
          candidate.id == nodeId ||
          !FlowGeometry.nodeRect(candidate, nodesById).contains(center)) {
        continue;
      }
      var parentId = candidate.parentId;
      var wouldCycle = false;
      final visited = <String>{};
      while (parentId != null && visited.add(parentId)) {
        if (parentId == nodeId) {
          wouldCycle = true;
          break;
        }
        parentId = nodesById[parentId]?.parentId;
      }
      if (!wouldCycle) {
        nextParent = candidate;
        break;
      }
    }
    if (node.parentId == nextParent?.id) return;
    final nextPosition = nextParent == null
        ? anchor
        : anchor - FlowGeometry.nodeAbsoluteTopLeft(nextParent, nodesById);
    _nodes = List.unmodifiable([
      for (final item in _nodes)
        if (item.id == nodeId)
          item.copyWith(parentId: nextParent?.id, position: nextPosition)
        else
          item,
    ]);
    _publishNodes();
    _rebuild(() {});
  }

  void _emitProximityConnection(FlowNode<T> node) {
    final nodesById = {for (final item in _nodes) item.id: item};
    final threshold = widget.proximityConnectThreshold /
        _transformController.value.getMaxScaleOnAxis();
    for (final handle in node.resolvedHandles) {
      if (handle.type != FlowHandleType.source) continue;
      final connection = FlowGraphInteraction.connectionAt<T>(
        nodes: _nodes,
        edges: _edges,
        sourceId: node.id,
        sourceHandleId: handle.id,
        point: FlowGeometry.handleAnchor(node, handle, nodes: nodesById),
        isValidConnection: widget.isValidConnection,
        snapRadius: threshold,
        connectionMode: widget.connectionMode,
      );
      if (connection != null && connection.targetId != node.id) {
        widget.onProximityConnect?.call(connection);
        return;
      }
    }
  }

  void _cancelNodeDrag([Object? gestureKey]) {
    if (gestureKey != null &&
        !_ownsGesturePointer(gestureKey, _pendingNodeDragPointerId)) {
      return;
    }
    _stopAutoPan();
    final id = _draggingNodeId;
    if (id != null) {
      final node = _nodes.where((item) => item.id == id).firstOrNull;
      if (node != null) widget.onNodeDragEnd?.call(node);
    }
    _draggingNodeId = null;
    final pointerId = _pendingNodeDragPointerId;
    _pendingNodeDragId = null;
    _pendingNodeDragPointerId = null;
    _nodeDragStartGlobal = null;
    _lastDragFlowPosition = null;
    _alignmentGuides = null;
    _rebuild(() {});
    final history = widget.historyController;
    if (history?.isRecording ?? false) {
      history!.commitTransaction(_captureGraphState());
    }
    if (pointerId != null) _finishInteraction(pointerId);
  }

  void _startNodeResize(
    FlowNode<T> node,
    _FlowResizeDirection direction,
    DragStartDetails details,
  ) {
    final pointerId = _pointerForGesture(_resizeGestureKey(node.id, direction));
    if (pointerId == null ||
        !_claimCapturedInteraction(
          FlowInteractionKind.nodeResizing,
          pointerId,
          targetKind: FlowHitTargetKind.resizeHandle,
          nodeId: node.id,
          resizeDirection: direction.index,
        )) {
      return;
    }
    _resizePointerId = pointerId;
    _resizingNodeId = node.id;
    _resizeDirection = direction;
    _resizeStartGlobal = details.globalPosition;
    _resizeStartFlowPosition = _scenePointFromGlobal(details.globalPosition);
    _resizeStartSize = Size(node.width, node.height);
    _resizeStartPosition = node.position;
    widget.historyController?.beginTransaction(
      'Resize node',
      _captureGraphState(),
    );
    widget.onNodeResizeStart?.call(node);
  }

  void _updateNodeResize(
    DragUpdateDetails details,
    String gestureNodeId,
    _FlowResizeDirection gestureDirection,
  ) {
    if (!_ownsGesturePointer(
          _resizeGestureKey(gestureNodeId, gestureDirection),
          _resizePointerId,
        ) ||
        _interactionSession?.kind != FlowInteractionKind.nodeResizing) {
      return;
    }
    final id = _resizingNodeId;
    final start = _resizeStartGlobal;
    final size = _resizeStartSize;
    final startPosition = _resizeStartPosition;
    if (id == null || start == null || size == null || startPosition == null) {
      return;
    }
    final startFlow = _resizeStartFlowPosition;
    final currentFlow = _scenePointFromGlobal(details.globalPosition);
    if (startFlow == null || currentFlow == null) return;
    final delta = currentFlow - startFlow;
    final resizingNode = _nodes.where((node) => node.id == id).firstOrNull;
    if (resizingNode == null) return;
    final direction = _resizeDirection;
    final startLeft = startPosition.dx - size.width * resizingNode.origin.dx;
    final startTop = startPosition.dy - size.height * resizingNode.origin.dy;
    final width = (size.width + delta.dx * direction.x)
        .clamp(resizingNode.minWidth, resizingNode.maxWidth);
    final height = (size.height + delta.dy * direction.y)
        .clamp(resizingNode.minHeight, resizingNode.maxHeight);
    final left = direction.x < 0 ? startLeft + size.width - width : startLeft;
    final top = direction.y < 0 ? startTop + size.height - height : startTop;
    var resizedNode = resizingNode.copyWith(
      width: width.toDouble(),
      height: height.toDouble(),
      position: Offset(
        left + width * resizingNode.origin.dx,
        top + height * resizingNode.origin.dy,
      ),
    );
    resizedNode = resizedNode.copyWith(
      position: FlowGeometry.constrainNodePosition(
        resizedNode,
        resizedNode.position,
        {for (final node in _nodes) node.id: node},
        globalExtent: widget.nodeExtent,
      ),
    );
    _nodes = List.unmodifiable([
      for (final node in _nodes)
        if (node.id == id) resizedNode else node,
    ]);
    _expandParentsForNode(id);
    final resized = _nodes.where((node) => node.id == id).firstOrNull;
    if (resized != null) widget.onNodeResize?.call(resized);
    _publishNodes();
    _rebuild(() {});
  }

  void _endNodeResize(
    DragEndDetails details,
    String gestureNodeId,
    _FlowResizeDirection gestureDirection,
  ) {
    if (!_ownsGesturePointer(
      _resizeGestureKey(gestureNodeId, gestureDirection),
      _resizePointerId,
    )) {
      return;
    }
    _completeNodeResize();
  }

  void _completeNodeResize() {
    final id = _resizingNodeId;
    if (id != null) {
      final node = _nodes.where((item) => item.id == id).firstOrNull;
      if (node != null) widget.onNodeResizeEnd?.call(node);
    }
    _resizingNodeId = null;
    _resizeStartGlobal = null;
    _resizeStartFlowPosition = null;
    _resizeStartSize = null;
    _resizeStartPosition = null;
    final pointerId = _resizePointerId;
    _resizePointerId = null;
    final history = widget.historyController;
    if (history?.isRecording ?? false) {
      history!.commitTransaction(_captureGraphState());
    }
    if (pointerId != null) _finishInteraction(pointerId);
  }

  void _cancelNodeResize([Object? gestureKey]) {
    if (gestureKey != null &&
        !_ownsGesturePointer(gestureKey, _resizePointerId)) {
      return;
    }
    final id = _resizingNodeId;
    if (id != null) {
      final node = _nodes.where((item) => item.id == id).firstOrNull;
      if (node != null) widget.onNodeResizeEnd?.call(node);
    }
    _resizingNodeId = null;
    _resizeStartGlobal = null;
    _resizeStartFlowPosition = null;
    _resizeStartSize = null;
    _resizeStartPosition = null;
    final pointerId = _resizePointerId;
    _resizePointerId = null;
    final history = widget.historyController;
    if (history?.isRecording ?? false) {
      history!.commitTransaction(_captureGraphState());
    }
    if (pointerId != null) _finishInteraction(pointerId);
  }

  void _expandParentsForNode(String nodeId) {
    var nodes = List<FlowNode<T>>.of(_nodes);
    var child = nodes.where((node) => node.id == nodeId).firstOrNull;
    var shouldExpand = child?.expandParent ?? false;
    final visited = <String>{nodeId};
    while (child != null && shouldExpand && child.parentId != null) {
      final parentIndex =
          nodes.indexWhere((node) => node.id == child!.parentId);
      if (parentIndex < 0 || !visited.add(nodes[parentIndex].id)) break;
      final parent = nodes[parentIndex];
      final childTopLeft = Offset(
        child.position.dx - child.width * child.origin.dx,
        child.position.dy - child.height * child.origin.dy,
      );
      final shift = Offset(
        math.min(0, childTopLeft.dx),
        math.min(0, childTopLeft.dy),
      );
      final width = math.max(
        parent.width - shift.dx,
        childTopLeft.dx + child.width - shift.dx,
      );
      final height = math.max(
        parent.height - shift.dy,
        childTopLeft.dy + child.height - shift.dy,
      );
      if (width != parent.width ||
          height != parent.height ||
          shift != Offset.zero) {
        final sizeDelta = Offset(width - parent.width, height - parent.height);
        nodes[parentIndex] = parent.copyWith(
          position: parent.position +
              shift +
              Offset(sizeDelta.dx * parent.origin.dx,
                  sizeDelta.dy * parent.origin.dy),
          width: width,
          height: height,
        );
        if (shift != Offset.zero) {
          for (var index = 0; index < nodes.length; index++) {
            final sibling = nodes[index];
            if (sibling.parentId == parent.id) {
              nodes[index] =
                  sibling.copyWith(position: sibling.position - shift);
            }
          }
        }
      }
      child = nodes[parentIndex];
      shouldExpand = child.expandParent;
    }
    _nodes = List.unmodifiable(nodes);
  }
}
