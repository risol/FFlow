part of 'flow_canvas.dart';

extension _FlowCanvasViewportInteractions<T> on _FFlowCanvasState<T> {
  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (_FlowInteractionLocks.blocksWheelAt(event.position)) return;
    if (widget.panOnScroll && widget.panEnabled) {
      _panBy(Offset(
        -event.scrollDelta.dx * widget.panOnScrollSpeed,
        -event.scrollDelta.dy * widget.panOnScrollSpeed,
      ));
      return;
    }
    if (event.kind == PointerDeviceKind.trackpad) {
      if (widget.panEnabled) _panBy(-event.scrollDelta);
      return;
    }
    if (!widget.zoomEnabled || !widget.zoomOnScroll) return;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) return;
    final focalPoint = renderObject.globalToLocal(event.position);
    final factor =
        math.exp(-event.scrollDelta.dy / 500).clamp(0.5, 2.0).toDouble();
    final current = _transformController.value.getMaxScaleOnAxis();
    final next =
        (current * factor).clamp(widget.minZoom, widget.maxZoom).toDouble();
    final scaleFactor = next / current;
    final aroundPoint = Matrix4.identity()
      ..translateByDouble(focalPoint.dx, focalPoint.dy, 0, 1)
      ..scaleByDouble(scaleFactor, scaleFactor, 1, 1)
      ..translateByDouble(-focalPoint.dx, -focalPoint.dy, 0, 1);
    _transformController.value = aroundPoint * _transformController.value;
  }

  void _handleInteractionUpdate(ScaleUpdateDetails details) {
    if (details.pointerCount < 2 || !widget.zoomEnabled) return;
    final startZoom = _pinchStartZoom;
    if (startZoom == null) return;
    final currentZoom = _transformController.value.getMaxScaleOnAxis();
    final targetZoom =
        (startZoom * details.scale).clamp(widget.minZoom, widget.maxZoom);
    if (targetZoom == currentZoom || currentZoom == 0) return;
    _zoomAt(details.localFocalPoint, targetZoom / currentZoom);
  }

  void _panBy(Offset delta) {
    _transformController.value =
        Matrix4.translationValues(delta.dx, delta.dy, 0) *
            _transformController.value;
  }

  void _autoPanForGesture(
    Offset globalPosition, {
    required FlowAutoPanInteraction interaction,
  }) {
    final enabled = widget.autoPan &&
        switch (interaction) {
          FlowAutoPanInteraction.nodeDrag => widget.autoPanOnNodeDrag,
          FlowAutoPanInteraction.connect => widget.autoPanOnConnect,
          FlowAutoPanInteraction.selection => widget.autoPanOnSelection,
        };
    if (!enabled ||
        _viewportSize.isEmpty ||
        widget.autoPanMargin <= 0 ||
        widget.autoPanSpeed <= 0) {
      _stopAutoPan();
      return;
    }
    _autoPanPointerGlobal = globalPosition;
    _autoPanInteraction = interaction;
    _autoPanLastTick = null;
    _autoPanTicker ??= createTicker(_tickAutoPan);
    if (!_autoPanTicker!.isActive) _autoPanTicker!.start();
  }

  void _tickAutoPan(Duration elapsed) {
    final pointer = _autoPanPointerGlobal;
    final interaction = _autoPanInteraction;
    if (pointer == null || interaction == null) {
      _stopAutoPan();
      return;
    }
    final previous = _autoPanLastTick;
    final frameSeconds = previous == null
        ? 1 / 60
        : (elapsed - previous).inMicroseconds / Duration.microsecondsPerSecond;
    _autoPanLastTick = elapsed;
    _performAutoPan(pointer, frameSeconds.clamp(0.0, 0.1).toDouble());
  }

  void _performAutoPan(Offset globalPosition, double elapsedSeconds) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) return;
    final point = renderObject.globalToLocal(globalPosition);
    final margin = widget.autoPanMargin;
    var dx = 0.0;
    var dy = 0.0;
    if (point.dx < margin) {
      dx = widget.autoPanSpeed *
          (1 - point.dx / margin).clamp(0.0, 1.0).toDouble();
    } else if (point.dx > _viewportSize.width - margin) {
      dx = -widget.autoPanSpeed *
          (1 - (_viewportSize.width - point.dx) / margin)
              .clamp(0.0, 1.0)
              .toDouble();
    }
    if (point.dy < margin) {
      dy = widget.autoPanSpeed *
          (1 - point.dy / margin).clamp(0.0, 1.0).toDouble();
    } else if (point.dy > _viewportSize.height - margin) {
      dy = -widget.autoPanSpeed *
          (1 - (_viewportSize.height - point.dy) / margin)
              .clamp(0.0, 1.0)
              .toDouble();
    }
    if (dx == 0 && dy == 0) {
      _stopAutoPan();
      return;
    }
    final panDelta = Offset(dx, dy) * (elapsedSeconds * 60);
    _panBy(panDelta);
    final flowPoint = _screenToFlow(point);
    final interaction = _interactionSession;
    if (interaction?.kind == FlowInteractionKind.nodeDragging) {
      final previous = _lastDragFlowPosition;
      if (previous != null) {
        _lastDragFlowPosition = flowPoint;
        _applyNodeDragDelta(flowPoint - previous, interaction!.movingNodeIds);
      }
    } else if (_selectionBoxStart != null) {
      _selectionBoxEnd = flowPoint;
      widget.onSelectionDrag
          ?.call(Rect.fromPoints(_selectionBoxStart!, flowPoint));
      _rebuild(() {});
    } else if (_connectionGestureStart != null) {
      if (_reconnectingEdgeId != null && _reconnectingSource) {
        _connectionStart = flowPoint;
      } else {
        _connectionPoint = flowPoint;
      }
      _rebuild(() {});
    }
  }

  void _stopAutoPan() {
    _autoPanPointerGlobal = null;
    _autoPanInteraction = null;
    _autoPanLastTick = null;
    if (_autoPanTicker?.isActive ?? false) _autoPanTicker!.stop();
  }

  Offset _snapPosition(Offset position, Offset? grid) {
    if (grid == null) return position;
    return Offset(
      grid.dx > 0 ? (position.dx / grid.dx).round() * grid.dx : position.dx,
      grid.dy > 0 ? (position.dy / grid.dy).round() * grid.dy : position.dy,
    );
  }

  void _zoomAt(Offset focalPoint, double factor) {
    final current = _transformController.value.getMaxScaleOnAxis();
    final next =
        (current * factor).clamp(widget.minZoom, widget.maxZoom).toDouble();
    final scale = next / current;
    final aroundPoint = Matrix4.identity()
      ..translateByDouble(focalPoint.dx, focalPoint.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-focalPoint.dx, -focalPoint.dy, 0, 1);
    _transformController.value = aroundPoint * _transformController.value;
  }

  Rect? get _sceneViewportRect {
    if (_viewportSize.isEmpty) return null;
    final topLeft = _screenToFlow(Offset.zero);
    final bottomRight =
        _screenToFlow(Offset(_viewportSize.width, _viewportSize.height));
    final margin = 120 / _transformController.value.getMaxScaleOnAxis();
    return Rect.fromPoints(topLeft, bottomRight).inflate(margin);
  }
}
