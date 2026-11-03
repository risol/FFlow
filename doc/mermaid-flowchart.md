# Mermaid flowchart subset

`parseMermaidFlowchart` parses text into a `DiagramDocument`, and
`FlowIsolatedRenderService.renderMermaid` parses and renders it through the
hidden Windows worker. The input is data: it is never executed and does not
load external resources.

```dart
final image = await renderer.renderMermaid('''
flowchart TB
  A([开始]) --> B{是否通过}
  B -->|是| C([完成])
  B -- 否 --> D[重试]
  D --> B
''', title: '审批流程');
```

Supported syntax:

- A `graph` or `flowchart` header followed by `LR`, `RL`, `TB`, `BT` or
  `TD` (an alias for `TB`).
- Node IDs made of ASCII letters, numbers, underscores and non-ASCII code
  units; `[text]`, `(text)`, `([text])`, `((text))` and `{text}` select rectangle,
  rounded rectangle, stadium terminator, circle and diamond respectively. An unadorned ID is a
  rectangular node with the ID as its label.
- `-->` directed links and `---` undirected links, including chains such as
  `A --> B --> C`. Link labels use `-->|label|` or `-- label -->`.
- Newlines or semicolons between statements, `%%` comments, Chinese text,
  and quoted node or pipe-delimited link labels. Inside these quoted labels,
  `\"` and `\\` escape a quote and backslash; raw newlines inside a label
  are not supported. The `-- label -->` form treats its label as plain text.
- A later explicit node declaration replaces its earlier label and shape;
  references without a shape never overwrite an explicit declaration.

The parser rejects unsupported directives and syntax with a
`MermaidParseException` carrying one-based `line` and `column` and a UTF-16
`offset`. It limits input to 2 MB, 5,000 nodes and 10,000 edges. Subgraphs,
styling/class directives, click actions, HTML interpretation, dotted or thick
links, multi-node junctions and additional Mermaid diagram types are not
supported. Quote a label that begins with a shape delimiter. Layout uses the
existing FFlow layered engine, aligns simple entry and exit paths to their
branch, and uses straight or orthogonal connectors. For up to 500 nodes and
1,000 edges it routes around nearby node obstacles; larger graphs use a bounded
step-routing fallback. Complex cycles can still have crossing lines or
overlapping labels.

## Reciprocal cycle routes

For a simple decision/retry loop with a clear incoming main line, the return
joins that line at a marked junction and includes a direction arrow. For other
automatically laid-out flowcharts, an isolated pair of opposite edges
between root nodes with implicit ports uses separate lanes and distinct points
on a non-rectangular outline when the corridor between the nodes is clear. A longer same-layer cycle edge can also be routed
around intervening nodes when a clear side corridor exists, and adjacent
same-layer nodes use facing ports. Explicit ports,
nested nodes, larger graphs and other complex cycles may retain ordinary
routing; their labels can still overlap.
