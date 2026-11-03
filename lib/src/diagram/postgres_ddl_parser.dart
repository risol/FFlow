import 'dart:convert';

import 'diagram_document.dart';
import 'json_depth.dart';

/// A syntax or semantic error in the supported PostgreSQL DDL subset.
class PostgresDdlException extends FormatException {
  PostgresDdlException(
      String message, String source, this.line, this.column, int offset)
      : super('$message at line $line, column $column', source, offset);
  final int line;
  final int column;
}

class ErName {
  const ErName(this.schema, this.name);
  final String schema;
  final String name;
  String get id => 'table:${jsonEncode([schema, name])}';
  @override
  String toString() => '$schema.$name';
}

class ErColumn {
  const ErColumn(
      {required this.name,
      required this.sqlType,
      required this.nullable,
      required this.primaryKey,
      required this.unique,
      required this.foreignKey,
      this.defaultExpression,
      this.nullabilityConstraintName,
      this.defaultConstraintName});
  final String name;
  final String sqlType;
  final bool nullable;
  final bool primaryKey;

  /// True for a single-column UNIQUE constraint, not a composite key member.
  final bool unique;
  final bool foreignKey;
  final String? defaultExpression;
  final String? nullabilityConstraintName, defaultConstraintName;

  Map<String, Object?> toJson() => {
        'name': name,
        'type': sqlType,
        'nullable': nullable,
        'primaryKey': primaryKey,
        'unique': unique,
        'foreignKey': foreignKey,
        if (defaultExpression != null) 'default': defaultExpression,
        if (nullabilityConstraintName != null)
          'nullabilityConstraintName': nullabilityConstraintName,
        if (defaultConstraintName != null)
          'defaultConstraintName': defaultConstraintName,
      };
}

class ErUniqueConstraint {
  ErUniqueConstraint(this.name, Iterable<String> columns)
      : columns = List.unmodifiable(columns);
  final String? name;
  final List<String> columns;
  Map<String, Object?> toJson() =>
      {if (name != null) 'name': name, 'columns': columns};
}

class ErForeignKey {
  ErForeignKey(
      {required this.source,
      required this.target,
      required Iterable<String> sourceColumns,
      required Iterable<String> targetColumns,
      required this.nullable,
      required this.sourceUnique,
      this.name,
      this.onDelete,
      this.onUpdate})
      : sourceColumns = List.unmodifiable(sourceColumns),
        targetColumns = List.unmodifiable(targetColumns);
  final ErName source, target;
  final List<String> sourceColumns, targetColumns;
  final bool nullable;
  final bool sourceUnique;
  final String? name, onDelete, onUpdate;
  Map<String, Object?> toJson() => {
        if (name != null) 'name': name,
        'sourceSchema': source.schema,
        'sourceTable': source.name,
        'targetSchema': target.schema,
        'targetTable': target.name,
        'sourceColumns': sourceColumns,
        'targetColumns': targetColumns,
        'nullable': nullable,
        'sourceCardinality': sourceUnique ? 'zeroOrOne' : 'zeroOrMany',
        'targetCardinality': nullable ? 'zeroOrOne' : 'one',
        if (onDelete != null) 'onDelete': onDelete,
        if (onUpdate != null) 'onUpdate': onUpdate,
      };
}

class ErTable {
  ErTable(
      {required this.name,
      required Iterable<ErColumn> columns,
      required Iterable<String> primaryKey,
      this.primaryKeyName,
      required Iterable<ErUniqueConstraint> uniqueConstraints,
      required Iterable<ErForeignKey> foreignKeys})
      : columns = List.unmodifiable(columns),
        primaryKey = List.unmodifiable(primaryKey),
        uniqueConstraints = List.unmodifiable(uniqueConstraints),
        foreignKeys = List.unmodifiable(foreignKeys);
  final ErName name;
  final String? primaryKeyName;
  final List<ErColumn> columns;
  final List<String> primaryKey;
  final List<ErUniqueConstraint> uniqueConstraints;
  final List<ErForeignKey> foreignKeys;
}

