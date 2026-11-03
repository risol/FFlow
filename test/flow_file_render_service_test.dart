import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fflow/diagram.dart';
import 'package:fflow/fflow_desktop.dart';
import 'package:fflow/src/desktop/atomic_file.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';

class _Renderer extends FlowIsolatedRenderService {
  _Renderer() : super(executable: 'unused');
  int snapshots = 0;
  final documents = <DiagramDocument>[];
  Completer<void>? hold;
  bool fail = false;
  FlowRenderOptions? lastOptions;

  Future<FlowWorkerResult> result() async {
    if (hold != null) await hold!.future;
    if (fail) {
      throw const FlowWorkerException('RENDER_INIT_ERROR', 'test failure');
    }
    return FlowWorkerResult(
        pngBytes: Uint8List.fromList([137, 80, 78, 71, 7]),
        width: 20,
        height: 30,
        elapsed: const Duration(milliseconds: 1));
  }

  @override
  Future<FlowWorkerResult> renderSnapshot(Map<String, Object?> snapshot,
      {double pixelRatio = 2,
      double padding = 32,
      FlowRenderOptions? options}) {
    snapshots++;
    lastOptions = options;
    return result();
  }

  @override
  Future<FlowWorkerResult> renderDiagram(DiagramDocument document,
      {double pixelRatio = 2,
      double padding = 32,
      FlowRenderOptions? options}) {
    documents.add(document);
    lastOptions = options;
    return result();
  }
}

