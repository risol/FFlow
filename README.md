# FFlow

FFlow is a reusable Flutter SDK for building interactive node and edge editors. The root package contains the public API and canvas implementation. The runnable workflow editor is an example app under [`example/`](example/).

## Add FFlow to an app

For local development, add the package to your app's `pubspec.yaml`:

```yaml
dependencies:
  fflow:
    path: ../FFlow
```

Then import the public library:

```dart
import 'package:fflow/fflow.dart';
```

Create typed node data in your application and provide a builder for each node:

```dart
FFlowCanvas<MyNodeData>(
  nodes: nodes,
  edges: edges,
  nodeBuilder: (context, node, selected) => MyNodeCard(
    data: node.data,
    selected: selected,
  ),
  onNodesChanged: (updated) => setState(() => nodes = updated),
  onEdgesChanged: (updated) => setState(() => edges = updated),
);
```

Node and edge lists are controlled by the host app. FFlow reports changes through callbacks; the host app stores the updated lists and rebuilds the canvas. The canvas provides panning, zooming, node dragging, connection handles, connection previews, and customizable node widgets.

## Included editor features

- Drag and resize nodes, snap to an optional grid, select multiple nodes and edges, shift-drag a selection box, and use Delete/Backspace, Ctrl/Cmd+A, or Escape.
- Connect named handles with max-connection and custom validation; select and reconnect edges.
- Choose bezier, straight, step, and smooth-step edges; add labels, markers, animation, or custom edge renderers.
- Control pan/zoom, scroll zoom, double-click zoom, and fit-to-view with `FlowCanvasController`; compose `FFlowControls` and `FFlowMiniMap`.
- Use `FlowGraphUtils` for graph edits and `FlowGraphSnapshot` to save/restore typed graph data.

The package has no third-party dependencies. React Flow's React hooks, DOM/CSS behavior, and React-specific integrations do not map directly to Flutter; FFlow exposes equivalent graph concepts through Flutter widgets and Dart APIs.

## SDK entry points

```dart
final controller = FlowCanvasController();

Stack(
  children: [
    FFlowCanvas<MyNodeData>(
      controller: controller,
      nodes: nodes,
      edges: edges,
      nodeBuilder: (context, node, selected) =>
          MyNodeCard(data: node.data, selected: selected),
      onNodesChanged: (value) => setState(() => nodes = value),
      onEdgesChanged: (value) => setState(() => edges = value),
      onConnect: (connection) {
        final edge = FlowGraphInteraction.createEdge(connection, createId());
        if (edge != null) {
          setState(() => edges = FlowGraphUtils.addEdge(edges, edge));
        }
      },
    ),
    FFlowControls(
      controller: controller,
      nodes: nodes,
      viewportSize: canvasSize,
    ),
  ],
)
```

## Run the example

Run these commands from the repository root:

```powershell
cd example
flutter pub get
flutter run -d windows
```

The example also supports Flutter targets configured on the host machine. The SDK itself does not include an application entry point or platform runner.

## Package layout

```text
lib/
  fflow.dart                 Public package API
  src/
    canvas/                  Reusable graph canvas and event orchestration
    controllers/             Viewport controller
    geometry/                Handle and edge geometry
    interactions/            Connection and graph interaction logic
    models/                  Node, edge, handle, selection, snapshot models
    rendering/               Grid, edges, and handles
    utils/                   Immutable graph editing helpers
    widgets/                 Controls and minimap
example/
  lib/                       Runnable demonstration app
  windows/, linux/, web/     Example app platform runners
```
