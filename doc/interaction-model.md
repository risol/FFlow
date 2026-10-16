# Interaction model

Canvas input is arbitrated by Flutter's gesture arena. Node widgets remain
ordinary Flutter subtrees, so nested controls can keep their own tap, text,
scroll, and drag behavior.

Wrap a control in `FFlowNoDrag` when node movement must not start from that
control. Wrap a region in `FFlowNoPan` to keep viewport panning disabled for its
pointer sequence, and use `FFlowNoWheel` for scrollable or zoom-sensitive child
content. `FFlowNodeDragHandle` marks the only draggable region when a node sets
`dragHandleOnly: true`.

`nodeDragThreshold` and `connectionDragThreshold` are measured in screen pixels.
The framework still applies its platform gesture slop; the FFlow thresholds
add a configurable minimum before an interaction session starts.

Loose connection mode supports source-to-source connections in addition to
source-to-target. Target-to-target connections are not accepted. Reconnect
events retain a nullable handle id; `null` means the node's resolved default
handle rather than an empty-string placeholder.

Box selection applies `selectionMode` to nodes and `edgeSelectionMode` to edge
paths. Partial edge selection detects path/rectangle crossing; full selection
requires the complete path bounds to fit inside the selection rectangle.

Auto-pan uses a ticker and runs independently for node dragging, connection
gestures, and selection. Each mode can be turned off separately. A gesture
stops auto-pan as soon as it ends or is cancelled.
