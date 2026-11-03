import 'dart:convert';

import 'json_depth.dart';

enum DiagramType { flowchart, er }

enum DiagramDirection { lr, rl, tb, bt }

enum DiagramLayoutMode { auto, preserve }

enum DiagramNodeOrder { input, id, label }

enum DiagramTheme { light, dark, print }

enum DiagramPortKind { source, target }

enum DiagramPortSide { left, right, top, bottom }

/// A graph reference points at a node, parent or port that does not exist.
class DiagramReferenceException extends FormatException {
  const DiagramReferenceException(super.message);
  @override
  String toString() => 'GRAPH_REFERENCE_ERROR: $message';
}

/// Immutable, versioned application-level graph. Unknown properties are
/// retained at their original location for forward-compatible round trips.
class DiagramDocument {
  DiagramDocument._(this.type, this.title, this.nodes, this.edges, this.layout,
      this.theme, this.metadata, this.extra);

  final DiagramType type;
  final String? title;
  final List<DiagramNode> nodes;
  final List<DiagramEdge> edges;
  final DiagramLayout layout;
  final DiagramTheme theme;
  final Map<String, Object?> metadata;
  final Map<String, Object?> extra;

  factory DiagramDocument.parse(String source) {
    try {
      if (exceedsUtf8Limit(source, 16000000)) {
        throw const FormatException('Graph JSON input exceeds 16000000 bytes');
      }
      checkJsonDepth(source);
      return DiagramDocument.fromJson(jsonDecode(source));
    } on FormatException {
      rethrow;
    } catch (error) {
      throw FormatException('Invalid diagram JSON: $error');
    }
  }

  factory DiagramDocument.fromJson(Object? value) {
    final json = _map(value, r'$');
    final version = json['schemaVersion'];
    if (version is! int || version != 1) {
      throw const FormatException(r'$.schemaVersion: expected version 1');
    }
    final type =
        _enum(DiagramType.values, json['diagramType'], r'$.diagramType');
    final title = _optionalString(json['title'], r'$.title');
    final nodes = _list(json['nodes'], r'$.nodes');
    final edges = _list(json['edges'], r'$.edges');
    if (nodes.length > 5000 || edges.length > 10000) {
      throw const FormatException('Graph exceeds node or edge limits');
    }
    final parsedNodes = <DiagramNode>[];
    final ids = <String, DiagramNode>{};
    for (var i = 0; i < nodes.length; i++) {
      final node = DiagramNode._fromJson(nodes[i], r'$.nodes[' '$i]');
      if (ids.containsKey(node.id)) {
        throw FormatException('Duplicate node id "${node.id}"');
      }
      ids[node.id] = node;
      parsedNodes.add(node);
    }
    final parsedEdges = <DiagramEdge>[];
    final edgeIds = <String>{};
    for (var i = 0; i < edges.length; i++) {
      final edge = DiagramEdge._fromJson(edges[i], r'$.edges[' '$i]');
      if (!edgeIds.add(edge.id)) {
        throw FormatException('Duplicate edge id "${edge.id}"');
      }
      final source = ids[edge.source];
      final target = ids[edge.target];
      if (source == null || target == null) {
        throw DiagramReferenceException(
            'Edge "${edge.id}" references a missing node');
      }
      void checkPort(DiagramNode node, String? id, DiagramPortKind kind) {
        if (id != null &&
            !node.ports.any((p) => p.id == id && p.kind == kind)) {
          throw DiagramReferenceException(
              'Edge "${edge.id}" references missing ${kind.name} port "$id" on "${node.id}"');
        }
      }

      checkPort(source, edge.sourcePort, DiagramPortKind.source);
      checkPort(target, edge.targetPort, DiagramPortKind.target);
      parsedEdges.add(edge);
    }
    final parentDepths = <String, int>{};
    for (final node in parsedNodes) {
      final seen = <String>{};
      final path = <String>[];
      String? current = node.id;
      while (current != null && !parentDepths.containsKey(current)) {
        if (!seen.add(current)) {
          throw FormatException('Parent cycle at node "${node.id}"');
        }
        final item = ids[current];
        if (item == null) {
          throw DiagramReferenceException(
              'Missing parent "$current" for node "${node.id}"');
        }
        path.add(current);
        current = item.parentId;
      }
      var depth = current == null ? 0 : parentDepths[current]!;
      for (final id in path.reversed) {
        depth++;
        if (depth > 128) {
          throw FormatException('Parent nesting exceeds 128 at node "$id"');
        }
        parentDepths[id] = depth;
      }
    }
    final layout = DiagramLayout._fromJson(json['layout']);
    if (layout.mode == DiagramLayoutMode.preserve &&
        parsedNodes.any((node) => node.position == null)) {
      throw const FormatException(
          'Preserve layout requires a position for every node');
    }
    return DiagramDocument._(
        type,
        title,
        List.unmodifiable(parsedNodes),
        List.unmodifiable(parsedEdges),
        layout,
        _enum(DiagramTheme.values, json['theme'] ?? 'light', r'$.theme'),
        _jsonObject(json['metadata'], r'$.metadata'),
        _extra(json, {
          'schemaVersion',
          'diagramType',
          'title',
          'nodes',
          'edges',
          'layout',
          'theme',
          'metadata'
        }));
  }

