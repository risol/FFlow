import 'dart:convert';

import 'json_depth.dart';
import 'postgres_ddl_parser.dart';

/// An error in the supported MySQL CREATE TABLE subset.
class MysqlDdlException extends FormatException {
  MysqlDdlException(String message, String source, int offset)
      : super(
            '$message at line ${'\n'.allMatches(source.substring(0, offset)).length + 1}, column ${offset == 0 ? 1 : offset - source.lastIndexOf('\n', offset - 1)}',
            source,
            offset);
}

/// Parses MySQL CREATE TABLE statements without connecting to a database.
/// Unqualified names use [defaultSchema], a preceding USE, or an empty schema.
ErSchema parseMysqlDdl(String source, {String? defaultSchema}) {
  if (exceedsUtf8Limit(source, 2000000)) {
    throw const FormatException('SQL input exceeds 2000000 bytes');
  }
  return _Parser(source, defaultSchema ?? '').parse();
}

class _Token {
  _Token(this.text, this.value, this.offset, this.end, this.kind);
  final String text, value, kind;
  final int offset, end;
  bool isWord(String s) => kind == 'word' && value.toUpperCase() == s;
}

List<_Token> _lex(String s) {
  final tokens = <_Token>[];
  var i = 0;
  Never fail(String message, int offset) =>
      throw MysqlDdlException(message, s, offset);
  while (i < s.length) {
    final start = i;
    final c = s[i];
    if (RegExp(r'\s').hasMatch(c)) {
      i++;
      continue;
    }
    if (c == '#' ||
        (s.startsWith('--', i) &&
            (i + 2 == s.length || RegExp(r'\s').hasMatch(s[i + 2])))) {
      while (i < s.length && s[i] != '\n' && s[i] != '\r') {
        i++;
      }
      continue;
    }
    if (s.startsWith('/*', i)) {
      if (s.startsWith('/*!', i) || s.startsWith('/*+', i)) {
        fail('Executable comments and hints are unsupported', i);
      }
      final end = s.indexOf('*/', i + 2);
      if (end < 0) fail('Unterminated comment', i);
      i = end + 2;
      continue;
    }
    if (c == '`' || c == "'" || c == '"') {
      i++;
      final value = StringBuffer();
      var closed = false;
      while (i < s.length) {
        final ch = s[i++];
        if (ch == c) {
          if (i < s.length && s[i] == c) {
            value.write(c);
            i++;
            continue;
          }
          closed = true;
          break;
        }
        if (ch == '\\' && c != '`') {
          if (i >= s.length) fail('Unterminated escape', start);
          final escaped = s[i++];
          value.write(const {
                '0': '\u0000',
                'n': '\n',
                'r': '\r',
                't': '\t',
                'b': '\b',
                'Z': '\u001a'
              }[escaped] ??
              escaped);
        } else {
          value.write(ch);
        }
      }
      if (!closed) fail('Unterminated quoted value', start);
      tokens.add(_Token(s.substring(start, i), value.toString(), start, i,
          c == '`' ? 'identifier' : 'string'));
      continue;
    }
    if (RegExp(r'[\w$\u0080-\uFFFF]').hasMatch(c)) {
      i++;
      while (i < s.length && RegExp(r'[\w$\u0080-\uFFFF]').hasMatch(s[i])) {
        i++;
      }
      tokens.add(_Token(
          s.substring(start, i), s.substring(start, i), start, i, 'word'));
      continue;
    }
    if ('(),.;=+-*/%'.contains(c)) {
      i++;
      tokens.add(_Token(c, c, start, i, 'symbol'));
      continue;
    }
    fail('Unsupported character $c', i);
  }
  tokens.add(_Token('', '', s.length, s.length, 'end'));
  return tokens;
}

class _Column {
  _Column(this.name, this.type);
  final String name, type;
  bool nullable = true, explicitNull = false, primary = false, unique = false;
  String? defaultValue;
  final mysql = <String, Object?>{};
}

class _Foreign {
  _Foreign(this.name, this.columns, this.target, this.targets, this.onDelete,
      this.onUpdate);
  final String? name, onDelete, onUpdate;
  final List<String> columns, targets;
  final ErName target;
}

class _Table {
  _Table(this.name);
  final ErName name;
  final columns = <_Column>[];
  List<String> primary = [];
  String? primaryName;
  final uniques = <ErUniqueConstraint>[];
  final foreign = <_Foreign>[];
  final mysql = <String, Object?>{};
}

