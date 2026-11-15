<#
  record-session.ps1 - launch the game, record the session, and auto-label it.

  Per session, under build\sessions\<timestamp>\:
    timeline.err   one [FBHASH] line per frame (the scene timeline)
    ram\           ring of 64 KB work-RAM snapshots
    run.log        runner stderr without the per-frame hash lines
    summary.txt    labelled scene list + comparison against the good catalog

  Play normally; close the window when done. If a cutscene is skipped, summary.txt
  says so ("SKIPPED / MISSING scenes") without any manual analysis.
#>
param(
  [string]$Repo = 'D:\git\shrn\port\repo',
  [int]$RamEvery = 60,
  [int]$RamKeep = 300,
  [string]$Catalog = ''
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
Write-Output "session: $stamp"
Write-Output "  timeline -> $timeline"
Write-Output "  ram ring -> $ram"

$p = Start-Process -FilePath $exe -ArgumentList $runArgs -PassThru -RedirectStandardError $timeline
$null = $p.WaitForExit()

if (Test-Path $timeline) {
  Select-String -Path $timeline -Pattern '\[FBHASH\]' -NotMatch | ForEach-Object { $_.Line } |
    Out-File $log -Encoding utf8
}
$frames = (Select-String -Path $timeline -Pattern '\[FBHASH\]' -ErrorAction SilentlyContinue | Measure-Object).Count
Write-Output "session ended: $frames frames recorded"

# Label the session and compare it against the known-good scene catalog, so a
# skipped cutscene is reported automatically.
$labeller = Join-Path $Repo 'tools\label_session.py'
if ((Test-Path $labeller) -and (Test-Path $Catalog)) {
  $summary = Join-Path $out 'summary.txt'
  $py = Get-Command python -ErrorAction SilentlyContinue
  if (-not $py) { $py = Get-Command py -ErrorAction SilentlyContinue }
  if ($py) {
    if ($py.Name -eq 'py.exe') { $txt = & $py.Source -3 $labeller $timeline --compare $Catalog 2>&1 | Out-String }
    else { $txt = & $py.Source $labeller $timeline --compare $Catalog 2>&1 | Out-String }
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