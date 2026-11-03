# Desktop rendering public API

Import the Flutter desktop entry point in a Flutter desktop application:

```dart
import 'package:fflow/fflow_desktop_flutter.dart';
```

This Flutter entry point exports the diagram model and parsers, diagram-to-FFlow
adapter, FFlow graph types and widgets, in-process PNG capture, and isolated
worker/file services. The narrower imports `diagram.dart`,
`diagram_fflow.dart`, `fflow.dart`, and `fflow_capture.dart` remain available.
For a pure Dart host that launches the worker without Flutter, import
`package:fflow/fflow_desktop.dart`; it exposes the diagram model, parsers,
and worker/file services without requiring `dart:ui`.

## Isolated worker

Build and distribute the **entire** Windows Release runner directory from
`apps/hidden_render_poc` and pass the executable's full path to
`FlowIsolatedRenderService`. The current worker is experimental and requires a
Windows desktop session. Widget callbacks cannot cross the process boundary.
The worker executable and its companion files must match the package version.

```dart
final renderer = FlowIsolatedRenderService(executable: workerExePath);
final png = await renderer.renderMysqlDdl('''
CREATE TABLE customers (id bigint PRIMARY KEY);
CREATE TABLE orders (id bigint PRIMARY KEY, customer_id bigint,
  FOREIGN KEY (customer_id) REFERENCES customers(id));
''',
    title: 'Orders',
    defaultSchema: 'shop',
    groupBySchema: true,
    options: const FlowRenderOptions(
      pixelRatio: 2,
      padding: 32,
      theme: DiagramTheme.light,
      edgeRouting: FlowExportEdgeRouting.orthogonal,
    ));
// png.pngBytes, png.width, png.height, png.elapsed, png.diagnostics
```

| Method | Input | Specific options |
| --- | --- | --- |
| `renderSnapshot` | FFlow snapshot JSON map | Saved coordinates; no direction override |
| `renderDiagram` | `DiagramDocument` | Respects document layout |
| `renderMermaid` | Mermaid flowchart text | `title` |
| `renderPostgresDdl` | PostgreSQL DDL text | `title`, `groupBySchema` |
| `renderMysqlDdl` | MySQL DDL text | `title`, `defaultSchema`, `groupBySchema` |

`FlowRenderOptions` controls pixel ratio, padding, output width, height and
pixel limits, transparency, theme, direction and edge routing. Supplying it
overrides the individual `pixelRatio` and `padding` arguments. A service
serializes its tasks and supports configurable timeouts, byte limits, pending
queue size and Windows worker memory limit. `FlowWorkerResult` contains PNG
bytes, pixel dimensions, elapsed time and diagnostics.

## Files

```dart
final files = FlowFileRenderService(
  renderer: renderer,
  inputRoot: inputDirectory,
  outputRoot: outputDirectory,
);
final result = await files.render(
  inputPath: 'schema.sql',
  format: FlowFileFormat.mysqlDdl,
  defaultSchema: 'shop',
  groupBySchema: true,
  outputPath: 'schema.png',
);
// result.image, result.outputPath, result.inputBytes, result.parseElapsed,
// result.elapsed, result.diagnostics
```

`FlowFileFormat` selects `fflowJson`, `graphJson`, `mermaid`, `postgresDdl`,
or `mysqlDdl`. Paths are relative to existing, application-controlled roots;
output is optional, and parent directories must already exist. `defaultSchema`
applies only to MySQL, and `groupBySchema` only to SQL DDL. Parsing runs in a
background isolate, then the selected renderer generates the PNG. See
[isolated desktop rendering](isolated-desktop-rendering.md) for path rules,
queue and memory limits, diagnostics, and deployment details.

## Parse and capture in the host process

`parseMermaidFlowchart` returns a `DiagramDocument`;
`parsePostgresDdl` and `parseMysqlDdl` return an `ErSchema`, whose `toDiagram`
method produces a document. `DiagramDocument.fromJson` reads Graph JSON.
`diagramToFlow(document)` returns a `DiagramFlowGraph` with a laid-out
`snapshot` and the original `document`. SQL and Mermaid parsers accept the
subsets described in [PostgreSQL](postgresql-ddl.md), [MySQL](mysql-ddl.md),
and [Mermaid](mermaid-flowchart.md).

Use `renderFlowSnapshot` for in-process capture when you need Flutter widget
builders. It accepts a `FlutterView`, a `FlowGraphSnapshot`, a node builder,
and optional output and appearance settings; the result is `FlowGraphPng`.
For ER data from `diagramToFlow`, `ErTableWidget` renders the node's columns
and `ErSchemaWidget` renders a schema group. `edgeLabelMaxWidth: 320` together
with `compactEdgeLabels: true` enables the worker's wrapping and bounded label
placement. Custom label builders are supported, but do not use the built-in
collision placement and must fit within the measured bounds plus
`edgeLabelOutset`. In-process capture needs a running Flutter view; it supports
image limits but does not provide worker-process isolation or a process memory
limit.

## Errors and compatibility

`FlowWorkerException` exposes `code`, `message`, and optional `diagnostics`.
Common codes include `INPUT_NOT_FOUND`, `INPUT_READ_ERROR`, `INPUT_TOO_LARGE`,
`PARSE_ERROR`, `SCHEMA_ERROR`, `GRAPH_REFERENCE_ERROR`, `RESOURCE_EXHAUSTED`,
`RENDER_INIT_ERROR`, `RENDER_TIMEOUT`, `IMAGE_TOO_LARGE`, `PNG_ENCODE_ERROR`,
and `OUTPUT_WRITE_ERROR`. Invalid caller options can throw `ArgumentError`;
direct parser and document APIs can throw `FormatException` subclasses.
Experimental worker protocol and platform behavior may change; use the Dart
services rather than constructing process requests directly.
