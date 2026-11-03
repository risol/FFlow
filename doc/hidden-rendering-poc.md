# Detached rendering experiment

`fflow_capture.dart` contains an experimental capture path for a static
Flutter widget tree. It creates a separate `BuildOwner`, `PipelineOwner` and
`RenderView` for an existing Flutter view, performs layout and paint, and
captures a `RepaintBoundary`. The render tree is never sent to the window via
`RenderView.compositeFrame`. It does not create or hide a native window.

The widget test exercises FFlow itself, a canvas larger than the test host
view, a pixel inside a node outside that view, and 20 successive captures. This
is evidence for the detached-pipeline approach in the Flutter test environment,
not proof of the desktop acceptance criteria.

This experiment only supports a self-contained static widget that can paint in
two synchronous build/layout/paint passes. The second pass incorporates FFlow's
scene origin, which is computed during the first layout. The caller must provide inherited widgets such as
`Directionality` and must preload fonts and resources. Widgets depending on
subsequent frames, asynchronous loading, animations, host inherited state or
`GlobalKey.currentContext` in the detached tree are not supported. The lower
level `captureFlowOffscreen` API requires the caller to provide the canvas size
and viewport. The experimental `renderFlowSnapshot` API calculates bounds for
visible nodes, built-in edge paths and default edge labels, ignoring the saved
viewport. Node builders must stay inside their declared dimensions; custom edge
renderers and auto-measured nodes are not supported. No timeout, task queue or
file output is provided. Pixel limits are checked before rendering, but this
does not constitute a process memory limit.

`renderFlowSnapshot` disables the background grid by default. A Windows stress
run with 500 graph captures and the grid enabled grew from about 94 MB at task
10 to 606 MB at task 500; validating fewer images or forcing host frames did
not eliminate that growth. A same-size plain-widget capture stayed around
70–79 MB, while graph captures with the grid disabled reached about 135 MB.
A further 2,000-task no-grid run rose from about 84 MB to 273 MB, so disabling
the grid reduces growth but does not satisfy the long-run stability target.
In a grid-only 500-task run, Flutter reported 500 picture creations and
disposals and 506 image creations and disposals, yet working set rose from
about 85 MB to 556 MB. Explicit Dart-side handle disposal is therefore not
sufficient evidence that the underlying process memory has stabilized.
The precise cause and long-run behavior are still under investigation. Do not
enable the grid for sustained production workloads on the basis of this PoC.
The exporter intercepts Flutter-reported errors during its synchronous build,
layout and paint passes, restores the host handler before awaiting capture, and
also rejects a default Flutter `ErrorWidget`. Asynchronous errors and failures
silently swallowed inside application widgets remain outside that mechanism.

The Windows release sample in `apps/hidden_render_poc` was run on Windows 10
22H2 (build 19045.6466), Flutter 3.47.7, engine deb287481e. On one run it
completed 20 captures in 945 ms; 85 samples observed no visible or foreground
window and a peak working set of 128,372,736 bytes. The 1850 x 340 output was
visually checked: both nodes, their connecting edge, the edge label and
Chinese text were visible. The runner never calls `ShowWindow` and its default
focus-setting calls were removed. Sampling alone cannot exclude a transient
window state or demonstrate stable memory use; the font was the system font.

Before adopting this approach for production, verify Chinese glyphs with the
production font, content bounds including labels, repeated-task memory usage,
and behavior on each supported desktop and rendering backend. If the detached pipeline
cannot meet these requirements, compare the host-view and hidden-window
alternatives described in the development plan. The long-lived single-engine
path has not met its stability target. The separately documented isolated
Windows worker uses short-lived processes and has its own acceptance evidence:
see [desktop integration](isolated-desktop-rendering.md) and the
[acceptance record](desktop-rendering-acceptance.md).