  Map<String, Object?> toJson() => {
        ...extra,
        'schemaVersion': 1,
        'diagramType': type.name,
        if (title != null) 'title': title,
        'nodes': nodes.map((n) => n.toJson()).toList(),
        'edges': edges.map((e) => e.toJson()).toList(),
        'layout': layout.toJson(),
        'theme': theme.name,
        'metadata': metadata,
      };
}

class DiagramNode {
  DiagramNode._(this.id, this.type, this.label, this.data, this.position,
      this.size, this.parentId, this.ports, this.style, this.extra);
  final String id;
  final String type;
  final String label;
  final Map<String, Object?> data;
  final DiagramPosition? position;
  final DiagramSize? size;
  final String? parentId;
  final List<DiagramPort> ports;
  final Map<String, Object?> style;
  final Map<String, Object?> extra;

  factory DiagramNode._fromJson(Object? value, String path) {
    final json = _map(value, path);
    final ports = _list(json['ports'] ?? const [], '$path.ports');
    final parsedPorts = <DiagramPort>[];
    final ids = <String>{};
    for (var i = 0; i < ports.length; i++) {
      final port = DiagramPort._fromJson(ports[i], '$path.ports[$i]');
      if (!ids.add(port.id)) {
        throw FormatException('$path.ports: duplicate id "${port.id}"');
      }
      parsedPorts.add(port);
    }
    return DiagramNode._(
        _requiredString(json['id'], '$path.id'),
        _requiredString(json['type'] ?? 'default', '$path.type'),
        _requiredString(json['label'], '$path.label', allowEmpty: true),
        _jsonObject(json['data'], '$path.data'),
        json['position'] == null
            ? null
            : DiagramPosition._fromJson(json['position'], '$path.position'),
        json['size'] == null
            ? null
            : DiagramSize._fromJson(json['size'], '$path.size'),
        _optionalString(json['parentId'], '$path.parentId'),
        List.unmodifiable(parsedPorts),
        _style(json['style'], '$path.style'),
        _extra(json, {
          'id',
          'type',
          'label',
          'data',
          'position',
          'size',
          'parentId',
          'ports',
          'style'
        }));
  }
  Map<String, Object?> toJson() => {
        ...extra,
        'id': id,
        'type': type,
        'label': label,
        'data': data,
        if (position != null) 'position': position!.toJson(),
        if (size != null) 'size': size!.toJson(),
        if (parentId != null) 'parentId': parentId,
        'ports': ports.map((p) => p.toJson()).toList(),
        'style': style
      };
}

