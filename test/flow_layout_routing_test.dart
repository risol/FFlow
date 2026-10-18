import 'package:fflow/fflow.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

FlowNode<String> _node(
  String id, {
  Offset position = Offset.zero,
  double width = 100,
  double height = 60,
  String? parentId,
  bool hidden = false,
  bool collapsed = false,
  bool selected = false,
  double minWidth = 80,
  double minHeight = 48,
}) =>
    FlowNode<String>(
      id: id,
      position: position,
      data: id,
      width: width,
      height: height,
      parentId: parentId,
      hidden: hidden,
      collapsed: collapsed,
      selected: selected,
      minWidth: minWidth,
      minHeight: minHeight,
    );

void main() {
  group('FlowLayeredLayoutEngine', () {
    test('places directed nodes in successive layers', () {
      final nodes = [_node('a'), _node('b'), _node('c')];
      final result = const FlowLayeredLayoutEngine<String>().layout(
        nodes: nodes,
        edges: const [
          FlowEdge(id: 'ab', sourceId: 'a', targetId: 'b'),
          FlowEdge(id: 'bc', sourceId: 'b', targetId: 'c'),
        ],
      );

      expect(result.positions['a']!.dx, lessThan(result.positions['b']!.dx));
      expect(result.positions['b']!.dx, lessThan(result.positions['c']!.dx));
    });

    test('keeps cycles in one layer and advances downstream nodes', () {
      final result = const FlowLayeredLayoutEngine<String>().layout(
        nodes: [_node('a'), _node('b'), _node('c')],
        edges: const [
          FlowEdge(id: 'ab', sourceId: 'a', targetId: 'b'),
          FlowEdge(id: 'ba', sourceId: 'b', targetId: 'a'),
          FlowEdge(id: 'bc', sourceId: 'b', targetId: 'c'),
        ],
      );

      expect(result.positions['a']!.dx, result.positions['b']!.dx);
      expect(result.positions['c']!.dx, greaterThan(result.positions['b']!.dx));
    });

    test('arranges nested children in parent space and expands the parent', () {
      final nodes = [
        _node('group', width: 100, height: 80),
        _node('child', parentId: 'group', width: 200, height: 120),
      ];
      final result = const FlowLayeredLayoutEngine<String>(
        groupPadding: 32,
      ).layout(nodes: nodes, edges: const []);

      expect(result.sizes['group'], const Size(264, 184));
      expect(result.positions['child'], const Offset(32, 32));
      final laidOut = result.applyTo(nodes);
      expect(laidOut.first.width, 264);
      expect(laidOut.first.height, 184);
    });

    test('interpolates positions and sizes', () {
      final source = _node('a', width: 100, height: 60);
      final result = FlowLayoutResult(
        {'a': const Offset(100, 40)},
        sizes: {'a': const Size(200, 120)},
      );

      final middle = result.interpolate([source], 0.5).single;
      expect(middle.position, const Offset(50, 20));
      expect(middle.width, 150);
      expect(middle.height, 90);
    });
  });

  group('FlowForceLayoutEngine', () {
    test('is deterministic, pins existing nodes, and separates a new node', () {
      final nodes = [
        _node('fixed-a', position: Offset.zero),
        _node('fixed-b', position: const Offset(220, 0)),
        _node('new', position: Offset.zero),
      ];
      const engine = FlowForceLayoutEngine<String>(
        fixedNodeIds: {'fixed-a', 'fixed-b'},
      );
      final first = engine.layout(nodes: nodes, edges: const []);
      final second = engine.layout(nodes: nodes, edges: const []);

      expect(first.positions, second.positions);
      expect(first.positions['fixed-a'], nodes[0].position);
      expect(first.positions['fixed-b'], nodes[1].position);
      expect(first.positions['new'], isNot(nodes[2].position));
      final fixedRect = Rect.fromLTWH(
        first.positions['fixed-a']!.dx,
        first.positions['fixed-a']!.dy,
        nodes[0].width,
        nodes[0].height,
      );
      final newRect = Rect.fromLTWH(
        first.positions['new']!.dx,
        first.positions['new']!.dy,
        nodes[2].width,
        nodes[2].height,
      );
      expect(fixedRect.overlaps(newRect), isFalse);
    });

    test('lays out visible roots but not hidden or nested nodes', () {
      final result = const FlowForceLayoutEngine<String>().layout(
        nodes: [
          _node('root-a'),
          _node('root-b', position: const Offset(180, 0)),
          _node('group'),
          _node('child', parentId: 'group'),
          _node('hidden', hidden: true),
        ],
        edges: const [],
      );

      expect(result.positions.keys, {'root-a', 'root-b', 'group'});
    });
  });

  group('FlowOrthogonalEdgeRouter', () {
    const router = FlowOrthogonalEdgeRouter(clearance: 12);

    test('routes around an obstacle with orthogonal control points', () {
      final route = router.route(
        edge:
            const FlowEdge(id: 'edge', sourceId: 'source', targetId: 'target'),
        sourceBounds: const Rect.fromLTWH(0, 0, 100, 60),
        targetBounds: const Rect.fromLTWH(300, 0, 100, 60),
        sourceAnchor: const Offset(100, 30),
        targetAnchor: const Offset(300, 30),
        obstacles: const [Rect.fromLTWH(140, -10, 120, 80)],
      );

      expect(route.controlPoints.length, greaterThanOrEqualTo(2));
      final path = [
        const Offset(100, 30),
        ...route.controlPoints,
        const Offset(300, 30),
      ];
      final obstacle = const Rect.fromLTWH(140, -10, 120, 80).inflate(12);
      for (var index = 1; index < path.length; index++) {
        expect(_segmentCrossesRect(path[index - 1], path[index], obstacle),
            isFalse);
        expect(
          path[index - 1].dx == path[index].dx ||
              path[index - 1].dy == path[index].dy,
          isTrue,
        );
      }
    });

    test('uses a straight path when no obstacle blocks it', () {
      final route = router.route(
        edge:
            const FlowEdge(id: 'edge', sourceId: 'source', targetId: 'target'),
        sourceBounds: const Rect.fromLTWH(0, 0, 100, 60),
        targetBounds: const Rect.fromLTWH(300, 0, 100, 60),
        sourceAnchor: const Offset(100, 30),
        targetAnchor: const Offset(300, 30),
        obstacles: const [],
      );

      expect(route.controlPoints, isEmpty);
    });

    test('rejects invalid routing options', () {
      expect(
        () => router.route(
          edge: const FlowEdge(
              id: 'edge', sourceId: 'source', targetId: 'target'),
          sourceBounds: const Rect.fromLTWH(0, 0, 100, 60),
          targetBounds: const Rect.fromLTWH(300, 0, 100, 60),
          obstacles: const [],
          options: const {'clearance': -1},
        ),
        throwsArgumentError,
      );
    });
  });

  test('FlowGraphRouting leaves hidden edges alone and routes visible edges',
      () async {
    const hiddenPoints = [Offset(12, 18)];
    const visibleEdge = FlowEdge(
      id: 'visible',
      sourceId: 'source',
      targetId: 'target',
    );
    const hiddenEdge = FlowEdge(
      id: 'hidden',
      sourceId: 'source',
      targetId: 'target',
      hidden: true,
      controlPoints: hiddenPoints,
    );
    final routed = await FlowGraphRouting.routeEdges<String>(
      nodes: [
        _node('source'),
        _node('target', position: const Offset(300, 0)),
        _node('obstacle',
            position: const Offset(140, -10), width: 120, height: 80),
      ],
      edges: const [visibleEdge, hiddenEdge],
      router: const FlowOrthogonalEdgeRouter(),
    );

    expect(routed.first.controlPoints, isNotEmpty);
    expect(routed.last, hiddenEdge);
  });

  test(
      'collapse preserves descendant state and expanded size through snapshots',
      () {
    final controller = FlowGraphController<String>(
      nodes: [
        _node('group', width: 360, height: 240, minWidth: 176, minHeight: 54),
        _node('child', parentId: 'group', selected: true),
        _node('nested', parentId: 'group', collapsed: true),
        _node('grandchild', parentId: 'nested', selected: true),
      ],
      edges: const [
        FlowEdge(
          id: 'edge',
          sourceId: 'child',
          targetId: 'grandchild',
          selected: true,
        ),
      ],
    );
    addTearDown(controller.dispose);

    expect(controller.setNodeCollapsed('group', true), isTrue);
    final collapsedGroup = controller.getNode('group')!;
    expect(collapsedGroup.collapsed, isTrue);
    expect(collapsedGroup.width, 176);
    expect(collapsedGroup.height, 54);
    expect(collapsedGroup.expandedSize, const Size(360, 240));
    expect(controller.getNode('child')!.selected, isFalse);
    expect(controller.getNode('grandchild')!.selected, isFalse);
    expect(controller.getEdge('edge')!.selected, isFalse);
    expect(
      FlowGeometry.isVisible(
          controller.getNode('child')!, controller.index.nodesById),
      isFalse,
    );

    final snapshot = controller.toSnapshot(
      const FlowViewport(x: 0, y: 0, zoom: 1),
    );
    final restored = FlowGraphSnapshot<String>.fromJson(
      snapshot.toJson(encodeNodeData: (value) => value),
      decodeNodeData: (value) => value! as String,
    );
    expect(restored.nodes.first.collapsed, isTrue);
    expect(restored.nodes.first.expandedSize, const Size(360, 240));

    expect(controller.toggleNodeCollapsed('group'), isTrue);
    expect(controller.getNode('group')!.width, 360);
    expect(controller.getNode('group')!.height, 240);
    expect(controller.getNode('group')!.expandedSize, isNull);
    expect(controller.getNode('nested')!.collapsed, isTrue);
    expect(controller.getNode('child')!.position, const Offset(0, 0));
  });
}

bool _segmentCrossesRect(Offset first, Offset second, Rect rect) {
  if (first.dx == second.dx) {
    final top = first.dy < second.dy ? first.dy : second.dy;
    final bottom = first.dy > second.dy ? first.dy : second.dy;
    return first.dx > rect.left &&
        first.dx < rect.right &&
        top < rect.bottom &&
        bottom > rect.top;
  }
  final left = first.dx < second.dx ? first.dx : second.dx;
  final right = first.dx > second.dx ? first.dx : second.dx;
  return first.dy > rect.top &&
      first.dy < rect.bottom &&
      left < rect.right &&
      right > rect.left;
}
