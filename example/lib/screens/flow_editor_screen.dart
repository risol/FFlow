import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fflow/fflow.dart';

import '../models/demo_node_data.dart';
import '../widgets/demo_node_card.dart';
import '../widgets/demo_node_palette.dart';
import '../widgets/demo_properties_panel.dart';

class FlowEditorScreen extends StatefulWidget {
  const FlowEditorScreen({super.key});

  @override
  State<FlowEditorScreen> createState() => _FlowEditorScreenState();
}

class _FlowEditorScreenState extends State<FlowEditorScreen> {
  static const _initialWorkflowName = 'Research workflow';

  final FlowCanvasController _canvasController = FlowCanvasController();
  final FlowGraphController<DemoNodeData> _graph = FlowGraphController(
    nodes: _initialNodes(),
    edges: _initialEdges(),
  );
  final FlowHistoryController<DemoNodeData> _history =
      FlowHistoryController<DemoNodeData>();
  final FlowClipboard<DemoNodeData> _clipboard = FlowClipboard();
  final GlobalKey _canvasViewportKey = GlobalKey();
  final Set<String> _completedNodeIds = {};

  String _workflowName = _initialWorkflowName;
  String? _runningNodeId;
  String? _exportedFingerprint;
  FlowSelection _selection = FlowSelection();
  FlowBackgroundVariant? _backgroundVariant = FlowBackgroundVariant.dots;
  bool _hasUnexportedChanges = false;
  bool _canvasLocked = false;
  bool _isRunning = false;
  int _nodeIdCounter = 1;
  int _edgeIdCounter = 4;
  int _clipboardIdCounter = 1;
  int _runRevision = 0;

  static List<FlowNode<DemoNodeData>> _initialNodes() => const [
        FlowNode(
          id: 'trigger',
          position: Offset(124, 284),
          type: 'trigger',
          data: DemoNodeData(
            title: 'New research request',
            description: 'Runs when a request arrives',
            kind: DemoNodeKind.trigger,
          ),
          width: 244,
          height: 126,
          hasInput: false,
        ),
        FlowNode(
          id: 'summarize',
          position: Offset(454, 164),
          type: 'ai',
          data: DemoNodeData(
            title: 'Summarize sources',
            description: 'Create a concise research brief',
            kind: DemoNodeKind.ai,
          ),
          width: 244,
          height: 126,
        ),
        FlowNode(
          id: 'review',
          position: Offset(784, 284),
          type: 'review',
          data: DemoNodeData(
            title: 'Editorial review',
            description: 'Approve the brief before sharing',
            kind: DemoNodeKind.review,
          ),
          width: 244,
          height: 126,
        ),
        FlowNode(
          id: 'publish',
          position: Offset(1114, 164),
          type: 'output',
          data: DemoNodeData(
            title: 'Publish report',
            description: 'Send the approved report to Slack',
            kind: DemoNodeKind.output,
          ),
          width: 244,
          height: 126,
          hasOutput: false,
        ),
      ];

  static List<FlowEdge> _initialEdges() => const [
        FlowEdge(id: 'edge-1', sourceId: 'trigger', targetId: 'summarize'),
        FlowEdge(id: 'edge-2', sourceId: 'summarize', targetId: 'review'),
        FlowEdge(id: 'edge-3', sourceId: 'review', targetId: 'publish'),
      ];

  FlowNode<DemoNodeData>? get _selectedNode {
    final id = _selection.nodes.firstOrNull;
    return id == null ? null : _graph.getNode(id);
  }

  FlowEdge? get _selectedEdge {
    final id = _selection.edges.firstOrNull;
    return id == null ? null : _graph.getEdge(id);
  }

