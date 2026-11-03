import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../diagram/diagram_document.dart';
import 'flow_errors.dart';
import 'json_limits.dart';

enum FlowExportEdgeRouting { automatic, orthogonal }

/// Per-task export options. Limits may be tightened but not raised above the
/// worker's hard limits. When supplied, these override the legacy scale and
/// padding arguments on render methods.
class FlowRenderOptions {
  const FlowRenderOptions(
      {this.pixelRatio = 2,
      this.padding = 32,
      this.maxWidth = 8192,
      this.maxHeight = 8192,
      this.maxPixels = 32000000,
      this.transparentBackground = false,
      this.theme,
      this.direction,
      this.edgeRouting = FlowExportEdgeRouting.automatic});
  final double pixelRatio, padding;
  final int maxWidth, maxHeight, maxPixels;
  final bool transparentBackground;
  final DiagramTheme? theme;

  /// Overrides a DiagramDocument's layout direction; snapshots retain their
  /// existing coordinates and do not accept this option.
  final DiagramDirection? direction;
  final FlowExportEdgeRouting edgeRouting;

  void validate() {
    if (!pixelRatio.isFinite ||
        pixelRatio <= 0 ||
        !padding.isFinite ||
        padding < 0 ||
        maxWidth <= 0 ||
        maxWidth > 8192 ||
        maxHeight <= 0 ||
        maxHeight > 8192 ||
        maxPixels <= 0 ||
        maxPixels > 32000000) {
      throw ArgumentError('Invalid export options');
    }
  }
}

class FlowWorkerResult {
  FlowWorkerResult(
      {required this.pngBytes,
      required this.width,
      required this.height,
      required this.elapsed,
      Map<String, Object?> diagnostics = const {}})
      : diagnostics = Map.unmodifiable(diagnostics);
  final Uint8List pngBytes;
  final int width;
  final int height;
  final Duration elapsed;
  final Map<String, Object?> diagnostics;
}

/// Runs snapshot tasks serially in short-lived hidden desktop processes.
///
/// [executable] must be a compatible worker, such as the Windows PoC. Node
/// data is displayed as a string or the `label` field of an object; custom
/// widget builders cannot cross a process boundary. The returned PNG is held
/// in memory and task files are removed after the worker terminates.
class FlowIsolatedRenderService {
  FlowIsolatedRenderService(
      {required this.executable,
      this.temporaryDirectory,
      this.timeout = const Duration(seconds: 30),
      this.maxInputBytes = 16000000,
      this.maxOutputBytes = 64000000,
      this.maxWorkerMemoryBytes = 805306368,
      this.maxPendingTasks = 8}) {
    if (timeout <= Duration.zero ||
        maxInputBytes <= 0 ||
        maxInputBytes > 16000000 ||
        maxOutputBytes <= 0 ||
        maxOutputBytes > 64000000 ||
        maxWorkerMemoryBytes < 67108864 ||
        maxWorkerMemoryBytes > 0x7fffffffffffffff ||
        maxPendingTasks <= 0) {
      throw ArgumentError('Invalid worker limits');
    }
  }

  final String executable;

  /// Existing parent directory for private task directories; defaults to the
  /// platform temporary directory.
  final Directory? temporaryDirectory;
  final Duration timeout;
  final int maxInputBytes;
  final int maxOutputBytes;

  /// Windows worker process commit limit, applied before Flutter initializes.
  final int maxWorkerMemoryBytes;
  final int maxPendingTasks;
  int _pending = 0;
  Future<void> _previous = Future.value();

  Future<FlowWorkerResult> renderSnapshot(Map<String, Object?> snapshot,
      {double pixelRatio = 2,
      double padding = 32,
      FlowRenderOptions? options}) {
    if (options?.direction != null) {
      throw ArgumentError('Layout direction is not supported for snapshots');
    }
    return _enqueue({'snapshot': snapshot, 'inputFormat': 'fflowJson'},
        options ?? FlowRenderOptions(pixelRatio: pixelRatio, padding: padding));
  }

