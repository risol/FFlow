import 'dart:math' as math;

import 'package:fflow/fflow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('500 alternating node drags release pointer ownership',
      (tester) async {
    final controller = FlowCanvasController();
    addTearDown(controller.dispose);
    var latestNodes = const <FlowNode<String>>[];
    var dragStarts = 0;
    var dragEnds = 0;
    const initialNodes = [
      FlowNode<String>(
        id: 'a',
        position: Offset(100, 140),
        data: 'A',
        width: 100,
        height: 70,
        hasInput: false,
        hasOutput: false,
      ),
      FlowNode<String>(
        id: 'b',
        position: Offset(420, 140),
        data: 'B',
        width: 100,
        height: 70,
        hasInput: false,
        hasOutput: false,
      ),
    ];
    latestNodes = initialNodes;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: FFlowCanvas<String>(
            controller: controller,
            nodes: initialNodes,
            edges: const [],
            fitViewOnInit: false,
            defaultViewport: const FlowViewport(x: 0, y: 0, zoom: 1),
            nodeBuilder: (context, node, selected) =>
                Center(child: Text(node.data)),
            onNodesChanged: (nodes) => latestNodes = nodes,
            onNodeDragStart: (_) => dragStarts++,
            onNodeDragEnd: (_) => dragEnds++,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final perNodeDragCount = {'a': 0, 'b': 0};
    for (var index = 0; index < 500; index++) {
      final id = index.isEven ? 'a' : 'b';
      final count = perNodeDragCount[id]!;
      perNodeDragCount[id] = count + 1;
      final sign = count.isEven ? 1.0 : -1.0;
      final node = latestNodes.singleWhere((item) => item.id == id);
      final start = controller.flowToScreenPosition(
        node.position + Offset(node.width / 2, node.height / 2),
      );
      final gesture = await tester.startGesture(start, pointer: 47);
      await gesture.moveTo(start + Offset(sign * 12, 0));
      await tester.pump();
      if (index % 7 == 0) {
        await gesture.cancel();
      } else {
        await gesture.up();
      }
      await tester.pump();
    }

    expect(dragStarts, 500);
    expect(dragEnds, 500);
    expect(latestNodes.singleWhere((node) => node.id == 'a').position,
        initialNodes.first.position);
    expect(latestNodes.singleWhere((node) => node.id == 'b').position,
        initialNodes.last.position);
  });

  testWidgets('seeded overlapping graph interactions keep the down target',
      (tester) async {
    const nodeCount = 20;
    const interactionCount = 100;
    final random = math.Random(20261016);
    final controller = FlowCanvasController();
    addTearDown(controller.dispose);
    var latestNodes = List<FlowNode<int>>.generate(
      nodeCount,
      (index) => FlowNode<int>(
        id: 'node-$index',
        position: Offset(
          30 + random.nextInt(620).toDouble(),
          30 + random.nextInt(420).toDouble(),
        ),
        data: index,
        width: 130,
        height: 90,
        hasInput: false,
        hasOutput: false,
        zIndex: random.nextInt(4),
      ),
    );
    final initialNodes = latestNodes;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: FFlowCanvas<int>(
            controller: controller,
            nodes: initialNodes,
            edges: const [],
            fitViewOnInit: false,
            defaultViewport: const FlowViewport(x: 0, y: 0, zoom: 1),
            elevateNodesOnSelect: false,
            helperLinesEnabled: false,
            helperLineSnap: false,
            nodeBuilder: (context, node, selected) =>
                Center(child: Text('${node.data}')),
            onNodesChanged: (nodes) => latestNodes = nodes,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    for (var index = 0; index < interactionCount; index++) {
      final before = List<FlowNode<int>>.of(latestNodes);
      final source = before[random.nextInt(before.length)];
      final flowPoint = source.position +
          Offset(
            10 + random.nextDouble() * 100,
            10 + random.nextDouble() * 60,
          );
      final hitCandidates = <(int, FlowNode<int>)>[
        for (var nodeIndex = 0; nodeIndex < before.length; nodeIndex++)
          if (Rect.fromLTWH(
            before[nodeIndex].position.dx,
            before[nodeIndex].position.dy,
            before[nodeIndex].width,
            before[nodeIndex].height,
          ).inflate(12).contains(flowPoint))
            (nodeIndex, before[nodeIndex]),
      ]..sort((first, second) {
          final zOrder = first.$2.zIndex.compareTo(second.$2.zIndex);
          return zOrder != 0 ? zOrder : first.$1.compareTo(second.$1);
        });
      expect(hitCandidates, isNotEmpty);
      final expectedTarget = hitCandidates.last.$2.id;
      final screenPoint = controller.flowToScreenPosition(flowPoint);
      final delta = Offset(
        random.nextBool() ? 14 : -14,
        random.nextBool() ? 9 : -9,
      );
      final gesture = await tester.startGesture(screenPoint);
      await gesture.moveTo(screenPoint + delta);
      await tester.pump();
      if (index % 5 == 0) {
        await gesture.cancel();
      } else {
        await gesture.up();
      }
      await tester.pump();

      final moved = <FlowNode<int>>[
        for (var nodeIndex = 0; nodeIndex < latestNodes.length; nodeIndex++)
          if (latestNodes[nodeIndex].position != before[nodeIndex].position)
            latestNodes[nodeIndex],
      ];
      expect(moved, hasLength(1), reason: 'interaction $index');
      expect(
        moved.single.id,
        expectedTarget,
        reason: 'interaction $index at $flowPoint, '
            'expected candidates ${hitCandidates.map((entry) => '${entry.$2.id}(z=${entry.$2.zIndex}, order=${entry.$1})').toList()}; '
            'actual moved ${moved.single.id}',
      );
      final actualDelta = moved.single.position -
          before.singleWhere((node) => node.id == expectedTarget).position;
      expect(actualDelta, isNot(Offset.zero), reason: 'interaction $index');
      expect(latestNodes.map((node) => node.id).toSet(), hasLength(nodeCount));
    }
  });
}
