import 'dart:ui' as ui;

import 'package:fflow/fflow.dart';
import 'package:fflow/src/rendering/flow_edges_painter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('ER markers paint optional-many and exactly-one symbols',
      (tester) async {
    await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawColor(Colors.white, BlendMode.src);
      final painter = FlowEdgesPainter<String>(
        nodes: const [
          FlowNode(
              id: 'a',
              position: Offset(0, 20),
              data: 'a',
              width: 100,
              height: 40),
          FlowNode(
              id: 'b',
              position: Offset(200, 20),
              data: 'b',
              width: 100,
              height: 40),
        ],
        edges: const [
          FlowEdge(
              id: 'e',
              sourceId: 'a',
              targetId: 'b',
              type: FlowEdgeType.straight,
              markerStart: FlowEdgeMarker.crowFootZeroMany,
              markerEnd: FlowEdgeMarker.one)
        ],
        selectedEdgeIds: const {},
        defaultColor: Colors.black,
        previewStart: null,
        previewTarget: null,
        previewColor: Colors.black,
        animation: const AlwaysStoppedAnimation(0),
      );
      painter.paint(canvas, const Size(300, 100));
      final picture = recorder.endRecording();
      final image = await picture.toImage(300, 100);
      final bytes =
          (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      int red(int x, int y) => bytes.getUint8((y * 300 + x) * 4);
      expect(red(118, 37), lessThan(180), reason: 'Optional-many circle');
      expect(red(118, 40), 255,
          reason: 'Optionality circle must remain hollow');
      expect(red(190, 43), lessThan(180), reason: 'Exactly-one bar');
      expect(red(150, 37), 255, reason: 'Only the line crosses the midpoint');
      image.dispose();
      picture.dispose();
    });
  });
}
