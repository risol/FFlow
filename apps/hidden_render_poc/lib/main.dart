import 'dart:io';
import 'dart:ui' as ui;

import 'package:fflow/fflow.dart';
import 'package:fflow/fflow_capture.dart';
import 'package:flutter/material.dart';

import 'snapshot_worker.dart';

void main(List<String> arguments) {
  WidgetsFlutterBinding.ensureInitialized();
  if (arguments.isNotEmpty && arguments.first == '--render-snapshot-worker') {
    runSnapshotWorker(arguments.skip(1).toList());
    return;
  }
  if (arguments.isEmpty ||
      arguments.length > 5 ||
      arguments.skip(1).any((arg) => (int.tryParse(arg) ?? 0) <= 0)) {
    stderr.writeln(
        'Usage: fflow_hidden_render_poc <output directory> [iterations] [validate-every] [frame-every] [plain]');
    exit(2);
  }
  final iterations = arguments.length >= 2 ? int.parse(arguments[1]) : 100;
  final validateEvery = arguments.length >= 3 ? int.parse(arguments[2]) : 1;
  final frameEvery = arguments.length >= 4 ? int.parse(arguments[3]) : null;
  final mode = arguments.length == 5 ? int.parse(arguments[4]) : 0;
  final plain = mode == 1 || mode == 4 || mode == 5 || mode == 6;
  runApp(const SizedBox.shrink());
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      final directory = Directory(arguments.first);
      await directory.create(recursive: true);
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      const nodes = <FlowNode<String>>[
        FlowNode(
          id: 'a',
          position: Offset(80, 120),
          data: '开始：用户',
          width: 220,
          height: 90,
        ),
        FlowNode(
          id: 'b',
          position: Offset(1550, 120),
          data: '完成：订单',
          width: 220,
          height: 90,
        ),
      ];
      const edges = <FlowEdge>[
        FlowEdge(
          id: 'ab',
          sourceId: 'a',
          targetId: 'b',
          label: '处理',
          markerEnd: FlowEdgeMarker.arrowClosed,
        ),
      ];
      final original = FlowGraphSnapshot<String>(
        nodes: nodes,
        edges: mode == 3
            ? const [FlowEdge(id: 'ab', sourceId: 'a', targetId: 'b')]
            : edges,
        viewport: const FlowViewport(x: 2000, y: 2000, zoom: .5),
      );
      final snapshot = FlowGraphSnapshot<String>.fromJson(
        original.toJson(encodeNodeData: (data) => data),
        decodeNodeData: (data) => data as String,
      );
      var picturesCreated = 0;
      var picturesDisposed = 0;
      var pictureBytesCreated = 0;
      var pictureBytesDisposed = 0;
      var imagesCreated = 0;
      var imagesDisposed = 0;
      ui.Picture.onCreate = (picture) {
        picturesCreated++;
        pictureBytesCreated += picture.approximateBytesUsed;
      };
      ui.Picture.onDispose = (picture) {
        picturesDisposed++;
        pictureBytesDisposed += picture.approximateBytesUsed;
      };
      ui.Image.onCreate = (_) => imagesCreated++;
      ui.Image.onDispose = (_) => imagesDisposed++;
      final stopwatch = Stopwatch()..start();
      final memorySamples = <String>[];
      for (var i = 0; i < iterations; i++) {
        final FlowGraphPng result;
        if (plain) {
          const size = Size(1786, 186);
          final bytes = await captureFlowOffscreen(
            view: view,
            size: size,
            pixelRatio: 1,
            child: switch (mode) {
              4 =>
                const ColoredBox(color: Colors.white, child: FFlowBackground()),
              5 => const ColoredBox(
                  color: Colors.white,
                  child: CustomPaint(painter: _PathGridPainter())),
              6 => const ColoredBox(
                  color: Colors.white,
                  child: CustomPaint(painter: _CachedGridPainter())),
              _ => const ColoredBox(color: Colors.red),
            },
          );
          result = FlowGraphPng(
              bytes: bytes,
              graphBounds: Rect.zero,
              logicalSize: size,
              pixelRatio: 1);
        } else {
          result = await renderFlowSnapshot<String>(
            view: view,
            snapshot: snapshot,
            pixelRatio: 1,
            gridSpacing: mode == 2 || mode == 3 ? 0 : 24,
            nodeBuilder: (context, node, selected) => mode == 3
                ? ColoredBox(color: Colors.blue.shade100)
                : DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.blue.shade100,
                      border: Border.all(color: Colors.blue.shade900, width: 2),
                    ),
                    child: Center(
                      child: Text(
                        node.data,
                        style:
                            const TextStyle(color: Colors.black, fontSize: 20),
                      ),
                    ),
                  ),
          );
        }
        final png = result.bytes;
        if (png.length < 8 ||
            png[0] != 137 ||
            png[1] != 80 ||
            png[2] != 78 ||
            png[3] != 71) {
          throw StateError('Invalid PNG header on task $i');
        }
        if (i % validateEvery == 0 || i == iterations - 1) {
          final codec = await ui.instantiateImageCodec(png);
          try {
            final frame = await codec.getNextFrame();
            try {
              if (frame.image.width != result.logicalSize.width.toInt() ||
                  frame.image.height != result.logicalSize.height.toInt()) {
                throw StateError('Incorrect capture dimensions on task $i');
              }
              final pixels = await frame.image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              );
              if (pixels == null) throw StateError('Could not decode task $i');
              int pixelOffset(double x, double y) =>
                  (((y - result.graphBounds.top + 32).round() *
                          frame.image.width) +
                      (x - result.graphBounds.left + 32).round()) *
                  4;
              final edge = pixelOffset(600, 165);
              final farNode = pixelOffset(1600, 140);
              if (!plain &&
                  (pixels.getUint8(edge) > 220 ||
                      pixels.getUint8(farNode + 2) < 200 ||
                      pixels.getUint8(farNode) > 200)) {
                throw StateError('Missing edge or distant node on task $i');
              }
            } finally {
              frame.image.dispose();
            }
          } finally {
            codec.dispose();
          }
        }
        if ((i + 1) % 10 == 0 || i == iterations - 1) {
          memorySamples.add('${i + 1},${ProcessInfo.currentRss}');
        }
        if (i == iterations - 1) {
          await File('${directory.path}${Platform.pathSeparator}poc.png')
              .writeAsBytes(png, flush: true);
        }
        if (frameEvery != null && (i + 1) % frameEvery == 0) {
          WidgetsBinding.instance.scheduleForcedFrame();
          await WidgetsBinding.instance.endOfFrame
              .timeout(const Duration(seconds: 5));
        }
      }
      await File('${directory.path}${Platform.pathSeparator}result.txt')
          .writeAsString(
        'captures=$iterations\nvalidate_every=$validateEvery\nelapsed_ms=${stopwatch.elapsedMilliseconds}\n'
        'pictures_created=$picturesCreated\npictures_disposed=$picturesDisposed\n'
        'picture_bytes_created=$pictureBytesCreated\npicture_bytes_disposed=$pictureBytesDisposed\n'
        'images_created=$imagesCreated\nimages_disposed=$imagesDisposed\n'
        'rss_samples_task_bytes=${memorySamples.join(';')}\n',
      );
      exit(0);
    } catch (error, stack) {
      await File('${arguments.first}${Platform.pathSeparator}error.txt')
          .writeAsString('$error\n$stack');
      exit(1);
    }
  });
}

class _PathGridPainter extends CustomPainter {
  const _PathGridPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    for (double x = 12; x < size.width; x += 24) {
      for (double y = 12; y < size.height; y += 24) {
        path.addOval(Rect.fromCircle(center: Offset(x, y), radius: 1));
      }
    }
    canvas.drawPath(path, Paint()..color = const Color(0xFF272D39));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _CachedGridPainter extends CustomPainter {
  const _CachedGridPainter();
  static ui.Picture? _picture;

  @override
  void paint(Canvas canvas, Size size) {
    if (_picture == null) {
      final recorder = ui.PictureRecorder();
      final recordingCanvas = Canvas(recorder);
      const _PathGridPainter().paint(recordingCanvas, size);
      _picture = recorder.endRecording();
    }
    canvas.drawPicture(_picture!);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
