import 'dart:ui' as ui;

import 'package:fflow/fflow.dart';
import 'package:fflow/fflow_capture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('captures a painted FFlow canvas repeatedly as PNG',
      (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: RepaintBoundary(
          key: key,
          child: SizedBox(
            width: 400,
            height: 200,
            child: FFlowCanvas<String>(
              nodes: const [
                FlowNode(id: 'a', position: Offset(20, 40), data: '中文'),
              ],
              edges: const [],
              nodeBuilder: (context, node, selected) => Text(node.data),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      for (var i = 0; i < 3; i++) {
        final bytes = await captureFlowPng(key, pixelRatio: 2);
        expect(bytes.sublist(0, 8), [137, 80, 78, 71, 13, 10, 26, 10]);
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 800);
        expect(frame.image.height, 400);
        frame.image.dispose();
        codec.dispose();
      }
      await expectLater(captureFlowPng(key, maxPixels: 10), throwsStateError);
    });
  });

  testWidgets('rejects a missing boundary', (tester) async {
    await expectLater(captureFlowPng(GlobalKey()), throwsStateError);
  });

  testWidgets('rejects a failed widget build and permits a subsequent capture',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await expectLater(
        captureFlowOffscreen(
          view: tester.view,
          size: const Size(50, 50),
          child: Builder(builder: (_) => throw StateError('broken node')),
        ),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('broken node'))),
      );
      final bytes = await captureFlowOffscreen(
        view: tester.view,
        size: const Size(50, 50),
        child: const ColoredBox(color: Colors.red),
      );
      expect(bytes.sublist(0, 4), [137, 80, 78, 71]);
    });
  });

  testWidgets('paint exceptions fail capture and restore host error handler',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    final handler = FlutterError.onError;
    await tester.runAsync(() async {
      await expectLater(
        captureFlowOffscreen(
          view: tester.view,
          size: const Size(50, 50),
          child: CustomPaint(painter: _BrokenPainter()),
        ),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('broken paint'))),
      );
    });
    expect(FlutterError.onError, same(handler));
  });

  testWidgets('detached pipeline paints canvas beyond the host view repeatedly',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      for (var i = 0; i < 20; i++) {
        final bytes = await captureFlowOffscreen(
          view: tester.view,
          size: const Size(1400, 300),
          pixelRatio: 1,
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: FFlowCanvas<String>(
              backgroundColor: Colors.white,
              nodes: const [
                FlowNode(
                    id: 'near',
                    position: Offset(20, 60),
                    data: 'near',
                    width: 120,
                    height: 80),
                FlowNode(
                    id: 'far',
                    position: Offset(1100, 60),
                    data: '中文',
                    width: 120,
                    height: 80),
              ],
              edges: const [
                FlowEdge(
                    id: 'edge',
                    sourceId: 'near',
                    targetId: 'far',
                    type: FlowEdgeType.straight),
              ],
              nodeBuilder: (context, node, selected) => const ColoredBox(
                color: Colors.red,
                child: Center(child: Text('中文')),
              ),
            ),
          ),
        );
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, 1400);
        final pixels = (await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final offset = (80 * 1400 + 1120) * 4;
        expect(pixels.getUint8(offset), 244);
        expect(pixels.getUint8(offset + 1), 67);
        expect(pixels.getUint8(offset + 2), 54);
        final edgeOffset = (100 * 1400 + 500) * 4;
        expect(pixels.getUint8(edgeOffset), lessThan(200),
            reason: 'The edge painter must use the scene origin after layout');
        frame.image.dispose();
        codec.dispose();
      }
    });
  });

  testWidgets('detached canvas releases its recorded pictures', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final previousCreate = ui.Picture.onCreate;
    final previousDispose = ui.Picture.onDispose;
    var created = 0;
    var disposed = 0;
    ui.Picture.onCreate = (_) => created++;
    ui.Picture.onDispose = (_) => disposed++;
    try {
      await tester.runAsync(() async {
        for (var i = 0; i < 5; i++) {
          await captureFlowOffscreen(
            view: tester.view,
            size: const Size(1400, 300),
            pixelRatio: 1,
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: FFlowCanvas<String>(
                nodes: const [
                  FlowNode(id: 'a', position: Offset(20, 20), data: 'a')
                ],
                edges: const [],
                nodeBuilder: (_, node, selected) =>
                    const ColoredBox(color: Colors.red),
              ),
            ),
          );
        }
      });
      expect(created, greaterThan(0));
      expect(disposed, created,
          reason: 'All detached render layers must release their pictures');
    } finally {
      ui.Picture.onCreate = previousCreate;
      ui.Picture.onDispose = previousDispose;
    }
  });
}

class _BrokenPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) => throw StateError('broken paint');

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
