part of 'flow_canvas.dart';

extension _FlowCanvasSelection<T> on _FFlowCanvasState<T> {
  FlowSelection get _selection =>
      FlowSelection(nodes: _selectedNodes, edges: _selectedEdges);

  void _emitSelection() {
    _selectedNodes.removeWhere((id) => !_nodes.any((node) => node.id == id));
    _selectedEdges.removeWhere((id) => !_edges.any((edge) => edge.id == id));
    _nodes = List.unmodifiable([
      for (final node in _nodes)
        node.copyWith(selected: _selectedNodes.contains(node.id)),
    ]);
    _edges = List.unmodifiable([
      for (final edge in _edges)
        edge.copyWith(selected: _selectedEdges.contains(edge.id)),
    ]);
    _publishGraph(nodesChanged: true, edgesChanged: true);
    widget.onSelectionChanged?.call(_selection);
    _accessibilityAnnouncement = widget.selectionAnnouncementBuilder
            ?.call(_selection) ??
        (_selection.isEmpty
            ? 'Selection cleared'
            : '${_selectedNodes.length} nodes and ${_selectedEdges.length} connections selected');
    widget.onNodeSelected?.call(
      _selectedNodes.length == 1 ? _selectedNodes.first : null,
    );
  }

  void _selectNode(String id, {required bool toggle}) {
    final node = _nodes.where((item) => item.id == id).firstOrNull;
    if (node == null || !node.selectable) return;
    _rebuild(() {
      if (!toggle) {
        _selectedNodes
          ..clear()
          ..add(id);
        _selectedEdges.clear();
      } else if (!_selectedNodes.add(id)) {
        _selectedNodes.remove(id);
      }
    });
    _emitSelection();
  }

  void _selectEdge(String id, {required bool toggle}) {
    final edge = _edges.where((item) => item.id == id).firstOrNull;
    if (edge == null || !edge.selectable) return;
    _rebuild(() {
      if (!toggle) {
        _selectedNodes.clear();
        _selectedEdges
          ..clear()
          ..add(id);
      } else if (!_selectedEdges.add(id)) {
        _selectedEdges.remove(id);
      }
    });
    _emitSelection();
  }

  bool get _multiSelectPressed {
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    return widget.multiSelectionKeyCodes.any(keys.contains);
  }

  void _handleKey(FocusNode node, KeyEvent event) {
    final selectionKey = widget.selectionKeyCodes.contains(event.logicalKey);
    if (selectionKey && event is KeyDownEvent && !_selectionKeyPressed) {
      _selectionKeyPressed = true;
      _rebuild(() {});
    } else if (selectionKey && event is KeyUpEvent && _selectionKeyPressed) {
      _selectionKeyPressed = false;
      _rebuild(() {});
    }
    if (event is! KeyDownEvent) return;
    final focusedWidget = FocusManager.instance.primaryFocus?.context?.widget;
    if (focusedWidget is EditableText || focusedWidget is TextField) return;
    final key = event.logicalKey;
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final modifier = widget.multiSelectionKeyCodes.any(keys.contains);
    if (key == LogicalKeyboardKey.escape) {
      _clearSelection();
    } else if (widget.deleteKeyCodes.contains(key)) {
      _deleteSelection();
    } else if (modifier && key == LogicalKeyboardKey.keyA) {
      _rebuild(() {
        _selectedNodes
          ..clear()
          ..addAll(
              _nodes.where((node) => node.selectable).map((node) => node.id));
        _selectedEdges
          ..clear()
          ..addAll(
              _edges.where((edge) => edge.selectable).map((edge) => edge.id));
      });
      _emitSelection();
    }
  }