class _Parser {
  _Parser(this.source, this.schema) : tokens = _lex(source);
  final String source;
  String schema;
  final List<_Token> tokens;
  int pos = 0;
  _Token get t => tokens[pos];
  Never fail(String message, [_Token? at]) =>
      throw MysqlDdlException(message, source, (at ?? t).offset);
  bool word(String s) => t.isWord(s);
  bool take(String s) {
    if (word(s)) {
      pos++;
      return true;
    }
    return false;
  }

  void expect(String s) {
    if (!take(s)) fail('Expected $s');
  }

  bool sym(String s) => t.kind == 'symbol' && t.text == s;
  bool takeSym(String s) {
    if (sym(s)) {
      pos++;
      return true;
    }
    return false;
  }

  void expectSym(String s) {
    if (!takeSym(s)) fail('Expected $s');
  }

  String name() {
    if (t.kind != 'word' && t.kind != 'identifier') fail('Expected identifier');
    if (t.value.isEmpty ||
        (t.kind == 'word' && RegExp(r'^\d').hasMatch(t.value))) {
      fail('Invalid identifier');
    }
    return tokens[pos++].value;
  }

  ErName tableName() {
    final first = name();
    return takeSym('.') ? ErName(first, name()) : ErName(schema, first);
  }

  List<String> names() {
    expectSym('(');
    final result = <String>[name()];
    while (takeSym(',')) {
      result.add(name());
    }
    expectSym(')');
    if (result.map((e) => e.toLowerCase()).toSet().length != result.length) {
      fail('Duplicate column in key');
    }
    return result;
  }

  String raw(int from) =>
      source.substring(tokens[from].offset, tokens[pos - 1].end);
  void balanced() {
    expectSym('(');
    var depth = 1;
    while (depth > 0) {
      if (t.kind == 'end' || sym(';')) fail('Unterminated expression');
      if (takeSym('(')) {
        depth++;
        if (depth > 100) fail('Expression nesting limit exceeded');
      } else if (takeSym(')')) {
        depth--;
      } else {
        pos++;
      }
    }
  }

  String expression() {
    final start = pos;
    if (sym('(')) {
      balanced();
      return raw(start);
    }
    takeSym('+') || takeSym('-');
    if (t.kind != 'word' && t.kind != 'string') {
      fail('Expected default expression');
    }
    pos++;
    if (sym('.') && tokens[pos + 1].kind == 'word') {
      pos += 2;
    }
    if (sym('(')) balanced();
    return raw(start);
  }

  String action() {
    if (take('CASCADE')) return 'CASCADE';
    if (take('RESTRICT')) return 'RESTRICT';
    if (take('SET')) {
      expect('NULL');
      return 'SET NULL';
    }
    if (take('NO')) {
      expect('ACTION');
      return 'NO ACTION';
    }
    fail('Unsupported referential action');
  }

  void foreign(_Table table, String? constraint) {
    expect('KEY');
    if (!sym('(')) {
      name();
    }
    final columns = names();
    expect('REFERENCES');
    final target = tableName();
    final targets = names();
    String? delete, update;
    while (take('ON')) {
      if (take('DELETE')) {
        if (delete != null) fail('Duplicate ON DELETE');
        delete = action();
      } else if (take('UPDATE')) {
        if (update != null) fail('Duplicate ON UPDATE');
        update = action();
      } else {
        fail('Expected DELETE or UPDATE');
      }
    }
    table.foreign
        .add(_Foreign(constraint, columns, target, targets, delete, update));
  }

  void key(_Table table, String? constraint, {required bool unique}) {
    take('KEY') || take('INDEX');
    String? indexName;
    if (!sym('(')) indexName = name();
    final cols = names();
    if (unique) {
      table.uniques.add(ErUniqueConstraint(constraint ?? indexName, cols));
    } else {
      final indexes =
          table.mysql.putIfAbsent('indexes', () => <Map<String, Object?>>[])
              as List<Map<String, Object?>>;
      indexes.add({if (indexName != null) 'name': indexName, 'columns': cols});
    }
  }

