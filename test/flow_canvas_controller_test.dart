import 'package:fflow/fflow.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _ViewportAnimationHarness extends StatefulWidget {
  const _ViewportAnimationHarness();

  @override
  State<_ViewportAnimationHarness> createState() =>
      _ViewportAnimationHarnessState();
}

class _ViewportAnimationHarnessState extends State<_ViewportAnimationHarness>
    with TickerProviderStateMixin {
  final controller = FlowCanvasController();

  Future<bool> animate(FlowViewport target) => controller.animateToViewport(
        target,
        vsync: this,
        duration: const Duration(milliseconds: 200),
      );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

void main() {
  test('converts between screen and graph coordinates with scene padding', () {
    final controller = FlowCanvasController();
    addTearDown(controller.dispose);
    controller
      ..updateSceneOrigin(const Offset(32, 48))
      ..setViewport(const FlowViewport(x: 12, y: -6, zoom: 2));

    const flowPoint = Offset(70, 100);
    final screenPoint = controller.flowToScreenPosition(flowPoint);

    expect(screenPoint, const Offset(152, 194));
    expect(controller.screenToFlowPosition(screenPoint), flowPoint);
    expect(controller.viewport, const FlowViewport(x: 12, y: -6, zoom: 2));
  });

  test('clamps zoom and keeps the focal graph point in place', () {
    final controller = FlowCanvasController();
    addTearDown(controller.dispose);
    controller
      ..updateViewportSize(const Size(800, 600))
      ..setViewport(const FlowViewport(x: -40, y: 20, zoom: 1));

    const focalPoint = Offset(250, 175);
    final graphPoint = controller.screenToFlowPosition(focalPoint);
    controller.zoomTo(4, focalPoint: focalPoint, maxZoom: 2);

    expect(controller.viewport.zoom, 2);
    expect(controller.screenToFlowPosition(focalPoint), graphPoint);

    controller.zoomTo(0.01, focalPoint: focalPoint, minZoom: 0.5);
    expect(controller.viewport.zoom, 0.5);
    expect(controller.screenToFlowPosition(focalPoint), graphPoint);
  });

  test('pan, center, and fit helpers update the viewport consistently', () {
    final controller = FlowCanvasController();
    addTearDown(controller.dispose);
    const viewportSize = Size(800, 600);

    controller
      ..setViewport(const FlowViewport(x: 10, y: 20, zoom: 1))
      ..panBy(const Offset(30, -15));
    expect(controller.viewport, const FlowViewport(x: 40, y: 5, zoom: 1));

    controller.centerAt(const Offset(500, 300), viewportSize, zoom: 2);
    expect(controller.viewport, const FlowViewport(x: -600, y: -300, zoom: 2));
    expect(
      controller.flowToScreenPosition(const Offset(500, 300)),
      const Offset(400, 300),
    );

    const nodes = [
      FlowNode<String>(
        id: 'a',
        position: Offset(100, 200),
        data: 'a',
        width: 100,
        height: 80,
      ),
      FlowNode<String>(
        id: 'b',
        position: Offset(500, 400),
        data: 'b',
        width: 120,
        height: 80,
      ),
    ];
    controller.fitView(nodes, viewportSize, padding: 40);
    expect(
      controller.viewport,
      FlowGraphUtils.getViewportForBounds(
        const Rect.fromLTWH(100, 200, 520, 280),
        viewportSize,
        padding: 40,
      ),
    );
  });

  test('setCenter waits for a usable viewport size', () {
    final controller = FlowCanvasController();
    addTearDown(controller.dispose);

    controller.setCenter(100, 50);
    expect(controller.viewport, const FlowViewport(x: 0, y: 0, zoom: 1));

    controller
      ..updateViewportSize(const Size(400, 200))
      ..setCenter(100, 50, zoom: 2);
    expect(controller.viewport, const FlowViewport(x: 0, y: 0, zoom: 2));
    expect(
      controller.flowToScreenPosition(const Offset(100, 50)),
      const Offset(200, 100),
    );
  });

  testWidgets('viewport animation completes and reports interruption',
      (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: _ViewportAnimationHarness()));
    final state = tester.state<_ViewportAnimationHarnessState>(
      find.byType(_ViewportAnimationHarness),
    );

    final completed =
        state.animate(const FlowViewport(x: 100, y: -50, zoom: 1.5));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(await completed, isTrue);
    expect(state.controller.viewport,
        const FlowViewport(x: 100, y: -50, zoom: 1.5));

    final interrupted =
        state.animate(const FlowViewport(x: 300, y: 250, zoom: 2));
    await tester.pump(const Duration(milliseconds: 50));
    state.controller.panBy(const Offset(5, 0));
    await tester.pumpAndSettle();
    expect(await interrupted, isFalse);
  });
}
