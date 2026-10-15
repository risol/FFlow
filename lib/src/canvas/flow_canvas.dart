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
import '../utils/flow_graph_utils.dart';

part 'flow_canvas_selection.dart';
part 'flow_canvas_pointer.dart';
part 'flow_canvas_connections.dart';
part 'flow_canvas_viewport.dart';
part 'flow_canvas_nodes.dart';
part 'flow_canvas_edges.dart';
part 'flow_canvas_changes.dart';

final Set<LogicalKeyboardKey> _defaultDeleteKeyCodes = Set.unmodifiable([
  LogicalKeyboardKey.delete,
  LogicalKeyboardKey.backspace,
]);
final Set<LogicalKeyboardKey> _defaultSelectionKeyCodes = Set.unmodifiable([
  LogicalKeyboardKey.shiftLeft,
  LogicalKeyboardKey.shiftRight,
]);
final Set<LogicalKeyboardKey> _defaultMultiSelectionKeyCodes =
    Set.unmodifiable([
  LogicalKeyboardKey.controlLeft,
  LogicalKeyboardKey.controlRight,
  LogicalKeyboardKey.metaLeft,
  LogicalKeyboardKey.metaRight,
]);

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
    this.onNodesChange,
    this.onEdgesChange,
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
    Set<LogicalKeyboardKey>? deleteKeyCodes,
    Set<LogicalKeyboardKey>? selectionKeyCodes,
    Set<LogicalKeyboardKey>? multiSelectionKeyCodes,
  })  : assert((nodes == null) == (edges == null),
            'Pass both nodes and edges, or omit both when using graphController.'),
        assert(graphController != null || nodes != null,
            'Pass nodes and edges or provide graphController.'),
        assert(graphController == null || nodes == null,
            'Do not combine graphController with controlled nodes/edges.'),
        assert(controller == null || transformationController == null,
            'Use either controller or transformationController, not both.'),
        _deleteKeyCodes = deleteKeyCodes,
        _selectionKeyCodes = selectionKeyCodes,
        _multiSelectionKeyCodes = multiSelectionKeyCodes;

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

  /// Receives batched node additions, removals, replacements, position,
  /// dimension, and selection changes before [onNodesChanged] is called.
  final ValueChanged<List<FlowNodeChange<T>>>? onNodesChange;

  /// Receives batched edge additions, removals, replacements, and selection
  /// changes before [onEdgesChanged] is called.
  final ValueChanged<List<FlowEdgeChange>>? onEdgesChange;
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
  final Set<LogicalKeyboardKey>? _deleteKeyCodes;
  final Set<LogicalKeyboardKey>? _selectionKeyCodes;
  final Set<LogicalKeyboardKey>? _multiSelectionKeyCodes;
  Set<LogicalKeyboardKey> get deleteKeyCodes =>
      _deleteKeyCodes ?? _defaultDeleteKeyCodes;
  Set<LogicalKeyboardKey> get selectionKeyCodes =>
      _selectionKeyCodes ?? _defaultSelectionKeyCodes;
  Set<LogicalKeyboardKey> get multiSelectionKeyCodes =>
      _multiSelectionKeyCodes ?? _defaultMultiSelectionKeyCodes;

  @override
  State<FFlowCanvas<T>> createState() => _FFlowCanvasState<T>();
}

class _FFlowCanvasState<T> extends State<FFlowCanvas<T>>
    with SingleTickerProviderStateMixin {
  late final FlowCanvasController _ownedController;
  late TransformationController _transformController;
  late List<FlowNode<T>> _nodes;
  late List<FlowEdge> _edges;
  late List<FlowNode<T>> _lastPublishedNodes;
  late List<FlowEdge> _lastPublishedEdges;
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
    _lastPublishedNodes = List.of(_nodes);
    _lastPublishedEdges = List.of(_edges);
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
    _lastPublishedNodes = List.of(_nodes);
    _lastPublishedEdges = List.of(_edges);
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
    _lastPublishedNodes = List.of(_nodes);
    _lastPublishedEdges = List.of(_edges);
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
    final nodeChanges =
        nodesChanged ? _diffNodes(_lastPublishedNodes, _nodes) : null;
    final edgeChanges =
        edgesChanged ? _diffEdges(_lastPublishedEdges, _edges) : null;
    if (nodesChanged) _lastPublishedNodes = List.of(_nodes);
    if (edgesChanged) _lastPublishedEdges = List.of(_edges);
    final graphController = widget.graphController;
    if (graphController != null) {
      _publishingGraphController = true;
      graphController.setGraph(nodes: _nodes, edges: _edges);
      _publishingGraphController = false;
    }
    if (nodesChanged) {
      if (nodeChanges != null && nodeChanges.isNotEmpty) {
        widget.onNodesChange?.call(List.unmodifiable(nodeChanges));
      }
      widget.onNodesChanged?.call(_nodes);
    }
    if (edgesChanged) {
      if (edgeChanges != null && edgeChanges.isNotEmpty) {
        widget.onEdgesChange?.call(List.unmodifiable(edgeChanges));
      }
      widget.onEdgesChanged?.call(_edges);
    }
  }

  void _publishNodes() => _publishGraph(nodesChanged: true);

  void _publishEdges() => _publishGraph(edgesChanged: true);

  void _rebuild(VoidCallback update) {
    if (mounted) setState(update);
  }

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
