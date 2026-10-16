import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';

import '../controllers/flow_canvas_controller.dart';
import '../controllers/flow_clipboard.dart';
import '../controllers/flow_graph_controller.dart';
import '../controllers/flow_history_controller.dart';
import '../geometry/flow_edge_geometry_cache.dart';
import '../geometry/flow_geometry.dart';
import '../interactions/flow_graph_interaction.dart';
import '../interactions/flow_hit_test.dart';
import '../interactions/flow_interaction_session.dart';
import '../interactions/flow_pointer_capture.dart';
import '../models/flow_connection.dart';
import '../models/flow_edge.dart';
import '../models/flow_diagnostic.dart';
import '../models/flow_graph_index.dart';
import '../models/flow_graph_transaction.dart';
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
part 'flow_canvas_interaction.dart';

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
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) =>
          _FlowInteractionLocks.dragHandle.add(event.pointer),
      onPointerUp: (event) =>
          _FlowInteractionLocks.dragHandle.remove(event.pointer),
      onPointerCancel: (event) =>
          _FlowInteractionLocks.dragHandle.remove(event.pointer),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: scope.onPanStart,
        onPanUpdate: scope.onPanUpdate,
        onPanEnd: scope.onPanEnd,
        onPanCancel: scope.onPanCancel,
        child: child,
      ),
    );
  }
}

/// Prevents the containing node from starting a node drag from [child].
///
/// This is useful for controls that need their own horizontal drag gesture,
/// such as sliders, text selection handles, and embedded editors.
class FFlowNoDrag extends StatelessWidget {
  const FFlowNoDrag({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) =>
            _FlowInteractionLocks.noDrag.add(event.pointer),
        onPointerUp: (event) =>
            _FlowInteractionLocks.noDrag.remove(event.pointer),
        onPointerCancel: (event) =>
            _FlowInteractionLocks.noDrag.remove(event.pointer),
        child: child,
      );
}

/// Marks [child] as an area where pointer drags should not pan the canvas.
class FFlowNoPan extends StatelessWidget {
  const FFlowNoPan({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (event) =>
            _FlowInteractionLocks.noPan.add(event.pointer),
        onPointerUp: (event) =>
            _FlowInteractionLocks.noPan.remove(event.pointer),
        onPointerCancel: (event) =>
            _FlowInteractionLocks.noPan.remove(event.pointer),
        child: child,
      );
}

/// Marks [child] as an area where pointer wheel and trackpad scroll events
/// should not zoom or pan the canvas.
class FFlowNoWheel extends StatefulWidget {
  const FFlowNoWheel({super.key, required this.child});
  final Widget child;

  @override
  State<FFlowNoWheel> createState() => _FFlowNoWheelState();
}

class _FFlowNoWheelState extends State<FFlowNoWheel> {
  @override
  void initState() {
    super.initState();
    _FlowInteractionLocks.noWheelRegions.add(this);
  }

  @override
  void dispose() {
    _FlowInteractionLocks.noWheelRegions.remove(this);
    super.dispose();
  }

  bool containsGlobalPosition(Offset position) {
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox ||
        !renderObject.attached ||
        !renderObject.hasSize) {
      return false;
    }
    final rect = Rect.fromPoints(
      renderObject.localToGlobal(Offset.zero),
      renderObject.localToGlobal(renderObject.size.bottomRight(Offset.zero)),
    );
    return rect.contains(position);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

abstract final class _FlowInteractionLocks {
  static final Set<int> noDrag = {};
  static final Set<int> noPan = {};
  static final Set<int> dragHandle = {};
  static final Set<_FFlowNoWheelState> noWheelRegions = {};

