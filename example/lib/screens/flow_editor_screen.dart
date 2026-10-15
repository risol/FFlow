import 'package:flutter/material.dart';
import 'package:fflow/fflow.dart';

import '../models/demo_node_data.dart';
import '../widgets/demo_node_card.dart';

class FlowEditorScreen extends StatefulWidget {
  const FlowEditorScreen({super.key});

  @override
  State<FlowEditorScreen> createState() => _FlowEditorScreenState();
}

class _FlowEditorScreenState extends State<FlowEditorScreen> {
  final FlowCanvasController _transformController = FlowCanvasController();
  final GlobalKey _viewportKey = GlobalKey();
  List<FlowNode<DemoNodeData>> _nodes = [
    const FlowNode(
      id: 'trigger',
      position: Offset(124, 284),
      type: 'trigger',
      data: DemoNodeData(
          title: 'New research request',
          description: 'Runs when a request arrives',
          kind: DemoNodeKind.trigger),
      width: 244,
      height: 126,
      hasInput: false,
    ),
    const FlowNode(
      id: 'summarize',
      position: Offset(454, 164),
      type: 'ai',
      data: DemoNodeData(
          title: 'Summarize sources',
          description: 'Create a concise research brief',
          kind: DemoNodeKind.ai),
      width: 244,
      height: 126,
    ),
    const FlowNode(
      id: 'review',
      position: Offset(784, 284),
      type: 'review',
      data: DemoNodeData(
          title: 'Editorial review',
          description: 'Approve the brief before sharing',
          kind: DemoNodeKind.review),
      width: 244,
      height: 126,
    ),
    const FlowNode(
      id: 'publish',
      position: Offset(1114, 164),
      type: 'output',
      data: DemoNodeData(
          title: 'Publish report',
          description: 'Send the approved report to Slack',
          kind: DemoNodeKind.output),
      width: 244,
      height: 126,
      hasOutput: false,
    ),
  ];
  List<FlowEdge> _edges = const [
    FlowEdge(id: 'edge-1', sourceId: 'trigger', targetId: 'summarize'),
    FlowEdge(id: 'edge-2', sourceId: 'summarize', targetId: 'review'),
    FlowEdge(id: 'edge-3', sourceId: 'review', targetId: 'publish'),
  ];
  String? _selectedNodeId;
  int _nodeCounter = 1;
  int _edgeCounter = 4;

