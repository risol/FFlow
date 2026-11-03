import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../diagram/diagram_document.dart';
import '../diagram/mermaid_flowchart_parser.dart';
import '../diagram/mysql_ddl_parser.dart';
import '../diagram/postgres_ddl_parser.dart';
import 'atomic_file.dart';
import 'flow_errors.dart';
import 'flow_isolated_render_service.dart';
import 'json_limits.dart';

enum FlowFileFormat { fflowJson, graphJson, mermaid, postgresDdl, mysqlDdl }

class FlowFileRenderResult {
  const FlowFileRenderResult(
      {required this.image,
      required this.inputFormat,
      required this.inputBytes,
      required this.parseElapsed,
      required this.elapsed,
      this.outputPath});
  final FlowWorkerResult image;
  final FlowFileFormat inputFormat;
  final int inputBytes;
  final Duration parseElapsed;
  final Duration elapsed;

  /// Canonical output path, or null when the caller requested bytes only.
  final String? outputPath;

  Map<String, Object?> get diagnostics => Map.unmodifiable({
        ...image.diagnostics,
        'inputFormat': inputFormat.name,
        'inputBytes': inputBytes,
        'parseMicros': parseElapsed.inMicroseconds,
        'totalElapsedMicros': elapsed.inMicroseconds,
      });
}

/// Root-confined file input and optional PNG output for the desktop worker.
///
/// Roots must be existing, application-controlled directories. Paths passed to
/// [render] must be relative to the appropriate root and cannot contain `..`.
/// Parsing runs in a background isolate; the renderer serializes worker tasks.
class FlowFileRenderService {
  FlowFileRenderService(
      {required this.renderer,
      required this.inputRoot,
      required this.outputRoot,
      this.maxInputBytes = 16000000,
      this.maxPendingTasks = 8}) {
    if (maxInputBytes <= 0 || maxPendingTasks <= 0) {
      throw ArgumentError('Invalid file service limits');
    }
  }

  final FlowIsolatedRenderService renderer;
  final Directory inputRoot;
  final Directory outputRoot;
  final int maxInputBytes;
  final int maxPendingTasks;
  int _pending = 0;

  Future<FlowFileRenderResult> render(
      {required String inputPath,
      required FlowFileFormat format,
      String? outputPath,
      String? title,
      String? defaultSchema,
      bool groupBySchema = false,
      double pixelRatio = 2,
      double padding = 32,
      FlowRenderOptions? options}) async {
    final resolvedOptions =
        options ?? FlowRenderOptions(pixelRatio: pixelRatio, padding: padding);
    resolvedOptions.validate();
    if (format == FlowFileFormat.fflowJson &&
        resolvedOptions.direction != null) {
      throw ArgumentError('Layout direction is not supported for snapshots');
    }
    if (groupBySchema &&
        format != FlowFileFormat.postgresDdl &&
        format != FlowFileFormat.mysqlDdl) {
      throw ArgumentError('Schema grouping applies only to SQL DDL');
    }
    if (defaultSchema != null && format != FlowFileFormat.mysqlDdl) {
      throw ArgumentError('defaultSchema applies only to MySQL DDL');
    }
    if (_pending >= maxPendingTasks) {
      throw const FlowWorkerException(
          'RESOURCE_EXHAUSTED', 'File render queue is full');
    }
    if (title != null && format == FlowFileFormat.fflowJson) {
      throw ArgumentError(
          'A title override is not supported for FFlow snapshots');
    }
    _pending++;
    final stopwatch = Stopwatch()..start();
    try {
      final input = await _resolveInput(inputPath);
      _OutputTarget? target;
      if (outputPath != null) {
        target = await _resolveOutput(outputPath);
        final bool sameFile;
        try {
          sameFile = p.equals(input.path, target.path) ||
              (await FileSystemEntity.type(target.path) ==
                      FileSystemEntityType.file &&
                  await FileSystemEntity.identical(input.path, target.path));
        } on FileSystemException catch (error) {
          throw FlowWorkerException('OUTPUT_WRITE_ERROR',
              'Cannot verify output identity: ${error.message}');
        }
        if (sameFile) {
          throw const FlowWorkerException(
              'OUTPUT_WRITE_ERROR', 'Output must not overwrite the input');
        }
      }
      final bytes = await _readBounded(input, inputPath);
      if ((format == FlowFileFormat.mermaid ||
              format == FlowFileFormat.postgresDdl ||
              format == FlowFileFormat.mysqlDdl) &&
          bytes.length > 2000000) {
        throw FlowWorkerException(
            'INPUT_TOO_LARGE', '$inputPath exceeds the 2 MB parser limit');
      }
      final parseClock = Stopwatch()..start();
      final _ParsedInput parsed;
      try {
        parsed = await Isolate.run(
            () => _parse(bytes, format, title, groupBySchema, defaultSchema));
      } on DiagramReferenceException catch (error) {
        throw FlowWorkerException(
            'GRAPH_REFERENCE_ERROR', '$inputPath: ${error.message}');
      } on _InputException catch (error) {
        throw FlowWorkerException(error.code, '$inputPath: ${error.message}');
      } on FormatException catch (error) {
        throw FlowWorkerException(
            'PARSE_ERROR', '$inputPath: ${error.message}');
      }
      parseClock.stop();
      final FlowWorkerResult image;
      if (parsed.snapshot != null) {
        image = await renderer.renderSnapshot(parsed.snapshot!,
            options: resolvedOptions);
      } else {
        image = await renderer.renderDiagram(parsed.document!,
            options: resolvedOptions);
      }
      if (target != null) {
        await _writeOutput(target, outputPath!, image.pngBytes);
      }
      return FlowFileRenderResult(
          image: image,
          inputFormat: format,
          inputBytes: bytes.length,
          parseElapsed: parseClock.elapsed,
          elapsed: stopwatch.elapsed,
          outputPath: target?.path);
    } finally {
      _pending--;
    }
  }

