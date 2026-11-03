import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import '../diagram/json_depth.dart';
import 'flow_errors.dart';

/// Validate object graphs iteratively so cyclic or deeply nested input cannot
/// overflow the JSON encoder stack. Shared (non-cyclic) values are allowed.
void validateJsonGraph(Object? root) {
  final active = HashSet<Object>.identity();
  final stack = <(Object?, int, bool)>[(root, 0, false)];
  var count = 0;
  while (stack.isNotEmpty) {
    final (value, depth, exiting) = stack.removeLast();
    if (exiting) {
      active.remove(value);
      continue;
    }
    if (++count > 200000) {
      throw const FlowWorkerException(
          'INPUT_TOO_LARGE', 'JSON contains too many values');
    }
    if (depth > 64) {
      throw const FlowWorkerException(
          'SCHEMA_ERROR', 'JSON nesting exceeds 64');
    }
    if (value == null || value is bool) continue;
    if (value is String) {
      if (value.length > 1000000) {
        throw const FlowWorkerException(
            'INPUT_TOO_LARGE', 'JSON string exceeds limit');
      }
      continue;
    }
    if (value is num) {
      if (!value.isFinite) {
        throw const FlowWorkerException(
            'SCHEMA_ERROR', 'JSON numbers must be finite');
      }
      continue;
    }
    if (value is! List && value is! Map) {
      throw const FlowWorkerException(
          'SCHEMA_ERROR', 'Input contains a non-JSON value');
    }
    final object = value;
    if (!active.add(object)) {
      throw const FlowWorkerException('SCHEMA_ERROR', 'Cyclic JSON input');
    }
    stack.add((object, depth, true));
    if (value is List) {
      if (value.length > 200000) {
        throw const FlowWorkerException(
            'INPUT_TOO_LARGE', 'JSON array exceeds limit');
      }
      for (final item in value) {
        stack.add((item, depth + 1, false));
      }
    } else if (value is Map) {
      if (value.length > 200000) {
        throw const FlowWorkerException(
            'INPUT_TOO_LARGE', 'JSON object exceeds limit');
      }
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw const FlowWorkerException(
              'SCHEMA_ERROR', 'JSON keys must be strings');
        }
        stack.add((entry.key, depth + 1, false));
        stack.add((entry.value, depth + 1, false));
      }
    }
  }
}

Uint8List encodeJsonBounded(Object? value, int maxBytes) {
  validateJsonGraph(value);
  final output = _LimitedSink(maxBytes);
  final encoder = JsonUtf8Encoder().startChunkedConversion(output);
  encoder.add(value);
  encoder.close();
  return output.bytes.takeBytes();
}

class _LimitedSink implements Sink<List<int>> {
  _LimitedSink(this.limit);
  final int limit;
  final BytesBuilder bytes = BytesBuilder(copy: false);
  var length = 0;
  @override
  void add(List<int> data) {
    length += data.length;
    if (length > limit) {
      throw const FlowWorkerException(
          'INPUT_TOO_LARGE', 'JSON exceeds input byte limit');
    }
    bytes.add(data);
  }

  @override
  void close() {}
}

/// Check nesting before handing potentially hostile text to jsonDecode.
void checkJsonTextDepth(String text) {
  checkJsonDepth(text);
}
