import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:isolate';

import 'package:fflow/diagram.dart';
import 'package:fflow/fflow_desktop.dart';

Future<void> sampleGcIfEnabled() async {
  final uri = (await developer.Service.getInfo()).serverUri;
  final isolateId = developer.Service.getIsolateId(Isolate.current);
  if (uri == null || isolateId == null) return;
  final socket = await WebSocket.connect(
      uri.replace(scheme: 'ws', path: '${uri.path}ws').toString());
  final messages = StreamIterator(socket);
  var id = 0;
  Future<Map<String, dynamic>> call(
      String method, Map<String, Object?> params) async {
    final requestId = ++id;
    socket.add(jsonEncode({
      'jsonrpc': '2.0',
      'id': requestId,
      'method': method,
      'params': params
    }));
    while (await messages.moveNext()) {
      final message =
          jsonDecode(messages.current as String) as Map<String, dynamic>;
      if (message['id'] == requestId) {
        if (message['error'] != null) {
          throw StateError('VM service failed: ${message['error']}');
        }
        return message['result'] as Map<String, dynamic>;
      }
    }
    throw StateError('VM service disconnected');
  }

  final rssBefore = ProcessInfo.currentRss;
  final before = await call('getMemoryUsage', {'isolateId': isolateId});
  await call('getAllocationProfile', {'isolateId': isolateId, 'gc': true});
  final after = await call('getMemoryUsage', {'isolateId': isolateId});
  stdout.writeln('gc_sample=${jsonEncode({
        'rssBefore': rssBefore,
        'rssAfter': ProcessInfo.currentRss,
        'heapBefore': before['heapUsage'],
        'heapAfter': after['heapUsage'],
        'externalBefore': before['externalUsage'],
        'externalAfter': after['externalUsage']
      })}');
  await messages.cancel();
  await socket.close();
}