class ErSchema {
  ErSchema(Iterable<ErTable> tables) : tables = List.unmodifiable(tables);
  final List<ErTable> tables;

  /// Converts semantic tables and foreign keys to the common document format.
  DiagramDocument toDiagram({String? title, bool groupBySchema = false}) {
    var edgeIndex = 0;
    return DiagramDocument.fromJson({
      'schemaVersion': 1,
      'diagramType': 'er',
      if (title != null) 'title': title,
      'layout': {
        'mode': 'auto',
        'direction': 'LR',
        'nodeSpacing': 90,
        'layerSpacing': 180,
        if (groupBySchema) 'groupPadding': 112
      },
      'metadata': {'sourceFormat': 'postgresql'},
      'nodes': [
        if (groupBySchema)
          for (final schema in {for (final table in tables) table.name.schema})
            {
              'id': 'schema:${jsonEncode(schema)}',
              'type': 'erSchema',
              'label': schema,
              'data': {'schema': schema},
            },
        for (final table in tables)
          {
            'id': table.name.id,
            'type': 'erTable',
            'label': table.name.toString(),
            if (groupBySchema)
              'parentId': 'schema:${jsonEncode(table.name.schema)}',
            'size': {'width': 380, 'height': 48 + 26 * table.columns.length},
            'data': {
              'schema': table.name.schema,
              'name': table.name.name,
              'columns': [for (final column in table.columns) column.toJson()],
              'primaryKey': table.primaryKey,
              if (table.primaryKeyName != null)
                'primaryKeyName': table.primaryKeyName,
              'uniqueConstraints': [
                for (final unique in table.uniqueConstraints) unique.toJson()
              ]
            },
          }
      ],
      'edges': [
        for (final table in tables)
          for (final fk in table.foreignKeys)
            {
              'id': 'foreign_key_${++edgeIndex}',
              'source': fk.source.id,
              'target': fk.target.id,
              'type': 'erRelationship',
              'data': fk.toJson(),
              'label':
                  '${fk.sourceColumns.join(', ')} → ${fk.targetColumns.join(', ')}',
            }
      ],
    });
  }
}

/// Parse the documented PostgreSQL CREATE TABLE subset without executing SQL.
ErSchema parsePostgresDdl(String source) {
  if (exceedsUtf8Limit(source, 2000000)) {
    throw const FormatException('SQL input exceeds 2000000 bytes');
  }
  return _DdlParser(source).parse();
}

enum _Kind { word, quotedIdentifier, string, symbol, end }

class _Token {
  const _Token(this.kind, this.text, this.value, this.offset, this.end,
      this.line, this.column);
  final _Kind kind;
  final String text, value;
  final int offset, end, line, column;
  bool isKeyword(String keyword) =>
      kind == _Kind.word && value.toUpperCase() == keyword;
}

class _Lexer {
  _Lexer(this.source);
  final String source;
  int offset = 0, line = 1, column = 1;
  bool get done => offset >= source.length;
  String get current => done ? '' : source[offset];
  bool starts(String text) => source.startsWith(text, offset);
  Never fail(String message) =>
      throw PostgresDdlException(message, source, line, column, offset);
  void advance() {
    if (done) return;
    final c = source[offset++];
    if (c == '\r') {
      if (!done && current == '\n') offset++;
      line++;
      column = 1;
    } else if (c == '\n') {
      line++;
      column = 1;
    } else {
      column++;
    }
  }