  FlowNode<DemoNodeData>? get _selectedNode {
    for (final node in _nodes) {
      if (node.id == _selectedNodeId) return node;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _fitToView();
    });
  }

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  Size? get _viewportSize {
    final renderObject = _viewportKey.currentContext?.findRenderObject();
    if (renderObject is RenderBox) return renderObject.size;
    return null;
  }

  void _addNode(DemoNodeKind kind) {
    final viewport = _viewportSize;
    final center = viewport == null
        ? const Offset(650, 420)
        : _transformController
            .toScene(Offset(viewport.width / 2, viewport.height / 2));
    final id = 'node-${_nodeCounter++}';
    setState(() {
      _nodes = [
        for (final node in _nodes) node.copyWith(selected: false),
        FlowNode(
          id: id,
          position: Offset(center.dx - 122, center.dy - 63),
          type: kind.name,
          data: DemoNodeData(
              title: 'New ${kind.displayName}',
              description: 'Click to configure this step',
              kind: kind),
          width: 244,
          height: 126,
          hasInput: kind != DemoNodeKind.trigger,
          hasOutput: kind != DemoNodeKind.output,
          selected: true,
        ),
      ];
      _selectedNodeId = id;
    });
  }

  void _removeSelectedNode() {
    final id = _selectedNodeId;
    if (id == null) return;
    setState(() {
      _nodes = _nodes.where((node) => node.id != id).toList();
      _edges = _edges
          .where((edge) => edge.sourceId != id && edge.targetId != id)
          .toList();
      _selectedNodeId = null;
    });
  }

  void _fitToView() {
    final viewport = _viewportSize;
    if (viewport == null || _nodes.isEmpty) return;
    _transformController.fitView(_nodes, viewport, padding: 130);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedNode;
    final isNarrow = MediaQuery.sizeOf(context).width < 760;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(onAdd: _showAddMenu),
            Expanded(
              child: Stack(
                key: _viewportKey,
                fit: StackFit.expand,
                children: [
                  Positioned.fill(
                    child: FFlowCanvas<DemoNodeData>(
                      nodes: _nodes,
                      edges: _edges,
                      controller: _transformController,
                      nodeBuilder: (context, node, isSelected) =>
                          DemoNodeCard(node: node, selected: isSelected),
                      onNodesChanged: (nodes) => setState(() => _nodes = nodes),
                      onEdgesChanged: (edges) => setState(() => _edges = edges),
                      onNodeSelected: (id) =>
                          setState(() => _selectedNodeId = id),
                      onConnect: (connection) {
                        final edge = FlowGraphInteraction.createEdge(
                          connection,
                          'edge-${_edgeCounter++}',
                        );
                        setState(() =>
                            _edges = FlowGraphUtils.addEdge(_edges, edge));
                      },
                    ),
                  ),
                  Positioned(
                      left: 20,
                      top: 18,
                      child: _CanvasBadge(
                          nodeCount: _nodes.length, edgeCount: _edges.length)),
                  Positioned(
                    right: 18,
                    bottom: 18,
                    child: FFlowControls<DemoNodeData>(
                      controller: _transformController,
                      nodes: _nodes,
                      viewportSize: _viewportSize ?? Size.zero,
                      padding: 130,
                    ),
                  ),
                  if (!isNarrow)
                    Positioned(
                      right: 18,
                      bottom: 68,
                      child: FFlowMiniMap<DemoNodeData>(
                        nodes: _nodes,
                        controller: _transformController,
                        viewportSize: _viewportSize ?? Size.zero,
                      ),
                    ),
                  if (selected != null && !isNarrow)
                    Positioned(
                        right: 18,
                        top: 18,
                        child: _Inspector(
                            node: selected, onDelete: _removeSelectedNode)),
                  if (selected != null && isNarrow)
                    Positioned(
                        left: 16,
                        right: 16,
                        bottom: 78,
                        child: _CompactInspector(
                            node: selected, onDelete: _removeSelectedNode)),
                  Positioned(
                      left: 20,
                      bottom: 22,
                      child: _CanvasHint(isNarrow: isNarrow)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF171B25),
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Add to canvas',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              for (final kind in DemoNodeKind.values)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                        color: kind.accent.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(11)),
                    child: Icon(kind.icon, color: kind.accent, size: 19),
                  ),
                  title: Text(kind.displayName,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Text(kind.kindLabel,
                      style: const TextStyle(
                          fontSize: 10, color: Color(0xFF9299A8))),
                  onTap: () {
                    Navigator.pop(context);
                    _addNode(kind);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: const BoxDecoration(
          color: Color(0xFF10131B),
          border: Border(bottom: BorderSide(color: Color(0xFF242936)))),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFA89BFF), Color(0xFF7564E8)]),
                borderRadius: BorderRadius.circular(9)),
            child: const Icon(Icons.account_tree_rounded,
                color: Colors.white, size: 17),
          ),
          const SizedBox(width: 10),
          const Text('FFlow SDK',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  letterSpacing: -0.25)),
          SizedBox(width: compact ? 10 : 18),
          Container(width: 1, height: 24, color: const Color(0xFF303543)),
          SizedBox(width: compact ? 10 : 18),
          const Flexible(
            child: Text('Workflow example',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: Color(0xFFDDE0E8),
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
          ),
          const Spacer(),
          if (!compact) ...[
            const Icon(Icons.circle, size: 7, color: Color(0xFF5CC6A4)),
            const SizedBox(width: 7),
            const Text('SDK canvas',
                style: TextStyle(color: Color(0xFF8D95A5), fontSize: 10)),
          ],
          SizedBox(width: compact ? 8 : 18),
          FilledButton.icon(
            onPressed: onAdd,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF8878F5),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9)),
              textStyle:
                  const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
            ),
            icon: const Icon(Icons.add_rounded, size: 16),
            label: compact ? const SizedBox.shrink() : const Text('Add node'),
          ),
        ],
      ),
    );
  }
}

