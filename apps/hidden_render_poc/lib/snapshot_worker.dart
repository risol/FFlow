import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fflow/diagram.dart';
import 'package:fflow/diagram_fflow.dart';
import 'package:fflow/fflow.dart';
import 'package:fflow/fflow_capture.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'er_table_widget.dart';

/// Entry point for the experimental per-task Windows process protocol.
void runSnapshotWorker(List<String> args) {
  if (args.length != 4) exit(2);
  runApp(const SizedBox.shrink());
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final workerClock = Stopwatch()..start();
    final resultFile = File(args[2]);
    var phase = 'INPUT_NOT_FOUND';
    try {
      final requestFile = File(args[0]);
      if (await requestFile.length() > 16000000) {
        throw StateError('INPUT_TOO_LARGE: request exceeds worker limit');
      }
      phase = 'SCHEMA_ERROR';
      final contents = BytesBuilder(copy: false);
      var byteCount = 0;
      await for (final chunk in requestFile.openRead()) {
        byteCount += chunk.length;
        if (byteCount > 16000000) {
          throw StateError('INPUT_TOO_LARGE: request exceeds worker limit');
        }
        contents.add(chunk);
      }
      final text = utf8.decode(contents.takeBytes());
      checkJsonDepth(text);
      final request = jsonDecode(text) as Map<String, dynamic>;
      final DiagramDocument? document;
      late FlowGraphSnapshot<Object?> snapshot;
      var layoutTime = Duration.zero;
      if (request['diagram'] != null ||
          request['mermaid'] != null ||
          request['postgresDdl'] != null ||
          request['mysqlDdl'] != null) {
        final DiagramDocument parsedDocument;
        if (request['mermaid'] != null) {
          phase = 'PARSE_ERROR';
          if (exceedsUtf8Limit(request['mermaid'] as String, 2000000)) {
            throw StateError('INPUT_TOO_LARGE: Mermaid exceeds 2 MB');
          }
          parsedDocument = parseMermaidFlowchart(request['mermaid'] as String,
              title: request['title'] as String?);
        } else if (request['postgresDdl'] != null) {
          phase = 'PARSE_ERROR';
          if (exceedsUtf8Limit(request['postgresDdl'] as String, 2000000)) {
            throw StateError('INPUT_TOO_LARGE: SQL exceeds 2 MB');
          }
          parsedDocument = parsePostgresDdl(request['postgresDdl'] as String)
              .toDiagram(
                  title: request['title'] as String?,
                  groupBySchema: request['groupBySchema'] as bool? ?? false);
        } else if (request['mysqlDdl'] != null) {
          phase = 'PARSE_ERROR';
          if (exceedsUtf8Limit(request['mysqlDdl'] as String, 2000000)) {
            throw StateError('INPUT_TOO_LARGE: SQL exceeds 2 MB');
          }
          parsedDocument = parseMysqlDdl(request['mysqlDdl'] as String,
                  defaultSchema: request['defaultSchema'] as String?)
              .toDiagram(
                  title: request['title'] as String?,
                  groupBySchema: request['groupBySchema'] as bool? ?? false);
        } else {
          parsedDocument = DiagramDocument.fromJson(request['diagram']);
        }
        phase = 'SCHEMA_ERROR';
        final themeOverride = request['theme'] as String?;
        final directionOverride = request['direction'] as String?;
        document = themeOverride == null && directionOverride == null
            ? parsedDocument
            : DiagramDocument.fromJson({
                ...parsedDocument.toJson(),
                if (themeOverride != null) 'theme': themeOverride,
                if (directionOverride != null)
                  'layout': {
                    ...parsedDocument.layout.toJson(),
                    'direction': directionOverride
                  },
              });
        final layoutClock = Stopwatch()..start();
        snapshot = diagramToFlow(document).snapshot;
        layoutTime = layoutClock.elapsed;
      } else {
        document = null;
        snapshot = FlowGraphSnapshot<Object?>.fromJson(
          request['snapshot'] as Map<String, Object?>,
          decodeNodeData: (data) => data,
        );
      }
      final routing = request['edgeRouting'] as String? ?? 'automatic';
      if (routing != 'automatic' && routing != 'orthogonal') {
        throw const FormatException('Unknown edge routing option');
      }
      var routingTime = Duration.zero;
      if (routing == 'orthogonal') {
        if (snapshot.nodes.length > 500 || snapshot.edges.length > 1000) {
          throw StateError(
              'RESOURCE_EXHAUSTED: orthogonal routing is limited to 500 nodes and 1000 edges');
        }
        final clock = Stopwatch()..start();
        final routed = await FlowGraphRouting.routeEdges<Object?>(
          nodes: snapshot.nodes,
          edges: snapshot.edges.where((edge) =>
              edge.sourceId != edge.targetId && edge.controlPoints.isEmpty),
          router: const FlowOrthogonalEdgeRouter(),
        );
        final routes = {for (final edge in routed) edge.id: edge};
        snapshot = FlowGraphSnapshot<Object?>(
          nodes: snapshot.nodes,
          edges: [for (final edge in snapshot.edges) routes[edge.id] ?? edge],
          viewport: snapshot.viewport,
        );
        routingTime = clock.elapsed;
      }
      final inputDecodeTime = workerClock.elapsed - layoutTime - routingTime;
      final snapshotTheme = request['theme'] as String?;
      if (document == null &&
          ((snapshotTheme != null &&
                  !const {'light', 'dark', 'print'}.contains(snapshotTheme)) ||
              request['direction'] != null)) {
        throw const FormatException(
            'Invalid snapshot theme or layout override');
      }
      final dark = document?.theme == DiagramTheme.dark ||
          (document == null && snapshotTheme == 'dark');
      final printTheme = document?.theme == DiagramTheme.print ||
          (document == null && snapshotTheme == 'print');
      final standardFlowchart = document?.type == DiagramType.flowchart;
      final declaredFormat = request['inputFormat'];
      final maxWidth = request['maxWidth'] as int? ?? 8192;
      final maxHeight = request['maxHeight'] as int? ?? 8192;
      final maxPixels = request['maxPixels'] as int? ?? 32000000;
      final maxBytes = request['maxBytes'] as int;
      final transparent = request['transparentBackground'] as bool? ?? false;
      if (maxWidth <= 0 ||
          maxWidth > 8192 ||
          maxHeight <= 0 ||
          maxHeight > 8192 ||
          maxPixels <= 0 ||
          maxPixels > 32000000 ||
          maxBytes <= 0 ||
          maxBytes > 64000000) {
        throw const FormatException('Invalid worker rendering limits');
      }
      final nodesById = {for (final node in snapshot.nodes) node.id: node};
      phase = 'RENDER_INIT_ERROR';
      final fontLoader = FontLoader('FFlowNotoSansSC')
        ..addFont(rootBundle.load('assets/fonts/NotoSansSC.ttf'));
      await fontLoader.load();
      // Let Flutter deliver its font-change notification before attaching the
      // detached render tree; its paragraph measurements then use this font.
      await WidgetsBinding.instance.endOfFrame;
      final output = await renderFlowSnapshot<Object?>(
        view: WidgetsBinding.instance.platformDispatcher.views.first,
        snapshot: snapshot,
        pixelRatio: (request['pixelRatio'] as num).toDouble(),
        padding: (request['padding'] as num).toDouble(),
        maxBytes: maxBytes,
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        maxPixels: maxPixels,
        title: document?.title,
        fontFamily: 'FFlowNotoSansSC',
        backgroundColor: transparent
            ? Colors.transparent
            : (dark
                ? const Color(0xff121923)
                : printTheme
                    ? Colors.white
                    : standardFlowchart
                        ? Colors.white
                        : const Color(0xfff8fafc)),
        titleColor: dark ? const Color(0xffedf3fa) : const Color(0xff1e293b),
        edgeColor: dark
            ? const Color(0xffa8b9ce)
            : printTheme
                ? Colors.black
                : standardFlowchart
                    ? const Color(0xff303b48)
                    : const Color(0xff71839a),
        edgeLabelBackgroundColor: dark
            ? (standardFlowchart
                ? const Color(0xff121923)
                : const Color(0xff253344))
            : Colors.white,
        edgeLabelTextColor: dark
            ? const Color(0xffe0eaf4)
            : printTheme
                ? Colors.black
                : standardFlowchart
                    ? const Color(0xff202832)
                    : const Color(0xff43556d),
        edgeLabelBorderColor: dark
            ? const Color(0xff45566c)
            : printTheme
                ? Colors.black
                : const Color(0xffd8e2ed),
        plainEdgeLabels: standardFlowchart,
        edgeLabelOutset: document?.type == DiagramType.er ? 36 : 0,
        edgeLabelBuilder: document?.type == DiagramType.er
            ? (context, edge) {
                final source = FlowGeometry.edgeSource(edge, nodesById);
                final target = FlowGeometry.edgeTarget(edge, nodesById);
                final available = source == null || target == null
                    ? 160.0
                    : math.max(
                        60.0, math.min(220.0, (target - source).distance - 56));
                return Transform.translate(
                    offset: const Offset(0, -24),
                    child: Container(
                      constraints: BoxConstraints(maxWidth: available),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 3),
                      decoration: BoxDecoration(
                          color: dark ? const Color(0xff202633) : Colors.white,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: dark
                                  ? const Color(0xffb5cce4)
                                  : printTheme
                                      ? Colors.black
                                      : const Color(0xff68778b))),
                      child: Text(edge.label ?? '',
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 10,
                              color: dark ? Colors.white : Colors.black)),
                    ));
              }
            : null,
        nodeBuilder: (context, node, selected) {
          final data = node.data;
          final label = data is String
              ? data
              : data is Map && data['label'] is String
                  ? data['label'] as String
                  : node.id;
          final rawDiagram = data is Map ? data['diagram'] : null;
          final rawStyle = rawDiagram is Map ? rawDiagram['style'] : null;
          final style = rawStyle is Map ? rawStyle : const {};
          final shapeValue = style['shape'];
          final shape = shapeValue is String ? shapeValue : node.type;
          final diamond = shape == 'diamond' || shape == 'decision';
          final ellipse = shape == 'circle' || shape == 'ellipse';
          final stadium = shape == 'stadium' || shape == 'terminal';
          Color getColor(String key, Color fallback) {
            final raw = style[key];
            if (raw is! String ||
                !RegExp(r'^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$').hasMatch(raw)) {
              return fallback;
            }
            final hex = raw.substring(1);
            return Color(
                int.parse(hex.length == 6 ? 'ff$hex' : hex, radix: 16));
          }

          final background = getColor(
              'background',
              dark
                  ? const Color(0xff273447)
                  : printTheme
                      ? Colors.white
                      : document?.type == DiagramType.er
                          ? const Color(0xffe7f0fb)
                          : standardFlowchart
                              ? (diamond
                                  ? const Color(0xfffff4c2)
                                  : stadium
                                      ? const Color(0xffe7f0fb)
                                      : const Color(0xffe8f5e5))
                              : diamond
                                  ? const Color(0xffeff6ff)
                                  : ellipse
                                      ? const Color(0xffeef8f4)
                                      : Colors.white);
          final border = getColor(
              'border',
              dark
                  ? const Color(0xffb5cce4)
                  : printTheme
                      ? Colors.black
                      : document?.type == DiagramType.er
                          ? const Color(0xff275684)
                          : standardFlowchart
                              ? const Color(0xff303b48)
                              : diamond
                                  ? const Color(0xff98b5d9)
                                  : ellipse
                                      ? const Color(0xff8ebda8)
                                      : const Color(0xffc4d1df));
          final foreground = getColor(
              'foreground',
              dark
                  ? Colors.white
                  : printTheme
                      ? Colors.black
                      : const Color(0xff172b40));
          if (node.type == 'erSchema') {
            return DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: foreground, fontWeight: FontWeight.bold)),
                ),
              ),
            );
          }
          if (node.type == 'erTable' &&
              rawDiagram is Map &&
              rawDiagram['data'] is Map &&
              (rawDiagram['data'] as Map)['columns'] is List) {
            return ErTableWidget(
                label: label,
                columns: (rawDiagram['data'] as Map)['columns'] as List,
                background: background,
                foreground: foreground,
                border: border);
          }
          final ShapeBorder outline = diamond || ellipse
              ? _FlowShapeBorder(
                  diamond: diamond, side: BorderSide(color: border))
              : stadium
                  ? StadiumBorder(side: BorderSide(color: border))
                  : RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(shape == 'rectangle'
                          ? (standardFlowchart ? 0 : 6)
                          : 12),
                      side: BorderSide(color: border));
          return DecoratedBox(
            decoration: ShapeDecoration(
              color: background,
              shape: outline,
              shadows: printTheme || transparent || standardFlowchart
                  ? null
                  : [
                      BoxShadow(
                          color: Colors.black
                              .withValues(alpha: dark ? 0.14 : 0.055),
                          blurRadius: 10,
                          offset: const Offset(0, 3))
                    ],
            ),
            child: Padding(
              padding: diamond
                  ? EdgeInsets.symmetric(
                      horizontal: node.width * 0.25,
                      vertical: node.height * 0.25)
                  : const EdgeInsets.all(8),
              child: Center(
                  child: Text(label,
                      textAlign: TextAlign.center,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: foreground,
                          fontSize: 15,
                          fontWeight: standardFlowchart
                              ? FontWeight.w500
                              : FontWeight.w600))),
            ),
          );
        },
      );
      final expectedWidth =
          (output.logicalSize.width * output.pixelRatio).ceil();
      final expectedHeight =
          (output.logicalSize.height * output.pixelRatio).ceil();
      final validateClock = Stopwatch()..start();
      try {
        final codec = await ui.instantiateImageCodec(output.bytes);
        try {
          final frame = await codec.getNextFrame();
          try {
            if (frame.image.width != expectedWidth ||
                frame.image.height != expectedHeight) {
              throw StateError('Unexpected decoded image dimensions');
            }
          } finally {
            frame.image.dispose();
          }
        } finally {
          codec.dispose();
        }
      } catch (error) {
        throw StateError('PNG_ENCODE_ERROR: Unable to decode image: $error');
      }
      final validateTime = validateClock.elapsed;
      int? peakRss;
      try {
        peakRss = ProcessInfo.maxRss;
      } on UnsupportedError {
        peakRss = null;
      }
      phase = 'OUTPUT_WRITE_ERROR';
      await File(args[1]).writeAsBytes(output.bytes, flush: true);
      await resultFile.writeAsString(
          jsonEncode({
            'ok': true,
            'width': expectedWidth,
            'height': expectedHeight,
            'diagnostics': {
              'inputFormat': declaredFormat is String &&
                      const {
                        'fflowJson',
                        'graphJson',
                        'mermaid',
                        'postgresDdl',
                        'mysqlDdl'
                      }.contains(declaredFormat)
                  ? declaredFormat
                  : 'unknown',
              'diagramType': document?.type.name ?? 'fflow',
              'inputBytes': byteCount,
              'nodeCount': snapshot.nodes.length,
              'edgeCount': snapshot.edges.length,
              'logicalWidth': output.logicalSize.width,
              'logicalHeight': output.logicalSize.height,
              'pixelWidth': expectedWidth,
              'pixelHeight': expectedHeight,
              'pngBytes': output.bytes.length,
              'transparentBackground': transparent,
              'theme': document?.theme.name ?? snapshotTheme ?? 'light',
              if (document != null)
                'direction': document.layout.direction.name.toUpperCase(),
              if (document != null) 'nodeOrder': document.layout.nodeOrder.name,
              'inputDecodeMicros': inputDecodeTime.inMicroseconds,
              'graphLayoutMicros': layoutTime.inMicroseconds,
              'edgeRouting': routing,
              'edgeRoutingMicros': routingTime.inMicroseconds,
              'renderPreparationMicros': output.preparation.inMicroseconds,
              'layoutPaintMicros':
                  output.timings?.layoutPaint.inMicroseconds ?? 0,
              'rasterMicros': output.timings?.raster.inMicroseconds ?? 0,
              'pngEncodeMicros': output.timings?.pngEncode.inMicroseconds ?? 0,
              'pngValidationMicros': validateTime.inMicroseconds,
              'workerElapsedMicros': workerClock.elapsedMicroseconds,
              'peakRssBytes': peakRss,
              'engineInitialization': 'isolated-windows-worker',
              'renderingBackend': 'unknown',
              'operatingSystem': Platform.operatingSystemVersion,
            },
          }),
          flush: true);
      exit(0);
    } catch (error) {
      final message = error.toString();
      final match = RegExp(
              r'\b(INPUT_TOO_LARGE|SCHEMA_ERROR|GRAPH_REFERENCE_ERROR|IMAGE_TOO_LARGE|RESOURCE_EXHAUSTED|RENDER_INIT_ERROR|PNG_ENCODE_ERROR)\b')
          .firstMatch(message);
      try {
        await resultFile.writeAsString(
            jsonEncode({
              'ok': false,
              'code': match?.group(0) ?? phase,
              'message': message
            }),
            flush: true);
      } catch (_) {
        // The parent reports a missing result if the output location failed.
      }
      exit(1);
    }
  });
}

class _FlowShapeBorder extends ShapeBorder {
  const _FlowShapeBorder({required this.diamond, required this.side});
  final bool diamond;
  final BorderSide side;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    if (!diamond) return Path()..addOval(rect);
    return Path()
      ..moveTo(rect.center.dx, rect.top)
      ..lineTo(rect.right, rect.center.dy)
      ..lineTo(rect.center.dx, rect.bottom)
      ..lineTo(rect.left, rect.center.dy)
      ..close();
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect.deflate(side.width), textDirection: textDirection);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    canvas.drawPath(
        getOuterPath(rect.deflate(side.width / 2),
            textDirection: textDirection),
        side.toPaint());
  }

  @override
  ShapeBorder scale(double t) =>
      _FlowShapeBorder(diamond: diamond, side: side.scale(t));
}
