# Changelog

Notable changes to FFlow are recorded here. Entries stay under `Unreleased` until they are included in a versioned release.

## 0.1.0

### Added

- Initial Flutter SDK for controlled node and edge canvases, custom node and edge rendering, viewport controls, graph utilities, and typed graph snapshots.
- Example workflow editor targeting Windows, Linux, macOS, and Web.
- Platform support notes and a feature comparison with React Flow in the README.
- Keyboard and screen-reader semantics, configurable selection/connection behavior, interaction lifecycle callbacks, node origins/extents, parent expansion, edge toolbar and path options, and opt-in viewport culling.
- Observable `FlowGraphController` queries and updates, click-to-connect, floating edges, node measurement and resizing, z-order, pointer callbacks, and additional viewport controller methods.
- Loose-mode source-to-source connections with snapshot persistence, filtered graph queries, and node/rectangle intersection checks.
- Typed `onNodesChange` / `onEdgesChange` callbacks, canvas implementation split by interaction/rendering/change responsibilities, and graph/canvas tests.
- Graph indexing, edge geometry results/cache, spatial broad-phase hit testing, versioned snapshots, and graph diagnostics.
- Transaction-based history, clipboard operations, alignment guides, adapter contracts for layout/routing/collaboration, editable edge points, connection-drop and proximity intents, and dynamic group reparenting.
- Controlled and initial-fit viewports, animated viewport helpers, per-interaction auto-pan, nested interaction scopes, drag thresholds, and full/partial edge box selection.
- CI and release build workflows, deterministic large-graph benchmark, contributor guide, and coordinate/interaction/accessibility/migration documentation.

### Changed

- Removed Android and iOS runners from the example; mobile platforms are outside this project's target scope.
- Nullable model `copyWith` arguments can explicitly clear fields; delete results expose the actual cascade-deleted entities.
- Select-all excludes hidden elements by default; loose connections support source-to-source and explicitly reject target-to-target. Snapshots use schema version 1 and omit transient selection unless requested.
- Fixed distant-node handle hit testing, nested control gesture arbitration, stationary-pointer auto-pan, and selected-edge reconnect hit targets.
- Added reconnect capacity/validation, keyboard deletion/cancel, scroll/slider, workflow lifecycle, and visual golden regression coverage.