Future<void> main(List<String> args) async {
  if (args.length < 2 ||
      args.length > 3 ||
      (args.length == 3 && (int.tryParse(args[2]) ?? 0) <= 0)) {
    stderr.writeln(
        'Usage: dart run tool/worker_smoke.dart <worker.exe> <output.png> [stress-count]');
    exitCode = 2;
    return;
  }
  final temp = await Directory.systemTemp.createTemp('fflow_worker_smoke_');
  final service =
      FlowIsolatedRenderService(executable: args[0], temporaryDirectory: temp);
  for (final probe in [
    ['--memory-limit-probe', '67108864', '134217728', 'fail'],
    ['--memory-limit-probe', '268435456', '8388608', 'succeed'],
  ]) {
    final result = await Process.run(args[0], probe);
    if (result.exitCode != 0) {
      throw StateError('Native memory-limit probe failed: $probe');
    }
  }
  final stressCount = args.length == 3 ? int.parse(args[2]) : 0;
  final snapshot = <String, Object?>{
    'schemaVersion': 1,
    'nodes': [
      {
        'id': 'a',
        'position': {'x': -80, 'y': 40},
        'data': '开始：用户'
      },
      {
        'id': 'b',
        'position': {'x': 600, 'y': 40},
        'data': {'label': '完成：订单'}
      },
    ],
    'edges': [
      {'id': 'ab', 'source': 'a', 'target': 'b', 'label': '处理'},
    ],
    'viewport': {'x': 5000, 'y': 5000, 'zoom': 0.5},
  };
  final outputs = await Future.wait([
    service.renderSnapshot(snapshot, pixelRatio: 1),
    service.renderSnapshot(snapshot, pixelRatio: 2),
  ]);
  final darkSnapshot = await service.renderSnapshot(snapshot,
      options:
          const FlowRenderOptions(pixelRatio: 1, theme: DiagramTheme.dark));
  if (darkSnapshot.diagnostics['theme'] != 'dark') {
    throw StateError('Snapshot theme override did not reach the worker');
  }
  final diagram = DiagramDocument.fromJson({
    'schemaVersion': 1,
    'diagramType': 'flowchart',
    'title': '订单处理流程',
    'theme': 'dark',
    'layout': {'direction': 'TB'},
    'nodes': [
      {
        'id': 'a',
        'label': '开始处理',
        'style': {'background': '#223355'}
      },
      {'id': 'b', 'label': '完成订单', 'type': 'diamond'},
    ],
    'edges': [
      {'id': 'ab', 'source': 'a', 'target': 'b', 'label': '成功'}
    ],
  });
  final diagramImage = await service.renderDiagram(diagram, pixelRatio: 1);
  final orderedDiagram = DiagramDocument.fromJson({
    'schemaVersion': 1,
    'diagramType': 'flowchart',
    'layout': {'nodeOrder': 'id'},
    'nodes': [
      {'id': 'z', 'label': 'Z'},
      {'id': 'a', 'label': 'A'}
    ],
    'edges': [],
  });
  final orderedImage =
      await service.renderDiagram(orderedDiagram, pixelRatio: 1);
  if (orderedImage.diagnostics['nodeOrder'] != 'id') {
    throw StateError('Node ordering did not reach the worker');
  }
  await File('${args[1]}.diagram.png')
      .writeAsBytes(diagramImage.pngBytes, flush: true);
  if (diagramImage.height <= diagramImage.width) {
    throw StateError(
        'Top-to-bottom diagram has unexpected dimensions: ${diagramImage.width}x${diagramImage.height}');
  }
  const mermaid = '''
flowchart TB
start([开始]) --> decision{是否通过}
decision -->|是| done([完成])
decision -->|否| retry[重试]
retry --> decision
''';
  final mermaidImage =
      await service.renderMermaid(mermaid, title: '审批流程', pixelRatio: 1);
  final transparent = await service.renderMermaid(mermaid,
      options:
          const FlowRenderOptions(pixelRatio: 1, transparentBackground: true));
  if (transparent.diagnostics['transparentBackground'] != true) {
    throw StateError('Transparent export option did not reach the worker');
  }
  await File('${args[1]}.transparent.png').writeAsBytes(transparent.pngBytes);
  final overridden = await service.renderMermaid(mermaid,
      options: const FlowRenderOptions(
          pixelRatio: 1,
          theme: DiagramTheme.dark,
          direction: DiagramDirection.lr));
  if (overridden.diagnostics['theme'] != 'dark' ||
      overridden.diagnostics['direction'] != 'LR') {
    throw StateError('Theme or direction override did not reach the worker');
  }
  await File('${args[1]}.overridden.png').writeAsBytes(overridden.pngBytes);
  final cycleImage = await service.renderMermaid(
      'flowchart TB\nA --> B\nB --> C\nC -->|循环| A',
      pixelRatio: 1);
  await File('${args[1]}.cycle.png').writeAsBytes(cycleImage.pngBytes);
  final crowdedImage = await service.renderMermaid(
      'flowchart LR\nA -->|第一个比较长的标签| B\nA -->|第二个比较长的标签| B',
      pixelRatio: 1);
  await File('${args[1]}.labels.png').writeAsBytes(crowdedImage.pngBytes);
  for (final badInput in <Future<FlowWorkerResult> Function()>[
    () => service.renderMermaid('not a flowchart'),
    () => service.renderPostgresDdl('CREATE TABLE broken ('),
    () => service.renderMysqlDdl('CREATE TABLE broken (')
  ]) {
    try {
      await badInput();
      throw StateError('Invalid source was accepted');
    } on FlowWorkerException catch (error) {
      if (error.code != 'PARSE_ERROR') rethrow;
    }
  }
  try {
    await service.renderMermaid('图' * 700000);
    throw StateError('Oversized Mermaid source was accepted');
  } on FlowWorkerException catch (error) {
    if (error.code != 'INPUT_TOO_LARGE') rethrow;
  }
  try {
    await service.renderMermaid(mermaid,
        options: const FlowRenderOptions(pixelRatio: 1, maxWidth: 10));
    throw StateError('Image width limit was not enforced');
  } on FlowWorkerException catch (error) {
    if (error.code != 'IMAGE_TOO_LARGE') rethrow;
  }
  await File('${args[1]}.mermaid.png')
      .writeAsBytes(mermaidImage.pngBytes, flush: true);
  const ddl = '''
CREATE TABLE public.customers (
  tenant_id integer NOT NULL,
  id bigint NOT NULL UNIQUE,
  name varchar(100) NOT NULL,
  referrer_id bigint REFERENCES public.customers(id),
  CONSTRAINT pk_customers PRIMARY KEY (tenant_id, id),
  CONSTRAINT uq_customer_name UNIQUE (name)
);
CREATE TABLE public.orders (
  id bigint PRIMARY KEY,
  tenant_id integer NOT NULL,
  customer_id bigint,
  amount numeric(12, 2) DEFAULT 0,
  CONSTRAINT fk_customer FOREIGN KEY (tenant_id, customer_id)
    REFERENCES public.customers (tenant_id, id) ON DELETE RESTRICT
);
''';
  final erImage =
      await service.renderPostgresDdl(ddl, title: '订单数据结构', pixelRatio: 1);
  final routedEr = await service.renderPostgresDdl(ddl,
      options: const FlowRenderOptions(
          pixelRatio: 1, edgeRouting: FlowExportEdgeRouting.orthogonal));
  if (routedEr.diagnostics['edgeRouting'] != 'orthogonal' ||
      routedEr.diagnostics['edgeRoutingMicros'] is! int) {
    throw StateError('Orthogonal routing did not reach the worker');
  }
  await File('${args[1]}.orthogonal.png').writeAsBytes(routedEr.pngBytes);
  final obstacleImage = await service.renderSnapshot({
    'schemaVersion': 1,
    'nodes': [
      {
        'id': 'a',
        'position': {'x': 0, 'y': 0},
        'width': 120,
        'height': 80,
        'data': '起点'
      },
      {
        'id': 'b',
        'position': {'x': 600, 'y': 0},
        'width': 120,
        'height': 80,
        'data': '终点'
      },
      {
        'id': 'block',
        'position': {'x': 300, 'y': -30},
        'width': 120,
        'height': 140,
        'data': '障碍'
      },
    ],
    'edges': [
      {'id': 'ab', 'source': 'a', 'target': 'b'}
    ],
    'viewport': {'x': 0, 'y': 0, 'zoom': 1},
  },
      options: const FlowRenderOptions(
          pixelRatio: 1, edgeRouting: FlowExportEdgeRouting.orthogonal));
  await File('${args[1]}.obstacle.png').writeAsBytes(obstacleImage.pngBytes);
  try {
    await service.renderSnapshot({
      'schemaVersion': 1,
      'nodes': [
        for (var i = 0; i < 501; i++)
          {
            'id': 'n$i',
            'position': {'x': i * 10, 'y': 0},
            'data': 'n$i'
          }
      ],
      'edges': [],
      'viewport': {'x': 0, 'y': 0, 'zoom': 1},
    },
        options: const FlowRenderOptions(
            edgeRouting: FlowExportEdgeRouting.orthogonal));
    throw StateError('Orthogonal routing graph limit was not enforced');
  } on FlowWorkerException catch (error) {
    if (error.code != 'RESOURCE_EXHAUSTED') rethrow;
  }
  final diagnostics = erImage.diagnostics;
  if (diagnostics['nodeCount'] != 2 ||
      diagnostics['edgeCount'] != 2 ||
      diagnostics['inputFormat'] != 'postgresDdl' ||
      diagnostics['pngBytes'] != erImage.pngBytes.length ||
      diagnostics['taskId'] is! String ||
      diagnostics['pngEncodeMicros'] is! int ||
      diagnostics['layoutPaintMicros'] is! int) {
    throw StateError('Worker diagnostics are incomplete: $diagnostics');
  }
  await File('${args[1]}.er.png').writeAsBytes(erImage.pngBytes, flush: true);
  const multiSchemaDdl = '''
CREATE TABLE sales.customer (id bigint PRIMARY KEY);
CREATE TABLE accounting.invoice (id bigint PRIMARY KEY, customer_id bigint REFERENCES sales.customer(id));
''';
  final grouped = await service.renderPostgresDdl(multiSchemaDdl,
      groupBySchema: true, pixelRatio: 1);
  if (grouped.diagnostics['nodeCount'] != 4 ||
      grouped.diagnostics['edgeCount'] != 1) {
    throw StateError('Schema grouping failed');
  }
  const mysqlDdl = '''
CREATE TABLE `customers` (`id` BIGINT NOT NULL AUTO_INCREMENT PRIMARY KEY) ENGINE=InnoDB;
CREATE TABLE `orders` (`id` BIGINT PRIMARY KEY, `customer_id` BIGINT NOT NULL,
  KEY `ix_customer` (`customer_id`),
  CONSTRAINT `fk_customer` FOREIGN KEY (`customer_id`) REFERENCES `customers` (`id`)
  ON DELETE CASCADE) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
''';
  final mysql = await service.renderMysqlDdl(mysqlDdl,
      defaultSchema: 'shop', groupBySchema: true, pixelRatio: 1);
  if (mysql.diagnostics['inputFormat'] != 'mysqlDdl' ||
      mysql.diagnostics['nodeCount'] != 3 ||
      mysql.diagnostics['edgeCount'] != 1) {
    throw StateError('MySQL rendering failed: ${mysql.diagnostics}');
  }
  await File('${args[1]}.mysql.png').writeAsBytes(mysql.pngBytes);
  await File('${args[1]}.grouped.png')
      .writeAsBytes(grouped.pngBytes, flush: true);
  final inputDirectory =
      await Directory('${temp.path}${Platform.pathSeparator}inputs').create();
  final outputDirectory =
      await Directory('${temp.path}${Platform.pathSeparator}outputs').create();
  final fileService = FlowFileRenderService(
      renderer: service,
      inputRoot: inputDirectory,
      outputRoot: outputDirectory);
  final cases = <(String, FlowFileFormat, String)>[
    ('snapshot.json', FlowFileFormat.fflowJson, jsonEncode(snapshot)),
    ('graph.json', FlowFileFormat.graphJson, jsonEncode(diagram.toJson())),
    ('graph.mmd', FlowFileFormat.mermaid, mermaid),
    ('schema.sql', FlowFileFormat.postgresDdl, ddl),
    ('mysql.sql', FlowFileFormat.mysqlDdl, mysqlDdl),
  ];
  for (final entry in cases) {
    final inputFile =
        File('${inputDirectory.path}${Platform.pathSeparator}${entry.$1}');
    await inputFile.writeAsString(entry.$3, flush: true);
    final outputName = '${entry.$1}.png';
    final outputFile =
        File('${outputDirectory.path}${Platform.pathSeparator}$outputName');
    await outputFile.writeAsString('old');
    final result = await fileService.render(
        inputPath: entry.$1,
        format: entry.$2,
        outputPath: outputName,
        pixelRatio: 1);
    if (base64Encode(await outputFile.readAsBytes()) !=
            base64Encode(result.image.pngBytes) ||
        result.image.width <= 0 ||
        result.image.height <= 0) {
      throw StateError('File render failed for ${entry.$1}');
    }
    if (result.diagnostics['inputFormat'] != entry.$2.name ||
        result.diagnostics['inputBytes'] != utf8.encode(entry.$3).length) {
      throw StateError('File diagnostics failed for ${entry.$1}');
    }
    await inputFile.delete();
    await outputFile.delete();
  }
  await inputDirectory.delete();
  await outputDirectory.delete();
  if (outputs[1].width != outputs[0].width * 2 ||
      outputs[1].height != outputs[0].height * 2) {
    throw StateError('Incorrect scale');
  }
  await File(args[1]).writeAsBytes(outputs[0].pngBytes, flush: true);
  try {
    await service.renderSnapshot({
      'nodes': [],
      'edges': [
        {'id': 'bad', 'source': 'a', 'target': 'b'}
      ],
    });
    throw StateError('Invalid reference was accepted');
  } on FlowWorkerException catch (error) {
    if (error.code != 'GRAPH_REFERENCE_ERROR') rethrow;
    if (error.diagnostics['taskId'] is! String ||
        error.diagnostics['elapsedMicros'] is! int) {
      throw StateError('Failure diagnostics are incomplete');
    }
  }
  final recovered = await service.renderSnapshot(snapshot, pixelRatio: 1);
  if (recovered.width != outputs.first.width) {
    throw StateError('Render after an error failed');
  }
  final shortTimeout = FlowIsolatedRenderService(
      executable: args[0],
      temporaryDirectory: temp,
      timeout: const Duration(microseconds: 1));
  try {
    await shortTimeout.renderSnapshot(snapshot);
    throw StateError('Worker timeout was not enforced');
  } on FlowWorkerException catch (error) {
    if (error.code != 'RENDER_TIMEOUT') rethrow;
  }
  final limited = FlowIsolatedRenderService(
      executable: args[0], temporaryDirectory: temp, maxInputBytes: 10);
  try {
    await limited.renderSnapshot(snapshot);
    throw StateError('Input size limit was not enforced');
  } on FlowWorkerException catch (error) {
    if (error.code != 'INPUT_TOO_LARGE') rethrow;
  }
  try {
    await service.renderSnapshot({'schemaVersion': 999});
    throw StateError('Unsupported schema was accepted');
  } on FlowWorkerException catch (error) {
    if (error.code != 'SCHEMA_ERROR') rethrow;
  }
  final outputLimited = FlowIsolatedRenderService(
      executable: args[0], temporaryDirectory: temp, maxOutputBytes: 1);
  try {
    await outputLimited.renderSnapshot(snapshot);
    throw StateError('Output size limit was not enforced');
  } on FlowWorkerException catch (error) {
    if (error.code != 'IMAGE_TOO_LARGE') rethrow;
  }
  final singleSlot = FlowIsolatedRenderService(
      executable: args[0], temporaryDirectory: temp, maxPendingTasks: 1);
  final firstTask = singleSlot.renderSnapshot(snapshot, pixelRatio: 1);
  try {
    await singleSlot.renderSnapshot(snapshot);
    throw StateError('Queue limit was not enforced');
  } on FlowWorkerException catch (error) {
    if (error.code != 'RESOURCE_EXHAUSTED') rethrow;
  }
  await firstTask;
  final mediumSnapshot = <String, Object?>{
    'schemaVersion': 1,
    'nodes': [
      for (var i = 0; i < 100; i++)
        {
          'id': 'm$i',
          'position': {'x': (i % 10) * 180, 'y': (i ~/ 10) * 120},
          'data': '测试 $i'
        },
    ],
    'edges': [
      for (var i = 1; i < 100; i++)
        {'id': 'm$i', 'source': 'm${i - 1}', 'target': 'm$i'},
    ],
    'viewport': {'x': 0, 'y': 0, 'zoom': 1},
  };
  for (var i = 0; i < stressCount; i++) {
    final medium = i.isOdd;
    final result = await service
        .renderSnapshot(medium ? mediumSnapshot : snapshot, pixelRatio: 1);
    if (result.diagnostics['nodeCount'] != (medium ? 100 : 2) ||
        result.width <= 0 ||
        result.height <= 0) {
      throw StateError('Unexpected result for stress task $i');
    }
    if ((i + 1) % 10 == 0 || i + 1 == stressCount) {
      stdout.writeln(
          'stress_completed=${i + 1} host_rss=${ProcessInfo.currentRss}');
    }
    if ((i + 1) % 100 == 0) await sampleGcIfEnabled();
  }
  if (!await temp.list().isEmpty) {
    throw StateError('Task files were not cleaned up: ${temp.path}');
  }
  await temp.delete();
  stdout
      .writeln('Isolated renders, errors, recovery, timeout and limits passed; '
          'image ${outputs.first.width}x${outputs.first.height}.');
}
