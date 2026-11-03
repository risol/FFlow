import 'package:fflow/diagram.dart';
import 'package:fflow/diagram_fflow.dart';
import 'package:fflow/fflow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ddl = '''
-- quoted identifiers and composite keys
CREATE TABLE "Sales"."Order" (
  tenant_id integer NOT NULL,
  order_id bigint,
  "desc" character varying(80) DEFAULT '中文, test',
  created_at timestamp with time zone DEFAULT now(),
  CONSTRAINT pk_order PRIMARY KEY (tenant_id, order_id),
  CONSTRAINT uq_desc UNIQUE (tenant_id, "desc")
);
/* nested comments: /* ignored */ still ignored */
CREATE TABLE IF NOT EXISTS public.order_line (
  id bigint PRIMARY KEY,
  tenant_id integer NOT NULL,
  order_id bigint,
  CONSTRAINT fk_order FOREIGN KEY (tenant_id, order_id)
    REFERENCES "Sales"."Order" (tenant_id, order_id)
    ON DELETE CASCADE ON UPDATE NO ACTION
);
''';

  test('groups tables by schema while preserving cross-schema relationships',
      () {
    final doc = parsePostgresDdl(ddl).toDiagram(groupBySchema: true);
    final groups = doc.nodes.where((n) => n.type == 'erSchema').toList();
    final tables = doc.nodes.where((n) => n.type == 'erTable').toList();
    expect(groups.map((n) => n.label).toSet(), {'Sales', 'public'});
    expect(
        tables.every(
            (table) => groups.any((group) => group.id == table.parentId)),
        isTrue);
    expect(doc.edges, hasLength(1));
    final snapshot = diagramToFlow(doc).snapshot;
    final nodes = {for (final node in snapshot.nodes) node.id: node};
    for (final table in snapshot.nodes.where((node) => node.parentId != null)) {
      final parent = FlowGeometry.nodeRect(nodes[table.parentId]!, nodes);
      final child = FlowGeometry.nodeRect(table, nodes);
      expect(parent.contains(child.topLeft), isTrue);
      expect(parent.contains(child.bottomRight - const Offset(1, 1)), isTrue);
    }
    expect(
        FlowGraphValidator.validate(
            nodes: snapshot.nodes, edges: snapshot.edges),
        isEmpty);
  });

  test('schema group has room for a self-reference route', () {
    final doc = parsePostgresDdl('''
