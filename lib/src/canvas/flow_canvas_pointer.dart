part of 'flow_canvas.dart';

extension _FlowCanvasPointer<T> on _FFlowCanvasState<T> {
  void _handlePointerDown(PointerDownEvent event) {
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
    final scenePoint = _transformController.toScene(event.localPosition);
    final nodesById = {for (final node in _nodes) node.id: node};
    FlowNode<T>? hitNode;
    for (final node in _orderedVisibleNodes(nodesById).reversed) {
      if (FlowGeometry.isVisible(node, nodesById) &&
          FlowGeometry.nodeRect(node, nodesById)
              .inflate(12)
              .contains(scenePoint)) {
        hitNode = node;
        break;
      }
    }
    if (hitNode != null) {
      _lastBlankPointerDown = null;
      _lastBlankPointerPosition = null;
      _pointerDownNodeId = hitNode.id;
      _nodeWasSelectedOnPointerDown = _selectedNodes.contains(hitNode.id);
      if (!_selectedNodes.contains(hitNode.id)) {
        _selectNode(hitNode.id, toggle: _multiSelectPressed);
      }
      return;
    }
    if (_selectionKeyPressed || _isSelectionKeyDown || widget.selectionOnDrag) {
      if (!_multiSelectPressed) _clearSelection();
      _selectionBoxStart = scenePoint;
      _selectionBoxEnd = scenePoint;
      _selectionDragActive = true;
      widget.onSelectionDragStart
          ?.call(Rect.fromPoints(scenePoint, scenePoint));
      _rebuild(() {});
      return;
    }
    final hitEdge = _edgeAt(scenePoint);
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

  void _handlePointerMove(PointerMoveEvent event) {
    _updateHover(event);
    if (_selectionBoxStart == null) {
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
    _autoPanForGesture(event.position);
    final end = _transformController.toScene(local);
    _rebuild(() => _selectionBoxEnd = end);
    widget.onSelectionDrag?.call(Rect.fromPoints(_selectionBoxStart!, end));
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
      flowPosition: _transformController.toScene(local),
      deviceKind: deviceKind,
    );
  }

  FlowNode<T>? _nodeAt(Offset flowPosition) {
    final nodesById = {for (final node in _nodes) node.id: node};
    for (final node in _orderedVisibleNodes(nodesById).reversed) {
      if (FlowGeometry.nodeRect(node, nodesById)
          .inflate(12)
          .contains(flowPosition)) {
        return node;
      }
    }
    return null;
  }

  FlowEdge? _edgeAt(Offset flowPosition) {
    final nodesById = {for (final node in _nodes) node.id: node};
    final scale = _transformController.value.getMaxScaleOnAxis();
    for (final edge in _orderedVisibleEdges().reversed) {
      if (edge.hidden || !_edgeInViewport(edge, nodesById)) continue;
      final start = FlowGeometry.edgeSource(edge, nodesById);
      final end = FlowGeometry.edgeTarget(edge, nodesById);
      if (start == null || end == null) continue;
      final distance = FlowGeometry.distanceToPath(
        FlowGeometry.edgePathFor(edge, nodesById),
        flowPosition,
      );
      if (distance <= edge.interactionWidth / scale) return edge;
    }
    return null;
  }

  void _dispatchContextMenu(PointerDownEvent event) {
    final position = _pointerPosition(event.position, event.kind);
    final node = _nodeAt(position.flowPosition);
    if (node != null) {
      widget.onNodeContextMenu?.call(node, position);
      return;
    }
    final edge = _edgeAt(position.flowPosition);
    if (edge != null) {
      widget.onEdgeContextMenu?.call(edge, position);
      return;
    }
    widget.onPaneContextMenu?.call(position);
  }

  void _updateHover(PointerMoveEvent event) {
    if (event.kind != PointerDeviceKind.mouse) return;
    final position = _pointerPosition(event.position, event.kind);
    final node = _nodeAt(position.flowPosition);
    final edge = node == null ? _edgeAt(position.flowPosition) : null;
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
    final start = _selectionBoxStart;
    final end = _selectionBoxEnd;
    if (start == null || end == null) {
      if (event is PointerUpEvent && _pointerDownPane) {
        _pointerDownPane = false;
        _paneDownPosition = null;
        widget.onPaneClick?.call();
      } else if (event is PointerCancelEvent) {
        _pointerDownPane = false;
        _paneDownPosition = null;
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
    final nodesById = {for (final node in _nodes) node.id: node};
    final selection = <String>{};
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
      _selectedNodes.addAll(selection);
      _selectionBoxStart = null;
      _selectionBoxEnd = null;
      _selectionDragActive = false;
    });
    _emitSelection();
    widget.onSelectionDragEnd?.call(_selection);
  }

  void _startNodeDrag(FlowNode<T> node, DragStartDetails details) {
    _nodeFocusNode(node.id).requestFocus();
    if (!_selectedNodes.contains(node.id)) {
      _selectNode(node.id, toggle: _multiSelectPressed);
    }
    _draggingNodeId = node.id;
    _lastDragGlobalPosition = details.globalPosition;
    widget.onNodeDragStart?.call(node);
  }

  void _updateNodeDrag(DragUpdateDetails details) {
    _autoPanForGesture(details.globalPosition);
    final previous = _lastDragGlobalPosition;
    final draggingNodeId = _draggingNodeId;
    if (previous == null || draggingNodeId == null) return;
    final delta = (details.globalPosition - previous) /
        _transformController.value.getMaxScaleOnAxis();
    _lastDragGlobalPosition = details.globalPosition;
    final candidates = _selectedNodes.contains(draggingNodeId)
        ? _selectedNodes.toSet()
        : {draggingNodeId};
    final nodesById = {for (final node in _nodes) node.id: node};
    final movingIds = candidates.where((id) {
      final node = nodesById[id];
      var parentId = node?.parentId;
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
      final moved = _nodes.where((node) => node.id == id).firstOrNull;
      if (moved != null) widget.onNodeDrag?.call(moved);
    }
    _publishNodes();
    _rebuild(() {});
  }

  void _endNodeDrag(DragEndDetails details) {
    final id = _draggingNodeId;
    if (id != null) {
      final node = _nodes.where((item) => item.id == id).firstOrNull;
      if (node != null) widget.onNodeDragEnd?.call(node);
    }
    _draggingNodeId = null;
    _lastDragGlobalPosition = null;
  }

  void _cancelNodeDrag() {
    final id = _draggingNodeId;
    if (id != null) {
      final node = _nodes.where((item) => item.id == id).firstOrNull;
      if (node != null) widget.onNodeDragEnd?.call(node);
    }
    _draggingNodeId = null;
    _lastDragGlobalPosition = null;
  }

  void _startNodeResize(
    FlowNode<T> node,
    _FlowResizeDirection direction,
    DragStartDetails details,
  ) {
    _resizingNodeId = node.id;
    _resizeDirection = direction;
    _resizeStartGlobal = details.globalPosition;
    _resizeStartSize = Size(node.width, node.height);
    _resizeStartPosition = node.position;
    widget.onNodeResizeStart?.call(node);
  }

  void _updateNodeResize(DragUpdateDetails details) {
    final id = _resizingNodeId;
    final start = _resizeStartGlobal;
    final size = _resizeStartSize;
    final startPosition = _resizeStartPosition;
    if (id == null || start == null || size == null || startPosition == null) {
      return;
    }
    final delta = (details.globalPosition - start) /
        _transformController.value.getMaxScaleOnAxis();
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

  void _endNodeResize(DragEndDetails details) {
    final id = _resizingNodeId;
    if (id != null) {
      final node = _nodes.where((item) => item.id == id).firstOrNull;
      if (node != null) widget.onNodeResizeEnd?.call(node);
    }
    _resizingNodeId = null;
    _resizeStartGlobal = null;
    _resizeStartSize = null;
    _resizeStartPosition = null;
  }

  void _cancelNodeResize() {
    final id = _resizingNodeId;
    if (id != null) {
      final node = _nodes.where((item) => item.id == id).firstOrNull;
      if (node != null) widget.onNodeResizeEnd?.call(node);
    }
    _resizingNodeId = null;
    _resizeStartGlobal = null;
    _resizeStartSize = null;
    _resizeStartPosition = null;
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
