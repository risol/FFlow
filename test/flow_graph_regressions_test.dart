import 'package:fflow/fflow.dart';
import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

FlowNode<String> _node(
  String id, {
  Offset position = Offset.zero,
  double width = 100,
  double height = 60,
  Offset origin = Offset.zero,
  String? parentId,
  List<FlowHandle> handles = const [],
  bool hasInput = true,
  bool hasOutput = true,
  Rect? extent,
  bool groupable = false,
  bool selected = false,
}) =>
    FlowNode<String>(
      id: id,
      position: position,
      data: id,
      width: width,
      height: height,
      origin: origin,
      parentId: parentId,
      handles: handles,
      hasInput: hasInput,
      hasOutput: hasOutput,
      extent: extent,
      groupable: groupable,
      selected: selected,
    );

void main() {
  group('immutable model updates', () {
    test('FlowNode.copyWith can clear nullable values explicitly', () {
      const node = FlowNode<String?>(
        id: 'child',
        position: Offset.zero,
        data: 'payload',
        parentId: 'group',
        extent: Rect.fromLTWH(0, 0, 200, 100),
        ariaLabel: 'label',
      );

      final cleared = node.copyWith(
        data: null,
        parentId: null,
        extent: null,
        ariaLabel: null,
      );

      expect(cleared.data, isNull);
      expect(cleared.parentId, isNull);
      expect(cleared.extent, isNull);
      expect(cleared.ariaLabel, isNull);
      expect(node.parentId, 'group');
    });

    test(
        'FlowEdge.copyWith preserves omitted fields and clears nullable fields',
        () {
      const edge = FlowEdge(
        id: 'e',
        sourceId: 'a',
        targetId: 'b',
        sourceHandleId: 'out',
        targetHandleId: 'in',
        type: FlowEdgeType.step,
        customType: 'custom',
        label: 'label',
        color: Color(0xff123456),
        markerStart: FlowEdgeMarker.arrow,
        markerEnd: FlowEdgeMarker.arrowClosed,
        data: {'value': 1},
        reconnectableEnds: FlowReconnectable.both,
        markerColor: Color(0xffabcdef),
        ariaLabel: 'edge label',
        controlPoints: [Offset(20, 30)],
      );

      final cleared = edge.copyWith(
        sourceHandleId: null,
        targetHandleId: null,
        customType: null,
        label: null,
        color: null,
        markerStart: null,
        markerEnd: null,
        data: null,
        reconnectableEnds: null,
        markerColor: null,
        ariaLabel: null,
      );

      expect(cleared.type, FlowEdgeType.step);
      expect(cleared.controlPoints, [const Offset(20, 30)]);
      expect(cleared.sourceHandleId, isNull);
      expect(cleared.targetHandleId, isNull);
      expect(cleared.customType, isNull);
      expect(cleared.label, isNull);
      expect(cleared.color, isNull);
      expect(cleared.markerStart, isNull);
      expect(cleared.markerEnd, isNull);
      expect(cleared.data, isNull);
      expect(cleared.reconnectableEnds, isNull);
      expect(cleared.markerColor, isNull);
      expect(cleared.ariaLabel, isNull);
    });
  });

  group('FlowGeometry coordinate semantics', () {
    test('origin adjusts root node rect and anchors without a node map', () {
      final node = _node(
        'centered',
        position: const Offset(100, 100),
        origin: const Offset(.5, .5),
        width: 40,
        height: 20,
      );

      expect(FlowGeometry.nodeRect(node, {'centered': node}),
          const Rect.fromLTWH(80, 90, 40, 20));
      expect(FlowGeometry.inputAnchor(node), const Offset(80, 100));
      expect(FlowGeometry.outputAnchor(node), const Offset(120, 100));
      expect(
        FlowGeometry.handleAnchor(node, node.resolvedHandles.last),
        const Offset(120, 100),
      );
      expect(
        FlowGeometry.nodeAbsoluteAnchor(node, {'centered': node}),
        const Offset(100, 100),
      );
    });

    test('nested origins use parent-relative top-left coordinates', () {
      final parent = _node(
        'parent',
        position: const Offset(100, 100),
        origin: const Offset(.5, .5),
        width: 200,
        height: 100,
      );
      final child = _node(
        'child',
        parentId: 'parent',
        position: const Offset(20, 30),
        origin: const Offset(.5, .5),
        width: 40,
        height: 20,
      );
      final nodes = {'parent': parent, 'child': child};

      expect(FlowGeometry.nodeRect(child, nodes),
          const Rect.fromLTWH(0, 70, 40, 20));
      expect(
          FlowGeometry.nodeAbsoluteAnchor(child, nodes), const Offset(20, 80));
    });
  });

  test('connection validation enforces capacity and excludes the moved edge',
      () {
    final sourceA = _node(
      'source-a',
      hasInput: false,
      hasOutput: false,
      handles: const [
        FlowHandle(
          id: 'out',
          type: FlowHandleType.source,
          position: FlowHandlePosition.right,
          maxConnections: 1,
        ),
      ],
    );
    final sourceB = _node(
      'source-b',
      position: const Offset(0, 120),
      hasInput: false,
      hasOutput: false,
      handles: const [
        FlowHandle(
          id: 'out',
          type: FlowHandleType.source,
          position: FlowHandlePosition.right,
        ),
      ],
    );
    final targetA = _node(
      'target-a',
      position: const Offset(300, 0),
      hasInput: false,
      hasOutput: false,
      handles: const [
        FlowHandle(
          id: 'in',
          type: FlowHandleType.target,
          position: FlowHandlePosition.left,
          maxConnections: 1,
        ),
      ],
    );
    final targetB = _node(
      'target-b',
      position: const Offset(300, 120),
      hasInput: false,
      hasOutput: false,
      handles: const [
        FlowHandle(
          id: 'in',
          type: FlowHandleType.target,
          position: FlowHandlePosition.left,
        ),
      ],
    );
    final nodes = [sourceA, sourceB, targetA, targetB];
    const existing = FlowEdge(
      id: 'edge',
      sourceId: 'source-a',
      sourceHandleId: 'out',
      targetId: 'target-a',
      targetHandleId: 'in',
    );
    final edges = [existing];
    final targetBHandle = targetB.resolvedHandles.single;

    expect(
      FlowGraphInteraction.connectionAt<String>(
        nodes: nodes,
        edges: edges,
        sourceId: 'source-a',
        sourceHandleId: 'out',
        point: FlowGeometry.handleAnchor(targetB, targetBHandle),
        snapRadius: 1,
      ),
      isNull,
      reason: 'the source handle is already at capacity',
    );
    expect(
      FlowGraphInteraction.connectionAt<String>(
        nodes: nodes,
        edges: edges,
        sourceId: 'source-b',
        sourceHandleId: 'out',
        point:
            FlowGeometry.handleAnchor(targetA, targetA.resolvedHandles.single),
        snapRadius: 1,
      ),
      isNull,
      reason: 'the target handle is already at capacity',
    );
    expect(
      FlowGraphInteraction.connectionAt<String>(
        nodes: nodes,
        edges: const [],
        sourceId: 'source-b',
        sourceHandleId: 'out',
        point: FlowGeometry.handleAnchor(targetB, targetBHandle),
        snapRadius: 1,
        isValidConnection: (_) => false,
      ),
      isNull,
    );

    final sourceAHandle = sourceA.resolvedHandles.single;
    expect(
      FlowGraphInteraction.sourceConnectionAt<String>(
        nodes: nodes,
        edges: edges,
        targetId: 'target-a',
        targetHandleId: 'in',
        point: FlowGeometry.handleAnchor(sourceA, sourceAHandle),
        snapRadius: 1,
      ),
      isNull,
    );
    final reconnect = FlowGraphInteraction.sourceConnectionAt<String>(
      nodes: nodes,
      edges: edges,
      targetId: 'target-a',
      targetHandleId: 'in',
      point: FlowGeometry.handleAnchor(sourceA, sourceAHandle),
      snapRadius: 1,
      excludedEdgeId: 'edge',
    );
    expect(reconnect?.sourceId, 'source-a');
  });

  test('delete result reports cascaded edges and reparents children in place',
      () {
    final parent = _node(
      'parent',
      position: const Offset(100, 100),
      origin: const Offset(.5, .5),
      width: 200,
      height: 100,
    );
    final child = _node(
      'child',
      parentId: 'parent',
      position: const Offset(20, 30),
      origin: const Offset(.5, .5),
      width: 40,
      height: 20,
    );
    const edge = FlowEdge(id: 'edge', sourceId: 'parent', targetId: 'other');

    final result = FlowGraphUtils.deleteElements<String>(
      nodes: [parent, child, _node('other')],
      edges: const [edge],
      nodeIds: const ['parent'],
    );

    expect(result.deletedNodes.map((node) => node.id), ['parent']);
    expect(result.deletedEdges, [edge]);
    expect(result.edges, isEmpty);
    final retainedChild = result.nodes.firstWhere((node) => node.id == 'child');
    expect(retainedChild.parentId, isNull);
    expect(
        FlowGeometry.nodeRect(retainedChild, {
          for (final node in result.nodes) node.id: node,
        }),
        const Rect.fromLTWH(0, 70, 40, 20));
  });

  group('FlowGraphValidator', () {
    test('reports duplicate ids, missing entities, handles, cycles, and ranges',
        () {
      final a = _node('a', parentId: 'b', handles: const [
        FlowHandle(
            id: 'dup',
            type: FlowHandleType.source,
            position: FlowHandlePosition.right),
        FlowHandle(
            id: 'dup',
            type: FlowHandleType.target,
            position: FlowHandlePosition.left),
      ]);
      final b = _node('b', parentId: 'a');
      final invalid = _node('invalid', extent: const Rect.fromLTRB(4, 5, 1, 2));
      const dangling = FlowEdge(
        id: 'dangling',
        sourceId: 'missing',
        targetId: 'a',
        sourceHandleId: 'absent',
      );
      const loose = FlowEdge(
        id: 'loose',
        sourceId: 'a',
        targetId: 'b',
        targetHandleType: FlowHandleType.source,
      );
      const missingHandle = FlowEdge(
        id: 'missing-handle',
        sourceId: 'a',
        targetId: 'a',
        targetHandleId: 'absent',
      );

      final diagnostics = FlowGraphValidator.validate<String>(
        nodes: [a, b, _node('a'), invalid],
        edges: const [dangling, missingHandle, loose, loose],
        viewport: const FlowViewport(x: 0, y: 0, zoom: 0),
        minZoom: 2,
        maxZoom: 1,
        translateExtent: const Rect.fromLTRB(5, 4, 1, 2),
        connectionMode: FlowConnectionMode.strict,
      );
      final codes = diagnostics.map((diagnostic) => diagnostic.code).toSet();

      expect(
          codes,
          containsAll([
            'duplicate-node-id',
            'duplicate-edge-id',
            'duplicate-handle-id',
            'parent-cycle',
            'invalid-node-extent',
            'dangling-edge-source',
            'missing-target-handle',
            'invalid-viewport',
            'inverted-zoom-range',
            'invalid-translate-extent',
            'loose-edge-in-strict-mode',
          ]));
      expect(
        diagnostics
            .firstWhere((item) => item.code == 'loose-edge-in-strict-mode')
            .severity,
        FlowDiagnosticSeverity.warning,
      );
    });
  });

  group('FlowGraphIndex and controller revisions', () {
    test('indexes default handles, adjacency, and graph changes', () {
      final source = _node('source', hasInput: false);
      final target = _node('target', hasOutput: false);
      const first = FlowEdge(id: 'e1', sourceId: 'source', targetId: 'target');
      const second = FlowEdge(id: 'e2', sourceId: 'source', targetId: 'target');
      final controller = FlowGraphController<String>(
        nodes: [source, target],
        edges: const [first, second],
      );
      addTearDown(controller.dispose);

      expect(controller.getNode('source'), same(source));
      expect(controller.getEdge('e2'), same(second));
      expect(
          controller.getOutgoers('source').map((node) => node.id), ['target']);
      expect(
          controller.getIncomers('target').map((node) => node.id), ['source']);
      expect(
        controller.getNodeConnections('source',
            handleId: 'source', type: FlowHandleType.source),
        [first, second],
      );

      final oldIndex = controller.index;
      controller.updateNode(
          'source', (node) => node.copyWith(position: const Offset(8, 9)));
      expect(controller.graphRevision, 1);
      expect(controller.geometryRevision, 1);
      expect(controller.index, isNot(same(oldIndex)));
      expect(controller.getNode('source')!.position, const Offset(8, 9));
    });
  });

  group('snapshot migrations', () {
    test('legacy snapshots migrate defaults and current snapshots round-trip',
        () {
      final legacy = FlowGraphSnapshot<String>.fromJson(
        <String, Object?>{
          'nodes': [
            {'id': 'legacy', 'data': 'legacy'},
          ],
          'edges': <Object?>[],
        },
        decodeNodeData: (value) => value! as String,
      );
      expect(legacy.nodes.single.position, Offset.zero);
      expect(legacy.viewport, const FlowViewport(x: 0, y: 0, zoom: 1));

      final snapshot = FlowGraphSnapshot<String>(
        nodes: [_node('selected', selected: true)],
        edges: const [
          FlowEdge(
            id: 'route',
            sourceId: 'selected',
            targetId: 'selected',
            controlPoints: [Offset(40, 50)],
            selected: true,
          ),
        ],
        viewport: const FlowViewport(x: 10, y: 20, zoom: 1.25),
      );
      final json = snapshot.toJson(encodeNodeData: (data) => data);
      expect(json['schemaVersion'], FlowGraphSnapshot.currentSchemaVersion);
      final serializedNode =
          (json['nodes']! as List<Object?>).single as Map<String, Object?>;
      final serializedEdge =
          (json['edges']! as List<Object?>).single as Map<String, Object?>;
      expect(serializedNode.containsKey('selected'), isFalse);
      expect(serializedEdge.containsKey('selected'), isFalse);
      final restored = FlowGraphSnapshot<String>.fromJson(
        json,
        decodeNodeData: (value) => value! as String,
      );
      expect(restored.nodes.single.selected, isFalse);
      expect(restored.edges.single.selected, isFalse);
      expect(restored.edges.single.controlPoints, [const Offset(40, 50)]);
      expect(restored.viewport, snapshot.viewport);

      final withSelection = snapshot.toJson(
        encodeNodeData: (data) => data,
        includeSelection: true,
      );
      final selectedRestore = FlowGraphSnapshot<String>.fromJson(
        withSelection,
        decodeNodeData: (value) => value! as String,
      );
      expect(selectedRestore.nodes.single.selected, isTrue);
      expect(selectedRestore.edges.single.selected, isTrue);
      expect(
        () => FlowGraphSnapshot.migrateJson({'schemaVersion': 999}),
        throwsFormatException,
      );
    });
  });

  group('transaction history and clipboard', () {
    test('history groups edits, computes operations, and supports redo', () {
      final before =
          FlowGraphState<String>(nodes: [_node('a')], edges: const []);
      final after = FlowGraphState<String>(
        nodes: [_node('a', position: const Offset(10, 12)), _node('b')],
        edges: const [],
      );
      final history = FlowHistoryController<String>(maxEntries: 1);
      addTearDown(history.dispose);
      history.beginTransaction('Move and add', before);
      final transaction = history.commitTransaction(after);

      expect(transaction!.label, 'Move and add');
      expect(transaction.operations.map((op) => op.type), [
        FlowGraphOperationType.addNodes,
        FlowGraphOperationType.moveNodes,
      ]);
      expect(history.undo(), same(before));
      expect(history.canRedo, isTrue);
      expect(history.redo(), same(after));
      history.record(label: 'No-op', before: after, after: after);
      expect(history.undoCount, 1);
      expect(history.nextUndo!.label, 'Move and add');
    });

    test('clipboard copies internal edges and remaps ids and parents', () {
      final group = _node(
        'group',
        position: const Offset(200, 100),
        groupable: true,
        width: 200,
        height: 120,
      );
      final child = _node(
        'child',
        position: const Offset(20, 30),
        parentId: 'group',
        selected: true,
      );
      const internal =
          FlowEdge(id: 'inside', sourceId: 'group', targetId: 'child');
      const external =
          FlowEdge(id: 'outside', sourceId: 'child', targetId: 'elsewhere');
      final clipboard = FlowClipboard<String>();
      clipboard.copy(
        nodes: [group, child],
        edges: const [internal, external],
        selectedNodeIds: const ['group', 'child'],
      );
      expect(clipboard.payload!.edges, [internal]);

      var nextId = 0;
      final result = clipboard.paste(
        nodes: [group, child],
        edges: const [internal],
        createId: () => 'new-${nextId++}',
      );
      expect(result.pastedNodes.map((node) => node.id), ['new-0', 'new-1']);
      expect(result.pastedNodes.last.parentId, 'new-0');
      expect(result.pastedEdges.single.id, 'new-2');
      expect(result.pastedEdges.single.sourceId, 'new-0');
      expect(result.pastedEdges.single.targetId, 'new-1');
      expect(result.pastedNodes.first.position, const Offset(224, 124));
      expect(result.pastedNodes.last.position, const Offset(20, 30));

      final secondPaste = clipboard.paste(
        nodes: const [],
        edges: const [],
        createId: () => 'second-${nextId++}',
      );
      expect(secondPaste.pastedNodes.first.position, const Offset(248, 148));
    });
  });

  test(
      'edge path result includes endpoints, bounds, and editable control points',
      () {
    final source = _node('source', position: const Offset(20, 20));
    final target = _node('target', position: const Offset(240, 20));
    const edge = FlowEdge(
      id: 'edge',
      sourceId: 'source',
      targetId: 'target',
      type: FlowEdgeType.straight,
      controlPoints: [Offset(160, 120)],
    );
    final result = FlowGeometry.edgePathResult<String>(
      edge,
      {'source': source, 'target': target},
    );

    expect(result, isNotNull);
    expect(result!.sourceAnchor, const Offset(120, 50));
    expect(result.targetAnchor, const Offset(240, 50));
    expect(result.bounds.bottom, greaterThanOrEqualTo(120));
    expect(result.labelPosition, isNot(Offset.zero));
    expect(result.metrics, isNotEmpty);
  });
}
