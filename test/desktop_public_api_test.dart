import 'package:fflow/fflow_desktop_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('desktop entry point exposes parsing, ER widgets and PNG capture',
      (tester) async {
    final schema = parseMysqlDdl('''
CREATE TABLE customers (id int PRIMARY KEY);
CREATE TABLE orders (id int PRIMARY KEY, customer_id int,
  FOREIGN KEY (customer_id) REFERENCES customers(id));
''', defaultSchema: 'shop');
    final DiagramDocument document = schema.toDiagram(groupBySchema: true);
    final DiagramFlowGraph graph = diagramToFlow(document);
    expect(graph.snapshot.edges, hasLength(1));
    expect(FlowFileFormat.values, contains(FlowFileFormat.mysqlDdl));
    const options = FlowRenderOptions(
        theme: DiagramTheme.light,
        direction: DiagramDirection.lr,
        edgeRouting: FlowExportEdgeRouting.orthogonal);
    options.validate();
    final renderer = FlowIsolatedRenderService(executable: 'worker.exe');
    expect(renderer.maxPendingTasks, 8);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      final image = await renderFlowSnapshot<Map<String, Object?>>(
        view: tester.view,
        snapshot: graph.snapshot,
        pixelRatio: 1,
        compactEdgeLabels: true,
        edgeLabelMaxWidth: 320,
        nodeBuilder: (context, node, selected) {
          final data = node.data;
          final label = data['label'] as String;
          if (node.type == 'erSchema') {
            return ErSchemaWidget(
                label: label, foreground: Colors.black, border: Colors.black);
          }
          final diagram = data['diagram'] as Map;
          final nodeData = diagram['data'] as Map;
          return ErTableWidget(
              label: label,
              columns: nodeData['columns'] as List,
              background: Colors.white,
              foreground: Colors.black,
              border: Colors.black);
        },
      );
      expect(image.bytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      expect(image.logicalSize.width, greaterThan(0));
    });
  });
}