  /// Renders a validated application-level document, applying its layout in
  /// the worker. Parse Graph JSON with `DiagramDocument.fromJson` first.
  Future<FlowWorkerResult> renderDiagram(DiagramDocument document,
          {double pixelRatio = 2,
          double padding = 32,
          FlowRenderOptions? options}) =>
      _enqueue(
          {'diagram': document.toJson(), 'inputFormat': 'graphJson'},
          options ??
              FlowRenderOptions(pixelRatio: pixelRatio, padding: padding));

  /// Parses and renders the supported Mermaid flowchart subset.
  Future<FlowWorkerResult> renderMermaid(String source,
          {String? title,
          double pixelRatio = 2,
          double padding = 32,
          FlowRenderOptions? options}) =>
      _enqueue(
          {'mermaid': source, 'title': title, 'inputFormat': 'mermaid'},
          options ??
              FlowRenderOptions(pixelRatio: pixelRatio, padding: padding));

  /// Parses the documented PostgreSQL DDL subset and renders its ER diagram.
  Future<FlowWorkerResult> renderPostgresDdl(String source,
          {String? title,
          bool groupBySchema = false,
          double pixelRatio = 2,
          double padding = 32,
          FlowRenderOptions? options}) =>
      _enqueue(
          {
            'postgresDdl': source,
            'title': title,
            'groupBySchema': groupBySchema,
            'inputFormat': 'postgresDdl'
          },
          options ??
              FlowRenderOptions(pixelRatio: pixelRatio, padding: padding));

  /// Parses the supported MySQL DDL subset and renders its ER diagram.
  Future<FlowWorkerResult> renderMysqlDdl(String source,
          {String? title,
          String? defaultSchema,
          bool groupBySchema = false,
          double pixelRatio = 2,
          double padding = 32,
          FlowRenderOptions? options}) =>
      _enqueue(
          {
            'mysqlDdl': source,
            'title': title,
            'defaultSchema': defaultSchema,
            'groupBySchema': groupBySchema,
            'inputFormat': 'mysqlDdl'
          },
          options ??
              FlowRenderOptions(pixelRatio: pixelRatio, padding: padding));

  Future<FlowWorkerResult> _enqueue(
      Map<String, Object?> input, FlowRenderOptions options) {
    options.validate();
    if (_pending >= maxPendingTasks) {
      throw const FlowWorkerException(
          'RESOURCE_EXHAUSTED', 'Worker queue is full');
    }
    final request = encodeJsonBounded({
      ...input,
      'pixelRatio': options.pixelRatio,
      'padding': options.padding,
      'maxWidth': options.maxWidth,
      'maxHeight': options.maxHeight,
      'maxPixels': options.maxPixels,
      'transparentBackground': options.transparentBackground,
      if (options.theme != null) 'theme': options.theme!.name,
      if (options.direction != null)
        'direction': options.direction!.name.toUpperCase(),
      'edgeRouting': options.edgeRouting.name,
      'maxBytes': maxOutputBytes,
    }, maxInputBytes);
    _pending++;
    final result = _previous.then((_) => _run(request));
    _previous =
        result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result.whenComplete(() => _pending--);
  }

