# React Flow Pro feature comparison

This comparison uses the public [React Flow Pro examples catalog](https://reactflow.dev/examples/pro-examples), checked on 2026-10-18. It compares feature concepts, not React-specific APIs or private Pro example source code.

## Coverage

| React Flow Pro example area | FFlow status |
| --- | --- |
| Helper lines and snapping | Supported by canvas alignment guides and snap-to-grid. |
| Undo/redo and copy/paste | Supported by `FlowHistoryController` and `FlowClipboard`. |
| Selection grouping and parent/child relationships | Supported by nested nodes, parent expansion, and optional dynamic reparenting. |
| Editable edge control points | Supported by edge `controlPoints` and canvas handles. |
| Auto layout | **Added:** `FlowLayeredLayoutEngine` provides a dependency-free directed layered layout in four directions. Strongly connected nodes stay in one layer, and nested groups are arranged in parent coordinates and expand to fit children. |
| Node position animation | **Added:** `FlowLayoutResult.interpolate` animates node positions and sizes; the example editor uses it for auto and force layout transitions. |
| Force and dynamic layout | **Added:** `FlowForceLayoutEngine` provides deterministic force layout and can place newly added nodes while pinning existing ids. The example editor uses it when adding a node. |
| Obstacle-aware edge routing | **Added:** `FlowOrthogonalEdgeRouter` performs Manhattan routing around visible rectangular node obstacles; `FlowGraphRouting` applies the results to edge control points. |
| Expand and collapse | **Added:** parent nodes can collapse descendants without deleting or moving them; expansion restores nested group visibility. The example editor exposes collapse for a selected group. |
| Freehand drawing | Not included. This is a whiteboard extension rather than a core workflow graph feature. |
| Real-time collaboration | The transaction adapter boundary exists, but transport, persistence, and conflict resolution remain application or package responsibilities. |
| Server-side image generation | Not included; Flutter rendering and deployment targets differ from the React/Puppeteer example. |

## Auto-layout behavior

`FlowLayeredLayoutEngine<T>` accepts nodes and edges and returns a `FlowLayoutResult`. The result can update anchor-aware positions and expanded group sizes through `applyTo`, or interpolate between layouts with `interpolate`. Configure `direction`, `nodeSpacing`, `layerSpacing`, and `groupPadding` on the engine or pass per-call options to `layout`.

The example editor exposes **More → Auto layout**, **Force layout**, and **Route edges**. Layout transitions animate and record the final arrangement as one history transaction. New nodes are force-placed while existing node ids are pinned. Select two or more nodes and choose **More → Group selected nodes** to create a subflow; selecting that group exposes **Collapse group** and **Expand group**.

## Suggested next gaps

1. Add freehand annotations as a separate whiteboard layer that can be serialized alongside a graph snapshot.
2. Provide a collaboration package or documented adapter example for a chosen transport/CRDT, keeping networking out of the core SDK.

React Flow Pro lists these concepts in its [examples catalog](https://reactflow.dev/examples/pro-examples) and describes Pro as access to examples, templates, and support rather than a separate runtime library on its [Pro overview](https://reactflow.dev/pro).