  void skip() {
    while (!done) {
      if (current == ' ' ||
          current == '\t' ||
          current == '\n' ||
          current == '\r') {
        advance();
      } else if (starts('--')) {
        while (!done && current != '\r' && current != '\n') {
          advance();
        }
      } else if (starts('/*')) {
        advance();
        advance();
        var depth = 1;
        while (depth > 0) {
          if (done) fail('Unterminated SQL comment');
          if (starts('/*')) {
            advance();
            advance();
            depth++;
          } else if (starts('*/')) {
            advance();
            advance();
            depth--;
          } else {
            advance();
          }
        }
      } else {
        break;
      }
    }
  }

  _Token next() {
    skip();
    final start = offset, startLine = line, startColumn = column;
    if (done) {
      return _Token(_Kind.end, '', '', start, start, startLine, startColumn);
    }
    final c = current;
    if (c == '"' || c == "'") {
      final identifier = c == '"';
      final value = StringBuffer();
      advance();
      var closed = false;
      while (!done) {
        if (current == c) {
          advance();
          if (current == c) {
            value.write(c);
            advance();
            continue;
          }
          closed = true;
          break;
        }
        value.write(current);
        advance();
      }
      if (!closed) {
        fail(identifier
            ? 'Unterminated quoted identifier'
            : 'Unterminated SQL string');
      }
      final text = source.substring(start, offset);
      return _Token(identifier ? _Kind.quotedIdentifier : _Kind.string, text,
          value.toString(), start, offset, startLine, startColumn);
    }
    if (c == r'$') fail('Dollar-quoted strings are not supported');
    final code = source.codeUnitAt(offset);
    if (_wordCode(code)) {
      while (!done && _wordCode(source.codeUnitAt(offset))) {
        advance();
      }
      final text = source.substring(start, offset);
      if (text.toUpperCase() == 'E' && current == "'") {
        fail('PostgreSQL escape strings are not supported');
      }
      return _Token(
          _Kind.word, text, text, start, offset, startLine, startColumn);
    }
    advance();
    return _Token(_Kind.symbol, c, c, start, offset, startLine, startColumn);
  }

  bool _wordCode(int c) =>
      (c >= 65 && c <= 90) ||
      (c >= 97 && c <= 122) ||
      (c >= 48 && c <= 57) ||
      c == 95 ||
      c == 36 ||
      c >= 128;
}

class _Column {
  _Column(this.name, this.type, this.at);
  final String name, type;
  final _Token at;
  bool notNull = false;
  bool? explicitlyNullable;
  String? defaultExpression;
  String? nullabilityConstraintName, defaultConstraintName;
}

class _Key {
  _Key(this.name, this.columns, this.at);
  final String? name;
  final List<String> columns;
  final _Token at;
}

class _Foreign {
  _Foreign(this.name, this.columns, this.target, this.targetColumns, this.at,
      this.onDelete, this.onUpdate);
  final String? name;
  final List<String> columns, targetColumns;
  final ErName target;
  final _Token at;
  final String? onDelete, onUpdate;
}

class _Table {
  _Table(this.name, this.at);
  final ErName name;
  final _Token at;
  final columns = <_Column>[];
  _Key? primary;
  final uniques = <_Key>[];
  final foreignKeys = <_Foreign>[];
  final constraintNames = <String>{};
}

class _DdlParser {
  _DdlParser(this.source) : lexer = _Lexer(source) {
    token = lexer.next();
  }
  final String source;
  final _Lexer lexer;
  late _Token token;
  final tables = <_Table>[];
  final tableIds = <String>{};
  Never fail(String message, [_Token? at]) {
    final t = at ?? token;
    throw PostgresDdlException(message, source, t.line, t.column, t.offset);
  }

  void advance() => token = lexer.next();
  bool keyword(String value) => token.isKeyword(value);
  bool takeKeyword(String value) {
    if (!keyword(value)) return false;
    advance();
    return true;
  }

  void expectKeyword(String value) {
    if (!takeKeyword(value)) fail('Expected $value');
  }

  bool take(String value) {
    if (token.text != value || token.kind != _Kind.symbol) return false;
    advance();
    return true;
  }

