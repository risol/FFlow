import 'dart:ui' as ui;

import 'package:fflow/fflow.dart';
import 'package:fflow/fflow_capture.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('junction markers remain aligned after export normalization',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    final snapshot = FlowGraphSnapshot<String>(
      nodes: const [
        FlowNode(
            id: 'a',
            position: Offset(-100, -30),
            data: 'a',
            width: 100,
            height: 80),
        FlowNode(
            id: 'b',
            position: Offset(200, -30),
            data: 'b',
            width: 100,
            height: 80),
      ],
      edges: const [
        FlowEdge(
            id: 'e',
            sourceId: 'a',
            targetId: 'b',
            type: FlowEdgeType.straight,
            markerEnd: FlowEdgeMarker.arrowClosed,
            controlPoints: [Offset(20, 10), Offset(100, 10)],
            junctionPoints: [Offset(100, 10)])
      ],
      viewport: const FlowViewport(x: 0, y: 0, zoom: 1),
    );
    await tester.runAsync(() async {
      final result = await renderFlowSnapshot<String>(
        view: tester.view,
        snapshot: snapshot,
        pixelRatio: 1,
        nodeBuilder: (_, node, selected) => const ColoredBox(color: Colors.red),
      );
      final codec = await ui.instantiateImageCodec(result.bytes);
      final frame = await codec.getNextFrame();
      final pixels =
          (await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final x = (100 - result.graphBounds.left + 32).round();
      final y = (10 - result.graphBounds.top + 32).round();
      int redAt(int dy) =>
          pixels.getUint8(((y + dy) * frame.image.width + x) * 4);
      expect(redAt(-2), lessThan(200));
      expect(redAt(-6), 255);
      var arrowPixels = 0;
      for (var graphX = 63; graphX <= 73; graphX++) {
        for (var graphY = 12; graphY <= 14; graphY++) {
          final px = (graphX - result.graphBounds.left + 32).round();
          final py = (graphY - result.graphBounds.top + 32).round();
          if (pixels.getUint8((py * frame.image.width + px) * 4) < 200) {
            arrowPixels++;
          }
        }
      }
      expect(arrowPixels, greaterThan(0),
          reason: 'The incoming branch needs a direction arrow');
      frame.image.dispose();
      codec.dispose();
    });
  });
  testWidgets('export hides editor connection handles', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final snapshot = FlowGraphSnapshot<String>(
      nodes: const [
        FlowNode(
            id: 'a', position: Offset.zero, data: 'a', width: 100, height: 80),
      ],
      edges: const [],
      viewport: const FlowViewport(x: 0, y: 0, zoom: 1),
    );
    await tester.runAsync(() async {
      final result = await renderFlowSnapshot<String>(
        view: tester.view,
        snapshot: snapshot,
        pixelRatio: 1,
        backgroundColor: Colors.transparent,
        nodeBuilder: (_, node, selected) => const ColoredBox(color: Colors.red),
      );
      final codec = await ui.instantiateImageCodec(result.bytes);
      final frame = await codec.getNextFrame();
      final pixels =
          (await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      for (final x in [-5, 105]) {
        final px = (x - result.graphBounds.left + 32).round();
        final py = (40 - result.graphBounds.top + 32).round();
        expect(pixels.getUint8((py * frame.image.width + px) * 4 + 3), 0);
      }
      frame.image.dispose();
      codec.dispose();
    });
  });
  testWidgets('long edge labels avoid covering node interiors', (tester) async {
    await tester.pumpWidget(const SizedBox());
    final snapshot = FlowGraphSnapshot<String>(
      nodes: const [
        FlowNode(
            id: 'a', position: Offset.zero, data: 'a', width: 100, height: 80),
        FlowNode(
            id: 'b',
            position: Offset(148, 0),
            data: 'b',
            width: 100,
            height: 80),
      ],
      edges: [
        FlowEdge(
            id: 'e', sourceId: 'a', targetId: 'b', label: 'Long label ' * 12)
      ],
      viewport: const FlowViewport(x: 0, y: 0, zoom: 1),
    );
    await tester.runAsync(() async {
      final result = await renderFlowSnapshot<String>(
        view: tester.view,
        snapshot: snapshot,
        pixelRatio: 1,
        nodeBuilder: (_, node, selected) => const ColoredBox(color: Colors.red),
      );
      final codec = await ui.instantiateImageCodec(result.bytes);
      final frame = await codec.getNextFrame();
      final pixels =
          (await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      for (final x0 in [0, 148]) {
        for (var y = 20; y < 60; y++) {
          for (var x = x0 + 10; x < x0 + 90; x++) {
            final px = (x - result.graphBounds.left + 32).round();
            final py = (y - result.graphBounds.top + 32).round();
            final index = (py * frame.image.width + px) * 4;
            expect(pixels.getUint8(index), 244);
            expect(pixels.getUint8(index + 1), 67);
          }
        }
      }
      frame.image.dispose();
      codec.dispose();
    });
  });
  testWidgets(
      'transparent exports preserve alpha and enforce independent limits',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    final snapshot = FlowGraphSnapshot<String>(
      nodes: const [
        FlowNode(
            id: 'a', position: Offset.zero, data: 'a', width: 80, height: 48)
      ],
      edges: const [],
      viewport: const FlowViewport(x: 0, y: 0, zoom: 1),
    );
    await tester.runAsync(() async {
      final result = await renderFlowSnapshot<String>(
        view: tester.view,
        snapshot: snapshot,
        pixelRatio: 1,
        backgroundColor: Colors.transparent,
        title: 'Title',
        titleColor: Colors.black,
        nodeBuilder: (_, node, selected) => const ColoredBox(color: Colors.red),
      );
      final codec = await ui.instantiateImageCodec(result.bytes);
      final frame = await codec.getNextFrame();
      final pixels =
          (await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      expect(pixels.getUint8(3), 0);
      frame.image.dispose();
      codec.dispose();
      for (final limits in [
        (10, 8192, 32000000),
        (8192, 10, 32000000),
        (8192, 8192, 10)
      ]) {
        await expectLater(
            renderFlowSnapshot<String>(
              view: tester.view,
              snapshot: snapshot,
              pixelRatio: 1,
              maxWidth: limits.$1,
              maxHeight: limits.$2,
              maxPixels: limits.$3,
              nodeBuilder: (_, node, selected) => const SizedBox(),
            ),
            throwsA(anything));
      }
    });
  });
  testWidgets('snapshot export includes negative nodes and distant edge route',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    final original = FlowGraphSnapshot<String>(
      nodes: const [
        FlowNode(
            id: 'a',
            position: Offset(-500, -400),
            data: 'first',
            width: 100,
            height: 80),
        FlowNode(
            id: 'b',
            position: Offset(200, 100),
            data: 'second',
            width: 100,
            height: 80),
      ],
      edges: const [
        FlowEdge(
            id: 'ab',
            sourceId: 'a',
            targetId: 'b',
            controlPoints: [Offset(-800, -900), Offset(500, -900)],
            label: 'a long label for the exported connection'),
      ],
      viewport: const FlowViewport(x: 6000, y: 6000, zoom: 0.25),
    );
    final snapshot = FlowGraphSnapshot<String>.fromJson(
      original.toJson(encodeNodeData: (data) => data),
      decodeNodeData: (data) => data as String,
    );
    await tester.runAsync(() async {
      final result = await renderFlowSnapshot<String>(
        view: tester.view,
        snapshot: snapshot,
        pixelRatio: 1,
        nodeBuilder: (_, node, selected) => const ColoredBox(color: Colors.red),
      );
      expect(result.graphBounds.left, lessThan(-800));
      expect(result.graphBounds.top, lessThan(-900));
      expect(result.graphBounds.right, greaterThan(500));
      final codec = await ui.instantiateImageCodec(result.bytes);
      final frame = await codec.getNextFrame();
      final pixels = (await frame.image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      int redAt(double x, double y) {
        final px = (x - result.graphBounds.left + 32).round();
        final py = (y - result.graphBounds.top + 32).round();
        return pixels.getUint8((py * frame.image.width + px) * 4);
      }

      expect(redAt(-480, -380), 244);
      expect(redAt(220, 120), 244);
      expect(redAt(-400, -900), lessThan(200),
          reason: 'The distant routed edge must be painted inside the export');
      frame.image.dispose();
      codec.dispose();
    });
  });

  testWidgets('invalid graph is rejected before rendering', (tester) async {
    final snapshot = FlowGraphSnapshot<String>(nodes: const [], edges: const [
      FlowEdge(id: 'broken', sourceId: 'missing', targetId: 'missing'),
    ], viewport: const FlowViewport(x: 0, y: 0, zoom: 1));
    await expectLater(
        renderFlowSnapshot<String>(
          view: tester.view,
          snapshot: snapshot,
          nodeBuilder: (_, node, selected) => const SizedBox(),
        ),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('dangling-edge-source'))));
  });

  testWidgets('long labels expand the export and all pixel ratios are honored',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    final snapshot = FlowGraphSnapshot<String>(
      nodes: const [
        FlowNode(
            id: 'a', position: Offset.zero, data: 'a', width: 100, height: 80),
        FlowNode(
            id: 'b',
            position: Offset(150, 0),
            data: 'b',
            width: 100,
            height: 80),
      ],
      edges: [
        FlowEdge(id: 'e', sourceId: 'a', targetId: 'b', label: 'A' * 100)
      ],
      viewport: const FlowViewport(x: 0, y: 0, zoom: 1),
    );
    await tester.runAsync(() async {
      for (final ratio in [1.0, 2.0, 3.0]) {
        final result = await renderFlowSnapshot<String>(
          view: tester.view,
          snapshot: snapshot,
          pixelRatio: ratio,
          nodeBuilder: (_, node, selected) =>
              const ColoredBox(color: Colors.red),
        );
        expect(result.graphBounds.width, greaterThan(400));
        final codec = await ui.instantiateImageCodec(result.bytes);
        final frame = await codec.getNextFrame();
        expect(frame.image.width, result.logicalSize.width * ratio);
        expect(frame.image.height, result.logicalSize.height * ratio);
        frame.image.dispose();
        codec.dispose();
      }
    });
  });

  testWidgets('small graph at a large coordinate renders at bounded size',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    const originalPosition = Offset(1000000000000, -1000000000000);
    final snapshot = FlowGraphSnapshot<String>(
      nodes: const [
        FlowNode(
            id: 'a',
            position: originalPosition,
            data: 'a',
            width: 100,
            height: 80),
      ],
      edges: const [],
      viewport: const FlowViewport(x: 0, y: 0, zoom: 1),
    );
    await tester.runAsync(() async {
      final result = await renderFlowSnapshot<String>(
        view: tester.view,
        snapshot: snapshot,
        pixelRatio: 1,
        nodeBuilder: (_, node, selected) {
          expect(node.position, originalPosition);
          return const ColoredBox(color: Colors.red);
        },
      );
      expect(result.logicalSize.width, lessThan(300));
      final codec = await ui.instantiateImageCodec(result.bytes);
      final frame = await codec.getNextFrame();
      final data =
          (await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final offset = (68 * frame.image.width + 68) * 4;
      expect(data.getUint8(offset), 244);
      expect(data.getUint8(offset + 1), 67);
      frame.image.dispose();
      codec.dispose();
    });
    await expectLater(
        renderFlowSnapshot<String>(
          view: tester.view,
          snapshot: snapshot,
          gridSpacing: 0.00001,
          nodeBuilder: (_, node, selected) => const SizedBox(),
        ),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('background grid exceeds'))));
  });

  testWidgets('title expands the canvas and remains inside the image',
      (tester) async {
    await tester.pumpWidget(const SizedBox());
    final snapshot = FlowGraphSnapshot<String>(
      nodes: const [
        FlowNode(
            id: 'a', position: Offset.zero, data: 'a', width: 80, height: 48)
      ],
      edges: const [],
      viewport: const FlowViewport(x: 0, y: 0, zoom: 1),
    );
    await tester.runAsync(() async {
      final result = await renderFlowSnapshot<String>(
        view: tester.view,
        snapshot: snapshot,
        pixelRatio: 1,
        title: 'Long document title ' * 8,
        nodeBuilder: (_, node, selected) => const ColoredBox(color: Colors.red),
      );
      expect(result.logicalSize.width, greaterThan(500));
      expect(result.logicalSize.height, greaterThan(140));
      final codec = await ui.instantiateImageCodec(result.bytes);
      final frame = await codec.getNextFrame();
      final pixels =
          (await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final imageWidth = frame.image.width;
      var darkPixels = 0;
      for (var y = 4; y < 35; y++) {
        for (var x = 0; x < imageWidth; x++) {
          if (pixels.getUint8((y * imageWidth + x) * 4) < 100) darkPixels++;
        }
      }
      expect(darkPixels, greaterThan(0));
      frame.image.dispose();
      codec.dispose();
    });
  });
}
