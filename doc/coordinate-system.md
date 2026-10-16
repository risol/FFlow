# Coordinate system

FFlow uses four coordinate concepts:

- `FlowNode.position` is an anchor point selected by `origin`.
- A node's absolute top-left is `position - size * origin`, accumulated through
  its parent chain.
- Graph or flow coordinates are independent of the viewport transform.
- Viewport coordinates are local screen pixels inside the canvas.

The viewport maps graph points to screen points as:

```text
screen = translation + zoom * graph
graph = (screen - translation) / zoom
```

For parented nodes, `position` is expressed in the parent's coordinate space.
Use `FlowGeometry.nodeAbsoluteTopLeft`, `nodeAbsoluteAnchor`, `nodeRect`, and
`handleAnchor` when reading geometry. Drag and resize operations write back the
anchor position rather than silently changing it to top-left semantics.

The canvas may pad its internal scene bounds so Flutter can hit-test nodes at
negative or distant graph coordinates. `FlowCanvasController` keeps its public
viewport and conversion APIs in graph coordinates while it compensates for
that internal padding.