  void expect(String value) {
    if (!take(value)) fail('Expected "$value"');
  }

  String identifier() {
    if (token.kind != _Kind.word && token.kind != _Kind.quotedIdentifier) {
      fail('Expected identifier');
    }
    final t = token;
    advance();
    if (t.kind == _Kind.word &&
        t.value.codeUnitAt(0) >= 48 &&
        t.value.codeUnitAt(0) <= 57) {
      fail('Identifier cannot begin with a digit', t);
    }
    if (t.value.isEmpty) fail('Identifier cannot be empty', t);
    return t.kind == _Kind.word ? t.value.toLowerCase() : t.value;
  }

  ErName name() {
    final first = identifier();
    return take('.') ? ErName(first, identifier()) : ErName('public', first);
  }

  List<String> columns() {
    expect('(');
    final list = <String>[];
    do {
      list.add(identifier());
    } while (take(','));
    expect(')');
    if (list.toSet().length != list.length) {
      fail('Duplicate column in constraint');
    }
    return list;
  }

  ErSchema parse() {
    while (token.kind != _Kind.end) {
      if (take(';')) continue;
      final at = token;
      expectKeyword('CREATE');
      expectKeyword('TABLE');
      if (takeKeyword('IF')) {
        expectKeyword('NOT');
        expectKeyword('EXISTS');
      }
      final table = _Table(name(), at);
      if (!tableIds.add(table.name.id)) {
        fail('Duplicate table "${table.name}"', at);
      }
      if (tables.length >= 5000) fail('Schema exceeds 5000 tables', at);
      expect('(');
      if (!take(')')) {
        do {
          _item(table);
        } while (take(','));
        expect(')');
      }
      tables.add(table);
      if (token.kind != _Kind.end) expect(';');
    }
    return _resolve();
  }

  void _item(_Table table) {
    final at = token;
    String? constraintName;
    if (takeKeyword('CONSTRAINT')) constraintName = identifier();
    _registerConstraint(table, constraintName, at);
    if (takeKeyword('PRIMARY')) {
      expectKeyword('KEY');
      _primary(table, _Key(constraintName, columns(), at));
    } else if (takeKeyword('UNIQUE')) {
      table.uniques.add(_Key(constraintName, columns(), at));
    } else if (takeKeyword('FOREIGN')) {
      expectKeyword('KEY');
      final local = columns();
      expectKeyword('REFERENCES');
      table.foreignKeys.add(_reference(constraintName, local, at));
    } else if (constraintName != null ||
        keyword('CHECK') ||
        keyword('EXCLUDE')) {
      fail('Unsupported table constraint', at);
    } else {
      _column(table);
    }
  }

  void _registerConstraint(_Table table, String? name, _Token at) {
    if (name != null && !table.constraintNames.add(name)) {
      fail('Duplicate constraint "$name" on "${table.name}"', at);
    }
  }

  void _primary(_Table table, _Key key) {
    if (table.primary != null) {
      fail('Multiple primary keys on "${table.name}"', key.at);
    }
    table.primary = key;
  }

  static const _constraintWords = {
    'CONSTRAINT',
    'PRIMARY',
    'UNIQUE',
    'NOT',
    'NULL',
    'DEFAULT',
    'REFERENCES',
    'CHECK',
    'GENERATED',
    'COLLATE'
  };
  bool _startsConstraint() =>
      token.kind == _Kind.word &&
      _constraintWords.contains(token.value.toUpperCase());

