import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'large_graph_benchmark.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('writes benchmark results for fixed graph and query inputs', () async {
    final result = runLargeGraphBenchmark();
    final results = result['results']! as List<Map<String, Object?>>;
    expect(result['seed'], 20261016);
    expect(results.map((entry) => entry['nodes']), [100, 500, 1000, 5000]);
    expect(results.every((entry) => entry['geometryCacheMisses']! as int > 0),
        isTrue);

    final artifact = File('benchmark/results.json');
    await artifact.writeAsString(
      const JsonEncoder.withIndent('  ').convert(result),
    );
  });
}
