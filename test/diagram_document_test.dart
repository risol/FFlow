import 'dart:convert';

import 'package:fflow/diagram.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, Object?> graph() => {
        'schemaVersion': 1,
        'diagramType': 'flowchart',
        'title': '中文流程',
        'metadata': {'owner': '团队'},
        'futureFlag': {
          'nested': [1, true]
        },
        'layout': {'direction': 'BT', 'nodeSpacing': 30, 'futureLayout': 7},
        'theme': 'print',
        'nodes': [
          {
            'id': 'a',
            'label': '开始',
            'size': {'width': 120, 'height': 80},
            'ports': [
              {'id': 'out', 'kind': 'source', 'side': 'right'}
            ],
            'data': {
              'custom': [1, 2]
            },
            'futureNode': 'preserved',
          },
          {
            'id': 'b',
            'label': '结束',
            'ports': [
              {'id': 'in', 'kind': 'target', 'side': 'left'}
            ],
          },
        ],
        'edges': [
          {
            'id': 'e',
            'source': 'a',
            'target': 'b',
            'sourcePort': 'out',
            'targetPort': 'in',
            'label': '是',
            'futureEdge': true
          },
        ],
      };

  test('preserves extensions, ports and deeply freezes input', () {
    final source = graph();
    final document = DiagramDocument.fromJson(source);
    expect(document.layout.direction, DiagramDirection.bt);
    expect(document.nodes.first.ports.single.id, 'out');
    final original = (source['metadata'] as Map<String, Object?>);
    original['owner'] = 'changed';
    expect(document.metadata['owner'], '团队');
    expect(() => document.metadata['owner'] = 'x', throwsUnsupportedError);
    expect(() => (document.nodes.first.data['custom'] as List).add(3),
        throwsUnsupportedError);
    final restored = DiagramDocument.parse(jsonEncode(document.toJson()));
    expect(restored.toJson(), document.toJson());
    expect(restored.extra['futureFlag'], {
      'nested': [1, true]
    });
    expect(restored.nodes.first.extra['futureNode'], 'preserved');
    expect(restored.edges.first.extra['futureEdge'], true);
    expect(restored.layout.extra['futureLayout'], 7);
  });

  test('rejects schema, identity, references, ports and malformed values', () {
    void invalid(void Function(Map<String, Object?>) mutate, String message) {
      final value = graph();
      mutate(value);
      expect(
          () => DiagramDocument.fromJson(value),
          throwsA(isA<FormatException>()
              .having((e) => e.message, 'message', contains(message))));
    }

    invalid((g) => g['schemaVersion'] = 2, 'schemaVersion');
    invalid((g) => (g['nodes'] as List).add({'id': 'a', 'label': 'duplicate'}),
        'Duplicate node');
    invalid(
        (g) => (g['edges'] as List)
            .add({'id': 'x', 'source': 'a', 'target': 'missing'}),
        'missing node');
    invalid((g) => ((g['edges'] as List).first as Map)['sourcePort'] = 'absent',
        'missing source port');
    invalid(
        (g) => ((g['nodes'] as List).first as Map)['size'] = {
              'width': -1,
              'height': 2
            },
        'dimensions');
    invalid(
        (g) => ((g['nodes'] as List).first as Map)['style'] = {
              'background': 'red'
            },
        'expected #');
    invalid((g) => ((g['nodes'] as List).first as Map)['parentId'] = 'absent',
        'Missing parent');
    invalid((g) {
      ((g['nodes'] as List).first as Map)['parentId'] = 'b';
      ((g['nodes'] as List).last as Map)['parentId'] = 'a';
    }, 'cycle');
    invalid((g) => g['metadata'] = [], 'expected object');
    invalid((g) => g['layout'] = {'mode': 'preserve'}, 'requires a position');
  });

  test('rejects parent nesting beyond the rendering limit', () {
    final nodes = [
      for (var i = 0; i < 129; i++)
        {'id': 'n$i', 'label': 'n$i', if (i > 0) 'parentId': 'n${i - 1}'},
    ];
    expect(
      () => DiagramDocument.fromJson({
        'schemaVersion': 1,
        'diagramType': 'flowchart',
        'nodes': nodes,
        'edges': [],
      }),
      throwsA(isA<FormatException>()
          .having((e) => e.message, 'message', contains('nesting exceeds'))),
    );
  });

  test('checks JSON nesting before parsing text', () {
    final text =
        '{"schemaVersion":1,"diagramType":"flowchart","nodes":[],"edges":[],"extra":${'[' * 65}0${']' * 65}}';
    expect(
        () => DiagramDocument.parse(text),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', contains('JSON nesting exceeds'))));
  });
}