  String _span({required bool expression, List<_Token>? captured}) {
    final start = token.offset;
    var end = start;
    var depth = 0;
    var brackets = 0;
    var count = 0;
    while (token.kind != _Kind.end) {
      if (depth == 0 &&
          brackets == 0 &&
          (token.text == ',' || token.text == ')')) {
        break;
      }
      if (depth == 0 &&
          brackets == 0 &&
          _startsConstraint() &&
          (!expression || count > 0)) {
        break;
      }
      if (token.text == '(' && token.kind == _Kind.symbol) depth++;
      if (token.text == ')' && token.kind == _Kind.symbol) depth--;
      if (token.text == '[' && token.kind == _Kind.symbol) brackets++;
      if (token.text == ']' && token.kind == _Kind.symbol) brackets--;
      if (depth < 0 || brackets < 0) fail('Unbalanced SQL expression');
      captured?.add(token);
      end = token.end;
      count++;
      advance();
    }
    if (count == 0 || depth != 0 || brackets != 0) {
      fail(expression
          ? 'Expected valid default expression'
          : 'Expected valid column type');
    }
    return source.substring(start, end).trim();
  }

  void _column(_Table table) {
    final at = token;
    final columnName = identifier();
    if (table.columns.any((c) => c.name == columnName)) {
      fail('Duplicate column "$columnName"', at);
    }
    if (table.columns.length >= 300) fail('Table exceeds 300 columns', at);
    final typeTokens = <_Token>[];
    final sqlType = _span(expression: false, captured: typeTokens);
    _validateType(typeTokens);
    final column = _Column(columnName, sqlType, at);
    table.columns.add(column);
    while (token.kind != _Kind.end && token.text != ',' && token.text != ')') {
      final constraintAt = token;
      String? constraintName;
      if (takeKeyword('CONSTRAINT')) constraintName = identifier();
      _registerConstraint(table, constraintName, constraintAt);
      if (takeKeyword('NOT')) {
        expectKeyword('NULL');
        if (column.explicitlyNullable == true) {
          fail('Conflicting nullability for "$columnName"', constraintAt);
        }
        column.explicitlyNullable = false;
        column.notNull = true;
        column.nullabilityConstraintName = constraintName;
      } else if (takeKeyword('NULL')) {
        if (column.explicitlyNullable == false) {
          fail('Conflicting nullability for "$columnName"', constraintAt);
        }
        column.explicitlyNullable = true;
        column.nullabilityConstraintName = constraintName;
      } else if (takeKeyword('PRIMARY')) {
        expectKeyword('KEY');
        _primary(table, _Key(constraintName, [columnName], constraintAt));
      } else if (takeKeyword('UNIQUE')) {
        table.uniques.add(_Key(constraintName, [columnName], constraintAt));
      } else if (takeKeyword('DEFAULT')) {
        if (column.defaultExpression != null) {
          fail('Duplicate default for "$columnName"', constraintAt);
        }
        final expressionTokens = <_Token>[];
        column.defaultExpression =
            _span(expression: true, captured: expressionTokens);
        _validateDefault(expressionTokens);
        column.defaultConstraintName = constraintName;
      } else if (takeKeyword('REFERENCES')) {
        table.foreignKeys
            .add(_reference(constraintName, [columnName], constraintAt));
      } else {
        fail('Unsupported or invalid column constraint', constraintAt);
      }
    }
  }