class _CanvasBadge extends StatelessWidget {
  const _CanvasBadge({required this.nodeCount, required this.edgeCount});
  final int nodeCount;
  final int edgeCount;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
            color: const Color(0xE9161A24),
            border: Border.all(color: const Color(0xFF303645)),
            borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.hub_outlined, size: 13, color: Color(0xFFA99BFF)),
          const SizedBox(width: 7),
          Text('$nodeCount nodes',
              style: const TextStyle(
                  color: Color(0xFFD7DAE3),
                  fontSize: 10,
                  fontWeight: FontWeight.w600)),
          Container(
              width: 1,
              height: 12,
              margin: const EdgeInsets.symmetric(horizontal: 9),
              color: const Color(0xFF3A4050)),
          Text('$edgeCount connections',
              style: const TextStyle(color: Color(0xFF939BAB), fontSize: 10)),
        ]),
      );
}

class _CanvasHint extends StatelessWidget {
  const _CanvasHint({required this.isNarrow});
  final bool isNarrow;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
            color: const Color(0xE9161A24),
            border: Border.all(color: const Color(0xFF303645)),
            borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.touch_app_outlined,
              size: 14, color: Color(0xFF9F92FF)),
          const SizedBox(width: 7),
          Text(
              isNarrow
                  ? 'Drag nodes · Connect handles'
                  : 'Drag nodes to arrange · Pull a handle to connect',
              style: const TextStyle(color: Color(0xFF969EAE), fontSize: 9.5)),
        ]),
      );
}

class _Inspector extends StatelessWidget {
  const _Inspector({required this.node, required this.onDelete});
  final FlowNode<DemoNodeData> node;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Container(
        width: 218,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: const Color(0xF0191D27),
            border: Border.all(color: const Color(0xFF333A49)),
            borderRadius: BorderRadius.circular(13)),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Icon(node.data.kind.icon,
                    size: 15, color: node.data.kind.accent),
                const SizedBox(width: 7),
                const Expanded(
                    child: Text('NODE SETTINGS',
                        style: TextStyle(
                            color: Color(0xFF969EAE),
                            fontSize: 9,
                            letterSpacing: 1.05,
                            fontWeight: FontWeight.w800))),
                InkWell(
                    onTap: onDelete,
                    borderRadius: BorderRadius.circular(7),
                    child: const Padding(
                        padding: EdgeInsets.all(4),
                        child: Icon(Icons.delete_outline_rounded,
                            size: 16, color: Color(0xFF9AA1AF)))),
              ]),
              const SizedBox(height: 12),
              Text(node.data.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(node.data.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 10, height: 1.35, color: Color(0xFF959CAB))),
              const SizedBox(height: 11),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                    color: node.data.kind.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6)),
                child: Text(node.data.kind.kindLabel,
                    style: TextStyle(
                        color: node.data.kind.accent,
                        fontSize: 8,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.7)),
              ),
            ]),
      );
}

class _CompactInspector extends StatelessWidget {
  const _CompactInspector({required this.node, required this.onDelete});
  final FlowNode<DemoNodeData> node;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
            color: const Color(0xF0191D27),
            border: Border.all(color: const Color(0xFF333A49)),
            borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Icon(node.data.kind.icon, size: 17, color: node.data.kind.accent),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                Text(node.data.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700)),
                Text(node.data.kind.kindLabel,
                    style: TextStyle(
                        color: node.data.kind.accent,
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6)),
              ])),
          IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline_rounded, size: 17),
              color: const Color(0xFFABB2C0)),
        ]),
      );
}
