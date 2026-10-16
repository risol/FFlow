import 'package:fflow/fflow.dart';
import 'package:fflow/src/rendering/flow_port.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a distant node button remains tappable after centering',
      (tester) async {
    var presses = 0;
    final controller = FlowCanvasController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: FFlowCanvas<String>(
            controller: controller,
            nodes: const [
              FlowNode<String>(
                id: 'remote',
                position: Offset(2000, 1800),
                data: 'remote',
                width: 180,
                height: 100,
              ),
            ],
            edges: const [],
            nodeBuilder: (context, node, selected) => Center(
              child: ElevatedButton(
                key: const ValueKey('remote-button'),
                onPressed: () => presses++,
                child: Text(node.data),
              ),
            ),
          ),
        ),
      ),
    ));

    await tester.pumpAndSettle();
    controller.centerAt(const Offset(2090, 1850), const Size(800, 600));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('remote-button')));
    await tester.pump(const Duration(milliseconds: 400));

    expect(presses, 1);
  });

  testWidgets('distant port, drag handle, and resize handle remain interactive',
      (tester) async {
    final controller = FlowCanvasController();
    addTearDown(controller.dispose);
    final nodeChanges = <List<FlowNodeChange<String>>>[];
    final resizeEvents = <FlowNode<String>>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: FFlowCanvas<String>(
            controller: controller,
            nodes: const [
              FlowNode<String>(
                id: 'remote',
                position: Offset(2000, 1800),
                data: 'remote',
                width: 180,
                height: 100,
                selected: true,
                resizable: true,
                dragHandleOnly: true,
              ),
            ],
            edges: const [],
            nodeBuilder: (context, node, selected) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FFlowNodeDragHandle(
                  child: SizedBox(
                    key: const ValueKey('remote-drag-handle'),
                    width: 100,
                    height: 24,
                    child: Text(node.data),
                  ),
                ),
              ],
            ),
            onNodesChange: nodeChanges.add,
            onNodeResize: resizeEvents.add,
          ),
        ),
      ),
    ));
    controller.centerAt(const Offset(2090, 1850), const Size(800, 600));
    await tester.pumpAndSettle();

    final sourcePort = tester.widget<FlowPort>(find.byType(FlowPort).last);
    expect(sourcePort.enabled, isTrue);
    expect(sourcePort.onPanStart, isNotNull);
    final sourceHandle =
        controller.flowToScreenPosition(const Offset(2180, 1850));
    expect(tester.getRect(find.byType(FlowPort).last).contains(sourceHandle),
        isTrue);
    expect(
      tester.hitTestOnBinding(sourceHandle).path.first.target,
      isA<RenderDecoratedBox>(),
    );

    final dragHandle =
        tester.getCenter(find.byKey(const ValueKey('remote-drag-handle')));
    await tester.dragFrom(dragHandle, const Offset(40, 20));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      nodeChanges
          .expand((batch) => batch)
          .any((change) => change.type == FlowNodeChangeType.position),
      isTrue,
    );

    final resizedNodePosition = nodeChanges
        .expand((batch) => batch)
        .where((change) => change.type == FlowNodeChangeType.position)
        .last
        .position!;
    final bottomRight = controller.flowToScreenPosition(
      resizedNodePosition + const Offset(180, 100),
    );
    await tester.dragFrom(bottomRight, const Offset(30, 20));
    await tester.pump(const Duration(milliseconds: 400));
    expect(resizeEvents, isNotEmpty);
  });

  testWidgets('FFlowNoDrag lets a nested TextField receive input and drag',
      (tester) async {
    final nodeChanges = <List<FlowNodeChange<String>>>[];
    final controller = FlowCanvasController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: FFlowCanvas<String>(
            controller: controller,
            nodes: const [
              FlowNode<String>(
                id: 'editor',
                position: Offset(40, 40),
                data: 'editor',
                width: 240,
                height: 130,
              ),
            ],
            edges: const [],
            nodeBuilder: (context, node, selected) => const Padding(
              padding: EdgeInsets.all(12),
              child: FFlowNoDrag(
                child: FFlowNoWheel(
                  child: TextField(
                    key: ValueKey('editor-field'),
                    decoration: InputDecoration(labelText: 'Value'),
                  ),
                ),
              ),
            ),
            onNodesChange: nodeChanges.add,
          ),
        ),
      ),
    ));

    final field = find.byKey(const ValueKey('editor-field'));
    await tester.tap(field);
    await tester.enterText(field, 'typed value');
    await tester.drag(field, const Offset(60, 20));
    await tester.pumpAndSettle();

    expect(find.text('typed value'), findsOneWidget);
    expect(
      nodeChanges.expand((batch) => batch).where(
            (change) => change.type == FlowNodeChangeType.position,
          ),
      isEmpty,
    );

    final zoomBeforeScroll = controller.viewport.zoom;
    tester.binding.handlePointerEvent(PointerScrollEvent(
      position: tester.getCenter(field),
      scrollDelta: const Offset(0, -200),
    ));
    await tester.pump();
    expect(controller.viewport.zoom, zoomBeforeScroll);

    tester.binding.handlePointerEvent(const PointerScrollEvent(
      position: Offset(700, 500),
      scrollDelta: Offset(0, -200),
    ));
    await tester.pump();
    expect(controller.viewport.zoom, greaterThan(zoomBeforeScroll));
  });

  testWidgets('FFlowNoDrag preserves nested slider and scroll view gestures',
      (tester) async {
    final controller = FlowCanvasController();
    final scrollController = ScrollController();
    addTearDown(controller.dispose);
    addTearDown(scrollController.dispose);
    final nodeChanges = <List<FlowNodeChange<String>>>[];
    var sliderValue = 20.0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: FFlowCanvas<String>(
            controller: controller,
            nodes: const [
              FlowNode<String>(
                id: 'controls',
                position: Offset(40, 40),
                data: 'controls',
                width: 260,
                height: 280,
              ),
            ],
            edges: const [],
            nodeBuilder: (context, node, selected) => FFlowNoDrag(
              child: FFlowNoWheel(
                child: Column(
                  children: [
                    Slider(
                      key: const ValueKey('nested-slider'),
                      value: sliderValue,
                      min: 0,
                      max: 100,
                      onChanged: (value) => sliderValue = value,
                    ),
                    SizedBox(
                      height: 150,
                      child: ListView.builder(
                        key: const ValueKey('nested-scroll-view'),
                        controller: scrollController,
                        itemCount: 20,
                        itemBuilder: (context, index) => SizedBox(
                          height: 36,
                          child: Text('Row $index'),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            onNodesChange: nodeChanges.add,
          ),
        ),
      ),
    ));

    await tester.drag(
        find.byKey(const ValueKey('nested-slider')), const Offset(70, 0));
    await tester.pumpAndSettle();
    await tester.drag(
        find.byKey(const ValueKey('nested-scroll-view')), const Offset(0, -70));
    await tester.pumpAndSettle();

    expect(sliderValue, greaterThan(20));
    expect(scrollController.offset, greaterThan(0));
    expect(
      nodeChanges.expand((batch) => batch).where(
            (change) => change.type == FlowNodeChangeType.position,
          ),
      isEmpty,
    );
  });

  testWidgets('FFlowNoDrag preserves button, checkbox, and dropdown input',
      (tester) async {
    final controller = FlowCanvasController();
    addTearDown(controller.dispose);
    final nodeChanges = <List<FlowNodeChange<String>>>[];
    var buttonPresses = 0;
    bool? checkboxValue;
    String dropdownValue = 'one';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: FFlowCanvas<String>(
            controller: controller,
            nodes: const [
              FlowNode<String>(
                id: 'controls',
                position: Offset(40, 40),
                data: 'controls',
                width: 300,
                height: 240,
                hasInput: false,
                hasOutput: false,
              ),
            ],
            edges: const [],
            nodeBuilder: (context, node, selected) => FFlowNoDrag(
              child: FFlowNoWheel(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton(
                      key: const ValueKey('nested-button'),
                      onPressed: () => buttonPresses++,
                      child: const Text('Press'),
                    ),
                    Checkbox(
                      key: const ValueKey('nested-checkbox'),
                      value: checkboxValue ?? false,
                      onChanged: (value) => checkboxValue = value,
                    ),
                    DropdownButton<String>(
                      key: const ValueKey('nested-dropdown'),
                      value: dropdownValue,
                      items: const [
                        DropdownMenuItem(value: 'one', child: Text('One')),
                        DropdownMenuItem(value: 'two', child: Text('Two')),
                      ],
                      onChanged: (value) {
                        if (value != null) dropdownValue = value;
                      },
                    ),
                  ],
                ),
              ),
            ),
            onNodesChange: nodeChanges.add,
          ),
        ),
      ),
    ));

    final button = find.byKey(const ValueKey('nested-button'));
    await tester.tap(button);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nested-checkbox')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('One'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Two').last);
    await tester.pumpAndSettle();
    await tester.drag(button, const Offset(40, 0));
    await tester.pumpAndSettle();

    expect(buttonPresses, 1);
    expect(checkboxValue, isTrue);
    expect(dropdownValue, 'two');
    expect(
      nodeChanges.expand((batch) => batch).where(
            (change) => change.type == FlowNodeChangeType.position,
          ),
      isEmpty,
    );
  });

  testWidgets('node double click remains available without delaying child taps',
      (tester) async {
    var doubleClicks = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: FFlowCanvas<String>(
            nodes: const [
              FlowNode<String>(
                id: 'node',
                position: Offset(40, 40),
                data: 'node',
                width: 120,
                height: 80,
                hasInput: false,
                hasOutput: false,
              ),
            ],
            edges: const [],
            nodeBuilder: (context, node, selected) =>
                Center(child: Text(node.data)),
            onNodeDoubleClick: (_) => doubleClicks++,
          ),
        ),
      ),
    ));

    final node = find.text('node');
    await tester.tap(node);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(node);
    await tester.pumpAndSettle();

    expect(doubleClicks, 1);
  });

  testWidgets('node drag threshold leaves pointer jitter as a click',
      (tester) async {
    final nodeChanges = <List<FlowNodeChange<String>>>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: FFlowCanvas<String>(
            nodes: const [
              FlowNode<String>(
                id: 'node',
                position: Offset(20, 20),
                data: 'node',
                width: 120,
                height: 80,
              ),
            ],
            edges: const [],
            nodeDragThreshold: 8,
            nodeBuilder: (context, node, selected) =>
                Center(child: Text(node.data)),
            onNodesChange: nodeChanges.add,
          ),
        ),
      ),
    ));

    final gesture =
        await tester.startGesture(tester.getCenter(find.text('node')));
    await gesture.moveBy(const Offset(2, 1));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      nodeChanges.expand((batch) => batch).where(
            (change) => change.type == FlowNodeChangeType.position,
          ),
      isEmpty,
    );
  });

  testWidgets('overlapping node drag keeps the topmost down target captured',
      (tester) async {
    var latestNodes = const <FlowNode<String>>[];
    const nodes = [
      FlowNode<String>(
        id: 'bottom',
        position: Offset(40, 40),
        data: 'bottom',
        width: 160,
        height: 120,
      ),
      FlowNode<String>(
        id: 'top',
        position: Offset(100, 40),
        data: 'top',
        width: 160,
        height: 120,
        zIndex: 2,
      ),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: FFlowCanvas<String>(
            nodes: nodes,
            edges: const [],
            nodeBuilder: (context, node, selected) =>
                Center(child: Text(node.data)),
            onNodesChanged: (value) => latestNodes = value,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    const start = Offset(130, 90);
    final gesture = await tester.startGesture(start);
    await gesture.moveTo(start + const Offset(-80, 0));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(latestNodes.singleWhere((node) => node.id == 'bottom').position,
        const Offset(40, 40));
    expect(latestNodes.singleWhere((node) => node.id == 'top').position,
        const Offset(20, 40));
  });

  testWidgets('dragging a selected node moves its selected group',
      (tester) async {
    var latestNodes = const <FlowNode<String>>[];
    const nodes = [
      FlowNode<String>(
        id: 'selected-a',
        position: Offset(40, 40),
        data: 'A',
        width: 120,
        height: 80,
        selected: true,
      ),
      FlowNode<String>(
        id: 'selected-b',
        position: Offset(220, 40),
        data: 'B',
        width: 120,
        height: 80,
        selected: true,
      ),
      FlowNode<String>(
        id: 'unselected-c',
        position: Offset(400, 40),
        data: 'C',
        width: 120,
        height: 80,
      ),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: FFlowCanvas<String>(
            nodes: nodes,
            edges: const [],
            nodeBuilder: (context, node, selected) =>
                Center(child: Text(node.data)),
            onNodesChanged: (value) => latestNodes = value,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    const start = Offset(80, 70);
    final gesture = await tester.startGesture(start);
    await gesture.moveTo(start + const Offset(40, 20));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(
      latestNodes.singleWhere((node) => node.id == 'selected-a').position,
      const Offset(80, 60),
    );
    expect(
      latestNodes.singleWhere((node) => node.id == 'selected-b').position,
      const Offset(260, 60),
    );
    expect(
      latestNodes.singleWhere((node) => node.id == 'unselected-c').position,
      const Offset(400, 40),
    );
  });

  testWidgets('selected elevation and hit testing use the same paint order',
      (tester) async {
    var latestNodes = const <FlowNode<String>>[];
    const nodes = [
      FlowNode<String>(
        id: 'selected',
        position: Offset(80, 60),
        data: 'selected',
        width: 160,
        height: 120,
        selected: true,
      ),
      FlowNode<String>(
        id: 'later-in-list',
        position: Offset(80, 60),
        data: 'later',
        width: 160,
        height: 120,
      ),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: FFlowCanvas<String>(
            nodes: nodes,
            edges: const [],
            fitViewOnInit: false,
            defaultViewport: const FlowViewport(x: 0, y: 0, zoom: 1),
            elevateNodesOnSelect: true,
            nodeBuilder: (context, node, selected) =>
                Center(child: Text(node.data)),
            onNodesChanged: (value) => latestNodes = value,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    const start = Offset(120, 100);
    final gesture = await tester.startGesture(start);
    await gesture.moveTo(start + const Offset(30, 15));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(latestNodes.singleWhere((node) => node.id == 'selected').position,
        const Offset(110, 75));
    expect(
      latestNodes.singleWhere((node) => node.id == 'later-in-list').position,
      const Offset(80, 60),
    );
  });

  testWidgets('dragging a parent moves its child in scene space',
      (tester) async {
    var latestNodes = const <FlowNode<String>>[];
    const nodes = [
      FlowNode<String>(
        id: 'parent',
        position: Offset(100, 100),
        data: 'parent',
        width: 240,
        height: 180,
        hasInput: false,
        hasOutput: false,
        groupable: true,
      ),
      FlowNode<String>(
        id: 'child',
        position: Offset(40, 50),
        data: 'child',
        width: 80,
        height: 60,
        hasInput: false,
        hasOutput: false,
        parentId: 'parent',
      ),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: FFlowCanvas<String>(
            nodes: nodes,
            edges: const [],
            fitViewOnInit: false,
            defaultViewport: const FlowViewport(x: 0, y: 0, zoom: 1),
            nodeBuilder: (context, node, selected) =>
                Center(child: Text(node.data)),
            onNodesChanged: (value) => latestNodes = value,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    const start = Offset(115, 115);
    final gesture = await tester.startGesture(start);
    await gesture.moveTo(start + const Offset(30, 20));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(latestNodes.singleWhere((node) => node.id == 'parent').position,
        const Offset(130, 120));
    expect(latestNodes.singleWhere((node) => node.id == 'child').position,
        const Offset(40, 50));
  });

  testWidgets('negative-coordinate node dragging respects zoom and origin',
      (tester) async {
    final controller = FlowCanvasController();
    addTearDown(controller.dispose);
    var latestNodes = const <FlowNode<String>>[];
    const initial = FlowNode<String>(
      id: 'negative',
      position: Offset(-2400, -1400),
      data: 'negative',
      width: 120,
      height: 80,
      origin: Offset(.5, .5),
      hasInput: false,
      hasOutput: false,
    );
    latestNodes = const [initial];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: FFlowCanvas<String>(
            controller: controller,
            nodes: const [initial],
            edges: const [],
            fitViewOnInit: false,
            nodeBuilder: (context, node, selected) =>
                Center(child: Text(node.data)),
            onNodesChanged: (value) => latestNodes = value,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    for (final (zoom, screenDelta) in <(double, Offset)>[
      (.25, const Offset(40, 20)),
      (2, const Offset(40, 20)),
    ]) {
      controller.centerAt(initial.position, const Size(800, 600), zoom: zoom);
      await tester.pumpAndSettle();
      final current = latestNodes.singleWhere((node) => node.id == 'negative');
      final start = controller.flowToScreenPosition(current.position);
      final gesture = await tester.startGesture(start);
      await gesture.moveTo(start + screenDelta);
      await gesture.up();
      await tester.pumpAndSettle();
      final expectedDelta = screenDelta / zoom;
      expect(
        latestNodes.singleWhere((node) => node.id == 'negative').position,
        current.position + expectedDelta,
      );
    }
  });

  testWidgets('pointer cancel ends and releases a node drag', (tester) async {
    var latestNodes = const <FlowNode<String>>[];
    final dragEnds = <FlowNode<String>>[];
    const initial = FlowNode<String>(
      id: 'node',
      position: Offset(40, 40),
      data: 'node',
      width: 120,
      height: 80,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: FFlowCanvas<String>(
            nodes: const [initial],
            edges: const [],
            nodeBuilder: (context, node, selected) =>
                Center(child: Text(node.data)),
            onNodesChanged: (value) => latestNodes = value,
            onNodeDragEnd: dragEnds.add,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    const firstStart = Offset(100, 80);
    final cancelled = await tester.startGesture(firstStart);
    await cancelled.moveTo(firstStart + const Offset(40, 0));
    await tester.pump();
    await cancelled.cancel();
    await tester.pumpAndSettle();
    final afterCancel =
        latestNodes.singleWhere((node) => node.id == 'node').position;
    expect(afterCancel.dx, greaterThan(initial.position.dx));
    expect(dragEnds, hasLength(1));
  });

  testWidgets('focus loss cancels a captured node drag', (tester) async {
    final canvasController = FlowCanvasController();
    final outsideFocus = FocusNode();
    addTearDown(canvasController.dispose);
    addTearDown(outsideFocus.dispose);
    final dragEnds = <FlowNode<String>>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: FFlowCanvas<String>(
                controller: canvasController,
                nodes: const [
                  FlowNode<String>(
                    id: 'node',
                    position: Offset(40, 40),
                    data: 'node',
                    width: 120,
                    height: 80,
                  ),
                ],
                edges: const [],
                nodeBuilder: (context, node, selected) =>
                    Center(child: Text(node.data)),
                onNodeDragEnd: dragEnds.add,
              ),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Focus(
                focusNode: outsideFocus,
                child: const SizedBox(width: 1, height: 1),
              ),
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(const Offset(100, 80));
    await gesture.moveTo(const Offset(130, 80));
    await tester.pump();
    outsideFocus.requestFocus();
    await tester.pump();

    expect(dragEnds, hasLength(1));
    await gesture.cancel();
    await tester.pumpAndSettle();
    expect(dragEnds, hasLength(1));
  });

  testWidgets('auto-pan continues for a stationary edge pointer',
      (tester) async {
    final controller = FlowCanvasController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: FFlowCanvas<String>(
            controller: controller,
            nodes: const [
              FlowNode<String>(
                id: 'node',
                position: Offset(40, 40),
                data: 'node',
                width: 120,
                height: 80,
              ),
            ],
            edges: const [],
            nodeBuilder: (context, node, selected) => Text(node.data),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final drag = await tester.startGesture(const Offset(100, 80));
    await drag.moveTo(const Offset(780, 300));
    await tester.pump();
    final beforeHold = controller.viewport.x;
    await tester.pump(const Duration(milliseconds: 500));
    final afterHold = controller.viewport.x;
    expect(afterHold, lessThan(beforeHold));

    await drag.up();
    await tester.pumpAndSettle();
    final afterRelease = controller.viewport.x;
    await tester.pump(const Duration(milliseconds: 300));
    expect(controller.viewport.x, closeTo(afterRelease, 0.01));
  });

  testWidgets('two-finger pinch still changes the viewport scale',
      (tester) async {
    final controller = FlowCanvasController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: FFlowCanvas<String>(
            controller: controller,
            nodes: const [],
            edges: const [],
            nodeBuilder: (context, node, selected) => const SizedBox.shrink(),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final first = await tester.startGesture(
      const Offset(300, 300),
      pointer: 1,
    );
    final second = await tester.startGesture(
      const Offset(500, 300),
      pointer: 2,
    );
    await tester.pump();
    await first.moveTo(const Offset(250, 300));
    await second.moveTo(const Offset(550, 300));
    await tester.pump();

    expect(controller.viewport.zoom, greaterThan(1));
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
  });

  testWidgets('connection drag threshold ignores a short handle movement',
      (tester) async {
    final starts = <FlowConnectionStart>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: FFlowCanvas<String>(
            nodes: const [
              FlowNode<String>(
                id: 'source',
                position: Offset(40, 40),
                data: 'source',
                width: 100,
                height: 60,
                hasInput: false,
              ),
            ],
            edges: const [],
            connectionDragThreshold: 80,
            nodeBuilder: (context, node, selected) => Text(node.data),
            onConnectStart: starts.add,
          ),
        ),
      ),
    ));

    await tester.dragFrom(const Offset(140, 70), const Offset(30, 0));
    await tester.pump(const Duration(milliseconds: 400));

    expect(starts, isEmpty);
  });

  testWidgets('selected edges can reconnect either endpoint', (tester) async {
    const nodes = [
      FlowNode<String>(
        id: 'source-a',
        position: Offset(30, 30),
        data: 'source-a',
        width: 100,
        height: 60,
        hasInput: false,
      ),
      FlowNode<String>(
        id: 'source-b',
        position: Offset(30, 170),
        data: 'source-b',
        width: 100,
        height: 60,
        hasInput: false,
      ),
      FlowNode<String>(
        id: 'target-a',
        position: Offset(330, 30),
        data: 'target-a',
        width: 100,
        height: 60,
        hasOutput: false,
      ),
      FlowNode<String>(
        id: 'target-b',
        position: Offset(330, 170),
        data: 'target-b',
        width: 100,
        height: 60,
        hasOutput: false,
      ),
    ];
    const originalEdge = FlowEdge(
      id: 'edge',
      sourceId: 'source-a',
      targetId: 'target-a',
      type: FlowEdgeType.straight,
      selected: true,
    );
    final reconnects = <FlowEdge>[];
    final reconnectEnds = <FlowConnectionEnd>[];
    var allowReconnect = true;
    final controller = FlowCanvasController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: FFlowCanvas<String>(
            controller: controller,
            nodes: nodes,
            edges: const [originalEdge],
            connectionDragThreshold: 1,
            nodeBuilder: (context, node, selected) => Text(node.data),
            isValidConnection: (_) => allowReconnect,
            onReconnect: reconnects.add,
            onReconnectEnd: reconnectEnds.add,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final nodeMap = {for (final node in nodes) node.id: node};
    final sourceB = nodeMap['source-b']!;
    final sourceBHandle = FlowGeometry.handleFor(
      sourceB,
      null,
      FlowHandleType.source,
    )!;
    final sourceBPoint = FlowGeometry.handleAnchor(sourceB, sourceBHandle);
    final sourcePoint = FlowGeometry.edgeSource(originalEdge, nodeMap)!;
    await tester.dragFrom(sourcePoint, sourceBPoint - sourcePoint);
    await tester.pumpAndSettle();
    expect(reconnects.last.sourceId, 'source-b');
    expect(reconnectEnds.last.cancelled, isFalse);

    final targetB = nodeMap['target-b']!;
    final targetBHandle = FlowGeometry.handleFor(
      targetB,
      null,
      FlowHandleType.target,
    )!;
    final targetBPoint = FlowGeometry.handleAnchor(targetB, targetBHandle);
    final updatedEdge = reconnects.last;
    final oldTargetPoint = FlowGeometry.edgeTarget(updatedEdge, nodeMap)!;
    await tester.dragFrom(
      oldTargetPoint,
      targetBPoint - oldTargetPoint,
    );
    await tester.pumpAndSettle();
    expect(reconnects.last.targetId, 'target-b');
    expect(reconnectEnds.last.cancelled, isFalse);

    allowReconnect = false;
    final sourceA = nodeMap['source-a']!;
    final sourceAHandle = FlowGeometry.handleFor(
      sourceA,
      null,
      FlowHandleType.source,
    )!;
    final currentEdge = reconnects.last;
    final currentSourcePoint = FlowGeometry.edgeSource(currentEdge, nodeMap)!;
    final sourceAPoint = FlowGeometry.handleAnchor(sourceA, sourceAHandle);
    final reconnectCount = reconnects.length;
    await tester.dragFrom(
      currentSourcePoint,
      sourceAPoint - currentSourcePoint,
    );
    await tester.pumpAndSettle();
    expect(reconnects, hasLength(reconnectCount));
    expect(reconnectEnds.last.cancelled, isTrue);
  });

  testWidgets('selection box can select an edge in partial mode',
      (tester) async {
    final selections = <FlowSelection>[];
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
                width: 60,
                height: 60,
                hasInput: false,
              ),
              FlowNode<String>(
                id: 'target',
                position: Offset(300, 20),
                data: 'target',
                width: 60,
                height: 60,
                hasOutput: false,
              ),
            ],
            edges: const [
              FlowEdge(
                id: 'edge',
                sourceId: 'source',
                targetId: 'target',
                type: FlowEdgeType.straight,
              ),
            ],
            nodeBuilder: (context, node, selected) =>
                Center(child: Text(node.data)),
            selectionOnDrag: true,
            edgeSelectionMode: FlowSelectionMode.partial,
            onSelectionChanged: selections.add,
          ),
        ),
      ),
    ));

    await tester.dragFrom(const Offset(120, 45), const Offset(150, 10));
    await tester.pumpAndSettle();

    expect(selections.last.edges, contains('edge'));
  });

  testWidgets('selection drag threshold keeps blank pointer jitter as a click',
      (tester) async {
    final starts = <Rect>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: FFlowCanvas<String>(
            nodes: const [],
            edges: const [],
            nodeBuilder: (context, node, selected) => const SizedBox.shrink(),
            selectionOnDrag: true,
            selectionDragThreshold: 5,
            onSelectionDragStart: starts.add,
          ),
        ),
      ),
    ));

    final jitter = await tester.startGesture(const Offset(500, 400));
    await jitter.moveTo(const Offset(503, 402));
    await jitter.up();
    await tester.pumpAndSettle();
    expect(starts, isEmpty);

    final drag = await tester.startGesture(const Offset(500, 400));
    await drag.moveTo(const Offset(510, 400));
    await drag.up();
    await tester.pumpAndSettle();
    expect(starts, hasLength(1));
  });

  testWidgets('full edge selection requires the whole path inside the box',
      (tester) async {
    final selections = <FlowSelection>[];
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
                width: 60,
                height: 60,
                hasInput: false,
              ),
              FlowNode<String>(
                id: 'target',
                position: Offset(300, 20),
                data: 'target',
                width: 60,
                height: 60,
                hasOutput: false,
              ),
            ],
            edges: const [
              FlowEdge(
                id: 'edge',
                sourceId: 'source',
                targetId: 'target',
                type: FlowEdgeType.straight,
              ),
            ],
            nodeBuilder: (context, node, selected) =>
                Center(child: Text(node.data)),
            selectionOnDrag: true,
            edgeSelectionMode: FlowSelectionMode.full,
            onSelectionChanged: selections.add,
          ),
        ),
      ),
    ));

    await tester.dragFrom(const Offset(120, 45), const Offset(150, 10));
    await tester.pumpAndSettle();

    expect(selections.last.edges, isEmpty);
  });

  testWidgets('Ctrl+A follows the default hidden element policy',
      (tester) async {
    final selections = <FlowSelection>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: FFlowCanvas<String>(
            nodes: const [
              FlowNode<String>(
                id: 'visible',
                position: Offset(20, 20),
                data: 'visible',
                width: 100,
                height: 60,
              ),
              FlowNode<String>(
                id: 'hidden',
                position: Offset(180, 20),
                data: 'hidden',
                width: 100,
                height: 60,
                hidden: true,
              ),
            ],
            edges: const [],
            nodeBuilder: (context, node, selected) => Text(node.data),
            onSelectionChanged: selections.add,
          ),
        ),
      ),
    ));

    await tester.tapAt(const Offset(500, 400));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(selections.last.nodes, {'visible'});
  });

  testWidgets('Escape clears selection and Delete removes selected nodes',
      (tester) async {
    final deleted = <FlowSelection>[];
    final selections = <FlowSelection>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 800,
          height: 600,
          child: FFlowCanvas<String>(
            nodes: const [
              FlowNode<String>(
                id: 'node',
                position: Offset(40, 40),
                data: 'node',
                width: 120,
                height: 80,
              ),
            ],
            edges: const [],
            nodeBuilder: (context, node, selected) => Text(node.data),
            onDelete: deleted.add,
            onSelectionChanged: selections.add,
          ),
        ),
      ),
    ));

    await tester.tap(find.text('node'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(selections.last.isEmpty, isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.pump();
    expect(deleted, isEmpty);

    await tester.tap(find.text('node'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(selections.last.nodes, {'node'});
    await tester.sendKeyDownEvent(LogicalKeyboardKey.delete);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.delete);
    await tester.pumpAndSettle();
    expect(deleted.single.nodes, {'node'});
  });
}