  void column(_Table table) {
    final columnName = name();
    final typeStart = pos;
    final type = name().toUpperCase();
    const supported = {
      'TINYINT',
      'SMALLINT',
      'MEDIUMINT',
      'INT',
      'INTEGER',
      'BIGINT',
      'DECIMAL',
      'DEC',
      'NUMERIC',
      'FIXED',
      'FLOAT',
      'DOUBLE',
      'REAL',
      'BIT',
      'BOOL',
      'BOOLEAN',
      'DATE',
      'DATETIME',
      'TIMESTAMP',
      'TIME',
      'YEAR',
      'CHAR',
      'VARCHAR',
      'BINARY',
      'VARBINARY',
      'TINYBLOB',
      'BLOB',
      'MEDIUMBLOB',
      'LONGBLOB',
      'TINYTEXT',
      'TEXT',
      'MEDIUMTEXT',
      'LONGTEXT',
      'ENUM',
      'SET',
      'JSON',
      'GEOMETRY',
      'POINT',
      'LINESTRING',
      'POLYGON',
      'MULTIPOINT',
      'MULTILINESTRING',
      'MULTIPOLYGON',
      'GEOMETRYCOLLECTION'
    };
    if (!supported.contains(type)) {
      fail('Unsupported MySQL column type $type', tokens[typeStart]);
    }
    if (type == 'DOUBLE') take('PRECISION');
    if (sym('(')) balanced();
    take('UNSIGNED');
    take('ZEROFILL');
    final col = _Column(columnName, raw(typeStart));
    while (!sym(',') && !sym(')') && t.kind != 'end') {
      if (take('NOT')) {
        expect('NULL');
        col.nullable = false;
      } else if (take('NULL')) {
        col.nullable = true;
        col.explicitNull = true;
      } else if (take('DEFAULT')) {
        if (col.defaultValue != null) fail('Duplicate DEFAULT');
        col.defaultValue = expression();
      } else if (take('AUTO_INCREMENT')) {
        col.mysql['autoIncrement'] = true;
      } else if (take('PRIMARY')) {
        expect('KEY');
        col.primary = true;
      } else if (take('UNIQUE')) {
        take('KEY');
        col.unique = true;
      } else if (take('COMMENT')) {
        if (t.kind != 'string') fail('Expected comment string');
        col.mysql['comment'] = tokens[pos++].value;
      } else if (take('CHARACTER')) {
        expect('SET');
        col.mysql['characterSet'] = name();
      } else if (take('COLLATE')) {
        col.mysql['collation'] = name();
      } else if (take('ON')) {
        expect('UPDATE');
        col.mysql['onUpdate'] = expression();
      } else {
        fail('Unsupported column attribute ${t.text}');
      }
    }
    table.columns.add(col);
    if (table.columns.length > 300) fail('Too many columns');
    if (col.primary) {
      if (table.primary.isNotEmpty) fail('Duplicate PRIMARY KEY');
      table.primary = [col.name];
    }
    if (col.unique) table.uniques.add(ErUniqueConstraint(null, [col.name]));
  }

  void definition(_Table table) {
    String? constraint;
    if (take('CONSTRAINT')) constraint = name();
    if (take('PRIMARY')) {
      expect('KEY');
      if (table.primary.isNotEmpty) fail('Duplicate PRIMARY KEY');
      table.primary = names();
      table.primaryName = constraint;
    } else if (take('UNIQUE')) {
      key(table, constraint, unique: true);
    } else if (take('FOREIGN')) {
      foreign(table, constraint);
    } else if (take('KEY') || take('INDEX')) {
      if (constraint != null) fail('Unexpected constraint name');
      key(table, null, unique: false);
    } else {
      if (constraint != null) fail('Unsupported constraint');
      column(table);
    }
  }

  void options(_Table table) {
    while (!sym(';') && t.kind != 'end') {
      takeSym(',');
      take('DEFAULT');
      String option;
      if (take('ENGINE')) {
        option = 'engine';
      } else if (take('CHARSET')) {
        option = 'characterSet';
      } else if (take('CHARACTER')) {
        expect('SET');
        option = 'characterSet';
      } else if (take('COLLATE')) {
        option = 'collation';
      } else if (take('COMMENT')) {
        option = 'comment';
      } else if (take('AUTO_INCREMENT')) {
        option = 'autoIncrement';
      } else if (take('ROW_FORMAT')) {
        option = 'rowFormat';
      } else {
        fail('Unsupported table option ${t.text}');
      }
      takeSym('=');
      if (t.kind != 'word' && t.kind != 'string' && t.kind != 'identifier') {
        fail('Expected table option value');
      }
      table.mysql[option] = tokens[pos++].value;
    }
  }

