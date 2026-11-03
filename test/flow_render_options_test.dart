import 'package:fflow/fflow_desktop.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('render options reject invalid values and hard-limit increases', () {
    for (final options in [
      const FlowRenderOptions(pixelRatio: 0),
      const FlowRenderOptions(pixelRatio: double.infinity),
      const FlowRenderOptions(padding: -1),
      const FlowRenderOptions(maxWidth: 8193),
      const FlowRenderOptions(maxHeight: 0),
      const FlowRenderOptions(maxPixels: 32000001),
    ]) {
      expect(options.validate, throwsArgumentError);
    }
    const FlowRenderOptions(
            pixelRatio: 3, maxWidth: 400, maxHeight: 300, maxPixels: 120000)
        .validate();
  });

  test('worker request byte limits cannot exceed protocol hard limits', () {
    expect(
        () => FlowIsolatedRenderService(
            executable: 'unused', maxInputBytes: 16000001),
        throwsArgumentError);
    expect(
        () => FlowIsolatedRenderService(
            executable: 'unused', maxOutputBytes: 64000001),
        throwsArgumentError);
  });

  test('snapshot rendering rejects a layout direction override', () {
    final renderer = FlowIsolatedRenderService(executable: 'unused');
    expect(
        () => renderer.renderSnapshot({},
            options: const FlowRenderOptions(direction: DiagramDirection.tb)),
        throwsArgumentError);
  });
}
