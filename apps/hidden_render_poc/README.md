# Windows hidden rendering experiment

From this directory, run `flutter build windows --release`, then execute
`build/windows/x64/runner/Release/fflow_hidden_render_poc.exe <output-directory>`.
The native runner deliberately never shows or focuses its window. It makes 100 detached
FFlow snapshot captures with Chinese labels and a graph wider than the window, then writes
`poc.png` and `result.txt` to the output directory. Every capture is decoded
and checked for its dimensions, connecting edge and distant node. A failure is written to
`error.txt` and returns a nonzero process exit code. This is a diagnostic
sample, not the production API or proof of long-running memory stability.

Run from a logged-in Windows desktop session. The original diagnostic sample
uses system fonts; the isolated worker bundles and loads Noto Sans SC. See `../../doc/hidden-rendering-poc.md` for
the remaining acceptance work and limitations.

For sampled visibility, foreground and peak working-set checks, run
`./smoke.ps1 -OutputDirectory <new-output-directory>` after the release build.
The directory must not already contain output from an earlier run.
`-Iterations` changes the task count; `-ValidateEvery` controls how often the
PNG is fully decoded and checked (the header is checked on every task).
For diagnosis, `-Mode 1` captures a plain colored widget, `-Mode 2` captures
the graph with its grid disabled, `-Mode 3` also removes node and edge text,
`-Mode 4` renders only the standard grid, `-Mode 5` renders a test grid as a
single path, `-Mode 6` reuses that path's recorded picture, and `-FrameEvery` schedules a host frame at
the selected interval. These options are experiments, not production settings.
The sample's default mode explicitly enables the grid to preserve the stress
case; the `renderFlowSnapshot` API itself defaults to no grid.

The same executable also implements the process-isolated snapshot protocol
used by `FlowIsolatedRenderService`; see `../../doc/isolated-desktop-rendering.md`.
After building, run `dart run tool/worker_smoke.dart <worker.exe> <output.png>`
to check the protocol. Add a positive third argument to run that many extra
serial tasks and print the host process's sampled working set.

To regenerate the approval-flow preview, run
`dart run tool/render_preview.dart <worker.exe> <output.png> [light|dark|print]`.
