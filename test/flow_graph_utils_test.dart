import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fflow/fflow.dart';

FlowNode<String> _node(String id, {Offset position = Offset.zero}) =>
    FlowNode<String>(id: id, position: position, data: id);

FlowEdge _edge(String id, {bool selected = false}) => FlowEdge(
      id: id,
      sourceId: 'source',
      targetId: 'target',
      selected: selected,
    );

void main() {
  group('FlowGraphUtils.applyNodeChanges', () {
    test('applies add, remove, position, dimensions, and selection changes',
        () {
      final nodes = [_node('remove-me'), _node('keep-me')];

      final updated = FlowGraphUtils.applyNodeChanges<String>(
        [
          const FlowNodeChange<String>(
            type: FlowNodeChangeType.remove,
            id: 'remove-me',
          ),
          FlowNodeChange<String>(
            type: FlowNodeChangeType.add,
            id: 'added',
            node: _node('added'),
            index: 1,
          ),
          const FlowNodeChange<String>(
            type: FlowNodeChangeType.position,
            id: 'keep-me',
            position: Offset(12, 18),
          ),
          const FlowNodeChange<String>(
            type: FlowNodeChangeType.dimensions,
            id: 'keep-me',
            size: Size(300, 160),
          ),
          const FlowNodeChange<String>(
            type: FlowNodeChangeType.select,
            id: 'keep-me',
            selected: true,
          ),
        ],
        nodes,
      );

      expect(updated.map((node) => node.id), ['keep-me', 'added']);
      expect(updated.first.position, const Offset(12, 18));
      expect(updated.first.width, 300);
      expect(updated.first.height, 160);
      expect(updated.first.selected, isTrue);
    });
  });

  group('FlowGraphUtils.applyEdgeChanges', () {
    test('applies add, remove, replace, and selection changes', () {
      final edges = [_edge('remove-me'), _edge('update-me')];
      final replacement = _edge('update-me').copyWith(label: 'updated');

      final updated = FlowGraphUtils.applyEdgeChanges(
        [
          const FlowEdgeChange(
            type: FlowEdgeChangeType.remove,
            id: 'remove-me',
          ),
          FlowEdgeChange(
            type: FlowEdgeChangeType.add,
            id: 'added',
            edge: _edge('added'),
            index: 1,
          ),
          FlowEdgeChange(
            type: FlowEdgeChangeType.replace,
            id: 'update-me',
            edge: replacement,
          ),
          const FlowEdgeChange(
            type: FlowEdgeChangeType.select,
            id: 'added',
            selected: true,
          ),
        ],
        edges,
      );

      expect(updated.map((edge) => edge.id), ['update-me', 'added']);
      expect(updated.first.label, 'updated');
      expect(updated.last.selected, isTrue);
    });
  });

  test('edge de-duplication includes the target handle type', () {
    const existing = FlowEdge(
      id: 'target-edge',
      sourceId: 'source',
      targetId: 'target',
      targetHandleId: 'shared',
      targetHandleType: FlowHandleType.target,
    );
    const sameEndpointOnSourceHandle = FlowEdge(
      id: 'source-edge',
      sourceId: 'source',
      targetId: 'target',
      targetHandleId: 'shared',
      targetHandleType: FlowHandleType.source,
    );

    expect(
      FlowGraphUtils.addEdge([existing], sameEndpointOnSourceHandle),
      hasLength(2),
    );
    expect(FlowGraphUtils.addEdge([existing], existing), hasLength(1));
  });

  test('loose connection mode can end at another source handle', () {
    const source = FlowNode<String>(
      id: 'source-node',
      position: Offset.zero,
      data: 'source',
      width: 100,
      height: 100,
      handles: [
        FlowHandle(
          id: 'out',
          type: FlowHandleType.source,
          position: FlowHandlePosition.right,
        ),
      ],
    );
    const target = FlowNode<String>(
      id: 'target-node',
      position: Offset(300, 0),
      data: 'target',
      width: 100,
      height: 100,
      handles: [
        FlowHandle(
          id: 'also-out',
          type: FlowHandleType.source,
          position: FlowHandlePosition.right,
        ),
      ],
    );
    final nodes = [source, target];
    final point = FlowGeometry.handleAnchor(target, target.handles.single);

    expect(
      FlowGraphInteraction.connectionAt<String>(
        nodes: nodes,
        edges: const [],
        sourceId: source.id,
        sourceHandleId: 'out',
        point: point,
        snapRadius: 1,
      ),
      isNull,
    );
    final connection = FlowGraphInteraction.connectionAt<String>(
      nodes: nodes,
      edges: const [],
      sourceId: source.id,
      sourceHandleId: 'out',
      point: point,
      snapRadius: 1,
      connectionMode: FlowConnectionMode.loose,
    );
    expect(connection?.targetId, target.id);
    expect(connection?.targetHandleType, FlowHandleType.source);
  });

  test('graph snapshot round-trips loose target handles', () {
    final snapshot = FlowGraphSnapshot<String>(
      nodes: [_node('source'), _node('target')],
      edges: [
        const FlowEdge(
          id: 'edge',
          sourceId: 'source',
          targetId: 'target',
          targetHandleId: 'out',
          targetHandleType: FlowHandleType.source,
          data: {'tag': 'kept'},
        ),
      ],
      viewport: const FlowViewport(x: 12, y: 24, zoom: 1.5),
    );

    final json = snapshot.toJson(
      encodeNodeData: (data) => data,
      encodeEdgeData: (data) => data,
    );
    final restored = FlowGraphSnapshot<String>.fromJson(
      json,
      decodeNodeData: (value) => value! as String,
    );

    expect(restored.edges.single.targetHandleType, FlowHandleType.source);
    expect(restored.edges.single.data, {'tag': 'kept'});
    expect(restored.viewport, snapshot.viewport);

    final oldEdgeJson =
        (json['edges']! as List<Object?>).single as Map<String, Object?>;
    oldEdgeJson.remove('targetHandleType');
    final legacy = FlowGraphSnapshot<String>.fromJson(
      json,
      decodeNodeData: (value) => value! as String,
    );
    expect(legacy.edges.single.targetHandleType, FlowHandleType.target);
  });
}
