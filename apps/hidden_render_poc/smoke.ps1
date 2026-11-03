param(
    [Parameter(Mandatory = $true)][string]$OutputDirectory,
    [int]$TimeoutSeconds = 60,
    [ValidateRange(1, 100000)][int]$Iterations = 100,
    [ValidateRange(1, 100000)][int]$ValidateEvery = 1,
    [ValidateRange(0, 100000)][int]$FrameEvery = 0,
    [ValidateRange(0, 6)][int]$Mode = 0
)
$ErrorActionPreference = 'Stop'
$executable = Join-Path $PSScriptRoot 'build/windows/x64/runner/Release/fflow_hidden_render_poc.exe'
if (-not (Test-Path -LiteralPath $executable)) { throw 'Build the Windows release first.' }
$output = [IO.Path]::GetFullPath($OutputDirectory)
New-Item -ItemType Directory -Force -Path $output | Out-Null
$resultPath = Join-Path $output 'result.txt'
$imagePath = Join-Path $output 'poc.png'
$errorPath = Join-Path $output 'error.txt'
foreach ($path in @($resultPath, $imagePath, $errorPath)) {
    if (Test-Path -LiteralPath $path) { throw "Output already exists: $path" }
}
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class FFlowPocWindows {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
}
'@
$arguments = @('"' + $output + '"', $Iterations.ToString(), $ValidateEvery.ToString())
if ($FrameEvery -gt 0) { $arguments += $FrameEvery.ToString() }
if ($Mode -gt 0) {
    if ($FrameEvery -le 0) { $arguments += '100000' }
    $arguments += $Mode.ToString()
}
$process = Start-Process -FilePath $executable -ArgumentList $arguments -WindowStyle Hidden -PassThru
$watch = [Diagnostics.Stopwatch]::StartNew()
$visible = $false
$foreground = $false
$samples = 0
$peakBytes = 0
try {
    while (-not $process.HasExited) {
        if ($watch.Elapsed.TotalSeconds -gt $TimeoutSeconds) { throw 'Hidden rendering timed out.' }
        $process.Refresh()
        if (-not $process.HasExited) { $peakBytes = [Math]::Max($peakBytes, $process.WorkingSet64) }
        $script:visibleThisSample = $false
        [FFlowPocWindows]::EnumWindows({ param($window, $unused)
            [uint32]$owner = 0
            [void][FFlowPocWindows]::GetWindowThreadProcessId($window, [ref]$owner)
            if ($owner -eq $process.Id -and [FFlowPocWindows]::IsWindowVisible($window)) {
                $script:visibleThisSample = $true
            }
            return $true
        }, [IntPtr]::Zero) | Out-Null
        $visible = $visible -or $script:visibleThisSample
        [uint32]$foregroundOwner = 0
        [void][FFlowPocWindows]::GetWindowThreadProcessId([FFlowPocWindows]::GetForegroundWindow(), [ref]$foregroundOwner)
        $foreground = $foreground -or ($foregroundOwner -eq $process.Id)
        $samples++
        Start-Sleep -Milliseconds 10
    }
    $process.Refresh()
    if ($process.ExitCode -ne 0) { throw "Render process failed with exit code $($process.ExitCode). See $errorPath." }
    if ($visible -or $foreground) { throw "A render window was visible or foreground: visible=$visible foreground=$foreground" }
    if (-not (Test-Path -LiteralPath $resultPath) -or -not (Test-Path -LiteralPath $imagePath)) { throw 'Render output is missing.' }
    "samples=$samples visible=$visible foreground=$foreground peak_working_set_bytes=$peakBytes"
    Get-Content -LiteralPath $resultPath
} finally {
    if (-not $process.HasExited) { Stop-Process -Id $process.Id -Force }
    $process.Dispose()
}
