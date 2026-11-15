<#
  replay-run.ps1 - reproduce an archived session headlessly, with full capture.

  Given a replay (plus .sav/.config.ini/.mods.txt sidecars), this creates an
  isolated user directory, runs the exact input trajectory with a hidden window and
  muted audio, and captures a per-frame timeline plus a RAM ring. Playback runs at
  several hundred frames per second, so a 7000-frame session takes ~12 seconds.

  Use it to compare a known-bad session against a known-good one:
    .\replay-run.ps1 -Replay build\sessions\<bad>\replay -Tag bad
    .\replay-run.ps1 -Replay build\sessions\<good>\replay -Tag good
    python tools\compare_sessions.py build\replay-bad build\replay-good
#>
param(
  [Parameter(Mandatory=$true)][string]$Replay,
  [string]$Tag = 'run',
  [string]$Repo = 'D:\git\shrn\port\repo',
  [int]$RamEvery = 30,
  [switch]$Interp
)
$ErrorActionPreference = 'Stop'
$dir = Join-Path $Repo 'build'
$exe = Join-Path $dir 'ShadowrunRecomp.exe'
$rom = Join-Path $dir 'shadowrun.bin'
if (-not (Test-Path $Replay)) { throw "replay not found: $Replay" }

$work = Join-Path $dir ("replay-" + $Tag)
Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force -Path $work | Out-Null
$ram = Join-Path $work 'ram'
New-Item -ItemType Directory -Force -Path $ram | Out-Null

foreach ($suffix in @('', '.sav', '.config.ini', '.mods.txt')) {
  $src = $Replay + $suffix
  if (Test-Path $src) { Copy-Item $src (Join-Path $work ('capture.replay' + $suffix)) -Force }
}
Copy-Item (Join-Path $work 'capture.replay.config.ini') (Join-Path $work 'settings.ini') -Force

$env:GENESIS_USER_DIR = $work
$env:GENESIS_REPLAY_RECORD = '0'
if ($Interp) { $env:GENESIS_FORCE_INTERP = '1' }
$env:DSH_HIDDEN = '1'
$env:GENESIS_AUDIO_PREDRC = Join-Path $work 'audio_'
$env:SDL_AUDIODRIVER = 'dummy'
$env:SDL_VIDEODRIVER = 'dummy'
$env:SDL_RENDER_DRIVER = 'software'
$log = Join-Path $work 'replay.log'
$p = Start-Process -FilePath $exe -ArgumentList @("`"$rom`"", '--no-launcher', '--replay-diagnostic', "`"$(Join-Path $work 'capture.replay')`"",
      '--hash-frames', '1', '--autodump-ram-dir', "`"$ram`"", '--autodump-ram-every', "$RamEvery", '--autodump-ram-keep', '4000') `
      -PassThru -RedirectStandardOutput $log -RedirectStandardError (Join-Path $work 'replay.err') -WorkingDirectory $work
$null = $p.WaitForExit(1800000)
foreach ($k in 'GENESIS_USER_DIR','GENESIS_REPLAY_RECORD','GENESIS_FORCE_INTERP','GENESIS_AUDIO_PREDRC','DSH_HIDDEN','SDL_AUDIODRIVER','SDL_VIDEODRIVER','SDL_RENDER_DRIVER') {
  Remove-Item ("Env:" + $k) -ErrorAction SilentlyContinue
}
$matched = Select-String -Path (Join-Path $work 'replay.err') -Pattern 'executions matched' | Select-Object -First 1
Write-Output ("replay {0}: {1}" -f $Tag, $(if ($matched) { $matched.Line } else { 'NO MATCH LINE' }))
& python (Join-Path $Repo 'tools\label_session.py') (Join-Path $work 'replay.err') | Select-Object -First 3 | ForEach-Object { "  $_" }
Write-Output ("  artifacts: {0}" -f $work)