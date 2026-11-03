import 'diagram_document.dart';
import 'json_depth.dart';

/// Syntax error in the supported Mermaid flowchart subset. Locations are
/// one-based line and column numbers and an offset in Dart UTF-16 code units.
class MermaidParseException extends FormatException {
  MermaidParseException(
      String message, String source, this.line, this.column, int offset)
      : super('$message at line $line, column $column', source, offset);

  final int line;
  final int column;
}

/// Parses a documented subset of `graph` / `flowchart` into a diagram.
/// No Mermaid code, links, directives or remote resources are executed.
DiagramDocument parseMermaidFlowchart(String source, {String? title}) {
  if (exceedsUtf8Limit(source, 2000000)) {
    throw const FormatException('Mermaid input exceeds 2000000 bytes');
  }
  return _MermaidParser(source, title).parse();
}

class _MermaidParser {
  _MermaidParser(String source, this.title) : input = _Cursor(source);
  final _Cursor input;
  final String? title;
  final nodes = <String, _Node>{};
  final edges = <Map<String, Object?>>[];

  DiagramDocument parse() {
    input.skipSeparators();
    final header = input.identifier('Expected graph or flowchart declaration');
    if (header != 'graph' && header != 'flowchart') {
      input.fail('Only graph and flowchart declarations are supported');
    }
    if (!input.skipHorizontal()) {
      input.fail('Expected a direction after $header');
    }
    final direction = input.identifier('Expected LR, RL, TB, TD or BT');
    if (!const {'LR', 'RL', 'TB', 'BT', 'TD'}.contains(direction)) {
      input.fail('Unsupported flowchart direction "$direction"');
    }
    input.skipHorizontal();
    if (!input.atStatementEnd) {
      input.fail('Expected a newline or semicolon after declaration');
    }
    input.skipSeparators();
    while (!input.done) {
      _statement();
      input.skipHorizontal();
      if (!input.atStatementEnd) {
        input.fail('Expected an edge, newline or semicolon');
      }
      input.skipSeparators();
    }
    return DiagramDocument.fromJson({
      'schemaVersion': 1,
      'diagramType': 'flowchart',
      if (title != null) 'title': title,
      'layout': {
        'mode': 'auto',
        'direction': direction == 'TD' ? 'TB' : direction
      },
      'metadata': {'sourceFormat': 'mermaid'},
      'nodes': [for (final node in nodes.values) node.toJson()],
      'edges': edges,
    });
  }

  void _statement() {
    final first = _node(statementStart: true);
    var source = first;
    while (true) {
      input.skipHorizontal();
      if (input.atStatementEnd) return;
      final link = _link();
      input.skipHorizontal();
      final target = _node();
      if (edges.length >= 10000) input.fail('Flowchart exceeds 10000 edges');
      edges.add({
        'id': 'mermaid_edge_${edges.length + 1}',
        'source': source,
        'target': target,
        'type': link.directed ? 'directed' : 'undirected',
        if (link.label != null) 'label': link.label,
      });
      source = target;
    }
  }

  String _node({bool statementStart = false}) {
    final id = input.identifier('Expected a node identifier');
    if (statementStart &&
        const {
          'subgraph',
          'end',
          'class',
          'classDef',
          'style',
          'linkStyle',
          'click',
          'direction',
          'accTitle',
          'accDescr'
        }.contains(id)) {
      input.fail('Unsupported Mermaid directive "$id"');
    }
    input.skipHorizontal();
    String? shape;
    String? label;
    if (input.take('[', consume: true)) {
      input.skipHorizontal();
      if (input.take('[') ||
          input.take('(') ||
          input.take('/') ||
          input.take(r'\')) {
        input.fail('Unsupported node shape');
      }
      shape = 'rectangle';
      label = input.labelUntil(']');
    } else if (input.take('((', consume: true)) {
      shape = 'circle';
      label = input.labelUntil('))');
    } else if (input.take('(', consume: true)) {
      input.skipHorizontal();
      if (input.take('[')) input.fail('Unsupported node shape');
      shape = 'rounded';
      label = input.labelUntil(')');
    } else if (input.take('{', consume: true)) {
      shape = 'diamond';
      label = input.labelUntil('}');
    }
    final existing = nodes[id];
    if (existing == null) {
      if (nodes.length >= 5000) input.fail('Flowchart exceeds 5000 nodes');
      nodes[id] = _Node(id, label ?? id, shape ?? 'rectangle');
    } else if (label != null) {
      // References never overwrite a declaration. When there are multiple
      // explicit declarations, the last declaration wins deterministically.
      existing.label = label;
      existing.shape = shape!;
    }
    return id;
  }

  _Link _link() {
    bool directed;
    String? label;
    if (input.take('-->', consume: true)) {
      directed = true;
    } else if (input.take('---', consume: true)) {
      directed = false;
    } else if (input.take('--', consume: true)) {
      input.skipHorizontal();
      label = input.labelUntilArrow();
      directed = true;
    } else {
      input.fail('Expected -->, --- or -- label -->');
    }
    input.skipHorizontal();
    if (input.take('|', consume: true)) {
      if (label != null) input.fail('A link cannot have two labels');
      label = input.labelUntil('|');
    }
    return _Link(directed, label);
  }
}

class _Node {
  _Node(this.id, this.label, this.shape);
  final String id;
  String label;
  String shape;
  Map<String, Object?> toJson() => {
        'id': id,
        'type': shape,
        'label': label,
        if (shape == 'circle') 'size': {'width': 120, 'height': 120},
        if (shape == 'diamond') 'size': {'width': 180, 'height': 120},
      };
}

class _Link {
  const _Link(this.directed, this.label);
  final bool directed;
  final String? label;
}

class _Cursor {
  _Cursor(this.source);
  final String source;
  int offset = 0;
  int line = 1;
  int column = 1;
  bool get done => offset >= source.length;
  bool get atStatementEnd =>
      done ||
      _peek == '\n' ||
      _peek == '\r' ||
      _peek == ';' ||
      source.startsWith('%%', offset);
  String get _peek => done ? '' : source[offset];

