import 'package:fflow/fflow.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const engine = FlowHitTestEngine();

  test('higher priority wins before paint order', () {
    const node =
        FlowHitTestResult(kind: FlowHitTargetKind.node, nodeId: 'node');
    const reconnect = FlowHitTestResult(
      kind: FlowHitTargetKind.reconnectHandle,
      edgeId: 'edge',
      sourceSide: true,
    );

    final result = engine.hitTest(
      const Offset(50, 50),
      regions: [
        const FlowHitTestRegion(
          result: node,
          bounds: Rect.fromLTWH(0, 0, 100, 100),
          priority: 1,
          paintOrder: 100,
        ),
        const FlowHitTestRegion(
          result: reconnect,
          bounds: Rect.fromLTWH(40, 40, 20, 20),
          priority: 2,
          paintOrder: 0,
        ),
      ],
    );

    expect(result.kind, FlowHitTargetKind.reconnectHandle);
    expect(result.edgeId, 'edge');
    expect(result.sourceSide, isTrue);
  });

  test('paint order breaks ties and precise regions can reject a hit', () {
    const back =
        FlowHitTestResult(kind: FlowHitTargetKind.node, nodeId: 'back');
    const front =
        FlowHitTestResult(kind: FlowHitTargetKind.node, nodeId: 'front');
    final regions = [
      FlowHitTestRegion(
        result: front,
        bounds: const Rect.fromLTWH(0, 0, 100, 100),
        priority: 1,
        paintOrder: 3,
        containsPoint: (point) => point.dx < 60,
      ),
      const FlowHitTestRegion(
        result: back,
        bounds: Rect.fromLTWH(0, 0, 100, 100),
        priority: 1,
        paintOrder: 1,
      ),
    ];

    expect(
      engine.hitTest(const Offset(50, 50), regions: regions).nodeId,
      'front',
    );
    expect(
      engine.hitTest(const Offset(80, 50), regions: regions).nodeId,
      'back',
    );
    expect(
      engine.hitTest(const Offset(120, 50), regions: regions).kind,
      FlowHitTargetKind.pane,
    );
  });

  test('result identifies node targets without treating pane as a node', () {
    const pane = FlowHitTestResult.pane();
    const node = FlowHitTestResult(kind: FlowHitTargetKind.node, nodeId: 'n');

    expect(pane.hasNode, isFalse);
    expect(node.hasNode, isTrue);
  });
}