  // Validate the documented expression subset without evaluating it. This
  // prevents stray tokens or incomplete expressions from being silently
  // absorbed into the stored default value.
  void _validateDefault(List<_Token> tokens) {
    var index = 0;
    bool symbol(String value) =>
        index < tokens.length &&
        tokens[index].kind == _Kind.symbol &&
        tokens[index].text == value;
    bool takeSymbol(String value) {
      if (!symbol(value)) return false;
      index++;
      return true;
    }

    bool word(String value) =>
        index < tokens.length && tokens[index].isKeyword(value);
    bool nameToken(_Token item) =>
        item.kind == _Kind.word || item.kind == _Kind.quotedIdentifier;
    Never invalid([_Token? at]) => fail(
        'Unsupported or invalid default expression',
        at ?? (index < tokens.length ? tokens[index] : tokens.last));
    void expectSymbol(String value) {
      if (!takeSymbol(value)) invalid();
    }

    late void Function() expression;
    void commaSeparated(String end) {
      if (takeSymbol(end)) return;
      do {
        expression();
      } while (takeSymbol(','));
      expectSymbol(end);
    }

    void value() {
      if (index >= tokens.length) invalid();
      if (takeSymbol('+') || takeSymbol('-')) {
        value();
        return;
      }
      if (word('NOT')) {
        index++;
        value();
        return;
      }
      if (takeSymbol('(')) {
        expression();
        expectSymbol(')');
      } else if (word('ARRAY') &&
          index + 1 < tokens.length &&
          tokens[index + 1].text == '[') {
        index += 2;
        commaSeparated(']');
      } else if (tokens[index].kind == _Kind.string) {
        index++;
      } else if (tokens[index].kind == _Kind.word &&
          RegExp(r'^\d+([eE]\d+)?$').hasMatch(tokens[index].value)) {
        index++;
        if (symbol('.') &&
            index + 1 < tokens.length &&
            RegExp(r'^\d+$').hasMatch(tokens[index + 1].value)) {
          index += 2;
        }
      } else if (nameToken(tokens[index])) {
        final first = tokens[index++];
        final upper = first.value.toUpperCase();
        if (const {'DATE', 'TIME', 'TIMESTAMP', 'INTERVAL'}.contains(upper) &&
            index < tokens.length &&
            tokens[index].kind == _Kind.string) {
          index++;
        } else {
          var qualified = false;
          while (takeSymbol('.')) {
            if (index >= tokens.length || !nameToken(tokens[index])) invalid();
            index++;
            qualified = true;
          }
          if (takeSymbol('(')) {
            commaSeparated(')');
          } else if (qualified ||
              first.kind != _Kind.word ||
              !const {
                'NULL',
                'TRUE',
                'FALSE',
                'CURRENT_TIMESTAMP',
                'CURRENT_DATE',
                'CURRENT_TIME',
                'LOCALTIME',
                'LOCALTIMESTAMP',
                'CURRENT_USER',
                'SESSION_USER',
                'CURRENT_ROLE',
                'CURRENT_CATALOG',
                'CURRENT_SCHEMA',
                'USER'
              }.contains(upper)) {
            invalid(first);
          }
        }
      } else {
        invalid();
      }
      while (symbol(':') &&
          index + 1 < tokens.length &&
          tokens[index + 1].text == ':') {
        index += 2;
        final start = index;
        var depth = 0;
        while (index < tokens.length) {
          final t = tokens[index];
          if (depth == 0 &&
              t.text == '[' &&
              index + 1 < tokens.length &&
              tokens[index + 1].text == ']') {
            index += 2;
            continue;
          }
          if (depth == 0 &&
              (t.text == ',' ||
                  t.text == ')' ||
                  t.text == ']' ||
                  t.text == '+' ||
                  t.text == '-' ||
                  t.text == '*' ||
                  t.text == '/' ||
                  t.text == '%' ||
                  t.text == '^' ||
                  t.text == '|' ||
                  t.text == ':')) {
            break;
          }
          if (t.text == '(') depth++;
          if (t.text == ')') depth--;
          index++;
        }
        if (start == index || depth != 0) invalid();
        _validateType(tokens.sublist(start, index));
      }
    }

    expression = () {
      value();
      while (index < tokens.length) {
        if (symbol(')') || symbol(']') || symbol(',')) return;
        if (takeSymbol('|')) {
          expectSymbol('|');
        } else if (!(takeSymbol('+') ||
            takeSymbol('-') ||
            takeSymbol('*') ||
            takeSymbol('/') ||
            takeSymbol('%') ||
            takeSymbol('^'))) {
          invalid();
        }
        value();
      }
    };
    expression();
    if (index != tokens.length) invalid();
  }

