# Changelog

Notable changes to FFlow are recorded here. Entries stay under `Unreleased` until they are included in a versioned release.

## Unreleased

### Added

- Desktop rendering entry points for Dart hosts and Flutter applications, plus reusable ER table and schema widgets.

### Fixed

- Correct package release metadata for the next patch release and improve long ER relationship labels and their placement.

## 0.2.0

### Added

- Experimental Windows hidden rendering worker and Dart APIs for complete-graph PNG export, bounded file input/output, task limits, diagnostics, themes and optional orthogonal routing.
- Versioned Graph JSON, Mermaid flowchart, PostgreSQL and MySQL DDL adapters, ER table and relationship rendering, optional schema grouping, and cycle-routing improvements.
- Bundled Noto Sans SC font, Windows export goldens, integration and stress tools, and desktop rendering documentation.

### Changed

- Add the `path` package for desktop file integration and extend FFlow edge geometry with ER markers and explicit routed points.

## 0.1.5

### Added

- Built-in layered and force-directed layouts, animated layout transitions, incremental node placement, obstacle-aware orthogonal routing, collapsible groups, and example-editor controls for these features.

### Infrastructure

- Automate Linux demo builds in an Ubuntu 20.04 container (glibc 2.31) on Ubuntu 24.04 runners and publish Linux, Windows, macOS, and Web demo archives to GitHub Releases when a version tag is pushed.

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
