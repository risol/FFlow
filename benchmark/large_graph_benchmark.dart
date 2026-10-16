import 'package:fflow/fflow.dart';
import 'package:flutter/widgets.dart';

/// Runs deterministic large-graph index, geometry, and hit-test benchmarks.
///
/// This uses Flutter geometry types and should run through the Flutter test
/// runner, which writes the machine-readable artifact.
Map<String, Object?> runLargeGraphBenchmark() {
  const cases = [100, 500, 1000, 5000];
  final output = <Map<String, Object?>>[];
  for (final nodeCount in cases) {
    final columns = 100;
    final nodes = List<FlowNode<int>>.generate(nodeCount, (index) {
      final x = (index % columns) * 180.0;
      final y = (index ~/ columns) * 120.0;
      return FlowNode<int>(
        id: 'n$index',
        position: Offset(x, y),
        data: index,
        width: 100,
        height: 60,
      );
    }, growable: false);
    final edgeCount = nodeCount + nodeCount ~/ 2;
    final edges = List<FlowEdge>.generate(edgeCount, (index) {
      final source = index % nodeCount;
      final target = (source + 1 + index % 7) % nodeCount;
      return FlowEdge(
        id: 'e$index',
        sourceId: 'n$source',
        targetId: 'n$target',
        type: FlowEdgeType.smoothStep,
      );
    }, growable: false);

    final graphWatch = Stopwatch()..start();
    final graph = FlowGraphIndex<int>(nodes: nodes, edges: edges);
    graphWatch.stop();

    final geometryCache = FlowEdgeGeometryCache();
    final geometryWatch = Stopwatch()..start();
    for (final edge in edges) {
      geometryCache.result(edge, graph.nodesById);
    }
    geometryWatch.stop();

    final hitIndex = FlowHitTestIndex();
    final hitWatch = Stopwatch()..start();
    hitIndex.rebuild(
      nodes: nodes,
      edges: edges,
      nodesById: graph.nodesById,
      geometryCache: geometryCache,
    );
    hitWatch.stop();

    const queryCount = 1000;
    final queryWatch = Stopwatch()..start();
    var candidateCount = 0;
    for (var query = 0; query < queryCount; query++) {
      final x = (query * 97) % (columns * 180);
      final y = (query * 131) % (((nodeCount / columns).ceil() + 1) * 120);
      candidateCount +=
          hitIndex.edgeCandidates(Offset(x.toDouble(), y.toDouble())).length;
      graph.nodesById['n${query % nodeCount}'];
    }
    queryWatch.stop();

    output.add({
      'nodes': nodeCount,
      'edges': edgeCount,
      'indexBuildMs': graphWatch.elapsedMicroseconds / 1000,
      'geometryWarmMs': geometryWatch.elapsedMicroseconds / 1000,
      'spatialIndexBuildMs': hitWatch.elapsedMicroseconds / 1000,
      'queries': queryCount,
      'queryMs': queryWatch.elapsedMicroseconds / 1000,
      'averageEdgeCandidates': candidateCount / queryCount,
      'geometryCacheHits': geometryCache.hits,
      'geometryCacheMisses': geometryCache.misses,
    });
  }
  return {
    'seed': 20261016,
    'results': output,
  };
}
