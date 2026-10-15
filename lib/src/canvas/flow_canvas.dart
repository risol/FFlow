import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../controllers/flow_canvas_controller.dart';
import '../controllers/flow_graph_controller.dart';
import '../geometry/flow_geometry.dart';
import '../interactions/flow_graph_interaction.dart';
import '../models/flow_connection.dart';
import '../models/flow_edge.dart';
import '../models/flow_events.dart';
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

typedef FlowNodeToolbarBuilder<T> = Widget Function(
  BuildContext context,
  FlowNode<T> node,
);

typedef FlowEdgeToolbarBuilder = Widget Function(
  BuildContext context,
  FlowEdge edge,
);

/// Marks a region inside a node as a drag handle when [FlowNode.dragHandleOnly]
/// is enabled.
class FFlowNodeDragHandle extends StatelessWidget {
  const FFlowNodeDragHandle({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<_FlowNodeDragScope>();
    if (scope == null) {
      throw FlutterError('FFlowNodeDragHandle must be inside an FFlow node.');
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: scope.onPanStart,
      onPanUpdate: scope.onPanUpdate,
      onPanEnd: scope.onPanEnd,
      onPanCancel: scope.onPanCancel,
      child: child,
    );
  }
}

class _FlowNodeDragScope extends InheritedWidget {
  const _FlowNodeDragScope({
    required this.onPanStart,
    required this.onPanUpdate,
    required this.onPanEnd,
    required this.onPanCancel,
    required super.child,
  });

  final GestureDragStartCallback? onPanStart;
  final GestureDragUpdateCallback? onPanUpdate;
  final GestureDragEndCallback? onPanEnd;
  final GestureDragCancelCallback? onPanCancel;

  @override
  bool updateShouldNotify(_FlowNodeDragScope oldWidget) =>
      onPanStart != oldWidget.onPanStart ||
      onPanUpdate != oldWidget.onPanUpdate ||
      onPanEnd != oldWidget.onPanEnd ||
      onPanCancel != oldWidget.onPanCancel;
}

enum _FlowResizeDirection {
  topLeft(-1, -1),
  top(0, -1),
  topRight(1, -1),
  right(1, 0),
  bottomRight(1, 1),
  bottom(0, 1),
  bottomLeft(-1, 1),
  left(-1, 0);

  const _FlowResizeDirection(this.x, this.y);
  final int x;
  final int y;
}

/// A controlled node and edge canvas for building graph editors.
///
/// The host owns graph state and applies the lists passed to [onNodesChanged]
/// and [onEdgesChanged]. The canvas owns gesture handling, selection, and
/// viewport transforms. Pass [controller] to drive the viewport from controls.
class FFlowCanvas<T> extends StatefulWidget {
  const FFlowCanvas({
    super.key,
    this.nodes,
    this.edges,
    required this.nodeBuilder,
    this.controller,
    this.graphController,
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
    this.panOnScrollSpeed = 1,
    this.zoomOnScroll = true,
    this.zoomOnDoubleClick = true,
    this.snapGrid,
    this.onReconnect,
    this.selectionOnDrag = false,
    this.selectionMode = FlowSelectionMode.partial,
    this.connectionMode = FlowConnectionMode.strict,
    this.translateExtent,
    this.nodeExtent,
    this.elevateNodesOnSelect = true,
    this.elevateEdgesOnSelect = true,
    this.connectOnClick = true,
    this.onlyRenderVisibleElements = false,
    this.autoPan = true,
    this.autoPanMargin = 48,
    this.autoPanSpeed = 12,
    this.onNodeDragStart,
    this.onNodeDrag,
    this.onNodeDragEnd,
    this.onNodeResizeStart,
    this.onNodeResize,
    this.onNodeResizeEnd,
    this.onNodeClick,
    this.onNodeDoubleClick,
    this.onNodeContextMenu,
    this.onNodeMouseEnter,
    this.onNodeMouseMove,
    this.onNodeMouseLeave,
    this.onEdgeClick,
    this.onEdgeDoubleClick,
    this.onEdgeContextMenu,
    this.onEdgeMouseEnter,
    this.onEdgeMouseMove,
    this.onEdgeMouseLeave,
    this.onPaneClick,
    this.onPaneContextMenu,
    this.onPaneMouseEnter,
    this.onPaneMouseMove,
    this.onPaneMouseLeave,
    this.onBeforeDelete,
    this.onDelete,
    this.onSelectionDragStart,
    this.onSelectionDrag,
    this.onSelectionDragEnd,
    this.onConnectStart,
    this.onConnectEnd,
    this.onReconnectStart,
    this.onReconnectEnd,
    this.connectionLineBuilder,
    this.nodeToolbarBuilder,
    this.edgeToolbarBuilder,
    this.toolbarPlacement = FlowToolbarPlacement.top,
    this.toolbarOffset = 12,
    this.canvasLabel = 'Flow editor',
    this.selectionAnnouncementBuilder,
    this.keyboardMoveStep = 1,
    this.keyboardMoveStepWithShift = 10,
    this.deleteKeyCodes = const {
      LogicalKeyboardKey.delete,
      LogicalKeyboardKey.backspace,
    },
    this.selectionKeyCodes = const {
      LogicalKeyboardKey.shiftLeft,
      LogicalKeyboardKey.shiftRight,
    },
    this.multiSelectionKeyCodes = const {
      LogicalKeyboardKey.controlLeft,
      LogicalKeyboardKey.controlRight,
      LogicalKeyboardKey.metaLeft,
      LogicalKeyboardKey.metaRight,
    },
  })  : assert((nodes == null) == (edges == null),
            'Pass both nodes and edges, or omit both when using graphController.'),
        assert(graphController != null || nodes != null,
            'Pass nodes and edges or provide graphController.'),
        assert(graphController == null || nodes == null,
            'Do not combine graphController with controlled nodes/edges.'),
        assert(controller == null || transformationController == null,
            'Use either controller or transformationController, not both.');

