import 'package:fflow/fflow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('emits a granular selection change and keeps the list callback',
      (tester) async {
    final nodeChanges = <List<FlowNodeChange<String>>>[];
    final legacyNodeUpdates = <List<FlowNode<String>>>[];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: FFlowCanvas<String>(
            nodes: const [
              FlowNode<String>(
                id: 'alpha',
                position: Offset(20, 20),
                data: 'alpha',
                width: 180,
                height: 90,
              ),
            ],
            edges: const [],
            nodeBuilder: (context, node, selected) => Container(
              alignment: Alignment.center,
              color: selected ? Colors.deepPurple : Colors.blueGrey,
              child: Text(node.data),
            ),
            onNodesChange: nodeChanges.add,
            onNodesChanged: legacyNodeUpdates.add,
          ),
        ),
      ),
    ));

    await tester.tap(find.text('alpha'));
    await tester.pump(const Duration(milliseconds: 400));

    expect(nodeChanges, hasLength(1));
    expect(nodeChanges.single, hasLength(1));
    expect(nodeChanges.single.single.type, FlowNodeChangeType.select);
    expect(nodeChanges.single.single.id, 'alpha');
    expect(nodeChanges.single.single.selected, isTrue);
    expect(legacyNodeUpdates, hasLength(1));
    expect(legacyNodeUpdates.single.single.selected, isTrue);
  });

  testWidgets('emits a granular edge selection change', (tester) async {
    final edgeChanges = <List<FlowEdgeChange>>[];
    final legacyEdgeUpdates = <List<FlowEdge>>[];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: FFlowCanvas<String>(
            nodes: const [
              FlowNode<String>(
                id: 'source',
                position: Offset(20, 20),
                data: 'source',
                width: 120,
                height: 80,
              ),
              FlowNode<String>(
                id: 'target',
                position: Offset(300, 20),
                data: 'target',
                width: 120,
                height: 80,
              ),
            ],
            edges: const [
              FlowEdge(
                id: 'connection',
                sourceId: 'source',
                targetId: 'target',
                type: FlowEdgeType.straight,
              ),
            ],
            nodeBuilder: (context, node, selected) => Container(
              alignment: Alignment.center,
              color: Colors.blueGrey,
              child: Text(node.data),
            ),
            onEdgesChange: edgeChanges.add,
            onEdgesChanged: legacyEdgeUpdates.add,
          ),
        ),
      ),
    ));

    await tester.tapAt(const Offset(220, 60));
    await tester.pump(const Duration(milliseconds: 400));

    expect(edgeChanges, hasLength(1));
    expect(edgeChanges.single, hasLength(1));
    expect(edgeChanges.single.single.type, FlowEdgeChangeType.select);
    expect(edgeChanges.single.single.id, 'connection');
    expect(edgeChanges.single.single.selected, isTrue);
    expect(legacyEdgeUpdates, hasLength(1));
    expect(legacyEdgeUpdates.single.single.selected, isTrue);
  });

  testWidgets('emits node position changes while dragging', (tester) async {
    final nodeChanges = <List<FlowNodeChange<String>>>[];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: FFlowCanvas<String>(
            nodes: const [
              FlowNode<String>(
                id: 'move-me',
                position: Offset(20, 20),
                data: 'move me',
                width: 180,
                height: 90,
              ),
            ],
            edges: const [],
            nodeBuilder: (context, node, selected) => Container(
              alignment: Alignment.center,
              color: Colors.blueGrey,
              child: Text(node.data),
            ),
            onNodesChange: nodeChanges.add,
          ),
        ),
      ),
    ));

    await tester.drag(find.text('move me'), const Offset(40, 25));
    await tester.pumpAndSettle();

    final positionChange = nodeChanges
        .expand((batch) => batch)
        .where((change) => change.type == FlowNodeChangeType.position)
        .firstOrNull;
    expect(positionChange, isNotNull);
    expect(positionChange!.position, isNot(const Offset(20, 20)));
  });
}
