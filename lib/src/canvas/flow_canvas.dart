import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../controllers/flow_canvas_controller.dart';
import '../geometry/flow_geometry.dart';
import '../interactions/flow_graph_interaction.dart';
import '../models/flow_connection.dart';
import '../models/flow_edge.dart';
import '../models/flow_handle.dart';
import '../models/flow_node.dart';
import '../models/flow_selection.dart';
import '../models/flow_viewport.dart';
import '../rendering/flow_edges_painter.dart';
import '../rendering/flow_grid_painter.dart';
import '../rendering/flow_port.dart';

typedef FlowNodeBuilder<T> = Widget Function(
  BuildContext context,
  FlowNode<T> node,
  bool selected,
);

typedef FlowEdgeBuilder<T> = Widget Function(
  BuildContext context,
  FlowEdge edge,
  Offset source,
  Offset target,
  bool selected,
);

/// A controlled node and edge canvas for building graph editors.
///
/// The host owns graph state and applies the lists passed to [onNodesChanged]
/// and [onEdgesChanged]. The canvas owns gesture handling, selection, and
/// viewport transforms. Pass [controller] to drive the viewport from controls.
class FFlowCanvas<T> extends StatefulWidget {
  const FFlowCanvas({
    super.key,
    required this.nodes,
    required this.edges,
    required this.nodeBuilder,
    this.controller,
    this.transformationController,
    this.onNodesChanged,
    this.onEdgesChanged,
    this.onConnect,
    this.onNodeSelected,
    this.onSelectionChanged,
    this.onViewportChanged,
    this.isValidConnection,
    this.gridSpacing = 24,
    this.backgroundVariant = FlowBackgroundVariant.dots,
    this.gridColor = const Color(0xFF272D39),
    this.edgeColor = const Color(0xFF727C90),
    this.connectionColor = const Color(0xFF9A8BFF),
    this.backgroundColor = const Color(0xFF12151D),
    this.minZoom = 0.25,
    this.maxZoom = 2,
    this.snapRadius = 38,
    this.edgeLabelBuilder,
    this.edgeTypes = const {},
    this.panEnabled = true,
    this.zoomEnabled = true,
    this.panOnScroll = false,
    this.zoomOnScroll = true,
    this.zoomOnDoubleClick = true,
    this.snapGrid,
    this.onReconnect,
  }) : assert(controller == null || transformationController == null,
            'Use either controller or transformationController, not both.');

  final List<FlowNode<T>> nodes;
  final List<FlowEdge> edges;
  final FlowNodeBuilder<T> nodeBuilder;
  final FlowCanvasController? controller;

  /// Compatibility with Flutter's built-in InteractiveViewer controller.
  final TransformationController? transformationController;
  final ValueChanged<List<FlowNode<T>>>? onNodesChanged;
  final ValueChanged<List<FlowEdge>>? onEdgesChanged;
  final ValueChanged<FlowConnection>? onConnect;
  final ValueChanged<String?>? onNodeSelected;
  final ValueChanged<FlowSelection>? onSelectionChanged;
  final ValueChanged<FlowViewport>? onViewportChanged;
  final bool Function(FlowConnection connection)? isValidConnection;
  final double gridSpacing;
  final FlowBackgroundVariant backgroundVariant;
  final Color gridColor;
  final Color edgeColor;
  final Color connectionColor;
  final Color backgroundColor;
  final double minZoom;
  final double maxZoom;
  final double snapRadius;
  final Widget Function(BuildContext context, FlowEdge edge)? edgeLabelBuilder;
  final Map<String, FlowEdgeBuilder<T>> edgeTypes;
  final bool panEnabled;
  final bool zoomEnabled;
  final bool panOnScroll;
  final bool zoomOnScroll;
  final bool zoomOnDoubleClick;
  final Offset? snapGrid;
  final ValueChanged<FlowEdge>? onReconnect;

  @override
  State<FFlowCanvas<T>> createState() => _FFlowCanvasState<T>();
}

