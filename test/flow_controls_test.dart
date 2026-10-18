import 'package:fflow/fflow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('controls zoom, fit the graph, and report lock changes',
      (tester) async {
    final controller = FlowCanvasController();
    addTearDown(controller.dispose);
    const nodes = [
      FlowNode<String>(
        id: 'first',
        position: Offset(100, 120),
        data: 'first',
        width: 100,
        height: 80,
      ),
      FlowNode<String>(
        id: 'last',
        position: Offset(500, 400),
        data: 'last',
        width: 120,
        height: 80,
      ),
    ];
    final lockChanges = <bool>[];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: FFlowControls<String>(
            controller: controller,
            nodes: nodes,
            viewportSize: const Size(800, 600),
            locked: false,
            onLockChanged: lockChanges.add,
            additionalControls: [
              IconButton(
                tooltip: 'Extra action',
                onPressed: () {},
                icon: const Icon(Icons.star),
              ),
            ],
          ),
        ),
      ),
    ));

    await tester.tap(find.byTooltip('Zoom in'));
    await tester.pump();
    expect(controller.viewport.zoom, closeTo(1.2, 1e-10));

    await tester.tap(find.byTooltip('Zoom out'));
    await tester.pump();
    expect(controller.viewport.zoom, closeTo(1, 1e-10));

    await tester.tap(find.byTooltip('Fit graph to view'));
    await tester.pump();
    expect(
      controller.viewport,
      FlowGraphUtils.getViewportForBounds(
        const Rect.fromLTWH(100, 120, 520, 360),
        const Size(800, 600),
        padding: 72,
      ),
    );

    await tester.tap(find.byTooltip('Lock canvas'));
    expect(lockChanges, [true]);
    expect(find.byTooltip('Extra action'), findsOneWidget);
  });
}
