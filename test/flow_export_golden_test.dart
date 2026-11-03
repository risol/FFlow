import 'dart:io';

import 'package:fflow/diagram.dart';
import 'package:fflow/diagram_fflow.dart';
import 'package:fflow/fflow.dart';
import 'package:fflow/fflow_capture.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Windows export with bundled Chinese font', (tester) async {
    await tester.runAsync(() async {
      final fontBytes =
          await File('apps/hidden_render_poc/assets/fonts/NotoSansSC.ttf')
              .readAsBytes();
      final loader = FontLoader('FFlowGoldenNotoSansSC')
        ..addFont(Future.value(ByteData.sublistView(fontBytes)));
      await loader.load();
    });
    await tester.pumpWidget(const SizedBox());
    final snapshot = FlowGraphSnapshot<String>(
      nodes: const [
        FlowNode(
            id: 'a',
            position: Offset(0, 0),
            data: '开始：用户',
            width: 150,
            height: 64),
        FlowNode(
            id: 'b',
            position: Offset(250, 0),
            data: '完成：订单',
            width: 150,
            height: 64),
      ],
      edges: const [
        FlowEdge(id: 'e', sourceId: 'a', targetId: 'b', label: '处理')
      ],
      viewport: const FlowViewport(x: 0, y: 0, zoom: 1),
    );
    await tester.runAsync(() async {
      final image = await renderFlowSnapshot<String>(
        view: tester.view,
        snapshot: snapshot,
        title: '订单处理流程',
        fontFamily: 'FFlowGoldenNotoSansSC',
        pixelRatio: 1,
        nodeBuilder: (_, node, selected) => DecoratedBox(
          decoration: BoxDecoration(
              color: const Color(0xffe7f0fb), border: Border.all()),
          child: Center(
              child:
                  Text(node.data, style: const TextStyle(color: Colors.black))),
        ),
      );
      await expectLater(
          image.bytes, matchesGoldenFile('goldens/windows_chinese_export.png'));
      final cycle = diagramToFlow(DiagramDocument.fromJson({
        'schemaVersion': 1,
        'diagramType': 'flowchart',
        'layout': {'direction': 'TB'},
        'nodes': [
          for (final id in ['A', 'B', 'C']) {'id': id, 'label': id}
        ],
        'edges': [
          {'id': 'ab', 'source': 'A', 'target': 'B'},
          {'id': 'bc', 'source': 'B', 'target': 'C'},
          {'id': 'ca', 'source': 'C', 'target': 'A', 'label': '循环'},
        ],
      })).snapshot;
      final cycleImage = await renderFlowSnapshot<Map<String, Object?>>(
        view: tester.view,
        snapshot: cycle,
        fontFamily: 'FFlowGoldenNotoSansSC',
        pixelRatio: 1,
        nodeBuilder: (_, node, selected) => DecoratedBox(
          decoration: BoxDecoration(
              color: const Color(0xffe7f0fb), border: Border.all()),
          child: Center(
              child: Text(node.data['label'] as String,
                  style: const TextStyle(color: Colors.black))),
        ),
      );
      await expectLater(cycleImage.bytes,
          matchesGoldenFile('goldens/windows_cycle_export.png'));
      final crowded = FlowGraphSnapshot<String>(
        nodes: const [
          FlowNode(
              id: 'a',
              position: Offset.zero,
              data: 'A',
              width: 140,
              height: 80),
          FlowNode(
              id: 'b',
              position: Offset(188, 0),
              data: 'B',
              width: 140,
              height: 80),
        ],
        edges: const [
          FlowEdge(id: 'one', sourceId: 'a', targetId: 'b', label: '第一个比较长的标签'),
          FlowEdge(id: 'two', sourceId: 'a', targetId: 'b', label: '第二个比较长的标签'),
        ],
        viewport: const FlowViewport(x: 0, y: 0, zoom: 1),
      );
      final crowdedImage = await renderFlowSnapshot<String>(
        view: tester.view,
        snapshot: crowded,
        fontFamily: 'FFlowGoldenNotoSansSC',
        pixelRatio: 1,
        nodeBuilder: (_, node, selected) => DecoratedBox(
          decoration: BoxDecoration(
              color: const Color(0xffe7f0fb), border: Border.all()),
          child: Center(
              child:
                  Text(node.data, style: const TextStyle(color: Colors.black))),
        ),
      );
      await expectLater(crowdedImage.bytes,
          matchesGoldenFile('goldens/windows_crowded_labels.png'));
    });
  }, skip: !Platform.isWindows);
}