  Never fail(String message) =>
      throw MermaidParseException(message, source, line, column, offset);

  void _advance() {
    if (done) return;
    final char = source[offset++];
    if (char == '\r') {
      if (!done && source[offset] == '\n') offset++;
      line++;
      column = 1;
    } else if (char == '\n') {
      line++;
      column = 1;
    } else {
      column++;
    }
  }

  bool take(String value, {bool consume = false}) {
    if (!source.startsWith(value, offset)) return false;
    if (consume) {
      for (var i = 0; i < value.length; i++) {
        _advance();
      }
    }
    return true;
  }

  bool skipHorizontal() {
    var skipped = false;
    while (_peek == ' ' || _peek == '\t') {
      _advance();
      skipped = true;
    }
    return skipped;
  }

  void skipSeparators() {
    while (!done) {
      skipHorizontal();
      if (take('%%')) {
        while (!done && _peek != '\n' && _peek != '\r') {
          _advance();
        }
      } else if (_peek == '\n' || _peek == '\r' || _peek == ';') {
        _advance();
      } else {
        break;
      }
    }
  }

  String identifier(String message) {
    final start = offset;
    while (!done) {
      final code = source.codeUnitAt(offset);
      final valid = (code >= 65 && code <= 90) ||
          (code >= 97 && code <= 122) ||
          (code >= 48 && code <= 57) ||
          code == 95 ||
          code >= 128;
      if (!valid) break;
      _advance();
    }
    if (start == offset) fail(message);
    return source.substring(start, offset);
  }

  String labelUntil(String end) {
    skipHorizontal();
    final buffer = StringBuffer();
    if (_peek == '"') {
      _advance();
      while (!done && _peek != '"') {
        if (_peek == '\n' || _peek == '\r') fail('Unterminated quoted label');
        if (_peek == r'\') {
          _advance();
          if (done || (_peek != '"' && _peek != r'\')) {
            fail('Only quote and backslash escapes are supported');
          }
        }
        buffer.write(_peek);
        _advance();
      }
      if (done) fail('Unterminated quoted label');
      _advance();
      skipHorizontal();
      if (!take(end, consume: true)) fail('Expected "$end" after quoted label');
      return buffer.toString();
    }
    while (!done && !take(end)) {
      if (_peek == '\n' || _peek == '\r') {
        fail('Unterminated label; expected "$end"');
      }
      buffer.write(_peek);
      _advance();
    }
    if (!take(end, consume: true)) fail('Unterminated label; expected "$end"');
    return buffer.toString().trim();
  }

  String labelUntilArrow() {
    final buffer = StringBuffer();
    while (!done && !take('-->')) {
      if (_peek == '\n' || _peek == '\r' || _peek == ';') {
        fail('Unterminated link label; expected -->');
      }
      buffer.write(_peek);
      _advance();
    }
    if (!take('-->', consume: true)) {
      fail('Unterminated link label; expected -->');
    }
    final label = buffer.toString().trim();
    if (label.isEmpty) fail('Link label cannot be empty');
    return label;
  }
}