CREATE TABLE public.person (
  id bigint PRIMARY KEY,
  manager_id bigint REFERENCES public.person(id)
);
''').toDiagram(groupBySchema: true);
    final snapshot = diagramToFlow(doc).snapshot;
    final nodes = {for (final node in snapshot.nodes) node.id: node};
    final group = snapshot.nodes.singleWhere((node) => node.type == 'erSchema');
    final groupBounds = FlowGeometry.nodeRect(group, nodes);
    final route =
        FlowGeometry.edgePathResult(snapshot.edges.single, nodes)!.bounds;
    expect(groupBounds.contains(route.topLeft), isTrue);
    expect(groupBounds.contains(route.bottomRight), isTrue);
  });

  test('parses schema, columns, composite keys, constraints and defaults', () {
    final schema = parsePostgresDdl(ddl);
    expect(schema.tables.length, 2);
    final order = schema.tables.first;
    expect(order.name.schema, 'Sales');
    expect(order.name.name, 'Order');
    expect(order.primaryKey, ['tenant_id', 'order_id']);
    expect(order.primaryKeyName, 'pk_order');
    expect(order.columns[1].nullable, isFalse);
    expect(order.columns[2].sqlType, 'character varying(80)');
    expect(order.columns[2].defaultExpression, "'中文, test'");
    expect(order.columns[3].sqlType, 'timestamp with time zone');
    expect(order.columns[3].defaultExpression, 'now()');
    expect(order.uniqueConstraints.single.columns, ['tenant_id', 'desc']);
    expect(order.columns[2].unique, isFalse);
    final line = schema.tables.last;
    final fk = line.foreignKeys.single;
    expect(fk.sourceColumns, ['tenant_id', 'order_id']);
    expect(fk.targetColumns, ['tenant_id', 'order_id']);
    expect(fk.target.toString(), 'Sales.Order');
    expect(fk.nullable, isTrue);
    expect(fk.onDelete, 'CASCADE');
    expect(fk.onUpdate, 'NO ACTION');
    expect(line.columns[1].foreignKey, isTrue);
    final diagram = schema.toDiagram(title: '订单结构');
    expect(diagram.type, DiagramType.er);
    expect(diagram.nodes.length, 2);
    expect(
        diagram.edges.single.data['sourceColumns'], ['tenant_id', 'order_id']);
    expect(diagram.edges.single.label,
        'tenant_id, order_id → tenant_id, order_id');
    final graph = diagramToFlow(diagram);
    expect(graph.snapshot.edges.single.markerStart,
        FlowEdgeMarker.crowFootZeroMany);
    expect(graph.snapshot.edges.single.markerEnd, FlowEdgeMarker.zeroOrOne);
    final restored = FlowGraphSnapshot<Map<String, Object?>>.fromJson(
      graph.snapshot.toJson(encodeNodeData: (data) => data),
      decodeNodeData: (data) => Map<String, Object?>.from(data as Map),
    );
    expect(restored.edges.single.markerStart, FlowEdgeMarker.crowFootZeroMany);
    expect(restored.edges.single.markerEnd, FlowEdgeMarker.zeroOrOne);
  });

  test('resolves implicit primary key references and inline constraints', () {
    final result = parsePostgresDdl('''
      CREATE TABLE users (id int PRIMARY KEY, email text UNIQUE);
      CREATE TABLE posts (id int PRIMARY KEY, owner int NOT NULL REFERENCES users ON DELETE RESTRICT);
    ''');
    expect(result.tables.first.columns[1].unique, isTrue);
    final relation = result.tables.last.foreignKeys.single;
    expect(relation.targetColumns, ['id']);
    expect(relation.nullable, isFalse);
    expect(relation.onDelete, 'RESTRICT');
    expect(diagramToFlow(result.toDiagram()).snapshot.edges.single.markerEnd,
        FlowEdgeMarker.one);
  });

  test('routes self-referential foreign keys outside their table', () {
    final schema = parsePostgresDdl(
        'CREATE TABLE category (id int PRIMARY KEY, parent_id int REFERENCES category(id));');
    final graph = diagramToFlow(schema.toDiagram());
    final edge = graph.snapshot.edges.single;
    final node = graph.snapshot.nodes.single;
    final byId = {node.id: node};
    final rect = FlowGeometry.nodeRect(node, byId);
    expect(edge.controlPoints, isNotEmpty);
    expect(edge.controlPoints.every((point) => !rect.contains(point)), isTrue);
    final geometry = FlowGeometry.edgePathResult(edge, byId)!;
    expect(geometry.bounds.right, greaterThan(rect.right));
    expect(edge.controlPoints.every((point) => point.dx > rect.right), isTrue);
    expect(geometry.metrics, hasLength(1));
    final metric = geometry.metrics.single;
    expect(
        (metric.getTangentForOffset(0)!.position - geometry.sourceAnchor)
            .distance,
        lessThan(0.001));
    expect(
        (metric.getTangentForOffset(metric.length)!.position -
                geometry.targetAnchor)
            .distance,
        lessThan(0.001));
  });

  test('unique foreign key has zero-or-one cardinality at the source', () {
    final schema = parsePostgresDdl('''
      CREATE TABLE users (id int PRIMARY KEY);
      CREATE TABLE profile (user_id int UNIQUE NOT NULL REFERENCES users(id));
    ''');
    final relation = schema.tables.last.foreignKeys.single;
    expect(relation.sourceUnique, isTrue);
    expect(relation.toJson()['sourceCardinality'], 'zeroOrOne');
    final edge = diagramToFlow(schema.toDiagram()).snapshot.edges.single;
    expect(edge.markerStart, FlowEdgeMarker.zeroOrOne);
    expect(edge.markerEnd, FlowEdgeMarker.one);
  });

  test('handles supported type modifiers, arrays and named column constraints',
      () {
    final schema = parsePostgresDdl('''
      CREATE TABLE t (
        id integer CONSTRAINT pk PRIMARY KEY,
        amount numeric(12, -2) CONSTRAINT nn NOT NULL CONSTRAINT df DEFAULT 0,
        stamp timestamp(3) with time zone,
        tags text[],
        custom "Types"."Status"
      );
    ''');
    final table = schema.tables.single;
    expect(table.primaryKeyName, 'pk');
    expect(table.columns[1].sqlType, 'numeric(12, -2)');
    expect(table.columns[1].nullabilityConstraintName, 'nn');
    expect(table.columns[1].defaultConstraintName, 'df');
    expect(table.columns[2].sqlType, 'timestamp(3) with time zone');
    expect(table.columns[3].sqlType, 'text[]');
    expect(table.columns[4].sqlType, '"Types"."Status"');
  });

  test('preserves quoted names, literals, comments and SQL identifier case',
      () {
    final schema = parsePostgresDdl('''
      CREATE TABLE "Mixed.Schema"."Item" (
        foo\$bar text DEFAULT 'a;''b, c',
        "SELECT" integer CONSTRAINT "UniqueName" UNIQUE
      );
    ''');
    final table = schema.tables.single;
    expect(table.name.schema, 'Mixed.Schema');
    expect(table.name.name, 'Item');
    expect(table.columns.first.name, 'foo\$bar');
    expect(table.columns.first.defaultExpression, "'a;''b, c'");
    expect(table.columns.last.name, 'SELECT');
    expect(table.uniqueConstraints.single.name, 'UniqueName');
    expect(table.name.id, isNot(const ErName('Mixed', 'Schema.Item').id));
  });

  test('validates supported default expression forms without evaluating them',
      () {
    final schema = parsePostgresDdl('''
      CREATE TABLE defaults (
        id bigint DEFAULT nextval('seq'::regclass),
        until_time timestamp DEFAULT (now() + interval '1 day'),
        values_list int[] DEFAULT ARRAY[1, 2]::int[],
        count_value integer DEFAULT (3 + 4) * 2,
        value_text text DEFAULT 'a' || 'b',
        flag boolean DEFAULT NOT false
      );
    ''');
    expect(schema.tables.single.columns[0].defaultExpression,
        "nextval('seq'::regclass)");
    expect(schema.tables.single.columns[1].defaultExpression,
        "(now() + interval '1 day')");
    expect(schema.tables.single.columns[2].defaultExpression,
        'ARRAY[1, 2]::int[]');
  });

  test('rejects unsupported and invalid SQL with a location', () {
    void invalid(String sql, String message) {
      expect(
          () => parsePostgresDdl(sql),
          throwsA(isA<PostgresDdlException>()
              .having((e) => e.line, 'line', greaterThan(0))
              .having((e) => e.column, 'column', greaterThan(0))
              .having((e) => e.message, 'message', contains(message))));
    }

    invalid('CREATE TABLE t (a int, a text);', 'Duplicate column');
    invalid('CREATE TABLE t (a int, PRIMARY KEY (missing));', 'Unknown column');
    invalid(
        'CREATE TABLE t (a int REFERENCES missing(id));', 'Referenced table');
    invalid('CREATE TABLE t (a int, CHECK (a > 0));',
        'Unsupported table constraint');
    invalid(
        'CREATE TABLE t (a int GENERATED ALWAYS AS IDENTITY);', 'Unsupported');
    invalid('CREATE TABLE t (a int DEFAULT \'unterminated);',
        'Unterminated SQL string');
    invalid('ALTER TABLE t ADD COLUMN x int;', 'Expected CREATE');
    invalid('CREATE TABLE t (a int, PRIMARY KEY (a), PRIMARY KEY (a));',
        'Multiple primary');
    invalid('CREATE TABLE t (a int nonsense);',
        'Unsupported multiword column type');
    invalid('CREATE TABLE t (a int NULL NOT NULL);', 'Conflicting nullability');
    invalid(
        'CREATE TABLE t (a int CONSTRAINT duplicate UNIQUE, b int CONSTRAINT duplicate UNIQUE);',
        'Duplicate constraint');
    invalid('CREATE TABLE p (a int); CREATE TABLE c (b int REFERENCES p(a));',
        'not a primary or unique key');
    invalid("CREATE TABLE t (a text DEFAULT E'bad\\'text');", 'escape strings');
    invalid(
        'CREATE TABLE t (a int DEFAULT 1 +);', 'invalid default expression');
    invalid('CREATE TABLE t (a int DEFAULT 1 garbage);',
        'invalid default expression');
    invalid('CREATE TABLE t (a boolean DEFAULT true AND false);',
        'invalid default expression');
  });
}