  /// Controlled graph data. Omit both when using [graphController].
  final List<FlowNode<T>>? nodes;
  final List<FlowEdge>? edges;
  final FlowNodeBuilder<T> nodeBuilder;
  final FlowCanvasController? controller;
  final FlowGraphController<T>? graphController;

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

  /// Multiplier applied to the scroll delta when [panOnScroll] is enabled.
  final double panOnScrollSpeed;
  final bool zoomOnScroll;
  final bool zoomOnDoubleClick;
  final Offset? snapGrid;
  final ValueChanged<FlowEdge>? onReconnect;

  /// Allows blank-canvas dragging to create a selection box. Shift-drag works
  /// regardless of this setting.
  final bool selectionOnDrag;
  final FlowSelectionMode selectionMode;
  final FlowConnectionMode connectionMode;

  /// Optional canvas-coordinate bounds used to constrain viewport panning.
  final Rect? translateExtent;

  /// Optional graph-coordinate bounds for root-node positions. Child nodes use
  /// their parent-relative [FlowNode.extent] or [FlowNode.extentToParent].
  final Rect? nodeExtent;

  /// Raise selected nodes or edges above peers in their own paint layer.
  final bool elevateNodesOnSelect;
  final bool elevateEdgesOnSelect;

  /// Allow clicking a source handle and then a target handle to connect.
  final bool connectOnClick;

  /// Skip off-screen nodes and edges when true. Leave false for the default
  /// behavior; viewport culling is useful for large graphs.
  final bool onlyRenderVisibleElements;

  /// Auto-pan near the viewport edge while dragging nodes, selecting, or
  /// creating/reconnecting edges.
  final bool autoPan;
  final double autoPanMargin;
  final double autoPanSpeed;

  /// Node lifecycle callbacks receive the updated node model.
  final ValueChanged<FlowNode<T>>? onNodeDragStart;
  final ValueChanged<FlowNode<T>>? onNodeDrag;
  final ValueChanged<FlowNode<T>>? onNodeDragEnd;
  final ValueChanged<FlowNode<T>>? onNodeResizeStart;
  final ValueChanged<FlowNode<T>>? onNodeResize;
  final ValueChanged<FlowNode<T>>? onNodeResizeEnd;
  final ValueChanged<String>? onNodeClick;
  final ValueChanged<FlowNode<T>>? onNodeDoubleClick;
  final FlowNodePointerCallback<T>? onNodeContextMenu;
  final FlowNodePointerCallback<T>? onNodeMouseEnter;
  final FlowNodePointerCallback<T>? onNodeMouseMove;
  final FlowNodePointerCallback<T>? onNodeMouseLeave;
  final ValueChanged<String>? onEdgeClick;
  final FlowEdgePointerCallback? onEdgeDoubleClick;
  final FlowEdgePointerCallback? onEdgeContextMenu;
  final FlowEdgePointerCallback? onEdgeMouseEnter;
  final FlowEdgePointerCallback? onEdgeMouseMove;
  final FlowEdgePointerCallback? onEdgeMouseLeave;
  final VoidCallback? onPaneClick;
  final ValueChanged<FlowPointerPosition>? onPaneContextMenu;
  final ValueChanged<FlowPointerPosition>? onPaneMouseEnter;
  final ValueChanged<FlowPointerPosition>? onPaneMouseMove;
  final ValueChanged<FlowPointerPosition>? onPaneMouseLeave;
  final bool Function(FlowSelection selection)? onBeforeDelete;
  final ValueChanged<FlowSelection>? onDelete;