class DiagramEdge {
  DiagramEdge._(
      this.id,
      this.source,
      this.target,
      this.sourcePort,
      this.targetPort,
      this.label,
      this.type,
      this.data,
      this.style,
      this.extra);
  final String id, source, target, type;
  final String? sourcePort, targetPort, label;
  final Map<String, Object?> data, style, extra;
  factory DiagramEdge._fromJson(Object? value, String path) {
    final json = _map(value, path);
    return DiagramEdge._(
        _requiredString(json['id'], '$path.id'),
        _requiredString(json['source'], '$path.source'),
        _requiredString(json['target'], '$path.target'),
        _optionalString(json['sourcePort'], '$path.sourcePort'),
        _optionalString(json['targetPort'], '$path.targetPort'),
        _optionalString(json['label'], '$path.label'),
        _requiredString(json['type'] ?? 'directed', '$path.type'),
        _jsonObject(json['data'], '$path.data'),
        _style(json['style'], '$path.style'),
        _extra(json, {
          'id',
          'source',
          'target',
          'sourcePort',
          'targetPort',
          'label',
          'type',
          'data',
          'style'
        }));
  }
  Map<String, Object?> toJson() => {
        ...extra,
        'id': id,
        'source': source,
        'target': target,
        if (sourcePort != null) 'sourcePort': sourcePort,
        if (targetPort != null) 'targetPort': targetPort,
        if (label != null) 'label': label,
        'type': type,
        'data': data,
        'style': style
      };
}

class DiagramPosition {
  DiagramPosition._(this.x, this.y, this.extra);
  final double x, y;
  final Map<String, Object?> extra;
  factory DiagramPosition._fromJson(Object? value, String path) {
    final json = _map(value, path);
    return DiagramPosition._(_number(json['x'], '$path.x'),
        _number(json['y'], '$path.y'), _extra(json, {'x', 'y'}));
  }
  Map<String, Object?> toJson() => {...extra, 'x': x, 'y': y};
}

class DiagramSize {
  DiagramSize._(this.width, this.height, this.extra);
  final double width, height;
  final Map<String, Object?> extra;
  factory DiagramSize._fromJson(Object? value, String path) {
    final json = _map(value, path);
    final width = _number(json['width'], '$path.width');
    final height = _number(json['height'], '$path.height');
    if (width <= 0 || height <= 0 || width > 10000 || height > 10000) {
      throw FormatException('$path: dimensions must be > 0 and <= 10000');
    }
    return DiagramSize._(width, height, _extra(json, {'width', 'height'}));
  }
  Map<String, Object?> toJson() => {...extra, 'width': width, 'height': height};
}

class DiagramPort {
  DiagramPort._(this.id, this.kind, this.side, this.offset, this.extra);
  final String id;
  final DiagramPortKind kind;
  final DiagramPortSide side;
  final double offset;
  final Map<String, Object?> extra;
  factory DiagramPort._fromJson(Object? value, String path) {
    final json = _map(value, path);
    final offset = _number(json['offset'] ?? 0.5, '$path.offset');
    if (offset < 0 || offset > 1) {
      throw FormatException('$path.offset: expected 0..1');
    }
    return DiagramPort._(
        _requiredString(json['id'], '$path.id'),
        _enum(DiagramPortKind.values, json['kind'], '$path.kind'),
        _enum(DiagramPortSide.values, json['side'], '$path.side'),
        offset,
        _extra(json, {'id', 'kind', 'side', 'offset'}));
  }
  Map<String, Object?> toJson() => {
        ...extra,
        'id': id,
        'kind': kind.name,
        'side': side.name,
        'offset': offset
      };
}

