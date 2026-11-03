import 'package:fflow/diagram.dart';
import 'package:fflow/diagram_fflow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ddl = '''
USE `sales`;
CREATE TABLE `orders` (
  `tenant_id` BIGINT UNSIGNED NOT NULL,
  `id` BIGINT NOT NULL AUTO_INCREMENT,
  `status` ENUM('new','closed') DEFAULT 'new' COMMENT '状态',
  `updated` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`tenant_id`, `id`),
  UNIQUE KEY `uq_status` (`tenant_id`, `status`),
  KEY `ix_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COMMENT='订单';
CREATE TABLE `order_line` (
  id BIGINT PRIMARY KEY,
  tenant_id BIGINT NOT NULL,
  order_id BIGINT NOT NULL,
  CONSTRAINT `fk_order` FOREIGN KEY (`tenant_id`, `order_id`)
    REFERENCES `orders` (`tenant_id`, `id`) ON DELETE CASCADE ON UPDATE RESTRICT
) ENGINE=InnoDB;
''';

  test('parses MySQL tables, options and composite relationships', () {
    final result = parseMysqlDdl(ddl);
    expect(result.sourceFormat, 'mysql');
    expect(result.tables, hasLength(2));
    final orders = result.tables.first;
    expect(orders.name.toString(), 'sales.orders');
    expect(orders.primaryKey, ['tenant_id', 'id']);
    expect(orders.columns[0].sqlType, 'BIGINT UNSIGNED');
    expect(orders.columns[1].mysql['autoIncrement'], true);
    expect(orders.columns[2].defaultExpression, "'new'");
    expect(orders.columns[2].mysql['comment'], '状态');
    expect(orders.columns[3].mysql['onUpdate'], 'CURRENT_TIMESTAMP');
    expect(orders.mysql['engine'], 'InnoDB');
    expect(orders.mysql['characterSet'], 'utf8mb4');
    expect(orders.mysql['indexes'], hasLength(1));
    final fk = result.tables.last.foreignKeys.single;
    expect(fk.target.toString(), 'sales.orders');
    expect(fk.sourceColumns, ['tenant_id', 'order_id']);
    expect(fk.targetColumns, ['tenant_id', 'id']);
    expect(fk.onDelete, 'CASCADE');
    expect(fk.nullable, false);
    final diagram = result.toDiagram(groupBySchema: true);
    expect(
        diagram.nodes.where((n) => n.type == 'erSchema').single.label, 'sales');
    expect(diagram.edges, hasLength(1));
    expect(diagramToFlow(diagram).snapshot.edges, hasLength(1));
  });

  test(
      'handles unqualified names, default schema, comments and quoted identifiers',
      () {
    const input = '''# a comment
CREATE TABLE `odd``name` (`ID` int PRIMARY KEY, value varchar(40) DEFAULT 'a,b');
-- comment
CREATE TABLE child (parent int, FOREIGN KEY (parent) REFERENCES `odd``name` (`id`));
''';
    final result = parseMysqlDdl(input);
    expect(result.tables.first.name.toString(), 'odd`name');
    expect(result.tables.last.foreignKeys.single.targetColumns, ['ID']);
    expect(
        parseMysqlDdl(input, defaultSchema: 'db').tables.first.name.toString(),
        'db.odd`name');
    expect(
        result.toDiagram(groupBySchema: true).nodes.first.label, '(default)');
  });

  test('rejects unsupported and invalid SQL instead of losing constraints', () {
    for (final sql in [
      'CREATE TABLE t (id int, CHECK (id > 0));',
      'CREATE TABLE t (id int, UNIQUE KEY u (id(4)));',
      'CREATE TABLE t (id int, FOREIGN KEY (id) REFERENCES missing(id));',
      'CREATE TABLE t (id int, id INT);',
      'CREATE TABLE t (id int, PRIMARY KEY (missing));',
      'CREATE TABLE t (id int, KEY ix (missing));',
      'CREATE TABLE t (id int); /*! ALTER TABLE t ADD id2 int */',
      'ALTER TABLE t ADD x int;',
      'CREATE TABLE t (id int) ENGINE=InnoDB PARTITION BY HASH(id);',
      'CREATE TABLE t (id int, FOREIGN KEY (id) REFERENCES t(id));',
    ]) {
      expect(() => parseMysqlDdl(sql), throwsA(isA<MysqlDdlException>()),
          reason: sql);
    }
  });

  test('a unique subset of a composite foreign key makes it one-to-one', () {
    final schema = parseMysqlDdl('''
CREATE TABLE parent (a int, b int, PRIMARY KEY (a,b));
CREATE TABLE child (a int UNIQUE, b int,
  FOREIGN KEY (a,b) REFERENCES parent(a,b));
''');
    expect(schema.tables.last.foreignKeys.single.sourceUnique, isTrue);
  });

  test('errors include source position', () {
    expect(() => parseMysqlDdl('ALTER TABLE t ADD x int;'),
        throwsA(isA<MysqlDdlException>().having((e) => e.offset, 'offset', 0)));
  });
}