  /// Selection drag rectangles are expressed in graph coordinates.
  final ValueChanged<Rect>? onSelectionDragStart;
  final ValueChanged<Rect>? onSelectionDrag;
  final ValueChanged<FlowSelection>? onSelectionDragEnd;

  /// Connection event points use graph coordinates; [FlowConnectionEnd]
  /// reports a null connection and `cancelled` when no valid endpoint was hit.
  final ValueChanged<FlowConnectionStart>? onConnectStart;
  final ValueChanged<FlowConnectionEnd>? onConnectEnd;
  final ValueChanged<FlowConnectionStart>? onReconnectStart;
  final ValueChanged<FlowConnectionEnd>? onReconnectEnd;

  /// Builds the temporary connection line from graph-coordinate endpoints.
  final FlowConnectionLineBuilder? connectionLineBuilder;
  final FlowNodeToolbarBuilder<T>? nodeToolbarBuilder;
  final FlowEdgeToolbarBuilder? edgeToolbarBuilder;
  final FlowToolbarPlacement toolbarPlacement;
  final double toolbarOffset;
  final String canvasLabel;
  final String Function(FlowSelection selection)? selectionAnnouncementBuilder;
  final double keyboardMoveStep;
  final double keyboardMoveStepWithShift;
  final Set<LogicalKeyboardKey> deleteKeyCodes;
  final Set<LogicalKeyboardKey> selectionKeyCodes;
  final Set<LogicalKeyboardKey> multiSelectionKeyCodes;

