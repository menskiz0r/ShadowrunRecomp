<#
  record-session.ps1 - launch the game and record everything needed to compare a
  good session against a bad one.

  Per session it stores, under build\sessions\<timestamp>\:
    timeline.err   one [FBHASH] line per frame (the scene timeline)
    ram\           ring of 64 KB work-RAM snapshots
    run.log        the runner's stderr
  The runner's own input replay stays in build\logs and is rotated per session.

  Usage:  powershell -File scripts\record-session.ps1
  Play normally; close the window when done.
#>
param(
  [string]$Repo = 'D:\git\shrn\port\repo',
  [int]$RamEvery = 60,
  [int]$RamKeep = 300
)
$ErrorActionPreference = 'Stop'
$exe = Join-Path $Repo 'build\ShadowrunRecomp.exe'
$rom = Join-Path $Repo 'build\shadowrun.bin'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$out = Join-Path $Repo "build\sessions\$stamp"
$ram = Join-Path $out 'ram'
New-Item -ItemType Directory -Force -Path $ram | Out-Null

$timeline = Join-Path $out 'timeline.err'
$log = Join-Path $out 'run.log'
$args = @("`"$rom`"", '--hash-frames', '1', '--autodump-ram-dir', "`"$ram`"",
          '--autodump-ram-every', "$RamEvery", '--autodump-ram-keep', "$RamKeep")
Write-Output "session: $stamp"
Write-Output "  timeline -> $timeline"
Write-Output "  ram ring -> $ram"
$p = Start-Process -FilePath $exe -ArgumentList $args -PassThru -RedirectStandardError $timeline
# keep a copy of the runner's stderr that excludes the per-frame hash spam
$null = $p.WaitForExit()
if (Test-Path $timeline) {
  Select-String -Path $timeline -Pattern '\[FBHASH\]' -NotMatch | ForEach-Object { $_.Line } | Out-File $log -Encoding utf8
}
$frames = (Select-String -Path $timeline -Pattern '\[FBHASH\]' -ErrorAction SilentlyContinue | Measure-Object).Count
Write-Output "session ended: $frames frames recorded"