  void _validateType(List<_Token> tokens) {
    var index = 0;
    final words = <_Token>[];
    bool identifierToken(_Token t) =>
        t.kind == _Kind.word || t.kind == _Kind.quotedIdentifier;
    while (index < tokens.length &&
        tokens[index].text != '(' &&
        tokens[index].text != '[') {
      final t = tokens[index++];
      if (!identifierToken(t) && t.text != '.') {
        fail('Unsupported column type syntax', t);
      }
      words.add(t);
    }
    if (words.isEmpty || !identifierToken(words.first)) {
      fail('Expected column type', tokens.first);
    }
    for (final part in words.where(identifierToken)) {
      if (part.value.isEmpty ||
          (part.kind == _Kind.word && RegExp(r'^\d').hasMatch(part.value))) {
        fail('Invalid column type', part);
      }
    }
    if (index < tokens.length && tokens[index].text == '(') {
      final at = tokens[index++];
      var expectNumber = true;
      while (index < tokens.length && tokens[index].text != ')') {
        final t = tokens[index++];
        if (expectNumber && (t.text == '+' || t.text == '-')) {
          if (index >= tokens.length) fail('Invalid type modifier', t);
          final number = tokens[index++];
          if (number.kind != _Kind.word ||
              !RegExp(r'^\d+$').hasMatch(number.value)) {
            fail('Invalid type modifier', number);
          }
          expectNumber = false;
        } else if (expectNumber &&
            t.kind == _Kind.word &&
            RegExp(r'^\d+$').hasMatch(t.value)) {
          expectNumber = false;
        } else if (!expectNumber && t.text == ',') {
          expectNumber = true;
        } else {
          fail('Unsupported type modifier', t);
        }
      }
      if (index >= tokens.length || expectNumber) {
        fail('Invalid type modifier', at);
      }
      index++; // ')'
      while (index < tokens.length && identifierToken(tokens[index])) {
        words.add(tokens[index++]);
      }
    }
    while (index < tokens.length) {
      final at = tokens[index++];
      if (at.text != '[' ||
          index >= tokens.length ||
          tokens[index].text != ']') {
        fail('Unsupported column type syntax', at);
      }
      index++;
    }
    final hasDot = words.any((t) => t.text == '.');
    if (hasDot) {
      if (words.length != 3 ||
          !identifierToken(words[0]) ||
          words[1].text != '.' ||
          !identifierToken(words[2])) {
        fail('Invalid qualified type name', words.first);
      }
    } else if (words.length > 1) {
      const allowed = {
        'double precision',
        'character varying',
        'char varying',
        'bit varying',
        'timestamp with time zone',
        'timestamp without time zone',
        'time with time zone',
        'time without time zone'
      };
      if (words.any((t) => t.kind != _Kind.word) ||
          !allowed
              .contains(words.map((t) => t.value.toLowerCase()).join(' '))) {
        fail('Unsupported multiword column type', words.first);
      }
    }
  }

  _Foreign _reference(String? constraintName, List<String> local, _Token at) {
    final target = name();
    final targetColumns = token.text == '(' ? columns() : <String>[];
    String? onDelete, onUpdate;
    while (takeKeyword('ON')) {
      final delete = takeKeyword('DELETE');
      if (!delete) expectKeyword('UPDATE');
      String action;
      if (takeKeyword('NO')) {
        expectKeyword('ACTION');
        action = 'NO ACTION';
      } else if (takeKeyword('SET')) {
        if (takeKeyword('NULL')) {
          action = 'SET NULL';
        } else {
          expectKeyword('DEFAULT');
          action = 'SET DEFAULT';
        }
      } else if (takeKeyword('CASCADE')) {
        action = 'CASCADE';
      } else if (takeKeyword('RESTRICT')) {
        action = 'RESTRICT';
      } else {
        fail('Unsupported referential action');
      }
      if (delete) {
        if (onDelete != null) fail('Duplicate ON DELETE');
        onDelete = action;
      } else {
        if (onUpdate != null) fail('Duplicate ON UPDATE');
        onUpdate = action;
      }
    }
    return _Foreign(
        constraintName, local, target, targetColumns, at, onDelete, onUpdate);
  }