  Future<File> _resolveInput(String relative) async {
    final parts = _segments(relative, 'INPUT_NOT_FOUND');
    try {
      final root = await inputRoot.resolveSymbolicLinks();
      final candidate = File(p.joinAll([root, ...parts]));
      final resolved = await candidate.resolveSymbolicLinks();
      if (!p.isWithin(root, resolved)) {
        throw FlowWorkerException(
            'INPUT_NOT_FOUND', 'Input escapes its permitted root: $relative');
      }
      if (await FileSystemEntity.type(resolved) != FileSystemEntityType.file) {
        throw FlowWorkerException(
            'INPUT_NOT_FOUND', 'Input is not a file: $relative');
      }
      return File(resolved);
    } on FlowWorkerException {
      rethrow;
    } on FileSystemException catch (error) {
      throw FlowWorkerException(
          'INPUT_NOT_FOUND', '$relative: ${error.message}');
    }
  }

  Future<Uint8List> _readBounded(File input, String displayName) async {
    final builder = BytesBuilder(copy: false);
    var length = 0;
    try {
      if (await input.length() > maxInputBytes) {
        throw FlowWorkerException(
            'INPUT_TOO_LARGE', '$displayName exceeds input limit');
      }
      await for (final part in input.openRead()) {
        length += part.length;
        if (length > maxInputBytes) {
          throw FlowWorkerException(
              'INPUT_TOO_LARGE', '$displayName exceeds input limit');
        }
        builder.add(part);
      }
      return builder.takeBytes();
    } on FlowWorkerException {
      rethrow;
    } on FileSystemException catch (error) {
      throw FlowWorkerException(
          'INPUT_READ_ERROR', '$displayName: ${error.message}');
    }
  }

  Future<_OutputTarget> _resolveOutput(String relative) async {
    final parts = _segments(relative, 'OUTPUT_WRITE_ERROR');
    try {
      final root = await outputRoot.resolveSymbolicLinks();
      final candidate = p.joinAll([root, ...parts]);
      final parent =
          await Directory(p.dirname(candidate)).resolveSymbolicLinks();
      if (!p.equals(parent, root) && !p.isWithin(root, parent)) {
        throw FlowWorkerException('OUTPUT_WRITE_ERROR',
            'Output escapes its permitted root: $relative');
      }
      final path = p.join(parent, p.basename(candidate));
      final type = await FileSystemEntity.type(path, followLinks: false);
      if (type != FileSystemEntityType.notFound &&
          type != FileSystemEntityType.file) {
        throw FlowWorkerException(
            'OUTPUT_WRITE_ERROR', 'Output is not a regular file: $relative');
      }
      return _OutputTarget(path, parent);
    } on FlowWorkerException {
      rethrow;
    } on FileSystemException catch (error) {
      throw FlowWorkerException(
          'OUTPUT_WRITE_ERROR', '$relative: ${error.message}');
    }
  }

