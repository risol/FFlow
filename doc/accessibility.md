# Accessibility and localization

Nodes and edges expose focusability and accessible labels, and the canvas
announces selection changes. Keep node labels concise and meaningful; provide
application-localized strings through `ariaLabel`, `canvasLabel`,
`selectionAnnouncementBuilder`, and the `FFlowControls` labels.

Keyboard navigation supports Tab focus, Enter/Space selection, arrow-key node
movement, select-all, delete, Escape, and optional history and clipboard
shortcuts. Canvas shortcuts yield to editable text fields. Hidden graph elements
are not included in select-all unless configured.

When adding a custom node, preserve semantic labels for interactive controls and
ensure focus order follows the visual graph order. Applications should run
Flutter's semantics debugger and platform accessibility tools on their own node
widgets; FFlow cannot infer labels for arbitrary custom UI.
