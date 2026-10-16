# Performance and benchmarks

FFlow keeps node/edge identity and adjacency in `FlowGraphIndex`, caches
`FlowEdgePathResult` values by endpoint geometry and edge path settings, and
uses a uniform-grid broad phase before precise edge path hit testing. Selection,
paint color, and animation state do not invalidate a cached path. Static edges
do not subscribe to animation ticks.

Run `flutter test benchmark/large_graph_benchmark_test.dart` to produce
`benchmark/results.json` with measurements for fixed graph/query inputs at
100, 500, 1,000, and 5,000 nodes. Timings vary by host. The JSON includes index and spatial-index build time,
geometry-cache hits and misses, query time, and average broad-phase edge
candidates. Record Flutter/Dart version, OS, device, and power mode alongside
any published result. The benchmark uses Flutter geometry APIs, so it runs in
Flutter's test runtime rather than the standalone Dart VM.

The CI job archives benchmark JSON for comparison. It does not enforce a timing
threshold until maintainers have collected stable baselines for Windows, Web,
Linux, and macOS. The 5,000-node acceptance goal is no crash and a documented
degradation strategy; it is not a promise of a particular frame rate.
