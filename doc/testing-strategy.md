# Testing strategy

FFlow uses three layers of tests. Unit and widget tests protect the reusable
SDK; an integration test launches the example application and exercises its
visible workflow editing path.

## Test layers

| Layer | Location | What it verifies | CI command |
| --- | --- | --- | --- |
| Unit | `test/*_test.dart` | Graph updates and queries, geometry, hit-test ordering, caches, snapshots, history, clipboard, viewport math, layered/force layouts, obstacle routing, and collapsible groups. | `flutter test --coverage` |
| Widget | `test/*_test.dart` | Canvas gestures, keyboard and semantics, controls, minimap, rendering baseline, and interaction regressions. | Included in `flutter test --coverage` |
| App integration | `example/integration_test/` | Launches the example runner and covers workflow import/export, add/undo/redo, group/collapse/expand, edge routing and both layout actions, workflow run/stop, drag-to-connect, keyboard copy/paste, node property edits, cascade deletion, and invalid-import recovery. | `cd example && xvfb-run -a flutter test integration_test/fflow_editor_test.dart -d linux` |

The app integration test runs against the Linux runner in CI under Xvfb. The
ordinary `flutter test` suite remains fast and platform-independent.

## Coverage and follow-up work

CI uploads `coverage/lcov.info` as an artifact so the first instrumented run
provides a baseline. Add a numeric coverage gate only after reviewing that
baseline; a single percentage can hide untested public behaviors. When adding
or changing a public API, add a focused unit test for its contract. When adding
an interaction or widget, cover the user-visible behavior and an important
failure or boundary case. Extend the app integration test when a change spans
the example UI, graph state, and snapshot workflow.

Remaining areas to grow include platform-specific runs for the other supported
targets, paint-level coverage for edge variants, and example-app integration
coverage for edge reconnection, node drag/resize, keyboard navigation, and
responsive layouts. The widget suite already exercises reconnect, viewport
culling, keyboard navigation, and copy/paste without launching the example
runner.
