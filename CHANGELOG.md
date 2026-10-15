# Changelog

Notable changes to FFlow are recorded here. Entries stay under `Unreleased` until they are included in a versioned release.

## Unreleased

### Added

- Initial Flutter SDK for controlled node and edge canvases, custom node and edge rendering, viewport controls, graph utilities, and typed graph snapshots.
- Example workflow editor targeting Windows, Linux, macOS, and Web.
- Platform support notes and a feature comparison with React Flow in the README.
- Keyboard and screen-reader semantics, configurable selection/connection behavior, interaction lifecycle callbacks, node origins/extents, parent expansion, edge toolbar and path options, and opt-in viewport culling.
- Observable `FlowGraphController` queries and updates, click-to-connect, floating edges, node measurement and resizing, z-order, pointer callbacks, and additional viewport controller methods.
- Loose-mode source-to-source connections with snapshot persistence, filtered graph queries, and node/rectangle intersection checks.

### Changed

- Removed Android and iOS runners from the example; mobile platforms are outside this project's target scope.