  ErSchema _resolve() {
    final byId = {for (final table in tables) table.name.id: table};
    final output = <ErTable>[];
    for (final table in tables) {
      final byName = {for (final column in table.columns) column.name: column};
      void check(List<String> names, _Token at) {
        for (final name in names) {
          if (!byName.containsKey(name)) {
            fail('Unknown column "$name" in "${table.name}"', at);
          }
        }
      }

      if (table.primary case final key?) {
        check(key.columns, key.at);
        for (final name in key.columns) {
          if (byName[name]!.explicitlyNullable == true) {
            fail('Primary key column "$name" cannot be declared NULL', key.at);
          }
          byName[name]!.notNull = true;
        }
      }
      for (final unique in table.uniques) {
        check(unique.columns, unique.at);
      }
      final fks = <ErForeignKey>[];
      for (final fk in table.foreignKeys) {
        check(fk.columns, fk.at);
        final target = byId[fk.target.id];
        if (target == null) {
          fail('Referenced table "${fk.target}" was not provided', fk.at);
        }
        final targetColumns = fk.targetColumns.isEmpty
            ? target.primary?.columns
            : fk.targetColumns;
        if (targetColumns == null || targetColumns.isEmpty) {
          fail('Referenced table "${fk.target}" has no primary key', fk.at);
        }
        if (targetColumns.length != fk.columns.length) {
          fail('Foreign key column counts do not match', fk.at);
        }
        final targetNames = target.columns.map((c) => c.name).toSet();
        for (final name in targetColumns) {
          if (!targetNames.contains(name)) {
            fail('Unknown referenced column "$name" in "${fk.target}"', fk.at);
          }
        }
        bool matches(List<String> candidate) =>
            candidate.length == targetColumns.length &&
            candidate.toSet().containsAll(targetColumns);
        if (!(target.primary != null && matches(target.primary!.columns)) &&
            !target.uniques.any((unique) => matches(unique.columns))) {
          fail(
              'Referenced columns in "${fk.target}" are not a primary or unique key',
              fk.at);
        }
        bool coversUniqueKey(List<String> columns) =>
            columns.isNotEmpty && fk.columns.toSet().containsAll(columns);
        final sourceUnique = (table.primary != null &&
                coversUniqueKey(table.primary!.columns)) ||
            table.uniques.any((unique) => coversUniqueKey(unique.columns));
        fks.add(ErForeignKey(
            source: table.name,
            target: fk.target,
            sourceColumns: fk.columns,
            targetColumns: targetColumns,
            nullable: fk.columns.any((name) => !byName[name]!.notNull),
            sourceUnique: sourceUnique,
            name: fk.name,
            onDelete: fk.onDelete,
            onUpdate: fk.onUpdate));
      }
      final primary = table.primary?.columns ?? const <String>[];
      output.add(ErTable(
          name: table.name,
          primaryKeyName: table.primary?.name,
          primaryKey: primary,
          columns: [
            for (final column in table.columns)
              ErColumn(
                  name: column.name,
                  sqlType: column.type,
                  nullable: !column.notNull,
                  primaryKey: primary.contains(column.name),
                  unique: table.uniques.any((u) =>
                      u.columns.length == 1 && u.columns.first == column.name),
                  foreignKey:
                      fks.any((fk) => fk.sourceColumns.contains(column.name)),
                  defaultExpression: column.defaultExpression,
                  nullabilityConstraintName: column.nullabilityConstraintName,
                  defaultConstraintName: column.defaultConstraintName)
          ],
          uniqueConstraints: [
            for (final unique in table.uniques)
              ErUniqueConstraint(unique.name, unique.columns)
          ],
          foreignKeys: fks));
    }
    return ErSchema(output);
  }
}
