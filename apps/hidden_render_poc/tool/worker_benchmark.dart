import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:fflow/fflow_desktop.dart';

/// Repeatable diagnostic benchmark, not a performance guarantee.
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/worker_benchmark.dart <worker.exe>');
    exitCode = 2;
    return;
  }
  final renderer = FlowIsolatedRenderService(
      executable: args.single, timeout: const Duration(minutes: 2));
  for (final count in [20, 100, 500]) {
    final columns = math.sqrt(count).ceil();
    final snapshot = <String, Object?>{
      'schemaVersion': 1,
      'nodes': [
        for (var i = 0; i < count; i++)
          {
            'id': 'n$i',
            'position': {'x': (i % columns) * 180, 'y': (i ~/ columns) * 120},
            'data': 'Node $i',
          },
      ],
      'edges': [
        for (var i = 1; i < count; i++)
          {'id': 'e$i', 'source': 'n${i - 1}', 'target': 'n$i'},
      ],
      'viewport': {'x': 0, 'y': 0, 'zoom': 1},
    };
    final result = await renderer.renderSnapshot(snapshot, pixelRatio: 1);
    stdout.writeln(jsonEncode({
      'case': 'positioned_snapshot',
      'nodes': count,
      'hostElapsedUs': result.elapsed.inMicroseconds,
      ...result.diagnostics,
    }));
    final rows = math.min(25, math.sqrt(count).ceil());
    final diagram = DiagramDocument.fromJson({
      'schemaVersion': 1,
      'diagramType': 'flowchart',
      'layout': {'direction': 'LR', 'nodeSpacing': 24, 'layerSpacing': 40},
      'nodes': [
        for (var i = 0; i < count; i++)
          {
            'id': 'n$i',
            'label': 'Node $i',
            'size': {'width': 80, 'height': 48}
          },
      ],
      'edges': [
        for (var i = rows; i < count; i++)
          {'id': 'e$i', 'source': 'n${i - rows}', 'target': 'n$i'},
      ],
    });
    final laidOut = await renderer.renderDiagram(diagram, pixelRatio: 1);
    stdout.writeln(jsonEncode({
      'case': 'auto_layout',
      'nodes': count,
      'hostElapsedUs': laidOut.elapsed.inMicroseconds,
      ...laidOut.diagnostics,
    }));
  }
}
