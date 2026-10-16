import 'package:fflow/fflow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('editor canvas visual baseline', (tester) async {
    final controller = FlowCanvasController();
    addTearDown(controller.dispose);
    const nodes = [
      FlowNode<String>(
        id: 'source',
        position: Offset(60, 110),
        data: 'Source',
        width: 120,
        height: 76,
        selected: true,
        resizable: true,
      ),
      FlowNode<String>(
        id: 'target',
        position: Offset(320, 110),
        data: 'Target',
        width: 120,
        height: 76,
      ),
    ];
    const edges = [
      FlowEdge(
        id: 'edge',
        sourceId: 'source',
        targetId: 'target',
        type: FlowEdgeType.smoothStep,
        markerEnd: FlowEdgeMarker.arrowClosed,
        label: 'Approved',
        selected: true,
      ),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: Stack(
            children: [
              Positioned.fill(
                child: FFlowCanvas<String>(
                  controller: controller,
                  nodes: nodes,
                  edges: edges,
                  selectionOnDrag: true,
                  nodeBuilder: (context, node, selected) => DecoratedBox(
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xff34304f)
                          : const Color(0xff252a34),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: selected
                            ? const Color(0xff9b8bff)
                            : const Color(0xff50596b),
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        node.data,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                right: 18,
                bottom: 18,
                child: FFlowMiniMap<String>(
                  nodes: nodes,
                  edges: edges,
                  controller: controller,
                  viewportSize: const Size(800, 600),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final selection = await tester.startGesture(const Offset(560, 320));
    await selection.moveTo(const Offset(730, 390));
    await tester.pump();
    await expectLater(
      find.byType(FFlowCanvas<String>),
      matchesGoldenFile('goldens/fflow_canvas_editor.png'),
    );
    await selection.up();
    await tester.pumpAndSettle();
  });
}
