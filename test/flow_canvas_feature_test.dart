import 'package:fflow/fflow.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('dragging a source handle onto a target creates a connection',
      (tester) async {
    final controller = FlowCanvasController();
    addTearDown(controller.dispose);
    final connections = <FlowConnection>[];
    const source = FlowNode<String>(
      id: 'source',
      position: Offset(80, 120),
      data: 'Source',
      width: 120,
      height: 80,
      hasInput: false,
    );
    const target = FlowNode<String>(
      id: 'target',
      position: Offset(360, 120),
      data: 'Target',
      width: 120,
      height: 80,
      hasOutput: false,
    );

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: FFlowCanvas<String>(
            controller: controller,
            nodes: const [source, target],
            edges: const [],
            fitViewOnInit: false,
            defaultViewport: const FlowViewport(x: 0, y: 0, zoom: 1),
            nodeBuilder: (context, node, selected) => Center(
              child: Text(node.data),
            ),
            onConnect: connections.add,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final sourceHandle = FlowGeometry.handleFor(
      source,
      null,
      FlowHandleType.source,
    )!;
    final targetHandle = FlowGeometry.handleFor(
      target,
      null,
      FlowHandleType.target,
    )!;
    final start = controller.flowToScreenPosition(
      FlowGeometry.handleAnchor(source, sourceHandle),
    );
    final end = controller.flowToScreenPosition(
      FlowGeometry.handleAnchor(target, targetHandle),
    );

    final gesture = await tester.startGesture(start);
    await gesture.moveTo(end);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(connections, hasLength(1));
    expect(connections.single.sourceId, 'source');
    expect(connections.single.targetId, 'target');
  });

  testWidgets('viewport culling tracks which nodes are rendered',
      (tester) async {
    final controller = FlowCanvasController();
    addTearDown(controller.dispose);
    const nodes = [
      FlowNode<String>(
        id: 'near',
        position: Offset(100, 100),
        data: 'Near node',
        width: 100,
        height: 80,
      ),
      FlowNode<String>(
        id: 'far',
        position: Offset(5000, 5000),
        data: 'Far node',
        width: 100,
        height: 80,
      ),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: FFlowCanvas<String>(
            controller: controller,
            nodes: nodes,
            edges: const [],
            fitViewOnInit: false,
            defaultViewport: const FlowViewport(x: 0, y: 0, zoom: 1),
            onlyRenderVisibleElements: true,
            nodeBuilder: (context, node, selected) => Text(node.data),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Near node'), findsOneWidget);
    expect(find.text('Far node'), findsNothing);

    controller.centerAt(const Offset(5050, 5040), const Size(800, 600));
    await tester.pumpAndSettle();

    expect(find.text('Near node'), findsNothing);
    expect(find.text('Far node'), findsOneWidget);
  });

  testWidgets('copy and paste shortcuts add a remapped selected node',
      (tester) async {
    final clipboard = FlowClipboard<String>();
    var nextId = 0;
    var latestNodes = const <FlowNode<String>>[];
    const nodes = [
      FlowNode<String>(
        id: 'original',
        position: Offset(100, 100),
        data: 'Original node',
        width: 140,
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
            clipboard: clipboard,
            createId: () => 'copy-${nextId++}',
            nodeBuilder: (context, node, selected) => Text(node.data),
            onNodesChanged: (value) => latestNodes = value,
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Original node'));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(latestNodes.map((node) => node.id), ['original', 'copy-0']);
    expect(latestNodes.last.data, 'Original node');
    expect(latestNodes.last.selected, isTrue);
  });
}
