part of 'flow_canvas.dart';

extension _FlowCanvasEdges<T> on _FFlowCanvasState<T> {
  bool _edgeInViewport(FlowEdge edge, Map<String, FlowNode<T>> nodesById) {
    if (!widget.onlyRenderVisibleElements) return true;
    final viewport = _sceneViewportRect;
    if (viewport == null) return true;
    return FlowGeometry.edgePathFor(edge, nodesById)
        .getBounds()
        .inflate(edge.interactionWidth)
        .overlaps(viewport);
  }

  Widget _toolbarAt(Rect bounds, Widget child) {
    final placement = widget.toolbarPlacement;
    final point = switch (placement) {
      FlowToolbarPlacement.top => Offset(bounds.center.dx, bounds.top),
      FlowToolbarPlacement.right => Offset(bounds.right, bounds.center.dy),
      FlowToolbarPlacement.bottom => Offset(bounds.center.dx, bounds.bottom),
      FlowToolbarPlacement.left => Offset(bounds.left, bounds.center.dy),
    };
    final translation = switch (placement) {
      FlowToolbarPlacement.top => const Offset(-0.5, -1),
      FlowToolbarPlacement.right => const Offset(0, -0.5),
      FlowToolbarPlacement.bottom => const Offset(-0.5, 0),
      FlowToolbarPlacement.left => const Offset(-1, -0.5),
    };
    final offset = switch (placement) {
      FlowToolbarPlacement.top => Offset(0, -widget.toolbarOffset),
      FlowToolbarPlacement.right => Offset(widget.toolbarOffset, 0),
      FlowToolbarPlacement.bottom => Offset(0, widget.toolbarOffset),
      FlowToolbarPlacement.left => Offset(-widget.toolbarOffset, 0),
    };
    return Positioned(
      left: point.dx + offset.dx,
      top: point.dy + offset.dy,
      child: FractionalTranslation(translation: translation, child: child),
    );
  }

  Widget _buildEdgeSemantics(
    FlowEdge edge,
    Map<String, FlowNode<T>> nodesById,
    double order,
  ) {
    final point = FlowGeometry.pointAlongPath(
        FlowGeometry.edgePathFor(edge, nodesById), 0.5);
    final focused = _edgeFocusNode(edge.id);
    final label = edge.ariaLabel ??
        edge.label ??
        'Connection from ${edge.sourceId} to ${edge.targetId}';
    return Positioned(
      left: point.dx - 12,
      top: point.dy - 12,
      width: 24,
      height: 24,
      child: IgnorePointer(
        child: FocusTraversalOrder(
          order: NumericFocusOrder(order),
          child: Focus(
            focusNode: focused,
            canRequestFocus: edge.focusable,
            skipTraversal: !edge.focusable,
            onFocusChange: (hasFocus) {
              if (hasFocus) _keepPointInView(point);
              if (mounted) _rebuild(() {});
            },
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  (event.logicalKey == LogicalKeyboardKey.enter ||
                      event.logicalKey == LogicalKeyboardKey.space)) {
                if (edge.selectable) {
                  _selectEdge(edge.id, toggle: false);
                  widget.onEdgeClick?.call(edge.id);
                }
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Semantics(
              container: true,
              label: label,
              button: true,
              focusable: edge.focusable,
              focused: focused.hasFocus,
              selected: _selectedEdges.contains(edge.id),
              onTap: edge.selectable
                  ? () {
                      _selectEdge(edge.id, toggle: false);
                      widget.onEdgeClick?.call(edge.id);
                    }
                  : null,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEdgeLabel(FlowEdge edge, Map<String, FlowNode<T>> nodesById) {
    final start = FlowGeometry.edgeSource(edge, nodesById);
    final end = FlowGeometry.edgeTarget(edge, nodesById);
    if (start == null || end == null) return const SizedBox.shrink();
    final point = FlowGeometry.pointAlongPath(
        FlowGeometry.edgePathFor(edge, nodesById), 0.5);
    return Positioned(
      left: point.dx,
      top: point.dy,
      child: IgnorePointer(
        child: FractionalTranslation(
          translation: const Offset(-0.5, -0.5),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF202633),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: const Color(0xFF394151)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              child: Text(edge.label!,
                  style: const TextStyle(color: Colors.white, fontSize: 10)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCustomEdgeLabel(
      FlowEdge edge, Map<String, FlowNode<T>> nodesById) {
    final start = FlowGeometry.edgeSource(edge, nodesById);
    final end = FlowGeometry.edgeTarget(edge, nodesById);
    if (start == null || end == null) return const SizedBox.shrink();
    final point = FlowGeometry.pointAlongPath(
        FlowGeometry.edgePathFor(edge, nodesById), 0.5);
    return Positioned(
      left: point.dx,
      top: point.dy,
      child: FractionalTranslation(
        translation: const Offset(-0.5, -0.5),
        child: widget.edgeLabelBuilder!(context, edge),
      ),
    );
  }
}
