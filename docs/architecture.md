# FFlow architecture

FFlow is a Flutter SDK package. The repository root contains reusable graph models, interaction logic, rendering, utilities, and the public API. `example/` is an independent consumer app and owns demo-specific node widgets, editor chrome, and platform runners.

## Source layout

```text
lib/
  fflow.dart
  src/
    canvas/flow_canvas.dart             Controlled canvas and gesture lifecycle
    controllers/flow_canvas_controller.dart  Pan, zoom, fit, and coordinate conversion
    geometry/flow_geometry.dart         Handle anchors, edge paths, and hit testing
    interactions/flow_graph_interaction.dart  Connection validation and edge edits
    models/                              Nodes, edges, handles, selection, snapshots
    rendering/                           Edge/grid painters and default handle widget
    utils/flow_graph_utils.dart          Immutable graph list operations
    widgets/                             Controls and minimap
example/
  lib/                                   Workflow editor demo
  windows/, linux/, macos/, web/         Supported demo application runners
docs/architecture.md                    Package boundaries and design notes
```

The example imports only `package:fflow/fflow.dart`; it should not import `lib/src/`. Internal modules can then change without making those implementation details part of the supported API.

## Ownership and event flow

The host app owns node and edge lists. `FFlowCanvas` renders those lists and emits immutable replacements through `onNodesChanged` and `onEdgesChanged`. It reports a validated connection through `onConnect`; the host creates an edge and adds it to its state. Selection state is also reflected in the `selected` model fields and reported as a `FlowSelection`.

```text
host app state
    │ nodes / edges
    ▼
FFlowCanvas ── gestures ──> callbacks ──> host app state
    │
    ├── controller: viewport transforms
    ├── geometry: handles, paths, hit tests
    ├── interactions: validation, reconnect, move
    └── rendering: edges, handles, background
```

The SDK has no third-party package dependencies. Application-specific node data remains typed and is rendered by the `nodeBuilder`. Applications can register custom edges by `customType` or by a built-in edge type name.

## Current interaction coverage

- Pan and pinch zoom, `FlowCanvasController`, fit-to-view, and coordinate conversion.
- Node drag, group drag, parent-relative subflows, optional node resize, single/multi-select, shift-drag box selection, and keyboard delete/select-all/escape.
- Named source/target handles, connection previews, maximum-connection checks, duplicate prevention, and application validation.
- Bezier, straight, step, and smooth-step paths; labels, markers, hit testing, selection, animated edges, and reconnectable endpoints.
- Hidden/selectable/deletable node and edge options, custom node/edge renderers, controls, dotted/line/cross backgrounds, and interactive minimap.
- Immutable graph helpers, change application, neighborhood queries, deletion, and typed graph snapshots with caller-provided node-data codecs.

The SDK models React Flow's graph concepts and common editor interactions. React hooks, DOM/CSS node behavior, React-specific plugins, and the broader extension ecosystem are not Flutter APIs and are not emulated one-for-one.

Parent nodes position children relative to themselves and render beneath descendants. Extent constraints, automatic parent resizing, built-in layout algorithms, and React Flow's hook/store APIs remain application-level or future work.

## Dependency direction

`models` has no dependency on the canvas. `geometry` depends on models; `interactions` depends on geometry and models; painters and widgets depend on the lower-level modules. The public barrel exports supported symbols from `lib/fflow.dart`, while `src/` remains an implementation namespace.