  KeyEventResult _handleNodeKey(FlowNode<T> node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final focusedWidget = FocusManager.instance.primaryFocus?.context?.widget;
    if (focusedWidget is EditableText || focusedWidget is TextField) {
      return KeyEventResult.ignored;
    }
    switch (event.logicalKey) {
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.space:
        if (node.selectable) {
          _selectNode(node.id, toggle: false);
          widget.onNodeClick?.call(node.id);
        }
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        _moveNodeByKeyboard(node, Offset(0, -_keyboardStep));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        _moveNodeByKeyboard(node, Offset(0, _keyboardStep));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
        _moveNodeByKeyboard(node, Offset(-_keyboardStep, 0));
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
        _moveNodeByKeyboard(node, Offset(_keyboardStep, 0));
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  double get _keyboardStep =>
      _isShiftDown ? widget.keyboardMoveStepWithShift : widget.keyboardMoveStep;

  void _moveNodeByKeyboard(FlowNode<T> node, Offset delta) {
    if (!node.draggable) return;
    final nodeMap = {for (final item in _nodes) item.id: item};
    final position = FlowGeometry.constrainNodePosition(
      node,
      _snapPosition(node.position + delta, widget.snapGrid),
      nodeMap,
      globalExtent: widget.nodeExtent,
    );
    _nodes = List.unmodifiable([
      for (final item in _nodes)
        if (item.id == node.id) item.copyWith(position: position) else item,
    ]);
    _expandParentsForNode(node.id);
    _publishNodes();
    _keepNodeInView(node.id);
    _rebuild(() {});
  }

  void _keepNodeInView(String nodeId) {
    if (_viewportSize.isEmpty) return;
    final nodesById = {for (final node in _nodes) node.id: node};
    final node = nodesById[nodeId];
    if (node == null) return;
    final rect = FlowGeometry.nodeRect(node, nodesById);
    final topLeft = _transformController.toScene(Offset.zero);
    final bottomRight = _transformController
        .toScene(Offset(_viewportSize.width, _viewportSize.height));
    final viewport = Rect.fromPoints(topLeft, bottomRight);
    if (!viewport.contains(rect.topLeft) ||
        !viewport.contains(rect.bottomRight)) {
      _keepPointInView(rect.center);
    }
  }

  void _keepPointInView(Offset point) {
    if (_viewportSize.isEmpty) return;
    final topLeft = _transformController.toScene(Offset.zero);
    final bottomRight = _transformController
        .toScene(Offset(_viewportSize.width, _viewportSize.height));
    if (Rect.fromPoints(topLeft, bottomRight).contains(point)) return;
    final scale = _transformController.value.getMaxScaleOnAxis();
    final center = Offset(_viewportSize.width / 2, _viewportSize.height / 2);
    final translation = center - point * scale;
    final controller = _transformController;
    if (controller is FlowCanvasController) {
      controller.centerAt(point, _viewportSize);
    } else {
      controller.value = Matrix4.identity()
        ..translateByDouble(translation.dx, translation.dy, 0, 1)
        ..scaleByDouble(scale, scale, 1, 1);
    }
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    final isSelectionKey = widget.selectionKeyCodes.contains(event.logicalKey);
    if (isSelectionKey && event is KeyDownEvent && !_selectionKeyPressed) {
      _selectionKeyPressed = true;
      if (mounted) _rebuild(() {});
    } else if (isSelectionKey && event is KeyUpEvent && _selectionKeyPressed) {
      _selectionKeyPressed = false;
      if (mounted) _rebuild(() {});
    }
    return false;
  }

  void _clearSelection() {
    if (_selectedNodes.isEmpty && _selectedEdges.isEmpty) return;
    _rebuild(() {
      _selectedNodes.clear();
      _selectedEdges.clear();
    });
    _emitSelection();
  }

  void _deleteSelection() {
    final deletableNodes = _nodes
        .where((node) => _selectedNodes.contains(node.id) && node.deletable)
        .map((node) => node.id)
        .toSet();
    final deletableEdges = _edges
        .where((edge) => _selectedEdges.contains(edge.id) && edge.deletable)
        .map((edge) => edge.id)
        .toSet();
    if (deletableNodes.isEmpty && deletableEdges.isEmpty) return;
    final deleting =
        FlowSelection(nodes: deletableNodes, edges: deletableEdges);
    if (widget.onBeforeDelete?.call(deleting) == false) return;
    final nodesById = {for (final node in _nodes) node.id: node};
    _nodes = List.unmodifiable([
      for (final node in _nodes)
        if (!deletableNodes.contains(node.id))
          if (node.parentId != null && deletableNodes.contains(node.parentId))
            node.copyWith(
              position: FlowGeometry.absolutePosition(node, nodesById) +
                  Offset(node.width * node.origin.dx,
                      node.height * node.origin.dy),
              clearParentId: true,
            )
          else
            node,
    ]);
    _edges = List.unmodifiable(_edges.where((edge) =>
        !deletableEdges.contains(edge.id) &&
        !deletableNodes.contains(edge.sourceId) &&
        !deletableNodes.contains(edge.targetId)));
    _selectedNodes.removeAll(deletableNodes);
    _selectedEdges.removeAll(deletableEdges);
    _rebuild(() {});
    _emitSelection();
    widget.onDelete?.call(deleting);
  }
}