void main() {
  late Directory fixture;
  late Directory input;
  late Directory output;
  late _Renderer renderer;
  late FlowFileRenderService service;

  setUp(() async {
    final build = Directory('build').absolute;
    await build.create(recursive: true);
    fixture = await build.createTemp('file_render_test_');
    input = await Directory(p.join(fixture.path, 'input')).create();
    output = await Directory(p.join(fixture.path, 'output')).create();
    renderer = _Renderer();
    service = FlowFileRenderService(
        renderer: renderer, inputRoot: input, outputRoot: output);
  });
  tearDown(() async {
    final resolved = await fixture.resolveSymbolicLinks();
    final build = await Directory('build').resolveSymbolicLinks();
    if (!p.isWithin(build, resolved)) {
      throw StateError('Unexpected fixture path');
    }
    await fixture.delete(recursive: true);
  });

  test('reads all four formats and replaces output in the chosen directory',
      () async {
    await File(p.join(input.path, 'snapshot.json'))
        .writeAsString('{"nodes":[],"edges":[]}');
    await File(p.join(input.path, 'graph.json')).writeAsString(jsonEncode({
      'schemaVersion': 1,
      'diagramType': 'flowchart',
      'nodes': [],
      'edges': [],
    }));
    await File(p.join(input.path, 'graph.mmd'))
        .writeAsString('flowchart LR\nA-->B');
    await File(p.join(input.path, 'schema.sql'))
        .writeAsString('CREATE TABLE t (id int PRIMARY KEY);');
    final outputFile = File(p.join(output.path, '中文 image.png'));
    await outputFile.writeAsBytes([1, 2, 3]);
    final fileResult = await service.render(
        inputPath: 'snapshot.json',
        format: FlowFileFormat.fflowJson,
        outputPath: '中文 image.png');
    expect(await outputFile.readAsBytes(), [137, 80, 78, 71, 7]);
    expect(fileResult.outputPath, await outputFile.resolveSymbolicLinks());
    expect(fileResult.inputBytes, greaterThan(0));
    await service.render(
        inputPath: 'graph.json', format: FlowFileFormat.graphJson, title: '标题');
    await service.render(
        inputPath: 'graph.mmd', format: FlowFileFormat.mermaid);
    await service.render(
        inputPath: 'schema.sql',
        format: FlowFileFormat.postgresDdl,
        groupBySchema: true,
        options: const FlowRenderOptions(
            theme: DiagramTheme.print,
            direction: DiagramDirection.tb,
            edgeRouting: FlowExportEdgeRouting.orthogonal));
    expect(renderer.snapshots, 1);
    expect(renderer.documents.map((d) => d.type),
        [DiagramType.flowchart, DiagramType.flowchart, DiagramType.er]);
    expect(renderer.documents.first.title, '标题');
    expect(renderer.lastOptions?.theme, DiagramTheme.print);
    expect(renderer.lastOptions?.direction, DiagramDirection.tb);
    expect(renderer.lastOptions?.edgeRouting, FlowExportEdgeRouting.orthogonal);
    expect(
        renderer.documents.last.nodes.where((node) => node.type == 'erSchema'),
        hasLength(1));
    expect(await output.list().length, 1,
        reason: 'Temporary output files must be removed');
  });

  test(
      'rejects traversal, missing inputs, malformed JSON and invalid references',
      () async {
    Future<void> error(Future<Object?> Function() call, String code) async {
      await expectLater(
          call(),
          throwsA(
              isA<FlowWorkerException>().having((e) => e.code, 'code', code)));
    }

    await error(
        () => service.render(
            inputPath: '../secret', format: FlowFileFormat.fflowJson),
        'INPUT_NOT_FOUND');
    await error(
        () => service.render(
            inputPath: r'C:\secret', format: FlowFileFormat.fflowJson),
        'INPUT_NOT_FOUND');
    await error(
        () => service.render(
            inputPath: 'missing', format: FlowFileFormat.fflowJson),
        'INPUT_NOT_FOUND');
    await File(p.join(input.path, 'invalid.json')).writeAsString('{');
    await error(
        () => service.render(
            inputPath: 'invalid.json', format: FlowFileFormat.graphJson),
        'PARSE_ERROR');
    await File(p.join(input.path, 'invalid.json')).writeAsString(jsonEncode({
      'schemaVersion': 1,
      'diagramType': 'flowchart',
      'nodes': [],
      'edges': [
        {'id': 'e', 'source': 'missing', 'target': 'missing'}
      ],
    }));
    await error(
        () => service.render(
            inputPath: 'invalid.json', format: FlowFileFormat.graphJson),
        'GRAPH_REFERENCE_ERROR');
    await error(
        () => service.render(
            inputPath: 'invalid.json',
            format: FlowFileFormat.graphJson,
            outputPath: '../outside.png'),
        'OUTPUT_WRITE_ERROR');
    expect(renderer.documents, isEmpty);
  });

  test('enforces limits and leaves an existing output intact on failure',
      () async {
    await File(p.join(input.path, 'input.mmd'))
        .writeAsString('graph LR; A-->B');
    final existing = File(p.join(output.path, 'existing.png'));
    await existing.writeAsBytes([9, 8, 7]);
    final limited = FlowFileRenderService(
        renderer: renderer,
        inputRoot: input,
        outputRoot: output,
        maxInputBytes: 4);
    await expectLater(
        limited.render(
            inputPath: 'input.mmd',
            format: FlowFileFormat.mermaid,
            outputPath: 'existing.png'),
        throwsA(isA<FlowWorkerException>()
            .having((e) => e.code, 'code', 'INPUT_TOO_LARGE')));
    renderer.fail = true;
    await expectLater(
        service.render(
            inputPath: 'input.mmd',
            format: FlowFileFormat.mermaid,
            outputPath: 'existing.png'),
        throwsA(isA<FlowWorkerException>()
            .having((e) => e.code, 'code', 'RENDER_INIT_ERROR')));
    expect(await existing.readAsBytes(), [9, 8, 7]);
    expect(await output.list().length, 1);
  });

  test('rejects deeply nested JSON before decoding', () async {
    final source = File(p.join(input.path, 'deep.json'));
    await source.writeAsString('${'[' * 65}0${']' * 65}');
    await expectLater(
        service.render(
            inputPath: 'deep.json', format: FlowFileFormat.fflowJson),
        throwsA(isA<FlowWorkerException>()
            .having((e) => e.code, 'code', 'PARSE_ERROR')));
  });

  test('bounds concurrent file jobs', () async {
    await File(p.join(input.path, 'input.mmd'))
        .writeAsString('graph LR; A-->B');
    renderer.hold = Completer<void>();
    final single = FlowFileRenderService(
        renderer: renderer,
        inputRoot: input,
        outputRoot: output,
        maxPendingTasks: 1);
    final first =
        single.render(inputPath: 'input.mmd', format: FlowFileFormat.mermaid);
    await expectLater(
        single.render(inputPath: 'input.mmd', format: FlowFileFormat.mermaid),
        throwsA(isA<FlowWorkerException>()
            .having((e) => e.code, 'code', 'RESOURCE_EXHAUSTED')));
    renderer.hold!.complete();
    await first;
  });

  test('does not allow an output to replace its input', () async {
    await File(p.join(input.path, 'input.mmd'))
        .writeAsString('graph LR; A-->B');
    final sameRoot = FlowFileRenderService(
        renderer: renderer, inputRoot: input, outputRoot: input);
    await expectLater(
      sameRoot.render(
          inputPath: 'input.mmd',
          format: FlowFileFormat.mermaid,
          outputPath: 'input.mmd'),
      throwsA(isA<FlowWorkerException>()
          .having((e) => e.code, 'code', 'OUTPUT_WRITE_ERROR')),
    );
    expect(await File(p.join(input.path, 'input.mmd')).readAsString(),
        'graph LR; A-->B');
  });

  test('failed atomic replacement preserves the original target', () async {
    final folder = await Directory(p.join(output.path, 'existing')).create();
    final marker =
        await File(p.join(folder.path, 'marker')).writeAsString('keep');
    final staged =
        await File(p.join(output.path, 'staged.tmp')).writeAsString('new');
    await expectLater(
        replaceFile(staged, folder.path), throwsA(isA<FileSystemException>()));
    expect(await marker.readAsString(), 'keep');
    expect(await staged.readAsString(), 'new');
  });

  test('validates Windows aliases that could escape file policy', () async {
    if (!Platform.isWindows) return;
    await File(p.join(input.path, 'input.mmd'))
        .writeAsString('graph LR; A-->B');
    for (final bad in ['NUL.png', 'file.png:stream', 'file.png.', 'COM1.txt']) {
      await expectLater(
          service.render(
              inputPath: 'input.mmd',
              format: FlowFileFormat.mermaid,
              outputPath: bad),
          throwsA(isA<FlowWorkerException>()
              .having((e) => e.code, 'code', 'OUTPUT_WRITE_ERROR')));
    }
  });

  test('rejects input and output links escaping their roots', () async {
    final outside = await Directory(p.join(fixture.path, 'outside')).create();
    await File(p.join(outside.path, 'graph.mmd'))
        .writeAsString('graph LR; A-->B');
    final inputLink = Link(p.join(input.path, 'escape'));
    final outputLink = Link(p.join(output.path, 'escape'));
    try {
      await inputLink.create(outside.path);
      await outputLink.create(outside.path);
    } on FileSystemException {
      // Windows may prohibit creating symbolic links for the current account.
      return;
    }
    await expectLater(
        service.render(
            inputPath: 'escape/graph.mmd', format: FlowFileFormat.mermaid),
        throwsA(isA<FlowWorkerException>()
            .having((e) => e.code, 'code', 'INPUT_NOT_FOUND')));
    await File(p.join(input.path, 'valid.mmd'))
        .writeAsString('graph LR; A-->B');
    await expectLater(
        service.render(
            inputPath: 'valid.mmd',
            format: FlowFileFormat.mermaid,
            outputPath: 'escape/image.png'),
        throwsA(isA<FlowWorkerException>()
            .having((e) => e.code, 'code', 'OUTPUT_WRITE_ERROR')));
    expect(await File(p.join(outside.path, 'image.png')).exists(), isFalse);
  });
}