  @override
  State<FFlowCanvas<T>> createState() => _FFlowCanvasState<T>();
}

class _FFlowCanvasState<T> extends State<FFlowCanvas<T>>
    with SingleTickerProviderStateMixin {
  late final FlowCanvasController _ownedController;
  late TransformationController _transformController;
  late List<FlowNode<T>> _nodes;
  late List<FlowEdge> _edges;
  bool _publishingGraphController = false;
  final Set<String> _selectedNodes = {};
  final Set<String> _selectedEdges = {};
  final FocusNode _focusNode = FocusNode(debugLabel: 'FFlowCanvas');
  final Map<String, FocusNode> _nodeFocusNodes = {};
  final Map<String, FocusNode> _edgeFocusNodes = {};
  bool _selectionDragActive = false;
  bool _clampingViewport = false;
  Size _viewportSize = Size.zero;
  FlowConnectionStart? _connectionGestureStart;
  String _accessibilityAnnouncement = '';
  late final AnimationController _animationController;
  String? _connectingNodeId;
  String? _connectingHandleId;
  FlowHandleType? _connectingHandleType;
  Offset? _connectionStart;
  Offset? _connectionPoint;
  String? _reconnectingEdgeId;
  bool _reconnectingSource = false;
  String? _draggingNodeId;
  Offset? _lastDragGlobalPosition;
  bool _selectionKeyPressed = false;
  Offset? _selectionBoxStart;
  Offset? _selectionBoxEnd;
  String? _resizingNodeId;
  Offset? _resizeStartGlobal;
  Size? _resizeStartSize;
  Offset? _resizeStartPosition;
  _FlowResizeDirection _resizeDirection = _FlowResizeDirection.bottomRight;
  String? _pointerDownNodeId;
  bool _nodeWasSelectedOnPointerDown = false;
  bool _pointerDownPane = false;
  Offset? _paneDownPosition;
  String? _hoveredEdgeId;
  bool _pointerOverPane = false;
  Duration? _lastEdgeClickAt;
  Offset? _lastEdgeClickPosition;
  String? _lastEdgeClickId;
  Duration? _lastBlankPointerDown;
  Offset? _lastBlankPointerPosition;

  @override
  void initState() {
    super.initState();
    _nodes = List.of(widget.nodes ?? widget.graphController?.nodes ?? const []);
    _edges = List.of(widget.edges ?? widget.graphController?.edges ?? const []);
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
    widget.graphController?.addListener(_handleGraphControllerChanged);
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
    _syncEdgeAnimation();
  }

  @override
  void didUpdateWidget(covariant FFlowCanvas<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.graphController, widget.graphController)) {
      oldWidget.graphController?.removeListener(_handleGraphControllerChanged);
      widget.graphController?.addListener(_handleGraphControllerChanged);
      if (widget.nodes == null) {
        _nodes = List.of(widget.graphController?.nodes ?? const []);
        _edges = List.of(widget.graphController?.edges ?? const []);
        _selectedNodes
          ..clear()
          ..addAll(
              _nodes.where((node) => node.selected).map((node) => node.id));
        _selectedEdges
          ..clear()
          ..addAll(
              _edges.where((edge) => edge.selected).map((edge) => edge.id));
      }
    }
    final nextController = _controllerFor(widget);
    if (!identical(nextController, _transformController)) {
      _transformController.removeListener(_handleTransformChanged);
      _transformController = nextController;
      _transformController.addListener(_handleTransformChanged);
    }
    if (widget.nodes != null && !identical(oldWidget.nodes, widget.nodes)) {
      _nodes = List.of(widget.nodes!);
      _selectedNodes
        ..clear()
        ..addAll(_nodes.where((node) => node.selected).map((node) => node.id));
    }
    if (widget.edges != null && !identical(oldWidget.edges, widget.edges)) {
      _edges = List.of(widget.edges!);
      _selectedEdges
        ..clear()
        ..addAll(_edges.where((edge) => edge.selected).map((edge) => edge.id));
    }
    _syncFocusNodes();
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
    widget.graphController?.removeListener(_handleGraphControllerChanged);
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    _focusNode.dispose();
    for (final node in _nodeFocusNodes.values) {
      node.dispose();
    }
    for (final edge in _edgeFocusNodes.values) {
      edge.dispose();
    }
    _animationController.dispose();
    _ownedController.dispose();
    super.dispose();
  }

  void _handleGraphControllerChanged() {
    if (_publishingGraphController || !mounted) return;
    final graphController = widget.graphController;
    if (graphController == null) return;
    _nodes = List.of(graphController.nodes);
    _edges = List.of(graphController.edges);
    _selectedNodes
      ..clear()
      ..addAll(_nodes.where((node) => node.selected).map((node) => node.id));
    _selectedEdges
      ..clear()
      ..addAll(_edges.where((edge) => edge.selected).map((edge) => edge.id));
    _syncFocusNodes();
    _syncEdgeAnimation();
    setState(() {});
    widget.onSelectionChanged?.call(_selection);
    widget.onNodeSelected?.call(
      _selectedNodes.length == 1 ? _selectedNodes.first : null,
    );
  }

  void _publishGraph({bool nodesChanged = false, bool edgesChanged = false}) {
    final graphController = widget.graphController;
    if (graphController != null) {
      _publishingGraphController = true;
      graphController.setGraph(nodes: _nodes, edges: _edges);
      _publishingGraphController = false;
    }
    if (nodesChanged) widget.onNodesChanged?.call(_nodes);
    if (edgesChanged) widget.onEdgesChanged?.call(_edges);
  }

  void _publishNodes() => _publishGraph(nodesChanged: true);

  void _publishEdges() => _publishGraph(edgesChanged: true);

  void _handleTransformChanged() {
    final matrix = _transformController.value;
    final extent = widget.translateExtent;
    if (!_clampingViewport && extent != null && !_viewportSize.isEmpty) {
      final scale = matrix.getMaxScaleOnAxis();
      final minX = _viewportSize.width - extent.right * scale;
      final maxX = -extent.left * scale;
      final minY = _viewportSize.height - extent.bottom * scale;
      final maxY = -extent.top * scale;
      final x = minX <= maxX
          ? matrix.entry(0, 3).clamp(minX, maxX).toDouble()
          : (minX + maxX) / 2;
      final y = minY <= maxY
          ? matrix.entry(1, 3).clamp(minY, maxY).toDouble()
          : (minY + maxY) / 2;
      if (x != matrix.entry(0, 3) || y != matrix.entry(1, 3)) {
        _clampingViewport = true;
        _transformController.value = Matrix4.copy(matrix)
          ..setEntry(0, 3, x)
          ..setEntry(1, 3, y);
        _clampingViewport = false;
        widget.onViewportChanged?.call(FlowViewport(
          x: x,
          y: y,
          zoom: scale,
        ));
        if (widget.onlyRenderVisibleElements && mounted) setState(() {});
        return;
      }
    }
    widget.onViewportChanged?.call(FlowViewport(
      x: matrix.entry(0, 3),
      y: matrix.entry(1, 3),
      zoom: matrix.getMaxScaleOnAxis(),
    ));
    if (widget.onlyRenderVisibleElements && mounted) setState(() {});
  }

  void _syncFocusNodes() {
    final nodeIds = _nodes.map((node) => node.id).toSet();
    final edgeIds = _edges.map((edge) => edge.id).toSet();
    for (final id in _nodeFocusNodes.keys.toList()) {
      if (!nodeIds.contains(id)) _nodeFocusNodes.remove(id)?.dispose();
    }
    for (final id in _edgeFocusNodes.keys.toList()) {
      if (!edgeIds.contains(id)) _edgeFocusNodes.remove(id)?.dispose();
    }
  }

  FocusNode _nodeFocusNode(String id) => _nodeFocusNodes.putIfAbsent(
        id,
        () => FocusNode(debugLabel: 'FFlow node $id'),
      );

  FocusNode _edgeFocusNode(String id) => _edgeFocusNodes.putIfAbsent(
        id,
        () => FocusNode(debugLabel: 'FFlow edge $id'),
      );

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
    return widget.multiSelectionKeyCodes.any(keys.contains);
  }

  void _handleKey(FocusNode node, KeyEvent event) {
    final selectionKey = widget.selectionKeyCodes.contains(event.logicalKey);
    if (selectionKey && event is KeyDownEvent && !_selectionKeyPressed) {
      _selectionKeyPressed = true;
      setState(() {});
    } else if (selectionKey && event is KeyUpEvent && _selectionKeyPressed) {
      _selectionKeyPressed = false;
      setState(() {});
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
    setState(() {});
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
      if (mounted) setState(() {});
    } else if (isSelectionKey && event is KeyUpEvent && _selectionKeyPressed) {
      _selectionKeyPressed = false;
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
    setState(() {});
    _emitSelection();
    widget.onDelete?.call(deleting);
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse &&
        event.button == kSecondaryButton) {
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
      setState(() {});
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
    setState(() => _selectionBoxEnd = end);
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
      setState(() {
        _selectionBoxStart = null;
        _selectionBoxEnd = null;
        _selectionDragActive = false;
      });
      return;
    }
    final box = Rect.fromPoints(start, end);
    final nodesById = {for (final node in _nodes) node.id: node};
    final selection = <String>{};
    setState(() {
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
    setState(() {});
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
    setState(() {});
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

  void _startConnection(
      FlowNode<T> node, FlowHandle handle, DragStartDetails details) {
    _connectingNodeId = node.id;
    _connectingHandleId = handle.id;
    _connectingHandleType = handle.type;
    _connectionGestureStart = FlowConnectionStart(
      nodeId: node.id,
      handleId: handle.id,
      handleType: handle.type,
    );
    widget.onConnectStart?.call(_connectionGestureStart!);
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
    _autoPanForGesture(details.globalPosition);
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
                targetHandleId: targetHandle?.id ?? '',
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
                sourceHandleId: sourceHandle?.id ?? '',
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
      }
      setState(() {
        _reconnectingEdgeId = null;
        _connectingNodeId = null;
        _connectingHandleId = null;
        _connectingHandleType = null;
        _connectionStart = null;
        _connectionPoint = null;
        _connectionGestureStart = null;
      });
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
    }
    setState(() {
      _connectingNodeId = null;
      _connectingHandleId = null;
      _connectingHandleType = null;
      _connectionStart = null;
      _connectionPoint = null;
      _connectionGestureStart = null;
    });
  }

  void _cancelConnection() {
    final gesture = _connectionGestureStart;
    final point = _connectionPoint ?? _connectionStart ?? Offset.zero;
    if (gesture != null) {
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
    setState(() {
      _reconnectingEdgeId = null;
      _connectingNodeId = null;
      _connectingHandleId = null;
      _connectingHandleType = null;
      _connectionGestureStart = null;
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
    final nodeId = sourceSide ? edge.sourceId : edge.targetId;
    final handleId = sourceSide ? edge.sourceHandleId : edge.targetHandleId;
    _connectionGestureStart = FlowConnectionStart(
      nodeId: nodeId,
      handleId: handleId ?? '',
      handleType: sourceSide ? FlowHandleType.source : edge.targetHandleType,
      edgeId: edge.id,
      reconnecting: true,
    );
    widget.onReconnectStart?.call(_connectionGestureStart!);
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
          isOutput:
              sourceSide || edge.targetHandleType == FlowHandleType.source,
          enabled: true,
          onPanStart: (details) => _startReconnect(edge, sourceSide, details),
          onPanUpdate: _updateConnection,
          onPanEnd: _endConnection,
          onPanCancel: _cancelConnection,
        ),
      );

  void _handlePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (widget.panOnScroll && widget.panEnabled) {
      _panBy(Offset(
        -event.scrollDelta.dx * widget.panOnScrollSpeed,
        -event.scrollDelta.dy * widget.panOnScrollSpeed,
      ));
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

  void _autoPanForGesture(Offset globalPosition) {
    if (!widget.autoPan ||
        _viewportSize.isEmpty ||
        widget.autoPanMargin <= 0 ||
        widget.autoPanSpeed <= 0) {
      return;
    }
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
    if (dx != 0 || dy != 0) _panBy(Offset(dx, dy));
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
    final topLeft = _transformController.toScene(Offset.zero);
    final bottomRight = _transformController
        .toScene(Offset(_viewportSize.width, _viewportSize.height));
    final margin = 120 / _transformController.value.getMaxScaleOnAxis();
    return Rect.fromPoints(topLeft, bottomRight).inflate(margin);
  }

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
              if (mounted) setState(() {});
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

  @override
  Widget build(BuildContext context) {
    final nodesById = {for (final node in _nodes) node.id: node};
    final allVisibleNodes = _orderedVisibleNodes(nodesById);
    final orderedEdges = _orderedVisibleEdges();
    final viewport = _sceneViewportRect;
    final visibleNodes = widget.onlyRenderVisibleElements && viewport != null
        ? allVisibleNodes
            .where((node) =>
                FlowGeometry.nodeRect(node, nodesById).overlaps(viewport))
            .toList(growable: false)
        : allVisibleNodes;
    final edgeLayers = <Widget>[];
    final pendingDefaultEdges = <FlowEdge>[];
    void flushDefaultEdges() {
      if (pendingDefaultEdges.isEmpty) return;
      edgeLayers.add(Positioned.fill(
        child: CustomPaint(
          painter: FlowEdgesPainter<T>(
            nodes: _nodes,
            edges: List.unmodifiable(pendingDefaultEdges),
            selectedEdgeIds: _selectedEdges,
            defaultColor: widget.edgeColor,
            previewStart: null,
            previewTarget: null,
            previewColor: widget.connectionColor,
            animation: _animationController,
          ),
        ),
      ));
      pendingDefaultEdges.clear();
    }

    for (final edge in orderedEdges) {
      if (edge.hidden || !_edgeInViewport(edge, nodesById)) continue;
      final builder = widget.edgeTypes[edge.customType ?? edge.type.name];
      if (builder == null) {
        pendingDefaultEdges.add(edge);
        continue;
      }
      flushDefaultEdges();
      final source = FlowGeometry.edgeSource(edge, nodesById);
      final target = FlowGeometry.edgeTarget(edge, nodesById);
      if (source != null && target != null) {
        edgeLayers.add(Positioned.fill(
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
    flushDefaultEdges();
    return MouseRegion(
      onExit: _handleCanvasMouseExit,
      child: Semantics(
        container: true,
        label: widget.canvasLabel,
        child: FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Focus(
            focusNode: _focusNode,
            skipTraversal: true,
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
                if (_viewportSize != viewportSize) {
                  _viewportSize = viewportSize;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) _handleTransformChanged();
                  });
                }
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
                          !_selectionKeyPressed &&
                          !_isSelectionKeyDown &&
                          !_selectionDragActive,
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
                                      border: Border.all(
                                          color: widget.connectionColor),
                                    ),
                                  ),
                                ),
                              ),
                            ...edgeLayers,
                            if (widget.connectionLineBuilder == null &&
                                _connectionStart != null &&
                                _connectionPoint != null)
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: FlowEdgesPainter<T>(
                                    nodes: _nodes,
                                    edges: const [],
                                    selectedEdgeIds: _selectedEdges,
                                    defaultColor: widget.edgeColor,
                                    previewStart: _connectionStart,
                                    previewTarget: _connectionPoint,
                                    previewColor: widget.connectionColor,
                                    animation: _animationController,
                                  ),
                                ),
                              ),
                            if (widget.connectionLineBuilder != null &&
                                _connectionStart != null &&
                                _connectionPoint != null)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: widget.connectionLineBuilder!(
                                    context,
                                    _connectionStart!,
                                    _connectionPoint!,
                                  ),
                                ),
                              ),
                            for (final edge in orderedEdges)
                              if (!edge.hidden &&
                                  _edgeInViewport(edge, nodesById) &&
                                  edge.label != null &&
                                  widget.edgeLabelBuilder == null)
                                _buildEdgeLabel(edge, nodesById),
                            for (final edge in orderedEdges)
                              if (!edge.hidden &&
                                  _edgeInViewport(edge, nodesById) &&
                                  edge.label != null &&
                                  widget.edgeLabelBuilder != null)
                                _buildCustomEdgeLabel(edge, nodesById),
                            for (final edge in orderedEdges)
                              if (!edge.hidden &&
                                  _edgeInViewport(edge, nodesById) &&
                                  edge.reconnectable &&
                                  _selectedEdges.contains(edge.id)) ...[
                                if (edge.canReconnectSource)
                                  if (FlowGeometry.edgeSource(edge, nodesById)
                                      case final source?)
                                    _buildReconnectHandle(edge, true, source),
                                if (edge.canReconnectTarget)
                                  if (FlowGeometry.edgeTarget(edge, nodesById)
                                      case final target?)
                                    _buildReconnectHandle(edge, false, target),
                              ],
                            for (var index = 0;
                                index < orderedEdges.length;
                                index++)
                              if (!orderedEdges[index].hidden &&
                                  orderedEdges[index].focusable &&
                                  _edgeInViewport(
                                      orderedEdges[index], nodesById))
                                _buildEdgeSemantics(
                                  orderedEdges[index],
                                  nodesById,
                                  visibleNodes.length + index.toDouble(),
                                ),
                            for (var index = 0;
                                index < visibleNodes.length;
                                index++)
                              _buildNode(visibleNodes[index], nodesById, index),
                            if (widget.nodeToolbarBuilder != null)
                              for (final node in visibleNodes)
                                if (_selectedNodes.contains(node.id))
                                  _toolbarAt(
                                    FlowGeometry.nodeRect(node, nodesById),
                                    widget.nodeToolbarBuilder!(context, node),
                                  ),
                            if (widget.edgeToolbarBuilder != null)
                              for (final edge in orderedEdges)
                                if (_selectedEdges.contains(edge.id) &&
                                    _edgeInViewport(edge, nodesById))
                                  _toolbarAt(
                                    FlowGeometry.edgePathFor(edge, nodesById)
                                        .getBounds(),
                                    widget.edgeToolbarBuilder!(context, edge),
                                  ),
                            Positioned(
                              left: 0,
                              top: 0,
                              width: 1,
                              height: 1,
                              child: Semantics(
                                liveRegion: true,
                                label: _accessibilityAnnouncement,
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
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
          if (mounted) setState(() {});
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
    setState(() {});
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
      setState(() {});
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
    setState(() {
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

class _FlowMeasureSize extends SingleChildRenderObjectWidget {
  const _FlowMeasureSize({required this.onChange, required super.child});

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFlowMeasureSize(onChange);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderFlowMeasureSize renderObject,
  ) {
    renderObject.onChange = onChange;
  }
}

class _RenderFlowMeasureSize extends RenderProxyBox {
  _RenderFlowMeasureSize(this.onChange);

  ValueChanged<Size> onChange;
  Size? _lastSize;

  @override
  void performLayout() {
    super.performLayout();
    final measuredSize = child?.size ?? Size.zero;
    if (_lastSize == measuredSize) return;
    _lastSize = measuredSize;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) onChange(measuredSize);
    });
  }
}
