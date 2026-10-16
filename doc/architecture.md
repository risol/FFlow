# FFlow architecture

FFlow is a Flutter SDK package. The repository root contains reusable graph models, interaction logic, rendering, utilities, and the public API. `example/` is an independent consumer app and owns demo-specific node widgets, editor chrome, and platform runners.

## Source layout

```text
lib/
  fflow.dart
  src/
    canvas/flow_canvas.dart             Graph canvas and gesture lifecycle
    controllers/flow_canvas_controller.dart  Pan, zoom, fit, centering, and coordinate conversion
    controllers/flow_graph_controller.dart   Observable graph state and query/update API
    controllers/flow_history_controller.dart  Bounded transaction history
    controllers/flow_clipboard.dart      Copy, cut, paste, and identifier remapping
    geometry/flow_geometry.dart          Coordinate conversion and edge paths
    geometry/flow_edge_geometry_cache.dart  Cached geometry and spatial hit testing
    interactions/flow_graph_interaction.dart  Connection validation and edge edits
    interactions/flow_extension_adapters.dart  Layout, router, and collaboration contracts
    models/                               Nodes, edges, handles, index, diagnostics, snapshots
    rendering/                            Edge/grid painters and default handle widget
    utils/flow_graph_utils.dart           Immutable graph list operations
    widgets/                             Controls and minimap
example/
  lib/                                   Workflow editor demo
  windows/, linux/, macos/, web/         Supported demo application runners
doc/architecture.md                     Package boundaries and design notes
```

The example imports only `package:fflow/fflow.dart`; it should not import `lib/src/`. Internal modules can then change without making those implementation details part of the supported API.

## Ownership and event flow

The host app can own controlled node and edge lists, or use `FlowGraphController` as its observable graph store. `FFlowCanvas` reports controlled-list changes through `onNodesChanged` and `onEdgesChanged`; with a graph controller, it reads and writes the controller state directly. It reports a validated connection through `onConnect`; the host creates an edge and adds it to the selected state source. Selection state is reflected in the `selected` model fields and reported as a `FlowSelection`.

```text
host lists or FlowGraphController
    │ nodes / edges
    ▼
FFlowCanvas ── gestures ──> callbacks/controller updates
    │
    ├── controllers: graph state and viewport transforms
    ├── graph index: identity, hierarchy, adjacency, and handles
    ├── geometry/cache: coordinates, edge paths, bounds, and spatial hit tests
    ├── interactions: validation, reconnect, move
    ├── history/clipboard: graph transactions and copy/paste
    └── rendering: static/animated edges, handles, background
```

The SDK has no third-party package dependencies. Application-specific node data remains typed and is rendered by the `nodeBuilder`. Applications can register custom edges by `customType` or by a built-in edge type name.

## Current interaction coverage

- Pan and pinch zoom, `FlowCanvasController`, fit-to-view, and coordinate conversion.
- Node drag, group drag, parent-relative subflows, eight-direction resize, optional content measurement, single/multi-select, shift-drag box selection, and keyboard delete/select-all/escape.
- Named source/target handles, strict and loose source-to-source connections, connection previews, maximum-connection checks, duplicate prevention, and application validation.
- Click-to-connect, floating edge endpoints, z-order control, and node/edge/pane pointer lifecycle callbacks.
- Bezier, straight, step, and smooth-step paths; labels, markers, hit testing, selection, animated edges, and reconnectable endpoints.
- Hidden/selectable/deletable node and edge options, custom node/edge renderers, controls, dotted/line/cross backgrounds, and interactive minimap.
- Observable graph controller, immutable graph helpers, change application, filtered node/handle and neighborhood queries, rectangle intersection checks, deletion, and typed graph snapshots with caller-provided node-data codecs.
- Indexed node/edge lookup, parent and adjacency queries, geometry caching, and broad-phase spatial hit testing.
- Optional graph diagnostics, transaction history, keyboard undo/redo, clipboard operations, alignment helpers, and layout/router adapter contracts.

The SDK models React Flow's graph concepts and common editor interactions. React hooks, DOM/CSS node behavior, React-specific plugins, and the broader extension ecosystem are not Flutter APIs and are not emulated one-for-one.

Parent nodes position children relative to themselves and render beneath descendants. Extent constraints and automatic parent resizing are supported. History and clipboard are part of the core SDK; FFlow defines layout, routing, and collaboration operation contracts but leaves concrete algorithms, transport, CRDTs, and conflict resolution to optional packages or host applications. React Flow's hook/store APIs remain framework-specific.

## Dependency direction

`models` has no dependency on the canvas. `geometry` depends on models; `interactions` depends on geometry and models; painters and widgets depend on the lower-level modules. The public barrel exports supported symbols from `lib/fflow.dart`, while `src/` remains an implementation namespace.