  ErSchema parse() {
    final tables = <_Table>[];
    while (t.kind != 'end') {
      if (takeSym(';')) continue;
      if (take('USE')) {
        schema = name();
        expectSym(';');
        continue;
      }
      expect('CREATE');
      expect('TABLE');
      if (take('IF')) {
        expect('NOT');
        expect('EXISTS');
      }
      final table = _Table(tableName());
      expectSym('(');
      if (sym(')')) fail('Table must contain columns');
      do {
        definition(table);
      } while (takeSym(','));
      expectSym(')');
      options(table);
      if (t.kind != 'end') expectSym(';');
      if (table.columns.isEmpty) fail('Table must contain columns');
      tables.add(table);
      if (tables.length > 5000) fail('Too many tables');
    }
    if (tables.isEmpty) fail('No CREATE TABLE statements');
    return resolve(tables);
  }

  ErSchema resolve(List<_Table> tables) {
    final lookup = <String, _Table>{};
    String id(ErName n) => jsonEncode([n.schema, n.name]);
    for (final table in tables) {
      if (lookup.containsKey(id(table.name))) {
        fail('Duplicate table ${table.name}');
      }
      lookup[id(table.name)] = table;
      final cols = <String>{};
      for (final col in table.columns) {
        if (!cols.add(col.name.toLowerCase())) {
          fail('Duplicate column ${col.name}');
        }
      }
    }
    List<String> canonical(_Table table, List<String> cols) => [
          for (final c in cols)
            table.columns
                .firstWhere((x) => x.name.toLowerCase() == c.toLowerCase(),
                    orElse: () => fail('Unknown column $c in ${table.name}'))
                .name
        ];
    bool same(List<String> a, List<String> b) =>
        a.length == b.length &&
        List.generate(a.length, (i) => a[i].toLowerCase() == b[i].toLowerCase())
            .every((x) => x);
    bool unique(_Table table, List<String> cols) =>
        same(table.primary, cols) ||
        table.uniques.any((u) => same(u.columns, cols));
    bool sourceUnique(_Table table, List<String> cols) {
      final names = cols.map((c) => c.toLowerCase()).toSet();
      bool contained(List<String> key) =>
          key.isNotEmpty &&
          key.every((column) => names.contains(column.toLowerCase()));
      return contained(table.primary) ||
          table.uniques.any((key) => contained(key.columns));
    }

    for (final table in tables) {
      table.primary = canonical(table, table.primary);
      for (final u in table.uniques) {
        canonical(table, u.columns);
      }
      final indexes = table.mysql['indexes'] as List<Map<String, Object?>>?;
      for (final index in indexes ?? <Map<String, Object?>>[]) {
        index['columns'] = canonical(table, index['columns'] as List<String>);
      }
    }
    final result = <ErTable>[];
    for (final table in tables) {
      final fks = <ErForeignKey>[];
      for (final fk in table.foreign) {
        final target = lookup[id(fk.target)];
        if (target == null) fail('Unknown referenced table ${fk.target}');
        final from = canonical(table, fk.columns),
            to = canonical(target, fk.targets);
        if (from.length != to.length) fail('Foreign key column count mismatch');
        if (!unique(target, to)) {
          fail('Referenced columns must be a primary or unique key');
        }
        fks.add(ErForeignKey(
            source: table.name,
            target: target.name,
            sourceColumns: from,
            targetColumns: to,
            nullable: from.any((n) =>
                table.columns.firstWhere((c) => c.name == n).nullable &&
                !table.primary.contains(n)),
            sourceUnique: sourceUnique(table, from),
            name: fk.name,
            onDelete: fk.onDelete,
            onUpdate: fk.onUpdate));
      }
      final columns = <ErColumn>[];
      for (final col in table.columns) {
        final pk = table.primary.contains(col.name);
        if (pk && col.explicitNull && col.nullable) {
          fail('PRIMARY KEY column cannot be NULL');
        }
        columns.add(ErColumn(
            name: col.name,
            sqlType: col.type,
            nullable: col.nullable && !pk,
            primaryKey: pk,
            unique: table.uniques.any((u) =>
                u.columns.length == 1 &&
                u.columns.single.toLowerCase() == col.name.toLowerCase()),
            foreignKey: fks.any((fk) => fk.sourceColumns.contains(col.name)),
            defaultExpression: col.defaultValue,
            mysql: Map.unmodifiable(col.mysql)));
      }
      result.add(ErTable(
          name: table.name,
          columns: columns,
          primaryKey: table.primary,
          primaryKeyName: table.primaryName,
          uniqueConstraints: table.uniques,
          foreignKeys: fks,
          mysql: Map.unmodifiable(table.mysql)));
    }
    return ErSchema(result, sourceFormat: 'mysql');
  }
}
