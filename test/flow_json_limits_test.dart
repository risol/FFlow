import 'dart:convert';

import 'package:fflow/fflow_desktop.dart';
import 'package:fflow/src/desktop/json_limits.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  void expectCode(void Function() action, String code) {
    expect(
        action,
        throwsA(
            isA<FlowWorkerException>().having((e) => e.code, 'code', code)));
  }

  test('rejects cycles, deep values, non-JSON values and non-finite numbers',
      () {
    final cyclic = <String, Object?>{};
    cyclic['self'] = cyclic;
    expectCode(() => validateJsonGraph(cyclic), 'SCHEMA_ERROR');
    Object? deep = 0;
    for (var i = 0; i < 70; i++) {
      deep = [deep];
    }
    expectCode(() => validateJsonGraph(deep), 'SCHEMA_ERROR');
    expectCode(() => validateJsonGraph({'n': double.infinity}), 'SCHEMA_ERROR');
    expectCode(() => validateJsonGraph({'x': DateTime.now()}), 'SCHEMA_ERROR');
    expectCode(() => validateJsonGraph({1: 'bad key'}), 'SCHEMA_ERROR');
    final shared = [1, 2];
    expect(() => validateJsonGraph([shared, shared]), returnsNormally);
    final service = FlowIsolatedRenderService(executable: 'never-started');
    expectCode(() => service.renderSnapshot(cyclic), 'SCHEMA_ERROR');
  });

  test('chunked encoder enforces UTF-8 byte limits', () {
    final value = {'a': '中文'};
    final bytes = encodeJsonBounded(value, 100);
    expect(jsonDecode(utf8.decode(bytes)), value);
    expectCode(
        () => encodeJsonBounded(value, bytes.length - 1), 'INPUT_TOO_LARGE');
    expectCode(() => validateJsonGraph('x' * 1000001), 'INPUT_TOO_LARGE');
  });

  test('text depth checking ignores brackets inside escaped strings', () {
    expect(() => checkJsonTextDepth('{"x":"[[\\"{{"}'), returnsNormally);
    expect(() => checkJsonTextDepth('${'[' * 65}0${']' * 65}'),
        throwsFormatException);
  });

  test('UTF-8 limits account for CJK, emoji and invalid surrogate units', () {
    for (final value in ['abc', '中文', '😀', String.fromCharCode(0xd800)]) {
      final length = utf8.encode(value).length;
      expect(exceedsUtf8Limit(value, length), isFalse);
      expect(exceedsUtf8Limit(value, length - 1), isTrue);
    }
  });
}
