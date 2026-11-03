# Windows desktop rendering acceptance status

This record describes the Windows implementation against the development
plan. It is evidence for the tested configurations, not an assertion that
every possible graph or desktop environment has been validated.

| Plan item | Current evidence and limits |
| --- | --- |
| Hidden window and focus | The native runner does not show or focus its window. A Windows 10 22H2 sampling run observed no visible or foreground window; sampling cannot exclude every transient state. See [the rendering experiment](hidden-rendering-poc.md). |
| Desktop API and four input formats | Isolated Dart service and root-confined file service exercised against a real Windows worker; parser subsets are documented in [Graph JSON](graph-json.md), [Mermaid](mermaid-flowchart.md), and [PostgreSQL](postgresql-ddl.md). |
| Automatic layout and visual quality | FFlow layered layout supports four directions, configurable node ordering, nested schema groups, separate lanes for simple reciprocal flows and clear-corridor routing for some longer cycles. An optional bounded orthogonal router avoids nearby node obstacles, and default labels use bounded collision avoidance. More complex cycles, relationship crossings and custom-label collisions can still need improvement. |
| Complete PNG and scaling | Tests cover negative coordinates, distant edge routes and labels, 1×, 2×, 3×, limits and transparent pixels. Static export requires node builders to remain within declared dimensions. |
| Chinese | The worker bundles Noto Sans SC and loads it before measuring text. A Windows golden covers Chinese title, nodes and edge label. |
| Stability and resources | Short-lived workers have a Windows process commit cap, queue and timeout. A 100-task 2/100-node run initially showed rising host working set; a later uninstrumented 200-task run plateaued from tasks 120 to 200. An instrumented 300-task run included forced collections. Longer runs and other environments remain unverified. |
| Errors and release | Structured error codes, task diagnostics, real-worker recovery tests and Windows Release build are available. Host-specific deployment, signing and final product integration are not covered by this repository. |

The measured 20/100/500-node snapshot and automatic-layout runs, commands,
license information and operational limits are in [desktop integration](isolated-desktop-rendering.md).