  Future<FlowWorkerResult> _run(List<int> request) async {
    final stopwatch = Stopwatch()..start();
    late final Directory directory;
    try {
      directory = await (temporaryDirectory ?? Directory.systemTemp)
          .createTemp('fflow_render_');
    } on FileSystemException catch (error) {
      throw FlowWorkerException('OUTPUT_WRITE_ERROR', error.message);
    }
    final requestFile =
        File('${directory.path}${Platform.pathSeparator}request.json');
    final imageFile =
        File('${directory.path}${Platform.pathSeparator}image.png');
    final resultFile =
        File('${directory.path}${Platform.pathSeparator}result.json');
    Process? process;
    var terminated = true;
    try {
      await requestFile.writeAsBytes(request, flush: true);
      try {
        process = await Process.start(executable, [
          '--render-snapshot-worker',
          requestFile.path,
          imageFile.path,
          resultFile.path,
          maxWorkerMemoryBytes.toString(),
        ]);
      } on ProcessException catch (error) {
        throw FlowWorkerException('RENDER_INIT_ERROR', error.message);
      }
      terminated = false;
      // Drain both pipes so a noisy worker cannot block on a full buffer.
      final stdoutDone = process.stdout.drain<void>().catchError((Object _) {});
      final stderrDone = process.stderr.drain<void>().catchError((Object _) {});
      await process.stdin.close();
      int code;
      try {
        code = await process.exitCode.timeout(timeout);
        terminated = true;
      } on TimeoutException {
        process.kill();
        try {
          await process.exitCode.timeout(const Duration(seconds: 5));
          terminated = true;
        } on TimeoutException {
          throw FlowWorkerException('RENDER_TIMEOUT',
              'Worker did not terminate promptly; task directory: ${directory.path}');
        }
        throw const FlowWorkerException(
            'RENDER_TIMEOUT', 'Worker exceeded its time limit');
      }
      await Future.wait([stdoutDone, stderrDone]);
      if (!await resultFile.exists()) {
        throw FlowWorkerException('RENDER_INIT_ERROR',
            'Worker exited with code $code without a result (memory limit $maxWorkerMemoryBytes bytes)');
      }
      if (await resultFile.length() > 65536) {
        throw const FlowWorkerException(
            'RENDER_INIT_ERROR', 'Worker result exceeds metadata limit');
      }
      final data =
          jsonDecode(await resultFile.readAsString()) as Map<String, dynamic>;
      if (code != 0 || data['ok'] != true) {
        throw FlowWorkerException(
            data['code'] as String? ?? 'RENDER_INIT_ERROR',
            data['message'] as String? ?? 'Worker failed with code $code');
      }
      if (!await imageFile.exists()) {
        throw const FlowWorkerException(
            'PNG_ENCODE_ERROR', 'Worker did not produce an image');
      }
      if (await imageFile.length() > maxOutputBytes) {
        throw const FlowWorkerException(
            'IMAGE_TOO_LARGE', 'Worker image exceeds output limit');
      }
      final bytes = await imageFile.readAsBytes();
      const signature = [137, 80, 78, 71, 13, 10, 26, 10];
      if (bytes.length < 24 ||
          signature
              .asMap()
              .entries
              .any((entry) => bytes[entry.key] != entry.value) ||
          ascii.decode(bytes.sublist(12, 16), allowInvalid: true) != 'IHDR') {
        throw const FlowWorkerException(
            'PNG_ENCODE_ERROR', 'Worker output is not a PNG');
      }
      final header = ByteData.sublistView(bytes);
      final width = header.getUint32(16);
      final height = header.getUint32(20);
      if (width == 0 ||
          height == 0 ||
          width != data['width'] ||
          height != data['height']) {
        throw const FlowWorkerException(
            'PNG_ENCODE_ERROR', 'PNG dimensions disagree with worker result');
      }
      final rawDiagnostics = data['diagnostics'];
      if (rawDiagnostics != null && rawDiagnostics is! Map<String, dynamic>) {
        throw const FlowWorkerException(
            'RENDER_INIT_ERROR', 'Invalid worker diagnostics');
      }
      return FlowWorkerResult(
          pngBytes: bytes,
          width: width,
          height: height,
          elapsed: stopwatch.elapsed,
          diagnostics: {
            if (rawDiagnostics is Map<String, dynamic>) ...rawDiagnostics,
            'taskId': p.basename(directory.path),
            'workerMemoryLimitBytes': maxWorkerMemoryBytes,
          });
    } on FlowWorkerException catch (error) {
      throw FlowWorkerException(error.code, error.message,
          diagnostics: Map.unmodifiable({
            ...error.diagnostics,
            'taskId': p.basename(directory.path),
            'elapsedMicros': stopwatch.elapsedMicroseconds,
            'workerMemoryLimitBytes': maxWorkerMemoryBytes,
          }));
    } on FileSystemException catch (error) {
      throw FlowWorkerException('OUTPUT_WRITE_ERROR', error.message);
    } on FormatException catch (error) {
      throw FlowWorkerException(
          'RENDER_INIT_ERROR', 'Invalid worker metadata: ${error.message}');
    } on TypeError {
      throw const FlowWorkerException(
          'RENDER_INIT_ERROR', 'Invalid worker metadata');
    } finally {
      if (process != null && !terminated) {
        process.kill();
        try {
          await process.exitCode.timeout(const Duration(seconds: 5));
          terminated = true;
        } on TimeoutException {
          // Do not delete files while the worker may still be using them.
        }
      }
      if (terminated) await directory.delete(recursive: true);
    }
  }
}