  Future<void> _writeOutput(
      _OutputTarget initial, String relative, Uint8List bytes) async {
    Directory? tempDirectory;
    File? temporary;
    try {
      tempDirectory = await Directory(initial.parent).createTemp('.fflow-');
      temporary = File(p.join(tempDirectory.path, 'image.tmp'));
      await temporary.writeAsBytes(bytes, flush: true);
      final current = await _resolveOutput(relative);
      if (!p.equals(current.path, initial.path)) {
        throw const FlowWorkerException(
            'OUTPUT_WRITE_ERROR', 'Output directory changed during rendering');
      }
      await replaceFile(temporary, current.path);
    } on FlowWorkerException {
      rethrow;
    } on FileSystemException catch (error) {
      throw FlowWorkerException(
          'OUTPUT_WRITE_ERROR', '$relative: ${error.message}');
    } finally {
      if (temporary != null && await temporary.exists()) {
        await temporary.delete();
      }
      if (tempDirectory != null && await tempDirectory.exists()) {
        await tempDirectory.delete();
      }
    }
  }
}

List<String> _segments(String path, String code) {
  if (path.isEmpty ||
      path.contains('\u0000') ||
      p.isAbsolute(path) ||
      p.windows.isAbsolute(path) ||
      p.posix.isAbsolute(path) ||
      RegExp(r'^[A-Za-z]:').hasMatch(path)) {
    throw FlowWorkerException(
        code, 'Expected a relative path inside the permitted root: $path');
  }
  final parts = path.split(RegExp(r'[/\\]'));
  if (parts.any((part) =>
      part.isEmpty ||
      part == '.' ||
      part == '..' ||
      RegExp(r'[<>:"|?*]').hasMatch(part) ||
      (Platform.isWindows &&
          (part.endsWith('.') ||
              part.endsWith(' ') ||
              RegExp(r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$',
                      caseSensitive: false)
                  .hasMatch(part))))) {
    throw FlowWorkerException(code, 'Invalid path component: $path');
  }
  return parts;
}

class _OutputTarget {
  const _OutputTarget(this.path, this.parent);
  final String path, parent;
}

class _ParsedInput {
  const _ParsedInput({this.snapshot, this.document});
  final Map<String, Object?>? snapshot;
  final DiagramDocument? document;
}

class _InputException implements Exception {
  const _InputException(this.code, this.message);
  final String code, message;
}

_ParsedInput _parse(Uint8List bytes, FlowFileFormat format, String? title,
    bool groupBySchema, String? defaultSchema) {
  var text = utf8.decode(bytes);
  if (text.startsWith('\ufeff')) text = text.substring(1);
  if (format == FlowFileFormat.mermaid) {
    return _ParsedInput(document: parseMermaidFlowchart(text, title: title));
  }
  if (format == FlowFileFormat.postgresDdl) {
    return _ParsedInput(
        document: parsePostgresDdl(text)
            .toDiagram(title: title, groupBySchema: groupBySchema));
  }
  if (format == FlowFileFormat.mysqlDdl) {
    return _ParsedInput(
        document: parseMysqlDdl(text, defaultSchema: defaultSchema)
            .toDiagram(title: title, groupBySchema: groupBySchema));
  }
  final Object? json;
  try {
    checkJsonTextDepth(text);
    json = jsonDecode(text);
  } on FormatException catch (error) {
    throw _InputException('PARSE_ERROR', error.message);
  }
  if (format == FlowFileFormat.fflowJson) {
    if (json is! Map<String, dynamic>) {
      throw const _InputException(
          'SCHEMA_ERROR', 'FFlow snapshot must be a JSON object');
    }
    return _ParsedInput(snapshot: Map<String, Object?>.from(json));
  }
  try {
    final doc = DiagramDocument.fromJson(json);
    if (title == null) return _ParsedInput(document: doc);
    return _ParsedInput(
        document: DiagramDocument.fromJson({...doc.toJson(), 'title': title}));
  } on DiagramReferenceException {
    rethrow;
  } on FormatException catch (error) {
    throw _InputException('SCHEMA_ERROR', error.message);
  }
}
