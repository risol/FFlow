import 'package:fflow/diagram.dart';
import 'package:fflow/diagram_fflow.dart';
import 'package:fflow/fflow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses shapes, labels, directions, chained edges, comments and cycles',
      () {
    final graph = parseMermaidFlowchart('''
%% 注释
flowchart TB
start["开始：订单"] --> decision{是否通过}
decision -->|是| done((完成))
decision -- 否 --> retry(重试)
retry --> decision; done --- audit["归档;留存"] %% comment
''', title: '审批流程');
    expect(graph.title, '审批流程');
    expect(graph.layout.direction, DiagramDirection.tb);
    expect(graph.nodes.map((n) => n.id),
        ['start', 'decision', 'done', 'retry', 'audit']);
    expect(graph.nodes.map((n) => n.type),
        ['rectangle', 'diamond', 'circle', 'rounded', 'rectangle']);
    expect(graph.nodes.last.label, '归档;留存');
    expect(graph.edges.map((e) => e.label), [null, '是', '否', null, null]);
    expect(graph.edges.last.type, 'undirected');
    expect(graph.metadata['sourceFormat'], 'mermaid');
    final flow = diagramToFlow(graph);
    expect(
        FlowGraphValidator.validate(
            nodes: flow.snapshot.nodes, edges: flow.snapshot.edges),
        isEmpty);
    expect(flow.snapshot.edges.last.markerEnd, isNull);
    expect(
        flow.snapshot.nodes.first.resolvedHandles
            .singleWhere((h) => h.type == FlowHandleType.source)
            .position,
        FlowHandlePosition.bottom);
  });

  test('plain references retain declarations; last explicit declaration wins',
      () {
    final graph = parseMermaidFlowchart(
        'graph LR; A --> B; B["first"] --> C; B(("last")); A --> B');
    expect(graph.nodes.singleWhere((n) => n.id == 'B').label, 'last');
    expect(graph.nodes.singleWhere((n) => n.id == 'B').type, 'circle');
    expect(graph.edges.length, 3);
    expect(graph.edges.map((e) => e.id).toSet().length, 3);
  });

  test('empty graphs, Unicode IDs and escaped quoted text', () {
    expect(parseMermaidFlowchart('graph LR').nodes, isEmpty);
    final graph =
        parseMermaidFlowchart('graph RL\r\n节点["a \\"b\\" \\\\ c"]\r\n');
    expect(graph.nodes.single.id, '节点');
    expect(graph.nodes.single.label, 'a "b" \\ c');
  });

  test('expands chained edges and maps TD to TB', () {
    final graph = parseMermaidFlowchart('flowchart TD; A-->B-->C; C---A');
    expect(graph.layout.direction, DiagramDirection.tb);
    expect(graph.edges.map((e) => '${e.source}:${e.target}'),
        ['A:B', 'B:C', 'C:A']);
    expect(graph.edges.last.type, 'undirected');
  });

  test('reports source line and column for unsupported or invalid syntax', () {
    void fails(String text, int line, String message) {
      expect(
          () => parseMermaidFlowchart(text),
          throwsA(
            isA<MermaidParseException>()
                .having((e) => e.line, 'line', line)
                .having((e) => e.column, 'column', greaterThan(0))
                .having((e) => e.message, 'message', contains(message)),
          ));
    }

    fails('sequenceDiagram\nA-->B', 1, 'Only graph and flowchart');
    fails('flowchart TB\nA -->\nB', 2, 'node identifier');
    fails('flowchart LR\nA[unterminated\nB', 2, 'Unterminated label');
    fails('flowchart LR\nsubgraph X\nend', 2, 'Unsupported Mermaid directive');
    fails('flowchart LR\nA -.-> B', 2, 'Expected -->');
    fails('flowchart LR\nA([stadium])', 2, 'Unsupported node shape');
    fails('flowchart LR\nA[/parallelogram/]', 2, 'Unsupported node shape');
    fails('flowchart XX\nA', 1, 'Unsupported flowchart direction');
  });
}
