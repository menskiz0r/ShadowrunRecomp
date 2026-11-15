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

$env:GENESIS_AUDIO_PREDRC = Join-Path $out 'audio_'
$p = Start-Process -FilePath $exe -ArgumentList $runArgs -PassThru -RedirectStandardError $timeline
$null = $p.WaitForExit()
Remove-Item Env:\GENESIS_AUDIO_PREDRC -ErrorAction SilentlyContinue

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