import 'package:fflow/fflow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('clicking the map centers the viewport on the clicked graph area',
      (tester) async {
    final controller = FlowCanvasController();
    addTearDown(controller.dispose);
    const nodes = [
      FlowNode<String>(
        id: 'left',
        position: Offset.zero,
        data: 'left',
        width: 100,
        height: 80,
      ),
      FlowNode<String>(
        id: 'right',
        position: Offset(1000, 0),
        data: 'right',
        width: 100,
        height: 80,
      ),
    ];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: FFlowMiniMap<String>(
            nodes: nodes,
            controller: controller,
            viewportSize: const Size(200, 100),
          ),
        ),
      ),
    ));

    await tester.tap(find.byType(FFlowMiniMap<String>));
    await tester.pump();

    final center = controller.screenToFlowPosition(const Offset(100, 50));
    expect(center.dx, closeTo(550, 1e-8));
    expect(center.dy, closeTo(40, 1e-8));
    expect(controller.viewport.x, closeTo(-450, 1e-8));
    expect(controller.viewport.y, closeTo(10, 1e-8));
    expect(controller.viewport.zoom, 1);
  });

  testWidgets('empty graphs render safely and do not move the viewport',
      (tester) async {
    final controller = FlowCanvasController();
    addTearDown(controller.dispose);
    controller.setViewport(const FlowViewport(x: 12, y: 24, zoom: 1.5));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: FFlowMiniMap<String>(
            nodes: const [],
            controller: controller,
            viewportSize: const Size(200, 100),
          ),
        ),
      ),
    ));

    await tester.tap(find.byType(FFlowMiniMap<String>));
    await tester.pump();

    expect(controller.viewport, const FlowViewport(x: 12, y: 24, zoom: 1.5));
  });
}
