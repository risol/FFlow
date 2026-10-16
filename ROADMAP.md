# FFlow roadmap

## M0 — Stability baseline

Complete: expanded scene hit testing, origin-aware geometry, keyboard event
consumption, hidden selection policy, and regression coverage.

## M1 — Graph and API correctness

Complete: nullable `copyWith` sentinels, cascade delete results, graph
diagnostics, formal loose-mode semantics, nullable reconnect handle events, and
versioned snapshots with legacy migration.

## M2 — Performance foundation

Complete: graph index, edge geometry cache and result type, separate static and
animated edge painters, spatial broad-phase hit testing, and deterministic
benchmark harness. Performance thresholds remain tied to recorded platform
baselines.

## M3 — Interaction completeness

Complete: interaction isolation scopes, drag thresholds, controlled viewport,
edge box selection, and per-interaction ticker-driven auto-pan.

## M4 — Editor productivity

Complete: transaction history with undo/redo, clipboard operations, and optional
alignment guides with snapping.

## M5 — Extension ecosystem

Complete: layout and router adapter contracts, editable edge control points,
node-on-edge-drop intent, optional proximity connection callbacks, and dynamic
group reparenting. Concrete layout/router implementations remain optional
packages.

## M6 — 1.0 hardening

The repository now has platform build workflows, migration and interaction
documentation, accessibility guidance, and package gates. A 1.0 release still
requires maintainers to collect platform benchmark baselines, complete the
declared support matrix on available hosts, review API compatibility, and choose
a release version and publication date.

## Post-1.0

The collaboration operation adapter defines a transaction boundary for optional
transport packages. FFlow does not include a collaboration server, CRDT engine,
or conflict-resolution policy.