  static bool blocksWheelAt(Offset position) =>
      noWheelRegions.any((region) => region.containsGlobalPosition(position));
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
    this.historyController,
    this.clipboard,
    this.createId,
    this.clipboardPasteOffset,
    this.transformationController,
    this.onNodesChanged,
    this.onEdgesChanged,
    this.onNodesChange,
    this.onEdgesChange,
    this.onConnect,
    this.onNodeSelected,
    this.onSelectionChanged,
    this.onViewportChanged,
    this.viewport,
    this.defaultViewport,
    this.onViewportChange,
    this.onMoveStart,
    this.onMove,
    this.onMoveEnd,
    this.fitViewOnInit = false,
    this.fitViewOptions = const FlowFitViewOptions(),
    this.isValidConnection,
    this.validateGraphOnChange = false,
    this.onDiagnostics,
    this.onError,
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
    this.onConnectionDrop,
    this.proximityConnect = false,
    this.proximityConnectThreshold = 32,
    this.onProximityConnect,
    this.dynamicReparenting = false,
    this.edgeControlPointsEditable = false,
    this.helperLinesEnabled = false,
    this.helperLineSnap = true,
    this.helperLineThreshold = 6,
    this.selectionOnDrag = false,
    this.selectionMode = FlowSelectionMode.partial,
    this.edgeSelectionMode = FlowSelectionMode.partial,
    this.selectAllIncludesHidden = false,
    this.connectionMode = FlowConnectionMode.strict,
    this.translateExtent,
    this.nodeExtent,
    this.elevateNodesOnSelect = true,
    this.elevateEdgesOnSelect = true,
    this.connectOnClick = true,
    this.onlyRenderVisibleElements = false,
    this.autoPan = true,
    this.autoPanOnNodeDrag = true,
    this.autoPanOnConnect = true,
    this.autoPanOnSelection = true,
    this.autoPanMargin = 48,
    this.autoPanSpeed = 12,
    this.nodeHitTestTolerance = 12,
    this.nodeDragThreshold = 1,
    this.connectionDragThreshold = 1,
    this.selectionDragThreshold = 3,
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
  })  : assert(nodeDragThreshold >= 0 &&
            connectionDragThreshold >= 0 &&
            selectionDragThreshold >= 0),
        assert((nodes == null) == (edges == null),
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
  final FlowHistoryController<T>? historyController;
  final FlowClipboard<T>? clipboard;
  final String Function()? createId;
  final Offset? clipboardPasteOffset;

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
  final FlowViewport? viewport;
  final FlowViewport? defaultViewport;
  final ValueChanged<FlowViewport>? onViewportChange;
  final ValueChanged<FlowViewport>? onMoveStart;
  final ValueChanged<FlowViewport>? onMove;
  final ValueChanged<FlowViewport>? onMoveEnd;
  final bool fitViewOnInit;
  final FlowFitViewOptions fitViewOptions;
  final bool Function(FlowConnection connection)? isValidConnection;
  final bool validateGraphOnChange;
  final ValueChanged<List<FlowDiagnostic>>? onDiagnostics;
  final ValueChanged<FlowDiagnostic>? onError;
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
  final ValueChanged<FlowConnectionDrop>? onConnectionDrop;
  final bool proximityConnect;
  final double proximityConnectThreshold;
  final ValueChanged<FlowConnection>? onProximityConnect;
  final bool dynamicReparenting;
  final bool edgeControlPointsEditable;
  final bool helperLinesEnabled;
  final bool helperLineSnap;
  final double helperLineThreshold;

  /// Allows blank-canvas dragging to create a selection box. Shift-drag works
  /// regardless of this setting.
  final bool selectionOnDrag;
  final FlowSelectionMode selectionMode;
  final FlowSelectionMode edgeSelectionMode;

  /// Include hidden nodes and edges in the select-all keyboard shortcut.
  final bool selectAllIncludesHidden;
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
  final bool autoPanOnNodeDrag;
  final bool autoPanOnConnect;
  final bool autoPanOnSelection;
  final double autoPanMargin;
  final double autoPanSpeed;

  /// Extra graph-space padding used consistently for node pointer and
  /// context-menu hit testing. Set to zero to match the rendered node bounds.
  final double nodeHitTestTolerance;
  final double nodeDragThreshold;
  final double connectionDragThreshold;
  final double selectionDragThreshold;

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
    with TickerProviderStateMixin {
  late final FlowCanvasController _ownedController;
  late TransformationController _transformController;
  late List<FlowNode<T>> _nodes;
  late List<FlowEdge> _edges;
  late List<FlowNode<T>> _lastPublishedNodes;
  late List<FlowEdge> _lastPublishedEdges;
  late FlowGraphIndex<T> _graphIndex;
  int _graphRevision = 0;
  int _geometryRevision = 0;
  final FlowEdgeGeometryCache _edgeGeometryCache = FlowEdgeGeometryCache();
  final FlowHitTestIndex _hitTestIndex = FlowHitTestIndex();
  bool _hitTestIndexDirty = true;
  Offset _sceneOrigin = Offset.zero;
  Size _sceneSize = Size.zero;
  bool _updatingSceneFrame = false;
  bool _applyingHistory = false;
  bool _didInitializeViewport = false;
  bool _viewportInteractionActive = false;
  AnimationController? _viewportAnimationController;
  Map<String, int> _nodePaintRanks = {};
  Map<String, int> _edgePaintRanks = {};
  final FlowHitTestEngine _flowHitTestEngine = const FlowHitTestEngine();
  final Map<int, FlowPointerCapture> _pointerCaptures = {};
  // Pointer moves can arrive before a drag recognizer claims the gesture.
  final Map<int, Offset> _lastPointerGlobalPositions = {};
  final Map<Object, Set<int>> _gesturePointerIds = {};
  final ValueNotifier<(Offset, Offset)?> _connectionPreview =
      ValueNotifier<(Offset, Offset)?>(null);
  FlowInteractionSession? _interactionSession;
  FlowAlignmentGuides? _alignmentGuides;
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
  Offset? _connectionStartGlobal;
  int? _connectionPointerId;
  bool _connectionThresholdMet = false;
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
  String? _pendingNodeDragId;
  Offset? _nodeDragStartGlobal;
  Offset? _lastDragFlowPosition;
  int? _pendingNodeDragPointerId;
  bool _selectionKeyPressed = false;
  Offset? _selectionBoxStart;
  Offset? _selectionBoxEnd;
  int? _selectionCandidatePointerId;
  Offset? _selectionCandidateGlobalPosition;
  Offset? _selectionCandidateFlowPosition;
  String? _resizingNodeId;
  Offset? _resizeStartGlobal;
  Offset? _resizeStartFlowPosition;
  Size? _resizeStartSize;
  Offset? _resizeStartPosition;
  int? _resizePointerId;
  _FlowResizeDirection _resizeDirection = _FlowResizeDirection.bottomRight;
  bool _pointerDownPane = false;
  Offset? _paneDownPosition;
  String? _hoveredEdgeId;
  bool _pointerOverPane = false;
  bool _pointerNoDrag = false;
  bool _pointerNoPan = false;
  double? _pinchStartZoom;
  Ticker? _autoPanTicker;
  Offset? _autoPanPointerGlobal;
  FlowAutoPanInteraction? _autoPanInteraction;
  Duration? _autoPanLastTick;
  Duration? _lastEdgeClickAt;
  Offset? _lastEdgeClickPosition;
  String? _lastEdgeClickId;
  Duration? _lastNodeClickAt;
  Offset? _lastNodeClickPosition;
  String? _lastNodeClickId;
  Duration? _lastBlankPointerDown;
  Offset? _lastBlankPointerPosition;

  @override
  void initState() {
    super.initState();
    _nodes = List.of(widget.nodes ?? widget.graphController?.nodes ?? const []);
    _edges = List.of(widget.edges ?? widget.graphController?.edges ?? const []);
    _lastPublishedNodes = List.of(_nodes);
    _lastPublishedEdges = List.of(_edges);
    _refreshGraphIndex();
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
    final initialViewport = widget.viewport ?? widget.defaultViewport;
    if (initialViewport != null) _applyViewport(initialViewport);
    _didInitializeViewport = widget.viewport != null ||
        widget.defaultViewport != null ||
        !widget.fitViewOnInit;
    _focusNode.addListener(_handleCanvasFocusChanged);
    _transformController.addListener(_handleTransformChanged);
    _reportGraphDiagnostics();
    widget.graphController?.addListener(_handleGraphControllerChanged);
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
    _syncEdgeAnimation();
  }

  @override
  void didUpdateWidget(covariant FFlowCanvas<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldNodes = _nodes;
    final oldEdges = _edges;
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
    if (widget.viewport != null && widget.viewport != oldWidget.viewport) {
      _applyViewport(widget.viewport!);
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
    if (!identical(oldWidget.graphController, widget.graphController) ||
        !identical(oldWidget.nodes, widget.nodes) ||
        !identical(oldWidget.edges, widget.edges)) {
      _recordExternalHistory(oldNodes, oldEdges, _nodes, _edges);
    }
    _refreshGraphIndex();
    _reportGraphDiagnostics();
  }

  TransformationController _controllerFor(FFlowCanvas<T> configuration) =>
      configuration.controller ??
      configuration.transformationController ??
      _ownedController;

  @override
  void dispose() {
    _stopAutoPan();
    _interactionSession = null;
    for (final pointerId in _pointerCaptures.keys) {
      _FlowInteractionLocks.noDrag.remove(pointerId);
      _FlowInteractionLocks.noPan.remove(pointerId);
      _FlowInteractionLocks.dragHandle.remove(pointerId);
    }
    _pointerCaptures.clear();
    _gesturePointerIds.clear();
    final history = widget.historyController;
    if (history?.isRecording ?? false) {
      history!.commitTransaction(_captureGraphState());
    }
    _transformController.removeListener(_handleTransformChanged);
    _focusNode.removeListener(_handleCanvasFocusChanged);
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
    _viewportAnimationController?.dispose();
    _autoPanTicker?.dispose();
    _connectionPreview.dispose();
    _ownedController.dispose();
    super.dispose();
  }

  void _handleGraphControllerChanged() {
    if (_publishingGraphController || !mounted) return;
    _cancelActiveInteraction();
    if (_connectionGestureStart != null) _cancelConnection();
    final graphController = widget.graphController;
    if (graphController == null) return;
    final oldNodes = _nodes;
    final oldEdges = _edges;
    _nodes = List.of(graphController.nodes);
    _edges = List.of(graphController.edges);
    _recordExternalHistory(oldNodes, oldEdges, _nodes, _edges);
    _lastPublishedNodes = List.of(_nodes);
    _lastPublishedEdges = List.of(_edges);
    _refreshGraphIndex();
    _reportGraphDiagnostics();
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
    final beforeNodes = _lastPublishedNodes;
    final beforeEdges = _lastPublishedEdges;
    _refreshGraphIndex();
    _reportGraphDiagnostics();
    _recordExternalHistory(beforeNodes, beforeEdges, _nodes, _edges);
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

  FlowGraphState<T> _captureGraphState() => FlowGraphState<T>(
        nodes: _nodes,
        edges: _edges,
        selection: _selection,
      );

  void _recordExternalHistory(
    List<FlowNode<T>> beforeNodes,
    List<FlowEdge> beforeEdges,
    List<FlowNode<T>> afterNodes,
    List<FlowEdge> afterEdges,
  ) {
    final history = widget.historyController;
    if (_applyingHistory || history == null || history.isRecording) return;
    if (_historyFingerprint(beforeNodes, beforeEdges) ==
        _historyFingerprint(afterNodes, afterEdges)) {
      return;
    }
    history.record(
      label: 'Edit graph',
      before: FlowGraphState<T>(nodes: beforeNodes, edges: beforeEdges),
      after: FlowGraphState<T>(nodes: afterNodes, edges: afterEdges),
    );
  }

  int _historyFingerprint(
    Iterable<FlowNode<T>> nodes,
    Iterable<FlowEdge> edges,
  ) =>
      Object.hashAll([
        for (final node in nodes)
          Object.hashAll([
            node.id,
            node.type,
            node.position,
            node.data,
            node.width,
            node.height,
            node.hasInput,
            node.hasOutput,
            Object.hashAll(node.handles),
            node.draggable,
            node.resizable,
            node.selectable,
            node.deletable,
            node.connectable,
            node.hidden,
            node.parentId,
            node.origin,
            node.extent,
            node.extentToParent,
            node.expandParent,
            node.minWidth,
            node.minHeight,
            node.maxWidth,
            node.maxHeight,
            node.zIndex,
            node.groupable,
          ]),
        for (final edge in edges)
          Object.hashAll([
            edge.id,
            edge.sourceId,
            edge.targetId,
            edge.sourceHandleId,
            edge.targetHandleId,
            edge.targetHandleType,
            edge.type,
            edge.customType,
            edge.label,
            edge.color,
            edge.strokeWidth,
            edge.markerStart,
            edge.markerEnd,
            edge.selectable,
            edge.deletable,
            edge.reconnectable,
            edge.hidden,
            edge.animated,
            edge.interactionWidth,
            edge.data,
            edge.curvature,
            edge.stepPosition,
            edge.cornerRadius,
            edge.controlPoints,
          ]),
      ]);

  void _applyHistoryState(FlowGraphState<T> state) {
    _cancelActiveInteraction();
    if (_connectionGestureStart != null) _cancelConnection();
    _applyingHistory = true;
    _nodes = state.nodes;
    _edges = state.edges;
    _selectedNodes
      ..clear()
      ..addAll(state.selection.nodes);
    _selectedEdges
      ..clear()
      ..addAll(state.selection.edges);
    _refreshGraphIndex();
    _syncFocusNodes();
    _syncEdgeAnimation();
    _publishGraph(nodesChanged: true, edgesChanged: true);
    _applyingHistory = false;
    _rebuild(() {});
    widget.onSelectionChanged?.call(_selection);
  }

  void _publishNodes() => _publishGraph(nodesChanged: true);

  void _publishEdges() => _publishGraph(edgesChanged: true);

  void _rebuild(VoidCallback update) {
    if (mounted) setState(update);
  }

  void _handleTransformChanged() {
    if (_updatingSceneFrame) return;
    final matrix = _transformController.value;
    final scale = matrix.getMaxScaleOnAxis();
    final effectiveX = matrix.entry(0, 3) - scale * _sceneOrigin.dx;
    final effectiveY = matrix.entry(1, 3) - scale * _sceneOrigin.dy;
    final extent = widget.translateExtent;
    if (!_clampingViewport && extent != null && !_viewportSize.isEmpty) {
      final scale = matrix.getMaxScaleOnAxis();
      final minX = _viewportSize.width - extent.right * scale;
      final maxX = -extent.left * scale;
      final minY = _viewportSize.height - extent.bottom * scale;
      final maxY = -extent.top * scale;
      final x = minX <= maxX
          ? effectiveX.clamp(minX, maxX).toDouble()
          : (minX + maxX) / 2;
      final y = minY <= maxY
          ? effectiveY.clamp(minY, maxY).toDouble()
          : (minY + maxY) / 2;
      if (x != effectiveX || y != effectiveY) {
        _clampingViewport = true;
        _transformController.value = Matrix4.copy(matrix)
          ..setEntry(0, 3, x + scale * _sceneOrigin.dx)
          ..setEntry(1, 3, y + scale * _sceneOrigin.dy);
        _clampingViewport = false;
        _emitViewport(FlowViewport(
          x: x,
          y: y,
          zoom: scale,
        ));
        if (widget.onlyRenderVisibleElements && mounted) setState(() {});
        return;
      }
    }
    _emitViewport(FlowViewport(
      x: effectiveX,
      y: effectiveY,
      zoom: scale,
    ));
    if (widget.onlyRenderVisibleElements && mounted) setState(() {});
  }

  void _emitViewport(FlowViewport viewport) {
    widget.onViewportChanged?.call(viewport);
    widget.onViewportChange?.call(viewport);
    widget.onMove?.call(viewport);
  }

  FlowViewport _currentViewport() {
    final matrix = _transformController.value;
    final scale = matrix.getMaxScaleOnAxis();
    return FlowViewport(
      x: matrix.entry(0, 3) - scale * _sceneOrigin.dx,
      y: matrix.entry(1, 3) - scale * _sceneOrigin.dy,
      zoom: scale,
    );
  }

  void _applyViewport(FlowViewport viewport) {
    if (_transformController is FlowCanvasController) {
      (_transformController as FlowCanvasController).setViewport(viewport);
    } else {
      _transformController.value = Matrix4.identity()
        ..translateByDouble(
          viewport.x + viewport.zoom * _sceneOrigin.dx,
          viewport.y + viewport.zoom * _sceneOrigin.dy,
          0,
          1,
        )
        ..scaleByDouble(viewport.zoom, viewport.zoom, 1, 1);
    }
  }

  void _fitViewInitially() {
    _didInitializeViewport = true;
    final options = widget.fitViewOptions;
    final bounds = FlowGeometry.nodesBounds(_nodes);
    final viewport = FlowGraphUtils.getViewportForBounds(
      bounds,
      _viewportSize,
      padding: options.padding,
      minZoom: options.minZoom,
      maxZoom: options.maxZoom,
    );
    if (options.duration == Duration.zero) {
      _applyViewport(viewport);
      return;
    }
    if (_transformController is FlowCanvasController) {
      (_transformController as FlowCanvasController).animateToViewport(
        viewport,
        vsync: this,
        duration: options.duration,
        curve: options.curve,
      );
      return;
    }
    _animateViewport(viewport, options);
  }

  Future<bool> _animateViewport(
      FlowViewport target, FlowFitViewOptions options) async {
    _viewportAnimationController?.dispose();
    final start = _currentViewport();
    final controller = AnimationController(
      vsync: this,
      duration: options.duration,
    );
    _viewportAnimationController = controller;
    final animation = CurvedAnimation(parent: controller, curve: options.curve);
    void update() {
      _applyViewport(FlowViewport(
        x: start.x + (target.x - start.x) * animation.value,
        y: start.y + (target.y - start.y) * animation.value,
        zoom: start.zoom + (target.zoom - start.zoom) * animation.value,
      ));
    }

    animation.addListener(update);
    try {
      await controller.forward().orCancel;
    } on TickerCanceled {
      return false;
    } finally {
      animation
        ..removeListener(update)
        ..dispose();
      if (identical(_viewportAnimationController, controller)) {
        _viewportAnimationController = null;
      }
      controller.dispose();
    }
    return true;
  }

  Offset get _sceneOffset => Offset(-_sceneOrigin.dx, -_sceneOrigin.dy);

  Offset _screenToFlow(Offset viewportPosition) =>
      _transformController.toScene(viewportPosition) + _sceneOrigin;

  void _refreshGraphIndex() {
    _graphRevision++;
    var geometry = 0;
    var hitTestProperties = 0;
    for (final node in _nodes) {
      geometry = Object.hash(
        geometry,
        Object.hash(
          node.id,
          node.position,
          node.width,
          node.height,
          node.origin,
          node.parentId,
          Object.hashAll(node.resolvedHandles.map((handle) => Object.hash(
                handle.id,
                handle.type,
                handle.position,
                handle.offset,
              ))),
        ),
      );
      hitTestProperties = Object.hash(
        hitTestProperties,
        node.id,
        node.hidden,
      );
    }
    for (final edge in _edges) {
      geometry = Object.hash(
        geometry,
        Object.hash(
          edge.id,
          edge.sourceId,
          edge.targetId,
          edge.sourceHandleId,
          edge.targetHandleId,
          edge.targetHandleType,
          edge.type,
          edge.floating,
          edge.curvature,
          edge.stepPosition,
          edge.cornerRadius,
          Object.hashAll(edge.controlPoints),
        ),
      );
      hitTestProperties = Object.hash(
        hitTestProperties,
        edge.id,
        edge.hidden,
        edge.interactionWidth,
      );
    }
    if (geometry != _geometryRevisionSignature) {
      _geometryRevision++;
      _geometryRevisionSignature = geometry;
    }
    final hitTestRevision = Object.hash(
      geometry,
      widget.nodeHitTestTolerance,
      widget.minZoom,
      hitTestProperties,
    );
    if (hitTestRevision != _hitTestRevisionSignature) {
      _hitTestIndexDirty = true;
      _hitTestRevisionSignature = hitTestRevision;
    }
    _graphIndex = FlowGraphIndex<T>(
      nodes: _nodes,
      edges: _edges,
      graphRevision: _graphRevision,
      geometryRevision: _geometryRevision,
    );
    _edgeGeometryCache.retainEdges(_edges);
    _cancelInteractionIfTargetWasRemoved();
  }

  void _reportGraphDiagnostics() {
    if (!widget.validateGraphOnChange &&
        widget.onDiagnostics == null &&
        widget.onError == null) {
      return;
    }
    final diagnostics = FlowGraphValidator.validate<T>(
      nodes: _nodes,
      edges: _edges,
      viewport: _currentViewport(),
      minZoom: widget.minZoom,
      maxZoom: widget.maxZoom,
      translateExtent: widget.translateExtent,
      connectionMode: widget.connectionMode,
    );
    widget.onDiagnostics?.call(diagnostics);
    for (final diagnostic in diagnostics) {
      if (diagnostic.severity == FlowDiagnosticSeverity.error) {
        widget.onError?.call(diagnostic);
      }
    }
  }

  int? _geometryRevisionSignature;
  int? _hitTestRevisionSignature;

  void _updateSceneFrame(Size viewportSize) {
    var bounds = Rect.fromLTWH(
      0,
      0,
      math.max(1, viewportSize.width),
      math.max(1, viewportSize.height),
    );
    for (final node in _nodes) {
      if (!FlowGeometry.isVisible(node, _graphIndex.nodesById)) continue;
      bounds = bounds
          .expandToInclude(FlowGeometry.nodeRect(node, _graphIndex.nodesById));
    }
    bounds = bounds.inflate(256);
    final nextOrigin = bounds.topLeft;
    _sceneSize = Size(math.max(1, bounds.width), math.max(1, bounds.height));
    if (nextOrigin == _sceneOrigin) return;
    final delta = nextOrigin - _sceneOrigin;
    final matrix = _transformController.value;
    final scale = matrix.getMaxScaleOnAxis();
    _updatingSceneFrame = true;
    matrix
      ..setEntry(0, 3, matrix.entry(0, 3) + scale * delta.dx)
      ..setEntry(1, 3, matrix.entry(1, 3) + scale * delta.dy);
    _sceneOrigin = nextOrigin;
    if (_transformController is FlowCanvasController) {
      (_transformController as FlowCanvasController)
          .updateSceneOrigin(nextOrigin);
    }
    _updatingSceneFrame = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _transformController.value = Matrix4.copy(_transformController.value);
      // _updateSceneFrame runs inside the viewport LayoutBuilder, after the
      // edge painters have already been created for this build. Rebuild once
      // after the new scene origin is committed so painters use the same
      // offset as the nodes on the first rendered frame.
      _rebuild(() {});
    });
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
    final nodesById = _graphIndex.nodesById;
    if (_hitTestIndexDirty) {
      _hitTestIndex.rebuild(
        nodes: _nodes.where((node) => FlowGeometry.isVisible(node, nodesById)),
        edges: _edges.where((edge) => !edge.hidden),
        nodesById: nodesById,
        geometryCache: _edgeGeometryCache,
        nodeHitTestTolerance: widget.nodeHitTestTolerance,
        edgeHitTestScale: 1 / widget.minZoom,
      );
      _hitTestIndexDirty = false;
    }
    final allVisibleNodes = _orderedVisibleNodes(nodesById);
    final orderedEdges = _orderedVisibleEdges();
    final verticalGuide =
        widget.helperLinesEnabled ? _alignmentGuides?.vertical : null;
    final horizontalGuide =
        widget.helperLinesEnabled ? _alignmentGuides?.horizontal : null;
    final viewport = _sceneViewportRect;
    final visibleNodes = widget.onlyRenderVisibleElements && viewport != null
        ? allVisibleNodes
            .where((node) =>
                FlowGeometry.nodeRect(node, nodesById).overlaps(viewport))
            .toList(growable: false)
        : allVisibleNodes;
    _nodePaintRanks = {
      for (var index = 0; index < visibleNodes.length; index++)
        visibleNodes[index].id: index,
    };
    _edgePaintRanks = {
      for (var index = 0; index < orderedEdges.length; index++)
        orderedEdges[index].id: index,
    };
    final edgeLayers = <Widget>[];
    final pendingStaticEdges = <FlowEdge>[];
    final pendingAnimatedEdges = <FlowEdge>[];
    void flushDefaultEdges(List<FlowEdge> pending, {required bool animated}) {
      if (pending.isEmpty) return;
      edgeLayers.add(Positioned.fill(
        child: CustomPaint(
          painter: FlowEdgesPainter<T>(
            nodes: _nodes,
            edges: List.unmodifiable(pending),
            selectedEdgeIds: _selectedEdges,
            defaultColor: widget.edgeColor,
            previewStart: null,
            previewTarget: null,
            previewColor: widget.connectionColor,
            animation: _animationController,
            geometryCache: _edgeGeometryCache,
            sceneOffset: _sceneOffset,
            repaintOnAnimation: animated,
          ),
        ),
      ));
      pending.clear();
    }

    for (final edge in orderedEdges) {
      if (edge.hidden || !_edgeInViewport(edge, nodesById)) continue;
      final builder = widget.edgeTypes[edge.customType ?? edge.type.name];
      if (builder == null) {
        (edge.animated ? pendingAnimatedEdges : pendingStaticEdges).add(edge);
        continue;
      }
      flushDefaultEdges(pendingStaticEdges, animated: false);
      flushDefaultEdges(pendingAnimatedEdges, animated: true);
      final source = FlowGeometry.edgeSource(edge, nodesById);
      final target = FlowGeometry.edgeTarget(edge, nodesById);
      if (source != null && target != null) {
        edgeLayers.add(Positioned.fill(
          child: builder(
            context,
            edge,
            source + _sceneOffset,
            target + _sceneOffset,
            _selectedEdges.contains(edge.id),
          ),
        ));
      }
    }
    flushDefaultEdges(pendingStaticEdges, animated: false);
    flushDefaultEdges(pendingAnimatedEdges, animated: true);
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
            onKeyEvent: _handleKey,
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
                _updateSceneFrame(viewportSize);
                if (_viewportSize != viewportSize) {
                  _viewportSize = viewportSize;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    if (!_didInitializeViewport && widget.fitViewOnInit) {
                      _fitViewInitially();
                    }
                    _handleTransformChanged();
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
                      onInteractionStart: (_) {
                        _beginCanvasPanInteraction();
                        _pinchStartZoom =
                            _transformController.value.getMaxScaleOnAxis();
                        _viewportInteractionActive = true;
                        widget.onMoveStart?.call(_currentViewport());
                      },
                      onInteractionEnd: (_) {
                        _endCanvasPanInteraction();
                        if (!_viewportInteractionActive) return;
                        _viewportInteractionActive = false;
                        widget.onMoveEnd?.call(_currentViewport());
                      },
                      minScale: widget.minZoom,
                      maxScale: widget.maxZoom,
                      panEnabled: widget.panEnabled &&
                          !widget.selectionOnDrag &&
                          !_pointerNoPan &&
                          !_selectionKeyPressed &&
                          !_isSelectionKeyDown &&
                          !_selectionDragActive,
                      // Route scale changes through the canvas so wheel scopes
                      // can suppress them per global pointer position.
                      scaleEnabled: false,
                      trackpadScrollCausesScale: true,
                      onInteractionUpdate: _handleInteractionUpdate,
                      constrained: false,
                      boundaryMargin: const EdgeInsets.all(double.infinity),
                      child: SizedBox(
                        width: _sceneSize.width,
                        height: _sceneSize.height,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned.fill(
                              child: CustomPaint(
                                painter: FlowGridPainter(
                                  color: widget.gridColor,
                                  spacing: widget.gridSpacing,
                                  variant: widget.backgroundVariant,
                                  sceneOrigin: _sceneOrigin,
                                ),
                              ),
                            ),
                            if (_selectionBoxStart != null &&
                                _selectionBoxEnd != null)
                              Positioned.fromRect(
                                rect: Rect.fromPoints(
                                  _selectionBoxStart! + _sceneOffset,
                                  _selectionBoxEnd! + _sceneOffset,
                                ),
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
                            if (verticalGuide != null)
                              Positioned(
                                left: verticalGuide + _sceneOffset.dx - 0.5,
                                top: 0,
                                bottom: 0,
                                width: 1,
                                child: IgnorePointer(
                                  child: ColoredBox(
                                    color: widget.connectionColor
                                        .withValues(alpha: 0.9),
                                  ),
                                ),
                              ),
                            if (horizontalGuide != null)
                              Positioned(
                                left: 0,
                                right: 0,
                                top: horizontalGuide + _sceneOffset.dy - 0.5,
                                height: 1,
                                child: IgnorePointer(
                                  child: ColoredBox(
                                    color: widget.connectionColor
                                        .withValues(alpha: 0.9),
                                  ),
                                ),
                              ),
                            ...edgeLayers,
                            Positioned.fill(
                              child: ValueListenableBuilder<(Offset, Offset)?>(
                                valueListenable: _connectionPreview,
                                builder: (context, preview, child) {
                                  if (preview == null) {
                                    return const SizedBox.shrink();
                                  }
                                  final lineBuilder =
                                      widget.connectionLineBuilder;
                                  if (lineBuilder != null) {
                                    return IgnorePointer(
                                      child: lineBuilder(
                                        context,
                                        preview.$1,
                                        preview.$2,
                                      ),
                                    );
                                  }
                                  return CustomPaint(
                                    painter: FlowEdgesPainter<T>(
                                      nodes: _nodes,
                                      edges: const [],
                                      selectedEdgeIds: _selectedEdges,
                                      defaultColor: widget.edgeColor,
                                      previewStart: preview.$1,
                                      previewTarget: preview.$2,
                                      previewColor: widget.connectionColor,
                                      animation: _animationController,
                                      geometryCache: _edgeGeometryCache,
                                      sceneOffset: _sceneOffset,
                                    ),
                                  );
                                },
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
                            if (widget.edgeControlPointsEditable)
                              for (final edge in orderedEdges)
                                if (_selectedEdges.contains(edge.id) &&
                                    _edgeInViewport(edge, nodesById))
                                  for (var pointIndex = 0;
                                      pointIndex < edge.controlPoints.length;
                                      pointIndex++)
                                    _buildEdgeControlPoint(
                                      edge,
                                      pointIndex,
                                      edge.controlPoints[pointIndex],
                                    ),
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
                                    _edgeGeometryCache
                                            .result(edge, nodesById)
                                            ?.bounds ??
                                        Rect.zero,
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
