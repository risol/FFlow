import 'package:fflow/fflow.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

FlowNode<String> _node(String id, Offset position, {double size = 100}) =>
    FlowNode<String>(
      id: id,
      position: position,
      data: id,
      width: size,
      height: size,
    );

void main() {
  const edge = FlowEdge(
    id: 'edge',
    sourceId: 'source',
    targetId: 'target',
    type: FlowEdgeType.straight,
  );

  test('reuses path geometry and ignores paint-only edge changes', () {
    final nodes = {
      'source': _node('source', Offset.zero),
      'target': _node('target', const Offset(300, 0)),
    };
    final cache = FlowEdgeGeometryCache();

    final first = cache.result(edge, nodes);
    final second = cache.result(edge.copyWith(selected: true), nodes);

    expect(first, isNotNull);
    expect(second, same(first));
    expect(cache.misses, 1);
    expect(cache.hits, 1);
    expect(cache.length, 1);
  });

  test('recomputes when endpoint geometry changes and supports invalidation',
      () {
    final nodes = {
      'source': _node('source', Offset.zero),
      'target': _node('target', const Offset(300, 0)),
      'other': _node('other', const Offset(0, 240)),
    };
    const otherEdge = FlowEdge(
      id: 'other-edge',
      sourceId: 'source',
      targetId: 'other',
      type: FlowEdgeType.straight,
    );
    final cache = FlowEdgeGeometryCache();

    final first = cache.result(edge, nodes);
    cache.result(otherEdge, nodes);
    final movedNodes = {
      ...nodes,
      'source': nodes['source']!.copyWith(position: const Offset(20, 30)),
    };
    final moved = cache.result(edge, movedNodes);
    cache.invalidateNode('source', [edge, otherEdge]);

    expect(moved, isNot(same(first)));
    expect(cache.misses, 3);
    expect(cache.length, 0);
  });

  test('retains only live edges and clear resets counters', () {
    final nodes = {
      'source': _node('source', Offset.zero),
      'target': _node('target', const Offset(300, 0)),
      'other': _node('other', const Offset(0, 240)),
    };
    const otherEdge = FlowEdge(
      id: 'other-edge',
      sourceId: 'source',
      targetId: 'other',
    );
    final cache = FlowEdgeGeometryCache();
    cache.result(edge, nodes);
    cache.result(otherEdge, nodes);
    cache.retainEdges([edge]);

    expect(cache.length, 1);
    cache.clear();
    expect(cache.length, 0);
    expect(cache.hits, 0);
    expect(cache.misses, 0);
  });

  test('hit index queries negative, tolerance, large, and edge regions', () {
    final nodes = [
      _node('negative', const Offset(-30, -20)),
      _node('large', Offset.zero, size: 2000),
      _node('target', const Offset(2500, 0)),
    ];
    const edges = [
      FlowEdge(
        id: 'long-edge',
        sourceId: 'large',
        targetId: 'target',
        type: FlowEdgeType.straight,
      ),
    ];
    final nodesById = {for (final node in nodes) node.id: node};
    final geometry = FlowEdgeGeometryCache();
    final index = FlowHitTestIndex(cellSize: 32);

    index.rebuild(
      nodes: nodes,
      edges: edges,
      nodesById: nodesById,
      geometryCache: geometry,
      nodeHitTestTolerance: 8,
    );

    expect(index.nodeCandidates(const Offset(-35, -15)), contains('negative'));
    expect(index.nodeCandidates(const Offset(1999, 1999)), contains('large'));
    expect(index.nodeCandidates(const Offset(2007, 1000)), contains('large'));
    expect(index.nodeCandidates(const Offset(2010, 1000)),
        isNot(contains('large')));
    expect(
        index.edgeCandidates(const Offset(2250, 1000)), contains('long-edge'));
    expect(
      index.edgeCandidatesIn(const Rect.fromLTWH(2200, 950, 100, 100)),
      contains('long-edge'),
    );
    expect(index.edgeCandidatesIn(Rect.zero), isEmpty);
  });
}