  @override
  void initState() {
    super.initState();
    _graph.addListener(_handleGraphChanged);
    _history.addListener(_handleHistoryChanged);
    _canvasController.addListener(_handleViewportChanged);
    _exportedFingerprint = _documentFingerprint();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fitToView();
      _exportedFingerprint = _documentFingerprint();
      setState(() => _hasUnexportedChanges = false);
    });
  }

  @override
  void dispose() {
    _graph.removeListener(_handleGraphChanged);
    _history.removeListener(_handleHistoryChanged);
    _canvasController.removeListener(_handleViewportChanged);
    _graph.dispose();
    _history.dispose();
    _canvasController.dispose();
    super.dispose();
  }

  void _handleGraphChanged() {
    if (!mounted) return;
    _refreshDirtyState();
    setState(() {});
  }

  void _handleHistoryChanged() {
    if (mounted) setState(() {});
  }

  void _handleViewportChanged() => _refreshDirtyState();

  void _refreshDirtyState() {
    if (!mounted) return;
    final changed = _documentFingerprint() != _exportedFingerprint;
    if (changed != _hasUnexportedChanges) {
      setState(() => _hasUnexportedChanges = changed);
    }
  }

  String _documentFingerprint() => jsonEncode(_snapshotMap());

  Map<String, Object?> _snapshotMap() {
    final snapshot = FlowGraphSnapshot<DemoNodeData>(
      nodes: _graph.nodes,
      edges: _graph.edges,
      viewport: _canvasController.viewport,
    ).toJson(encodeNodeData: (data) => data.toJson());
    snapshot['workflowName'] = _workflowName;
    return snapshot;
  }

  String _snapshotJson() =>
      const JsonEncoder.withIndent('  ').convert(_snapshotMap());

  Size? get _viewportSize {
    final renderObject = _canvasViewportKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox) return renderObject.size;
    return null;
  }

  void _fitToView() {
    final viewport = _viewportSize;
    if (viewport == null || viewport.isEmpty || _graph.nodes.isEmpty) return;
    _canvasController.fitView(_graph.nodes, viewport, padding: 130);
  }

  String _newNodeId() {
    while (true) {
      final id = 'node-${_nodeIdCounter++}';
      if (_graph.getNode(id) == null) return id;
    }
  }

  String _newEdgeId() {
    while (true) {
      final id = 'edge-${_edgeIdCounter++}';
      if (_graph.getEdge(id) == null) return id;
    }
  }

  String _newClipboardId() => 'paste-${_clipboardIdCounter++}';

  void _addNode(DemoNodeKind kind) {
    final viewport = _viewportSize;
    final center = viewport == null
        ? const Offset(650, 420)
        : _canvasController.screenToFlowPosition(
            Offset(viewport.width / 2, viewport.height / 2),
          );
    final id = _newNodeId();
    final node = FlowNode<DemoNodeData>(
      id: id,
      position: Offset(center.dx - 122, center.dy - 63),
      type: kind.name,
      data: DemoNodeData(
        title: kind.defaultTitle,
        description: kind.defaultDescription,
        kind: kind,
      ),
      width: 244,
      height: 126,
      hasInput: kind != DemoNodeKind.trigger,
      hasOutput: kind != DemoNodeKind.output,
      selected: true,
    );
    _graph.setGraph(
      nodes: [
        for (final existing in _graph.nodes) existing.copyWith(selected: false),
        node,
      ],
      edges: [
        for (final edge in _graph.edges) edge.copyWith(selected: false),
      ],
    );
    _selection = FlowSelection(nodes: [id]);
  }

  void _duplicateNode(FlowNode<DemoNodeData> node) {
    final copy = node.copyWith(
      id: _newNodeId(),
      position: node.position + const Offset(34, 34),
      selected: true,
    );
    _graph.setGraph(
      nodes: [
        for (final existing in _graph.nodes) existing.copyWith(selected: false),
        copy,
      ],
      edges: [
        for (final edge in _graph.edges) edge.copyWith(selected: false),
      ],
    );
    _selection = FlowSelection(nodes: [copy.id]);
  }

  void _deleteNode(String id) {
    _graph.deleteElements(nodeIds: [id]);
    _selection = FlowSelection();
  }

  void _deleteSelected() {
    if (_selection.isEmpty) return;
    _graph.deleteElements(
      nodeIds: _selection.nodes,
      edgeIds: _selection.edges,
    );
    _selection = FlowSelection();
  }

  void _clearSelection() {
    _selection = FlowSelection();
    _graph.setSelection();
  }

  void _applyNodeProperties(
    FlowNode<DemoNodeData> node,
    String title,
    String description,
  ) {
    _graph.updateNode(
      node.id,
      (current) => current.copyWith(
        data: current.data.copyWith(title: title, description: description),
      ),
    );
    _showMessage('Node updated');
  }

  void _applyEdgeProperties(
    FlowEdge edge,
    String? label,
    FlowEdgeType type,
  ) {
    _graph.updateEdge(
      edge.id,
      (current) => current.copyWith(label: label, type: type),
    );
    _showMessage('Connection updated');
  }

  void _applyHistoryState(FlowGraphState<DemoNodeData> state) {
    // The graph controller notifies FFlow synchronously. A pending history
    // transaction prevents that external update from being recorded as a new
    // edit, preserving the redo stack.
    _history.beginTransaction(
      'Apply history state',
      FlowGraphState(nodes: _graph.nodes, edges: _graph.edges),
    );
    _graph.setGraph(nodes: state.nodes, edges: state.edges);
    _history.cancelTransaction();
    _selection = state.selection;
  }

  void _undo() {
    final state = _history.undo();
    if (state != null) _applyHistoryState(state);
  }

  void _redo() {
    final state = _history.redo();
    if (state != null) _applyHistoryState(state);
  }

  Future<void> _runWorkflow() async {
    if (_isRunning) {
      _runRevision++;
      setState(() {
        _isRunning = false;
        _runningNodeId = null;
      });
      _showMessage('Run stopped');
      return;
    }
    final revision = ++_runRevision;
    final nodes = List<FlowNode<DemoNodeData>>.of(_graph.nodes);
    if (nodes.isEmpty) {
      _showMessage('Add a node before running the workflow');
      return;
    }
    setState(() {
      _isRunning = true;
      _runningNodeId = null;
      _completedNodeIds.clear();
    });
    for (final node in nodes) {
      if (!mounted || revision != _runRevision) return;
      setState(() => _runningNodeId = node.id);
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted || revision != _runRevision) return;
      setState(() {
        _completedNodeIds.add(node.id);
        _runningNodeId = null;
      });
    }
    if (!mounted || revision != _runRevision) return;
    setState(() => _isRunning = false);
    _showMessage('Workflow completed');
  }

  Future<void> _renameWorkflow() async {
    final controller = TextEditingController(text: _workflowName);
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF191D27),
        title: const Text('Rename workflow'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 48,
          decoration: const InputDecoration(hintText: 'Workflow name'),
          onSubmitted: (text) => Navigator.pop(context, text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.trim().isEmpty) return;
    setState(() => _workflowName = value.trim());
    _refreshDirtyState();
  }

  Future<void> _showExportDialog() async {
    final json = _snapshotJson();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF191D27),
        title: const Row(
          children: [
            Icon(Icons.ios_share_rounded, size: 18, color: Color(0xFFA99BFF)),
            SizedBox(width: 10),
            Text('Export workflow'),
          ],
        ),
        content: SizedBox(
          width: 620,
          height: 420,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Copy this JSON snapshot to save or share the workflow.',
                style: TextStyle(color: Color(0xFF9AA2B2), fontSize: 12),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10131A),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(color: const Color(0xFF303746)),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      json,
                      style: const TextStyle(
                        color: Color(0xFFCDD2DE),
                        fontFamily: 'Consolas',
                        fontSize: 10,
                        height: 1.45,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: json));
              _exportedFingerprint = _documentFingerprint();
              _refreshDirtyState();
              if (context.mounted) Navigator.pop(context);
              _showMessage('Workflow JSON copied to clipboard');
            },
            icon: const Icon(Icons.copy_rounded, size: 15),
            label: const Text('Copy JSON'),
          ),
        ],
      ),
    );
  }

  Future<void> _showImportDialog() async {
    final controller = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF191D27),
        title: const Row(
          children: [
            Icon(Icons.file_download_outlined,
                size: 19, color: Color(0xFFA99BFF)),
            SizedBox(width: 10),
            Text('Import workflow'),
          ],
        ),
        content: SizedBox(
          width: 560,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 10,
            maxLines: 18,
            style: const TextStyle(
              color: Color(0xFFCDD2DE),
              fontFamily: 'Consolas',
              fontSize: 10,
            ),
            decoration: const InputDecoration(
              hintText: 'Paste a workflow JSON snapshot here',
              alignLabelWithHint: true,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, controller.text),
            icon: const Icon(Icons.file_download_outlined, size: 15),
            label: const Text('Import'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (input == null || input.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(input);
      if (decoded is! Map) {
        throw const FormatException('Expected a JSON object.');
      }
      final map = Map<String, Object?>.from(decoded);
      final name = map['workflowName'];
      final snapshot = FlowGraphSnapshot<DemoNodeData>.fromJson(
        map,
        decodeNodeData: DemoNodeData.fromJson,
      );
      _graph.setGraph(nodes: snapshot.nodes, edges: snapshot.edges);
      if (name is String && name.trim().isNotEmpty) {
        setState(() => _workflowName = name.trim());
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final zoom = snapshot.viewport.zoom.clamp(0.25, 2.0).toDouble();
        _canvasController.setViewport(
          snapshot.viewport.copyWith(zoom: zoom),
        );
      });
      _showMessage('Workflow imported');
    } on Object catch (error) {
      _showMessage('Could not import workflow: $error');
    }
  }

  Future<void> _showCompactNodePicker() async {
    final kind = await showModalBottomSheet<DemoNodeKind>(
      context: context,
      backgroundColor: const Color(0xFF171B25),
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('Add a workflow step',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
            ),
            for (final kind in DemoNodeKind.values)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _KindIcon(kind: kind),
                title: Text(kind.displayName),
                subtitle: Text(kind.kindDescription),
                trailing: const Icon(Icons.add_rounded, size: 18),
                onTap: () => Navigator.pop(context, kind),
              ),
          ],
        ),
      ),
    );
    if (kind != null) _addNode(kind);
  }

  void _undoOrRedo(bool redo) {
    if (redo) {
      _redo();
    } else {
      _undo();
    }
  }

  Future<void> _showMoreMenu() async {
    final size = MediaQuery.sizeOf(context);
    final action = await showMenu<String>(
      context: context,
      position:
          RelativeRect.fromLTRB(size.width - 210, 58, 8, size.height - 100),
      color: const Color(0xFF202532),
      items: const [
        PopupMenuItem(value: 'import', child: Text('Import JSON')),
        PopupMenuItem(value: 'export', child: Text('Export JSON')),
        PopupMenuDivider(),
        PopupMenuItem(value: 'delete', child: Text('Delete selection')),
        PopupMenuItem(value: 'fit', child: Text('Fit graph to view')),
      ],
    );
    switch (action) {
      case 'import':
        await _showImportDialog();
        break;
      case 'export':
        await _showExportDialog();
        break;
      case 'delete':
        _deleteSelected();
        break;
      case 'fit':
        _fitToView();
        break;
      case null:
        break;
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final showPalette = width >= 1080;
    final compact = width < 780;
    final node = _selectedNode;
    final edge = node == null ? _selectedEdge : null;
    final selected = node != null || edge != null;
    final nodesById = _graph.index.nodesById;
    final sourceTitle = edge == null
        ? null
        : nodesById[edge.sourceId]?.data.title ?? edge.sourceId;
    final targetTitle = edge == null
        ? null
        : nodesById[edge.targetId]?.data.title ?? edge.targetId;

    return Scaffold(
      backgroundColor: const Color(0xFF0C0F15),
      body: SafeArea(
        child: Column(
          children: [
            _EditorTopBar(
              workflowName: _workflowName,
              dirty: _hasUnexportedChanges,
              compact: compact,
              showPalette: showPalette,
              canUndo: _history.canUndo,
              canRedo: _history.canRedo,
              isRunning: _isRunning,
              selectionCount: _selection.nodes.length + _selection.edges.length,
              onRename: _renameWorkflow,
              onUndo: () => _undoOrRedo(false),
              onRedo: () => _undoOrRedo(true),
              onRun: _runWorkflow,
              onImport: _showImportDialog,
              onExport: _showExportDialog,
              onAdd: _showCompactNodePicker,
              onShowPalette: _showCompactNodePicker,
              onDelete: _deleteSelected,
              onMore: _showMoreMenu,
            ),
            Expanded(
              child: Row(
                children: [
                  if (showPalette) DemoNodePalette(onAdd: _addNode),
                  Expanded(
                    child: Stack(
                      key: _canvasViewportKey,
                      fit: StackFit.expand,
                      children: [
                        Positioned.fill(
                          child: FFlowCanvas<DemoNodeData>(
                            graphController: _graph,
                            historyController: _history,
                            clipboard: _clipboard,
                            createId: _newClipboardId,
                            controller: _canvasController,
                            backgroundVariant: _backgroundVariant ??
                                FlowBackgroundVariant.dots,
                            gridSpacing: _backgroundVariant == null ? 0 : 24,
                            nodes: null,
                            edges: null,
                            panEnabled: !_canvasLocked,
                            zoomEnabled: !_canvasLocked,
                            snapGrid: const Offset(24, 24),
                            helperLinesEnabled: true,
                            onlyRenderVisibleElements: true,
                            nodeBuilder: (context, node, isSelected) =>
                                DemoNodeCard(
                              node: node,
                              selected: isSelected,
                              running: node.id == _runningNodeId,
                              completed: _completedNodeIds.contains(node.id),
                              onDuplicate: () => _duplicateNode(node),
                              onDelete: () => _deleteNode(node.id),
                            ),
                            onSelectionChanged: (selection) {
                              setState(() => _selection = selection);
                            },
                            onConnect: (connection) => _graph.addEdges([
                              FlowGraphInteraction.createEdge(
                                connection,
                                _newEdgeId(),
                              ),
                            ]),
                          ),
                        ),
                        if (_graph.nodes.isEmpty)
                          Positioned.fill(
                            child: _EmptyCanvas(
                              onAdd: showPalette
                                  ? () => _addNode(DemoNodeKind.trigger)
                                  : _showCompactNodePicker,
                            ),
                          ),
                        Positioned(
                          left: 18,
                          top: 16,
                          child: _CanvasBadge(
                            nodeCount: _graph.nodes.length,
                            edgeCount: _graph.edges.length,
                            selectedCount: _selection.nodes.length +
                                _selection.edges.length,
                          ),
                        ),
                        if (selected && !compact)
                          Positioned(
                            right: 18,
                            top: 16,
                            child: DemoPropertiesPanel(
                              key: ValueKey(node?.id ?? edge!.id),
                              node: node,
                              edge: edge,
                              sourceTitle: sourceTitle,
                              targetTitle: targetTitle,
                              onApplyNode: (title, description) =>
                                  _applyNodeProperties(
                                      node!, title, description),
                              onApplyEdge: (label, type) =>
                                  _applyEdgeProperties(edge!, label, type),
                              onDuplicate: node == null
                                  ? () {}
                                  : () => _duplicateNode(node),
                              onDelete: _deleteSelected,
                              onClose: _clearSelection,
                            ),
                          ),
                        if (selected && compact)
                          Positioned(
                            left: 12,
                            right: 12,
                            bottom: 70,
                            child: DemoPropertiesPanel(
                              key: ValueKey(node?.id ?? edge!.id),
                              node: node,
                              edge: edge,
                              sourceTitle: sourceTitle,
                              targetTitle: targetTitle,
                              onApplyNode: (title, description) =>
                                  _applyNodeProperties(
                                      node!, title, description),
                              onApplyEdge: (label, type) =>
                                  _applyEdgeProperties(edge!, label, type),
                              onDuplicate: node == null
                                  ? () {}
                                  : () => _duplicateNode(node),
                              onDelete: _deleteSelected,
                              onClose: _clearSelection,
                            ),
                          ),
                        if (!compact)
                          Positioned(
                            right: 18,
                            bottom: 68,
                            child: FFlowMiniMap<DemoNodeData>(
                              nodes: _graph.nodes,
                              edges: _graph.edges,
                              controller: _canvasController,
                              viewportSize: _viewportSize ?? Size.zero,
                              nodeColorFor: (node) =>
                                  node.data.kind.accent.withValues(alpha: 0.78),
                              nodeBorderColorFor: (node) =>
                                  node.data.kind.accent,
                              nodeBorderWidth: 0.7,
                              edgeColor: const Color(0xFF687387),
                            ),
                          ),
                        Positioned(
                          right: 18,
                          bottom: 16,
                          child: FFlowControls<DemoNodeData>(
                            controller: _canvasController,
                            nodes: _graph.nodes,
                            viewportSize: _viewportSize ?? Size.zero,
                            padding: 130,
                            locked: _canvasLocked,
                            onLockChanged: (locked) =>
                                setState(() => _canvasLocked = locked),
                          ),
                        ),
                        Positioned(
                          left: 18,
                          bottom: 16,
                          child: _CanvasFooter(
                            locked: _canvasLocked,
                            onGridChanged: (variant) =>
                                setState(() => _backgroundVariant = variant),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditorTopBar extends StatelessWidget {
  const _EditorTopBar({
    required this.workflowName,
    required this.dirty,
    required this.compact,
    required this.showPalette,
    required this.canUndo,
    required this.canRedo,
    required this.isRunning,
    required this.selectionCount,
    required this.onRename,
    required this.onUndo,
    required this.onRedo,
    required this.onRun,
    required this.onImport,
    required this.onExport,
    required this.onAdd,
    required this.onShowPalette,
    required this.onDelete,
    required this.onMore,
  });

  final String workflowName;
  final bool dirty;
  final bool compact;
  final bool showPalette;
  final bool canUndo;
  final bool canRedo;
  final bool isRunning;
  final int selectionCount;
  final VoidCallback onRename;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onRun;
  final VoidCallback onImport;
  final VoidCallback onExport;
  final VoidCallback onAdd;
  final VoidCallback onShowPalette;
  final VoidCallback onDelete;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final iconOnly = width < 960;
    return Container(
      height: 62,
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 18),
      decoration: const BoxDecoration(
        color: Color(0xFF10131B),
        border: Border(bottom: BorderSide(color: Color(0xFF252B37))),
      ),
      child: Row(
        children: [
          Container(
            width: 31,
            height: 31,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFA89BFF), Color(0xFF7564E8)],
              ),
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(Icons.account_tree_rounded,
                color: Colors.white, size: 17),
          ),
          if (!compact) ...[
            const SizedBox(width: 10),
            const Text('FFlow',
                style: TextStyle(
                  color: Color(0xFFF0F1F5),
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.25,
                )),
            const SizedBox(width: 15),
            Container(width: 1, height: 23, color: const Color(0xFF343A47)),
            const SizedBox(width: 15),
          ] else
            const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: onRename,
              borderRadius: BorderRadius.circular(7),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        workflowName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFFDDE0E8),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.edit_outlined,
                        size: 12, color: Color(0xFF788193)),
                    if (!compact) ...[
                      const SizedBox(width: 12),
                      Icon(Icons.circle,
                          size: 7,
                          color: dirty
                              ? const Color(0xFFE7B05C)
                              : const Color(0xFF5CC6A4)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          dirty ? 'Changes not exported' : 'Example workflow',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF858D9D),
                            fontSize: 9,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (!showPalette)
            _BarIconButton(
              tooltip: 'Node library',
              icon: Icons.widgets_outlined,
              onPressed: onShowPalette,
            ),
          _BarIconButton(
            tooltip: 'Undo (Ctrl+Z)',
            icon: Icons.undo_rounded,
            onPressed: canUndo ? onUndo : null,
          ),
          _BarIconButton(
            tooltip: 'Redo (Ctrl+Shift+Z)',
            icon: Icons.redo_rounded,
            onPressed: canRedo ? onRedo : null,
          ),
          if (!iconOnly) ...[
            _BarIconButton(
              tooltip: 'Import workflow JSON',
              icon: Icons.file_download_outlined,
              onPressed: onImport,
            ),
            _BarIconButton(
              tooltip: 'Export workflow JSON',
              icon: Icons.ios_share_rounded,
              onPressed: onExport,
            ),
          ] else
            _BarIconButton(
              tooltip: 'More actions',
              icon: Icons.more_vert_rounded,
              onPressed: onMore,
            ),
          if (selectionCount > 0 && width > 700)
            _BarIconButton(
              tooltip: 'Delete selection',
              icon: Icons.delete_outline_rounded,
              onPressed: onDelete,
              color: const Color(0xFFE98C91),
            ),
          const SizedBox(width: 4),
          SizedBox(
            height: 36,
            child: FilledButton.icon(
              onPressed: onRun,
              style: FilledButton.styleFrom(
                backgroundColor: isRunning
                    ? const Color(0xFF55343A)
                    : const Color(0xFF263B39),
                foregroundColor: isRunning
                    ? const Color(0xFFF1A1A5)
                    : const Color(0xFF79D6BD),
                padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                  side: BorderSide(
                    color: isRunning
                        ? const Color(0xFF73474D)
                        : const Color(0xFF34514B),
                  ),
                ),
                textStyle: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              icon: Icon(
                isRunning ? Icons.stop_rounded : Icons.play_arrow_rounded,
                size: 17,
              ),
              label: compact
                  ? const SizedBox.shrink()
                  : Text(isRunning ? 'Stop' : 'Run'),
            ),
          ),
          const SizedBox(width: 7),
          SizedBox(
            height: 36,
            child: FilledButton.icon(
              onPressed: onAdd,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF8878F5),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9),
                ),
                textStyle: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: compact ? const SizedBox.shrink() : const Text('Add node'),
            ),
          ),
        ],
      ),
    );
  }
}

class _BarIconButton extends StatelessWidget {
  const _BarIconButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.color,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 36, height: 36),
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 17),
        color: color ?? const Color(0xFFAAB2C1),
        disabledColor: const Color(0xFF515866),
      );
}

class _CanvasBadge extends StatelessWidget {
  const _CanvasBadge({
    required this.nodeCount,
    required this.edgeCount,
    required this.selectedCount,
  });

  final int nodeCount;
  final int edgeCount;
  final int selectedCount;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xE9161A24),
          border: Border.all(color: const Color(0xFF303645)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.hub_outlined, size: 13, color: Color(0xFFA99BFF)),
            const SizedBox(width: 7),
            Text('$nodeCount steps',
                style: const TextStyle(
                  color: Color(0xFFD7DAE3),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                )),
            Container(
              width: 1,
              height: 12,
              margin: const EdgeInsets.symmetric(horizontal: 9),
              color: const Color(0xFF3A4050),
            ),
            Text('$edgeCount connections',
                style: const TextStyle(
                  color: Color(0xFF939BAB),
                  fontSize: 9,
                )),
            if (selectedCount > 0) ...[
              Container(
                width: 1,
                height: 12,
                margin: const EdgeInsets.symmetric(horizontal: 9),
                color: const Color(0xFF3A4050),
              ),
              Text('$selectedCount selected',
                  style: const TextStyle(
                    color: Color(0xFFB7ABFF),
                    fontSize: 9,
                  )),
            ],
          ],
        ),
      );
}

