# DiagramDocument Graph JSON v1

The machine-readable structural schema is
[`diagram-document.schema.json`](diagram-document.schema.json). In addition to
that schema, `DiagramDocument.fromJson` checks unique node, edge and per-node
port IDs; endpoint existence and port direction; parent existence and cycles;
finite values; a maximum nesting depth of 64 for retained JSON values; and a
maximum parent depth of 128 nodes.
Version must be the integer `1`. Unknown properties are preserved at their
original location when serializing. They are not automatically interpreted.

```json
{
  "schemaVersion": 1,
  "diagramType": "flowchart",
  "title": "订单处理",
  "theme": "light",
  "layout": {"mode": "auto", "direction": "TB"},
  "nodes": [
    {"id": "start", "label": "开始", "ports": [{"id": "out", "kind": "source", "side": "bottom"}]},
    {"id": "finish", "label": "完成", "style": {"background": "#e7f0fb"}}
  ],
  "edges": [{"id": "next", "source": "start", "sourcePort": "out", "target": "finish", "label": "成功"}],
  "metadata": {}
}
```

Parse with `DiagramDocument.parse` or `DiagramDocument.fromJson`. `auto`
discards input positions and applies the FFlow layered engine in LR, RL, TB or
BT direction. `preserve` requires every node's position; a child's position is
relative to its parent. Node dimensions default to 220 × 96 logical pixels.
For automatic layout, `layout.nodeOrder` can be `input` (the default), `id`,
or `label`. ID and label ordering use Dart string comparison, with IDs breaking
label ties. This changes layout order without changing the document's original
node serialization order.
Flowchart connections use straight or orthogonal segments by default; bounded
obstacle-aware routing applies to graphs of up to 500 nodes and 1,000 edges.
The FFlow adapter carries each node and edge's original data and extra fields
and places the complete document in the `fflowDiagram` snapshot namespace.
Flowchart export uses straight or orthogonal connections. For reciprocal
connections on diamonds and ellipses, the generated FFlow handles may include
a normalized `anchor` point on the outline; snapshots preserve that point.
Simple decision/retry loops may also include a `junctionPoints` entry on an
edge to mark where the return path merges with the incoming main line. These
points are stored in graph coordinates and survive FFlow snapshot round trips.

The current Windows worker supports light, dark and print themes; titles; node
`background`, `foreground`, `border` colors; edge `color` and `strokeWidth`;
explicit ports; and directed or `undirected` edges. Colors use `#RRGGBB` or
`#AARRGGBB`. Node `type` or `style.shape` can select `rectangle`, `rounded`,
`diamond`/`decision`, `stadium`/`terminal`, or `circle`/`ellipse`; an ellipse fills the declared
node rectangle, so use a square size for a circle. Other node types, relation
types and style fields are preserved
but do not yet have dedicated visual renderers. Arbitrary business JSON is not
inferred or mapped automatically. A limited Mermaid flowchart parser is
documented in [`mermaid-flowchart.md`](mermaid-flowchart.md). The PostgreSQL
DDL subset and ER rendering are documented in
[`postgresql-ddl.md`](postgresql-ddl.md). Complete theme customization remains
future work. Root-confined file input is available through
`FlowFileRenderService`.

```dart
final document = DiagramDocument.parse(graphJsonText);
final result = await renderer.renderDiagram(document, pixelRatio: 2);
// result.pngBytes, result.width, result.height, result.elapsed
```
