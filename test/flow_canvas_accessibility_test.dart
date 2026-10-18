import 'package:fflow/fflow.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('canvas, node, and edge labels are exposed to semantics',
      (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: FFlowCanvas<String>(
            canvasLabel: 'Order workflow canvas',
            nodes: const [
              FlowNode<String>(
                id: 'start',
                position: Offset(20, 20),
                data: 'Start',
                width: 120,
                height: 80,
                ariaLabel: 'Order start step',
              ),
              FlowNode<String>(
                id: 'finish',
                position: Offset(320, 20),
                data: 'Finish',
                width: 120,
                height: 80,
                ariaLabel: 'Order finish step',
              ),
            ],
            edges: const [
              FlowEdge(
                id: 'order-edge',
                sourceId: 'start',
                targetId: 'finish',
                ariaLabel: 'Order moves from start to finish',
              ),
            ],
            nodeBuilder: (context, node, selected) => Text(node.data),
          ),
        ),
      ),
    ));

    expect(find.bySemanticsLabel('Order workflow canvas'), findsOneWidget);
    expect(find.bySemanticsLabel('Order start step'), findsOneWidget);
    expect(find.bySemanticsLabel('Order finish step'), findsOneWidget);
    expect(find.bySemanticsLabel('Order moves from start to finish'),
        findsOneWidget);
    semantics.dispose();
  });

  testWidgets('focused nodes can be selected and moved by keyboard',
      (tester) async {
    var latestNodes = const <FlowNode<String>>[];
    final selections = <FlowSelection>[];
    const nodes = [
      FlowNode<String>(
        id: 'keyboard-node',
        position: Offset(40, 40),
        data: 'Keyboard node',
        width: 120,
        height: 80,
      ),
    ];
    latestNodes = nodes;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: FFlowCanvas<String>(
            nodes: nodes,
            edges: const [],
            nodeBuilder: (context, node, selected) => Text(node.data),
            onNodesChanged: (value) => latestNodes = value,
            onSelectionChanged: selections.add,
          ),
        ),
      ),
    ));

    final nodeFocus = Focus.of(tester.element(find.text('Keyboard node')));
    nodeFocus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();

    expect(selections.last.nodes, {'keyboard-node'});
    expect(latestNodes.single.position, const Offset(41, 40));
  });
}
