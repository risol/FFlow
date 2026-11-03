import 'package:fflow/diagram.dart';
import 'package:fflow/diagram_fflow.dart';
import 'package:fflow/fflow.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('automatic layout follows the configured node order', () {
    for (final (order, firstId) in [
      ('input', 'b'),
      ('id', 'a'),
      ('label', 'b')
    ]) {
      final doc = DiagramDocument.fromJson({
        'schemaVersion': 1,
        'diagramType': 'flowchart',
        'layout': {'direction': 'LR', 'nodeOrder': order},
        'nodes': [
          {'id': 'b', 'label': 'Alpha'},
          {'id': 'a', 'label': 'Zulu'},
        ],
        'edges': [],
      });
      final snapshot = diagramToFlow(doc).snapshot;
      final byId = {for (final node in snapshot.nodes) node.id: node};
      final otherId = firstId == 'a' ? 'b' : 'a';
      expect(byId[firstId]!.position.dy, lessThan(byId[otherId]!.position.dy));
      expect(snapshot.nodes.first.id, 'b',
          reason: 'Serialization order is preserved');
      expect(doc.layout.toJson()['nodeOrder'], order);
    }
    expect(
        () => DiagramDocument.fromJson({
              'schemaVersion': 1,
              'diagramType': 'flowchart',
              'layout': {'nodeOrder': 'random'},
              'nodes': [],
              'edges': [],
            }),
        throwsFormatException);
  });
  test('opposite implicit cycle edges use distinct lanes', () {
    for (final direction in ['LR', 'TB']) {
      final doc = DiagramDocument.fromJson({
        'schemaVersion': 1,
        'diagramType': 'flowchart',
        'layout': {'direction': direction},
        'nodes': [
          {'id': 'a', 'label': 'A'},
          {'id': 'b', 'label': 'B'}
        ],
        'edges': [
          {'id': 'ab', 'source': 'a', 'target': 'b', 'label': 'yes'},
          {'id': 'ba', 'source': 'b', 'target': 'a', 'label': 'no'},
        ],
      });
      final graph = diagramToFlow(doc).snapshot;
      final byId = {for (final node in graph.nodes) node.id: node};
      final a = FlowGeometry.edgePathResult(graph.edges.first, byId)!;
      final b = FlowGeometry.edgePathResult(graph.edges.last, byId)!;
      expect(
          graph.edges.every((edge) => edge.controlPoints.length == 2), isTrue);
      expect((a.labelPosition - b.labelPosition).distance, greaterThan(20));
      expect(
          FlowGraphValidator.validate(nodes: graph.nodes, edges: graph.edges),
          isEmpty);
    }
  });

  test('reciprocal edges retain user-specified ports', () {
    final doc = DiagramDocument.fromJson({
      'schemaVersion': 1,
      'diagramType': 'flowchart',
      'nodes': [
        {
          'id': 'a',
          'label': 'A',
          'ports': [
            {'id': 'custom', 'kind': 'source', 'side': 'top'}
          ]
        },
        {'id': 'b', 'label': 'B'},
      ],
      'edges': [
        {'id': 'ab', 'source': 'a', 'sourcePort': 'custom', 'target': 'b'},
        {'id': 'ba', 'source': 'b', 'target': 'a'},
      ],
    });
    final edges = diagramToFlow(doc).snapshot.edges;
    expect(edges.first.sourceHandleId, 'custom');
    expect(edges.every((edge) => edge.controlPoints.isEmpty), isTrue);
  });

  test('long cycle edges avoid the node between their endpoints', () {
    for (final direction in ['LR', 'RL', 'TB', 'BT']) {
      final doc = DiagramDocument.fromJson({
        'schemaVersion': 1,
        'diagramType': 'flowchart',
        'layout': {'direction': direction},
        'nodes': [
          for (final id in ['a', 'b', 'c']) {'id': id, 'label': id}
        ],
        'edges': [
          {'id': 'ab', 'source': 'a', 'target': 'b'},
          {'id': 'bc', 'source': 'b', 'target': 'c'},
          {'id': 'ca', 'source': 'c', 'target': 'a'},
        ],
      });
      final snapshot = diagramToFlow(doc).snapshot;
      final nodes = {for (final node in snapshot.nodes) node.id: node};
      final edge = snapshot.edges.singleWhere((edge) => edge.id == 'ca');
      final adjacent = snapshot.edges.singleWhere((edge) => edge.id == 'ab');
      final start = FlowGeometry.edgeSource(adjacent, nodes)!;
      final end = FlowGeometry.edgeTarget(adjacent, nodes)!;
      if (direction == 'LR' || direction == 'RL') {
        expect(start.dy, lessThan(end.dy));
      } else {
        expect(start.dx, lessThan(end.dx));
      }
      expect(edge.controlPoints, hasLength(2));
      final middle = FlowGeometry.nodeRect(nodes['b']!, nodes);
      if (direction == 'LR' || direction == 'RL') {
        expect(
            edge.controlPoints.first.dx > middle.right ||
                edge.controlPoints.first.dx < middle.left,
            isTrue);
      } else {
        expect(
            edge.controlPoints.first.dy > middle.bottom ||
                edge.controlPoints.first.dy < middle.top,
            isTrue);
      }
      expect(
          FlowGraphValidator.validate(
              nodes: snapshot.nodes, edges: snapshot.edges),
          isEmpty);
    }
  });
  test('maps ports, styles and four layout directions into FFlow', () {
    for (final direction in ['LR', 'RL', 'TB', 'BT']) {
      final document = DiagramDocument.fromJson({
        'schemaVersion': 1,
        'diagramType': 'flowchart',
        'layout': {'direction': direction},
        'nodes': [
          {
            'id': 'a',
            'label': '开始',
            'ports': [
              {'id': 'out', 'kind': 'source', 'side': 'right'}
            ]
          },
          {
            'id': 'b',
            'label': '结束',
            'ports': [
              {'id': 'in', 'kind': 'target', 'side': 'left'}
            ]
          },
        ],
        'edges': [
          {
            'id': 'e',
            'source': 'a',
            'target': 'b',
            'sourcePort': 'out',
            'targetPort': 'in',
            'style': {'color': '#ff0000', 'strokeWidth': 3}
          },
        ],
      });
      final result = diagramToFlow(document);
      final first = result.snapshot.nodes.first;
      final second = result.snapshot.nodes.last;
      final edge = result.snapshot.edges.single;
      expect(edge.sourceHandleId, 'out');
      expect(edge.targetHandleId, 'in');
      expect(edge.color, const Color(0xffff0000));
      expect(edge.strokeWidth, 3);
      expect(
          FlowGraphValidator.validate(
              nodes: result.snapshot.nodes, edges: result.snapshot.edges),
          isEmpty);
      switch (direction) {
        case 'LR':
          expect(first.position.dx, lessThan(second.position.dx));
        case 'RL':
          expect(first.position.dx, greaterThan(second.position.dx));
        case 'TB':
          expect(first.position.dy, lessThan(second.position.dy));
        case 'BT':
          expect(first.position.dy, greaterThan(second.position.dy));
      }
      expect((result.toSnapshotJson()['fflowDiagram'] as Map)['document'],
          document.toJson());
    }
  });

  test('preserves explicit positions and parent-local coordinates', () {
    final doc = DiagramDocument.fromJson({
      'schemaVersion': 1,
      'diagramType': 'flowchart',
      'layout': {'mode': 'preserve'},
      'nodes': [
        {
          'id': 'g',
          'label': 'group',
          'position': {'x': 300, 'y': 50}
        },
        {
          'id': 'c',
          'label': 'child',
          'parentId': 'g',
          'position': {'x': 20, 'y': 30}
        },
      ],
      'edges': [],
    });
    final graph = diagramToFlow(doc);
    expect(graph.snapshot.nodes.last.position, const Offset(20, 30));
    final index = {for (final node in graph.snapshot.nodes) node.id: node};
    expect(FlowGeometry.absolutePosition(graph.snapshot.nodes.last, index),
        const Offset(320, 80));
  });

  test('auto layout keeps nested child coordinates relative to its parent', () {
    final doc = DiagramDocument.fromJson({
      'schemaVersion': 1,
      'diagramType': 'flowchart',
      'nodes': [
        {'id': 'root', 'label': 'root'},
        {'id': 'g', 'label': 'group'},
        {'id': 'c', 'label': 'child', 'parentId': 'g'},
      ],
      'edges': [
        {'id': 'e', 'source': 'root', 'target': 'g'}
      ],
    });
    final graph = diagramToFlow(doc);
    final byId = {for (final node in graph.snapshot.nodes) node.id: node};
    expect(byId['g']!.position.dx, greaterThan(0));
    expect(byId['c']!.position, const Offset(32, 32));
    expect(FlowGeometry.absolutePosition(byId['c']!, byId),
        byId['g']!.position + const Offset(32, 32));
  });

  test('implicit ports follow the requested layout direction', () {
    const expected = {
      'LR': [FlowHandlePosition.right, FlowHandlePosition.left],
      'RL': [FlowHandlePosition.left, FlowHandlePosition.right],
      'TB': [FlowHandlePosition.bottom, FlowHandlePosition.top],
      'BT': [FlowHandlePosition.top, FlowHandlePosition.bottom],
    };
    for (final entry in expected.entries) {
      final doc = DiagramDocument.fromJson({
        'schemaVersion': 1,
        'diagramType': 'flowchart',
        'layout': {'direction': entry.key},
        'nodes': [
          {'id': 'n', 'label': 'Node'}
        ],
        'edges': [],
      });
      final handles = diagramToFlow(doc).snapshot.nodes.single.resolvedHandles;
      expect(
          handles.singleWhere((h) => h.type == FlowHandleType.source).position,
          entry.value[0]);
      expect(
          handles.singleWhere((h) => h.type == FlowHandleType.target).position,
          entry.value[1]);
    }
  });
}
