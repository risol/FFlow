import 'dart:io';

import 'package:fflow/fflow_desktop.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2 ||
      args.length > 3 ||
      (args.length == 3 &&
          !const {'light', 'dark', 'print'}.contains(args[2]))) {
    stderr.writeln(
        'Usage: dart run tool/render_preview.dart <worker.exe> <output.png> [light|dark|print]');
    exitCode = 2;
    return;
  }
  final renderer = FlowIsolatedRenderService(executable: args[0]);
  final image = await renderer.renderMermaid('''
flowchart TB
start([开始]) --> decision{是否通过}
decision -->|是| done([完成])
decision -->|否| retry[重试]
retry --> decision
''',
      title: '审批流程',
      options: FlowRenderOptions(
          pixelRatio: 2,
          theme:
              args.length == 3 ? DiagramTheme.values.byName(args[2]) : null));
  await File(args[1]).writeAsBytes(image.pngBytes, flush: true);
  stdout.writeln('Rendered ${image.width} × ${image.height}: ${args[1]}');
}