class _CanvasFooter extends StatelessWidget {
  const _CanvasFooter({required this.locked, required this.onGridChanged});

  final bool locked;
  final ValueChanged<FlowBackgroundVariant?> onGridChanged;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xE9161A24),
          border: Border.all(color: const Color(0xFF303645)),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(locked ? Icons.lock_outline_rounded : Icons.touch_app_outlined,
                size: 13, color: const Color(0xFFA99BFF)),
            const SizedBox(width: 7),
            Text(
              locked ? 'Canvas locked' : 'Drag · Connect · Ctrl+Z · Ctrl+C / V',
              style: const TextStyle(color: Color(0xFF969EAE), fontSize: 9),
            ),
            const SizedBox(width: 5),
            PopupMenuButton<String>(
              tooltip: 'Canvas background',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              iconSize: 15,
              icon:
                  const Icon(Icons.grid_4x4_rounded, color: Color(0xFF969EAE)),
              color: const Color(0xFF202532),
              onSelected: (value) {
                switch (value) {
                  case 'dots':
                    onGridChanged(FlowBackgroundVariant.dots);
                    break;
                  case 'lines':
                    onGridChanged(FlowBackgroundVariant.lines);
                    break;
                  case 'cross':
                    onGridChanged(FlowBackgroundVariant.cross);
                    break;
                  case 'off':
                    onGridChanged(null);
                    break;
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(value: 'dots', child: Text('Dot grid')),
                PopupMenuItem(value: 'lines', child: Text('Line grid')),
                PopupMenuItem(value: 'cross', child: Text('Cross grid')),
                PopupMenuItem(value: 'off', child: Text('Hide grid')),
              ],
            ),
          ],
        ),
      );
}

class _EmptyCanvas extends StatelessWidget {
  const _EmptyCanvas({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) => Center(
        child: Container(
          width: 310,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xF0191D27),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF353D4D)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: const Color(0xFF9B8BFF).withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.account_tree_outlined,
                    color: Color(0xFFA99BFF), size: 23),
              ),
              const SizedBox(height: 13),
              const Text('Start building your workflow',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFFE7E9EF),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  )),
              const SizedBox(height: 6),
              const Text('Add a trigger, then connect steps on the canvas.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF9AA2B2), fontSize: 10)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Add first step'),
              ),
            ],
          ),
        ),
      );
}

class _KindIcon extends StatelessWidget {
  const _KindIcon({required this.kind});
  final DemoNodeKind kind;

  @override
  Widget build(BuildContext context) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: kind.accent.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Icon(kind.icon, color: kind.accent, size: 18),
      );
}

extension on DemoNodeKind {
  String get kindDescription => switch (this) {
        DemoNodeKind.trigger => 'Start a workflow',
        DemoNodeKind.ai => 'Transform or generate content',
        DemoNodeKind.review => 'Pause for approval',
        DemoNodeKind.output => 'Send results to a destination',
      };
}
