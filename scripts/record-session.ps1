<#
  record-session.ps1 - launch the game, record the session, auto-label it.

  Per session, under build\sessions\<timestamp>\:
    timeline.err   one [FBHASH] line per frame (scene timeline)
    ram\           ring of 64 KB work-RAM snapshots
    run.log        runner stderr without the per-frame hash lines
    summary.txt    labelled scenes + comparison against the good catalog

  Play normally and close the window when done. If a cutscene is skipped,
  summary.txt reports it as "SKIPPED / MISSING scenes" automatically.

  -InputScript <path> drives the session from a script instead of the keyboard;
  useful for self-tests of this workflow.
#>
param(
  [string]$Repo = 'D:\git\shrn\port\repo',
  [int]$RamEvery = 60,
  [int]$RamKeep = 300,
  [string]$Catalog = '',
  [string]$InputScript = ''
)
$ErrorActionPreference = 'Stop'
$exe = Join-Path $Repo 'build\ShadowrunRecomp.exe'
$rom = Join-Path $Repo 'build\shadowrun.bin'
if (-not $Catalog) { $Catalog = Join-Path $Repo 'build\scene-catalog.json' }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$out = Join-Path $Repo "build\sessions\$stamp"
$ram = Join-Path $out 'ram'
New-Item -ItemType Directory -Force -Path $ram | Out-Null

$timeline = Join-Path $out 'timeline.err'
$log = Join-Path $out 'run.log'
$runArgs = @("`"$rom`"",
             '--hash-frames', '1',
             '--autodump-ram-dir', "`"$ram`"",
             '--autodump-ram-every', "$RamEvery",
             '--autodump-ram-keep', "$RamKeep")
if ($InputScript) {
  $runArgs += @('--input-script', "`"$InputScript`"")
  Write-Output "  input -> $InputScript"
}
Write-Output "session: $stamp"
Write-Output "  timeline -> $timeline"
Write-Output "  ram ring -> $ram"

$env:DSH_PAD_LOG = '1'
$env:GENESIS_AUDIO_DELIVERY_DUMP = Join-Path $out 'delivery.txt'
$env:GENESIS_AUDIO_PREDRC = Join-Path $out 'audio_'
$p = Start-Process -FilePath $exe -ArgumentList $runArgs -PassThru -RedirectStandardError $timeline

# Hold the game window in the foreground for the first seconds, so the first keys
# the player presses actually reach the game (a key sent while the console has
# focus is silently lost, which drops START and leaves the game in attract mode).
$cs = @('using System;','using System.Runtime.InteropServices;','public class FocusWin {','  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);','  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);','}') -join "`n"
try { Add-Type -TypeDefinition $cs -ErrorAction Stop } catch {}
$sw = [Diagnostics.Stopwatch]::StartNew()
while ($sw.Elapsed.TotalSeconds -lt 12) {
  $null = $p.Refresh()
  if ($p.HasExited) { break }
  $h = $p.MainWindowHandle
  if ($h -ne [IntPtr]::Zero) {
    [FocusWin]::ShowWindow($h, 9) | Out-Null
    [FocusWin]::SetForegroundWindow($h) | Out-Null
  }
  Start-Sleep -Milliseconds 250
}

# The .sav sidecar is the replay's STARTUP SRAM snapshot. The game rewrites it while
# running, so it must be archived early or the replay will later fail to load with
# "invalid startup SRAM attachment". The replay itself is archived after the session.
$logDir0 = Join-Path $Repo 'build\logs'
$sw2 = [Diagnostics.Stopwatch]::StartNew()
while ($sw2.Elapsed.TotalSeconds -lt 8) {
  $sv = Join-Path $logDir0 'Shadowrun-feedback.replay.sav'
  if (Test-Path $sv) { Copy-Item $sv (Join-Path $out 'replay.sav') -Force; break }
  Start-Sleep -Milliseconds 200
}
$null = $p.WaitForExit()
Remove-Item Env:\GENESIS_AUDIO_PREDRC, Env:\DSH_PAD_LOG, Env:\GENESIS_AUDIO_DELIVERY_DUMP -ErrorAction SilentlyContinue

# Archive the input replay with the session. The runner rotates it, so a bad
# session's inputs would otherwise be lost - and they are the only way to revisit
# that exact trajectory (tools/replay_diagnostic.py --headless reproduces them).
$logDir = Join-Path $Repo 'build\logs'
$archived = 0
foreach ($suffix in @('', '.sav', '.config.ini', '.mods.txt')) {
  $src = Join-Path $logDir ('Shadowrun-feedback.replay' + $suffix)
  if (Test-Path $src) {
    Copy-Item $src (Join-Path $out ('replay' + $suffix)) -Force
    $archived++
  }
}
if ($archived) { Write-Output "  replay archived -> $out\replay" }

if (Test-Path $timeline) {
  Select-String -Path $timeline -Pattern '\[FBHASH\]' -NotMatch | ForEach-Object { $_.Line } |
    Out-File $log -Encoding utf8
}
$frames = (Select-String -Path $timeline -Pattern '\[FBHASH\]' -ErrorAction SilentlyContinue | Measure-Object).Count
Write-Output "session ended: $frames frames recorded"

$labeller = Join-Path $Repo 'tools\label_session.py'
if ((Test-Path $labeller) -and (Test-Path $Catalog)) {
  $summary = Join-Path $out 'summary.txt'
  $py = Get-Command python -ErrorAction SilentlyContinue
  if (-not $py) { $py = Get-Command py -ErrorAction SilentlyContinue }
  if ($py) {
    if ($py.Name -eq 'py.exe') {
      $txt = & $py.Source -3 $labeller $timeline --compare $Catalog 2>&1 | Out-String
    } else {
      $txt = & $py.Source $labeller $timeline --compare $Catalog 2>&1 | Out-String
    }
    [IO.File]::WriteAllText($summary, $txt)
    Write-Output "  summary -> $summary"
    Get-Content $summary | Where-Object { $_ -match 'SKIPPED|TRUNCATED|no catalog scene|INCOMPLETE|^frames=' } |
      ForEach-Object { "  $_" }
  } else {
    Write-Output "  (python not found; scene summary skipped)"
  }
} else {
  Write-Output "  (catalog or labeller missing; scene summary skipped)"
}