class DiagramLayout {
  DiagramLayout._(this.mode, this.direction, this.nodeOrder, this.nodeSpacing,
      this.layerSpacing, this.groupPadding, this.extra);
  final DiagramLayoutMode mode;
  final DiagramDirection direction;
  final DiagramNodeOrder nodeOrder;
  final double nodeSpacing, layerSpacing, groupPadding;
  final Map<String, Object?> extra;
  factory DiagramLayout._fromJson(Object? value) {
    final json = _map(value ?? const <String, Object?>{}, r'$.layout');
    double spacing(String key, double fallback) {
      final number = _number(json[key] ?? fallback, r'$.layout.' + key);
      if (number < 0 || number > 10000) {
        throw FormatException('layout.$key: expected 0..10000');
      }
      return number;
    }

    final direction = json['direction'] ?? 'LR';
    if (direction is! String ||
        !const {'LR', 'RL', 'TB', 'BT'}.contains(direction)) {
      throw FormatException(
          r'$.layout.direction: unsupported value "' '$direction"');
    }
    return DiagramLayout._(
        _enum(
            DiagramLayoutMode.values, json['mode'] ?? 'auto', r'$.layout.mode'),
        _enum(DiagramDirection.values, direction.toLowerCase(),
            r'$.layout.direction'),
        _enum(DiagramNodeOrder.values, json['nodeOrder'] ?? 'input',
            r'$.layout.nodeOrder'),
        spacing('nodeSpacing', 48),
        spacing('layerSpacing', 96),
        spacing('groupPadding', 32),
        _extra(json, {
          'mode',
          'direction',
          'nodeOrder',
          'nodeSpacing',
          'layerSpacing',
          'groupPadding'
        }));
  }
  Map<String, Object?> toJson() => {
        ...extra,
        'mode': mode.name,
        'direction': direction.name.toUpperCase(),
        'nodeOrder': nodeOrder.name,
        'nodeSpacing': nodeSpacing,
        'layerSpacing': layerSpacing,
        'groupPadding': groupPadding
      };
}

Map<String, Object?> _map(Object? value, String path) {
  if (value is! Map || value.keys.any((k) => k is! String)) {
    throw FormatException('$path: expected object with string keys');
  }
  return Map<String, Object?>.from(value);
}

List<Object?> _list(Object? value, String path) {
  if (value is! List) throw FormatException('$path: expected array');
  return value.cast<Object?>();
}

String _requiredString(Object? value, String path, {bool allowEmpty = false}) {
  if (value is! String || (!allowEmpty && value.isEmpty)) {
    throw FormatException(
        '$path: expected ${allowEmpty ? 'string' : 'nonempty string'}');
  }
  return value;
}

String? _optionalString(Object? value, String path) =>
    value == null ? null : _requiredString(value, path, allowEmpty: true);
double _number(Object? value, String path) {
  if (value is! num || !value.isFinite) {
    throw FormatException('$path: expected finite number');
  }
  final result = value.toDouble();
  if (!result.isFinite) throw FormatException('$path: number is out of range');
  return result;
}

T _enum<T extends Enum>(List<T> values, Object? value, String path) {
  for (final item in values) {
    if (item.name == value) return item;
  }
  throw FormatException('$path: unsupported value "$value"');
}

Object? _freeze(Object? value, String path, [int depth = 0]) {
  if (depth > 64) throw FormatException('$path: JSON nesting exceeds 64');
  if (value == null || value is String || value is bool) return value;
  if (value is num && value.isFinite) return value;
  if (value is List) {
    return List<Object?>.unmodifiable(
        value.map((v) => _freeze(v, path, depth + 1)));
  }
  if (value is Map && value.keys.every((k) => k is String)) {
    return Map<String, Object?>.unmodifiable(value.map(
        (k, v) => MapEntry(k as String, _freeze(v, '$path.$k', depth + 1))));
  }
  throw FormatException('$path: expected a finite JSON value');
}

Map<String, Object?> _jsonObject(Object? value, String path) =>
    _freeze(_map(value ?? const <String, Object?>{}, path), path)
        as Map<String, Object?>;
Map<String, Object?> _extra(Map<String, Object?> json, Set<String> known) =>
    _jsonObject({
      for (final entry in json.entries)
        if (!known.contains(entry.key)) entry.key: entry.value
    }, r'$');
Map<String, Object?> _style(Object? value, String path) {
  final style = _jsonObject(value, path);
  if (style['shape'] != null && style['shape'] is! String) {
    throw FormatException('$path.shape: expected string');
  }
  if (style.containsKey('strokeWidth')) {
    final width = _number(style['strokeWidth'], '$path.strokeWidth');
    if (width <= 0 || width > 64) {
      throw FormatException('$path.strokeWidth: expected > 0 and <= 64');
    }
  }
  for (final key in ['background', 'foreground', 'border', 'color']) {
    final color = style[key];
    if (color != null &&
        (color is! String ||
            !RegExp(r'^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$').hasMatch(color))) {
      throw FormatException('$path.$key: expected #RRGGBB or #AARRGGBB');
    }
  }
  return style;
}