class _FFlowCanvasState<T> extends State<FFlowCanvas<T>>
    with SingleTickerProviderStateMixin {
  late final FlowCanvasController _ownedController;
  late TransformationController _transformController;
  late List<FlowNode<T>> _nodes;
  late List<FlowEdge> _edges;
  final Set<String> _selectedNodes = {};
  final Set<String> _selectedEdges = {};
  final FocusNode _focusNode = FocusNode(debugLabel: 'FFlowCanvas');
  late final AnimationController _animationController;
  String? _connectingNodeId;
  String? _connectingHandleId;
  Offset? _connectionStart;
  Offset? _connectionPoint;
  String? _reconnectingEdgeId;
  bool _reconnectingSource = false;
  String? _draggingNodeId;
  Offset? _lastDragGlobalPosition;
  bool _shiftPressed = false;
  Offset? _selectionBoxStart;
  Offset? _selectionBoxEnd;
  String? _resizingNodeId;
  Offset? _resizeStartGlobal;
  Size? _resizeStartSize;
  String? _pointerDownNodeId;
  bool _nodeWasSelectedOnPointerDown = false;
  Duration? _lastBlankPointerDown;
  Offset? _lastBlankPointerPosition;

  @override
  void initState() {
    super.initState();
    _nodes = List.of(widget.nodes);
    _edges = List.of(widget.edges);
    _selectedNodes
        .addAll(_nodes.where((node) => node.selected).map((node) => node.id));
    _selectedEdges
        .addAll(_edges.where((edge) => edge.selected).map((edge) => edge.id));
    _ownedController = FlowCanvasController();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _transformController = _controllerFor(widget);
    _transformController.addListener(_handleTransformChanged);
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
    _syncEdgeAnimation();
  }

  @override
  void didUpdateWidget(covariant FFlowCanvas<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextController = _controllerFor(widget);
    if (!identical(nextController, _transformController)) {
      _transformController.removeListener(_handleTransformChanged);
      _transformController = nextController;
      _transformController.addListener(_handleTransformChanged);
    }
    if (!identical(oldWidget.nodes, widget.nodes)) {
      _nodes = List.of(widget.nodes);
      _selectedNodes
        ..clear()
        ..addAll(_nodes.where((node) => node.selected).map((node) => node.id));
    }
    if (!identical(oldWidget.edges, widget.edges)) {
      _edges = List.of(widget.edges);
      _selectedEdges
        ..clear()
        ..addAll(_edges.where((edge) => edge.selected).map((edge) => edge.id));
    }
    _syncEdgeAnimation();
    _selectedNodes.removeWhere((id) => !_nodes.any((node) => node.id == id));
    _selectedEdges.removeWhere((id) => !_edges.any((edge) => edge.id == id));
  }

  TransformationController _controllerFor(FFlowCanvas<T> configuration) =>
      configuration.controller ??
      configuration.transformationController ??
      _ownedController;

  @override
  void dispose() {
    _transformController.removeListener(_handleTransformChanged);
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    _focusNode.dispose();
    _animationController.dispose();
    _ownedController.dispose();
    super.dispose();
  }

  void _handleTransformChanged() {
    final matrix = _transformController.value;
    widget.onViewportChanged?.call(FlowViewport(
      x: matrix.entry(0, 3),
      y: matrix.entry(1, 3),
      zoom: matrix.getMaxScaleOnAxis(),
    ));
  }

  void _syncEdgeAnimation() {
    final hasAnimatedEdges =
        _edges.any((edge) => edge.animated && !edge.hidden);
    if (hasAnimatedEdges && !_animationController.isAnimating) {
      _animationController.repeat();
    } else if (!hasAnimatedEdges && _animationController.isAnimating) {
      _animationController.stop();
      _animationController.value = 0;
    }
  }

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
    widget.onNodesChanged?.call(_nodes);
    widget.onEdgesChanged?.call(_edges);
    widget.onSelectionChanged?.call(_selection);
    widget.onNodeSelected?.call(
      _selectedNodes.length == 1 ? _selectedNodes.first : null,
    );
  }

  void _selectNode(String id, {required bool toggle}) {
    final node = _nodes.where((item) => item.id == id).firstOrNull;
    if (node == null || !node.selectable) return;
    setState(() {
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
    setState(() {
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
    return keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight) ||
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight) ||
        keys.contains(LogicalKeyboardKey.shiftLeft) ||
        keys.contains(LogicalKeyboardKey.shiftRight);
  }

  void _handleKey(FocusNode node, KeyEvent event) {
    final shiftKey = event.logicalKey == LogicalKeyboardKey.shiftLeft ||
        event.logicalKey == LogicalKeyboardKey.shiftRight;
    if (shiftKey && event is KeyDownEvent && !_shiftPressed) {
      _shiftPressed = true;
      setState(() {});
    } else if (shiftKey && event is KeyUpEvent && _shiftPressed) {
      _shiftPressed = false;
      setState(() {});
    }
    if (event is! KeyDownEvent) return;
    final focusedWidget = FocusManager.instance.primaryFocus?.context?.widget;
    if (focusedWidget is EditableText || focusedWidget is TextField) return;
    final key = event.logicalKey;
    final keys = HardwareKeyboard.instance.logicalKeysPressed;
    final modifier = keys.contains(LogicalKeyboardKey.controlLeft) ||
        keys.contains(LogicalKeyboardKey.controlRight) ||
        keys.contains(LogicalKeyboardKey.metaLeft) ||
        keys.contains(LogicalKeyboardKey.metaRight);
    if (key == LogicalKeyboardKey.escape) {
      _clearSelection();
    } else if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      _deleteSelection();
    } else if (modifier && key == LogicalKeyboardKey.keyA) {
      setState(() {
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

  bool _handleGlobalKeyEvent(KeyEvent event) {
    final isShift = event.logicalKey == LogicalKeyboardKey.shiftLeft ||
        event.logicalKey == LogicalKeyboardKey.shiftRight;
    if (isShift && event is KeyDownEvent && !_shiftPressed) {
      _shiftPressed = true;
      if (mounted) setState(() {});
    } else if (isShift && event is KeyUpEvent && _shiftPressed) {
      _shiftPressed = false;
      if (mounted) setState(() {});
    }
    return false;
  }

  void _clearSelection() {
    if (_selectedNodes.isEmpty && _selectedEdges.isEmpty) return;
    setState(() {
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
    final nodesById = {for (final node in _nodes) node.id: node};
    _nodes = List.unmodifiable([
      for (final node in _nodes)
        if (!deletableNodes.contains(node.id))
          if (node.parentId != null && deletableNodes.contains(node.parentId))
            node.copyWith(
              position: FlowGeometry.absolutePosition(node, nodesById),
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
    widget.onNodesChanged?.call(_nodes);
    widget.onEdgesChanged?.call(_edges);
    setState(() {});
    _emitSelection();
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse &&
        (event.buttons & kPrimaryButton) == 0) {
      return;
    }
    _focusNode.requestFocus();
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
    if (_shiftPressed || _isShiftDown) {
      _selectionBoxStart = scenePoint;
      _selectionBoxEnd = scenePoint;
      setState(() {});
      return;
    }
    for (final edge in _edges.reversed) {
      if (edge.hidden || !edge.selectable) continue;
      final start = FlowGeometry.edgeSource(edge, nodesById);
      final end = FlowGeometry.edgeTarget(edge, nodesById);
      if (start == null || end == null) continue;
      final path = FlowGeometry.edgePathFor(edge, nodesById);
      if (FlowGeometry.distanceToPath(path, scenePoint) <=
          edge.interactionWidth /
              _transformController.value.getMaxScaleOnAxis()) {
        _selectEdge(edge.id, toggle: _multiSelectPressed);
        _lastBlankPointerDown = null;
        _lastBlankPointerPosition = null;
        return;
      }
    }
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

  void _handlePointerMove(PointerMoveEvent event) {
    if (_selectionBoxStart == null) {
      if (_lastBlankPointerDown != null && event.delta.distance > kTouchSlop) {
        _lastBlankPointerDown = null;
        _lastBlankPointerPosition = null;
      }
      return;
    }
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) return;
    final local = renderObject.globalToLocal(event.position);
    setState(() => _selectionBoxEnd = _transformController.toScene(local));
  }

  void _handlePointerUp(PointerEvent event) {
    final start = _selectionBoxStart;
    final end = _selectionBoxEnd;
    if (start == null || end == null) return;
    final box = Rect.fromPoints(start, end);
    final nodesById = {for (final node in _nodes) node.id: node};
    setState(() {
      _selectedNodes.addAll(_nodes.where((node) {
        if (!node.selectable || !FlowGeometry.isVisible(node, nodesById)) {
          return false;
        }
        final rect = FlowGeometry.nodeRect(node, nodesById);
        return box.overlaps(rect);
      }).map((node) => node.id));
      _selectionBoxStart = null;
      _selectionBoxEnd = null;
    });
    _emitSelection();
  }

  void _startNodeDrag(FlowNode<T> node, DragStartDetails details) {
    _focusNode.requestFocus();
    if (!_selectedNodes.contains(node.id)) {
      _selectNode(node.id, toggle: _multiSelectPressed);
    }
    _draggingNodeId = node.id;
    _lastDragGlobalPosition = details.globalPosition;
  }

  void _updateNodeDrag(DragUpdateDetails details) {
    final previous = _lastDragGlobalPosition;
    if (previous == null) return;
    final delta = (details.globalPosition - previous) /
        _transformController.value.getMaxScaleOnAxis();
    _lastDragGlobalPosition = details.globalPosition;
    final candidates = _selectedNodes.contains(_draggingNodeId)
        ? _selectedNodes.toSet()
        : {_draggingNodeId};
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
            position: _snapPosition(node.position + delta, grid),
          )
        else
          node,
    ]);
    widget.onNodesChanged?.call(_nodes);
    setState(() {});
  }

  void _endNodeDrag(DragEndDetails details) {
    _draggingNodeId = null;
    _lastDragGlobalPosition = null;
  }

  void _startNodeResize(FlowNode<T> node, DragStartDetails details) {
    _resizingNodeId = node.id;
    _resizeStartGlobal = details.globalPosition;
    _resizeStartSize = Size(node.width, node.height);
  }

  void _updateNodeResize(DragUpdateDetails details) {
    final id = _resizingNodeId;
    final start = _resizeStartGlobal;
    final size = _resizeStartSize;
    if (id == null || start == null || size == null) return;
    final delta = (details.globalPosition - start) /
        _transformController.value.getMaxScaleOnAxis();
    _nodes = List.unmodifiable([
      for (final node in _nodes)
        if (node.id == id)
          node.copyWith(
            width: (size.width + delta.dx).clamp(80.0, 2000.0).toDouble(),
            height: (size.height + delta.dy).clamp(48.0, 2000.0).toDouble(),
          )
        else
          node,
    ]);
    widget.onNodesChanged?.call(_nodes);
    setState(() {});
  }

  void _endNodeResize(DragEndDetails details) {
    _resizingNodeId = null;
    _resizeStartGlobal = null;
    _resizeStartSize = null;
  }

  void _startConnection(
      FlowNode<T> node, FlowHandle handle, DragStartDetails details) {
    _connectingNodeId = node.id;
    _connectingHandleId = handle.id;
    final renderObject = context.findRenderObject();
    final local = renderObject is RenderBox
        ? renderObject.globalToLocal(details.globalPosition)
        : details.localPosition;
    _connectionStart = FlowGeometry.handleAnchor(
      node,
      handle,
      nodes: {for (final item in _nodes) item.id: item},
    );
    _connectionPoint = _transformController.toScene(local);
    setState(() {});
  }

  void _updateConnection(DragUpdateDetails details) {
    if (_connectingNodeId == null && _reconnectingEdgeId == null) return;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) return;
    final local = renderObject.globalToLocal(details.globalPosition);
    final point = _transformController.toScene(local);
    setState(() {
      if (_reconnectingEdgeId != null && _reconnectingSource) {
        _connectionStart = point;
      } else {
        _connectionPoint = point;
      }
    });
  }

  void _endConnection(DragEndDetails details) {
    final dropPoint = _scenePointFromGlobal(details.globalPosition);
    final reconnectEdgeId = _reconnectingEdgeId;
    if (reconnectEdgeId != null) {
      final edge =
          _edges.where((item) => item.id == reconnectEdgeId).firstOrNull;
      final point = dropPoint ??
          (_reconnectingSource ? _connectionStart : _connectionPoint);
      if (edge != null && point != null) {
        final nodeMap = {for (final node in _nodes) node.id: node};
        final targetHandle = nodeMap[edge.targetId] == null
            ? null
            : FlowGeometry.handleFor(
                nodeMap[edge.targetId]!,
                edge.targetHandleId,
                FlowHandleType.target,
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
                targetHandleId: targetHandle?.id ?? '',
                point: point,
                excludedEdgeId: edge.id,
                isValidConnection: widget.isValidConnection,
                snapRadius: _sceneSnapRadius,
              )
            : FlowGraphInteraction.connectionAt(
                nodes: _nodes,
                edges: _edges,
                sourceId: edge.sourceId,
                sourceHandleId: sourceHandle?.id ?? '',
                point: point,
                excludedEdgeId: edge.id,
                isValidConnection: widget.isValidConnection,
                snapRadius: _sceneSnapRadius,
              );
        if (connection != null) {
          _edges = FlowGraphInteraction.reconnectEdge(
            edges: _edges,
            edgeId: edge.id,
            connection: connection,
          );
          final updatedEdge = _edges.firstWhere((item) => item.id == edge.id);
          widget.onReconnect?.call(updatedEdge);
          widget.onEdgesChanged?.call(_edges);
        }
      }
      setState(() {
        _reconnectingEdgeId = null;
        _connectingNodeId = null;
        _connectingHandleId = null;
        _connectionStart = null;
        _connectionPoint = null;
      });
      return;
    }

    final sourceId = _connectingNodeId;
    final handleId = _connectingHandleId;
    final point = dropPoint ?? _connectionPoint;
    if (sourceId != null && handleId != null && point != null) {
      final connection = FlowGraphInteraction.connectionAt(
        nodes: _nodes,
        edges: _edges,
        sourceId: sourceId,
        sourceHandleId: handleId,
        point: point,
        isValidConnection: widget.isValidConnection,
        snapRadius: _sceneSnapRadius,
      );
      if (connection != null) widget.onConnect?.call(connection);
    }
    setState(() {
      _connectingNodeId = null;
      _connectingHandleId = null;
      _connectionStart = null;
      _connectionPoint = null;
    });
  }

  double get _sceneSnapRadius =>
      widget.snapRadius / _transformController.value.getMaxScaleOnAxis();

  Offset? _scenePointFromGlobal(Offset globalPosition) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox) return null;
    return _transformController
        .toScene(renderObject.globalToLocal(globalPosition));
  }

  void _startReconnect(
      FlowEdge edge, bool sourceSide, DragStartDetails details) {
    final nodeMap = {for (final node in _nodes) node.id: node};
    final source = FlowGeometry.edgeSource(edge, nodeMap);
    final target = FlowGeometry.edgeTarget(edge, nodeMap);
    if (source == null || target == null) return;
    _reconnectingEdgeId = edge.id;
    _reconnectingSource = sourceSide;
    _connectionStart = source;
    _connectionPoint = target;
    setState(() {});
  }

  Widget _buildReconnectHandle(FlowEdge edge, bool sourceSide, Offset point) =>
      Positioned(
        left: point.dx - 11,
        top: point.dy - 11,
        width: 22,
        height: 22,
        child: FlowPort(
          isOutput: sourceSide,
          enabled: true,
          onPanStart: (details) => _startReconnect(edge, sourceSide, details),
          onPanUpdate: _updateConnection,
          onPanEnd: _endConnection,
        ),
      );

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (widget.panOnScroll && widget.panEnabled) {
      _panBy(Offset(-event.scrollDelta.dx, -event.scrollDelta.dy));
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

  void _panBy(Offset delta) {
    _transformController.value =
        Matrix4.translationValues(delta.dx, delta.dy, 0) *
            _transformController.value;
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

  @override
  Widget build(BuildContext context) {
    final nodesById = {for (final node in _nodes) node.id: node};
    final visibleNodes = _orderedVisibleNodes(nodesById);
    final customEdges = <Widget>[];
    final defaultEdges = <FlowEdge>[];
    for (final edge in _edges) {
      final builder = widget.edgeTypes[edge.customType ?? edge.type.name];
      if (builder == null || edge.hidden) {
        defaultEdges.add(edge);
        continue;
      }
      final source = FlowGeometry.edgeSource(edge, nodesById);
      final target = FlowGeometry.edgeTarget(edge, nodesById);
      if (source != null && target != null) {
        customEdges.add(Positioned.fill(
          child: builder(
            context,
            edge,
            source,
            target,
            _selectedEdges.contains(edge.id),
          ),
        ));
      }
    }
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        _handleKey(node, event);
        return KeyEventResult.ignored;
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _handlePointerDown,
        onPointerMove: _handlePointerMove,
        onPointerUp: _handlePointerUp,
        onPointerCancel: _handlePointerUp,
        onPointerSignal: _handlePointerSignal,
        child: LayoutBuilder(builder: (context, constraints) {
          final viewportSize =
              Size(constraints.maxWidth, constraints.maxHeight);
          if (_transformController is FlowCanvasController) {
            (_transformController as FlowCanvasController)
                .updateViewportSize(viewportSize);
          }
          return ClipRect(
            child: ColoredBox(
              color: widget.backgroundColor,
              child: InteractiveViewer(
                transformationController: _transformController,
                minScale: widget.minZoom,
                maxScale: widget.maxZoom,
                panEnabled: widget.panEnabled &&
                    !_shiftPressed &&
                    !_isShiftDown &&
                    _selectionBoxStart == null,
                scaleEnabled: widget.zoomEnabled,
                trackpadScrollCausesScale: false,
                constrained: false,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                child: SizedBox(
                  width: viewportSize.width,
                  height: viewportSize.height,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: CustomPaint(
                          painter: FlowGridPainter(
                            color: widget.gridColor,
                            spacing: widget.gridSpacing,
                            variant: widget.backgroundVariant,
                          ),
                        ),
                      ),
                      if (_selectionBoxStart != null &&
                          _selectionBoxEnd != null)
                        Positioned.fromRect(
                          rect: Rect.fromPoints(
                              _selectionBoxStart!, _selectionBoxEnd!),
                          child: IgnorePointer(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: widget.connectionColor
                                    .withValues(alpha: 0.12),
                                border:
                                    Border.all(color: widget.connectionColor),
                              ),
                            ),
                          ),
                        ),
                      Positioned.fill(
                        child: CustomPaint(
                          painter: FlowEdgesPainter<T>(
                            nodes: _nodes,
                            edges: defaultEdges,
                            selectedEdgeIds: _selectedEdges,
                            defaultColor: widget.edgeColor,
                            previewStart: _connectionStart,
                            previewTarget: _connectionPoint,
                            previewColor: widget.connectionColor,
                            animation: _animationController,
                          ),
                        ),
                      ),
                      for (final edge in _edges)
                        if (!edge.hidden &&
                            edge.label != null &&
                            widget.edgeLabelBuilder == null)
                          _buildEdgeLabel(edge, nodesById),
                      for (final edge in _edges)
                        if (!edge.hidden &&
                            edge.label != null &&
                            widget.edgeLabelBuilder != null)
                          _buildCustomEdgeLabel(edge, nodesById),
                      ...customEdges,
                      for (final edge in _edges)
                        if (!edge.hidden &&
                            edge.reconnectable &&
                            _selectedEdges.contains(edge.id)) ...[
                          if (FlowGeometry.edgeSource(edge, nodesById)
                              case final source?)
                            _buildReconnectHandle(edge, true, source),
                          if (FlowGeometry.edgeTarget(edge, nodesById)
                              case final target?)
                            _buildReconnectHandle(edge, false, target),
                        ],
                      for (final node in visibleNodes)
                        _buildNode(node, nodesById),
                    ],
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

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
            : order[first.id]!.compareTo(order[second.id]!);
      });
  }

  Widget _buildNode(FlowNode<T> node, Map<String, FlowNode<T>> nodesById) {
    final selected = _selectedNodes.contains(node.id);
    final position = FlowGeometry.absolutePosition(node, nodesById);
    return Positioned(
      left: position.dx,
      top: position.dy,
      width: node.width,
      height: node.height,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (_pointerDownNodeId == node.id &&
                    !_nodeWasSelectedOnPointerDown &&
                    _selectedNodes.contains(node.id)) {
                  _pointerDownNodeId = null;
                  return;
                }
                _selectNode(node.id, toggle: _multiSelectPressed);
                _pointerDownNodeId = null;
              },
              onPanStart: node.draggable
                  ? (details) => _startNodeDrag(node, details)
                  : null,
              onPanUpdate: node.draggable ? _updateNodeDrag : null,
              onPanEnd: node.draggable ? _endNodeDrag : null,
              child: widget.nodeBuilder(context, node, selected),
            ),
          ),
          for (final handle in node.resolvedHandles)
            _buildHandle(node, handle, nodesById, position),
          if (selected && node.resizable)
            Positioned(
              right: -6,
              bottom: -6,
              width: 18,
              height: 18,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (details) => _startNodeResize(node, details),
                onPanUpdate: _updateNodeResize,
                onPanEnd: _endNodeResize,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: widget.connectionColor,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildHandle(
    FlowNode<T> node,
    FlowHandle handle,
    Map<String, FlowNode<T>> nodesById,
    Offset nodePosition,
  ) {
    final anchor = FlowGeometry.handleAnchor(node, handle, nodes: nodesById);
    final canStart = node.connectable &&
        handle.type == FlowHandleType.source &&
        handle.connectable &&
        handle.connectableStart;
    return Positioned(
      left: anchor.dx - nodePosition.dx - 11,
      top: anchor.dy - nodePosition.dy - 11,
      width: 22,
      height: 22,
      child: FlowPort(
        isOutput: handle.type == FlowHandleType.source,
        enabled: canStart,
        onPanStart: canStart
            ? (details) => _startConnection(node, handle, details)
            : null,
        onPanUpdate: canStart ? _updateConnection : null,
        onPanEnd: canStart ? _endConnection : null,
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
