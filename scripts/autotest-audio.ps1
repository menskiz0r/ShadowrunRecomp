<#
  autotest-audio.ps1 - run the port N times and classify the sound outcome.

  Each launch drives the game with an input script and captures the pre-DRC mixer
  stream. The run is classified by the FM peak in the last third of the stream:
  the known-good launches keep music alive there (peak > 2000), the failing ones
  fade to a few hundred.

  No button pressing: the scripted route does the navigation.
#>
param(
  [int]$Runs = 6,
  [string]$Exe = "",
  [string]$Rom = "",
  [string]$InputScript = "",
  [int]$MaxFrames = 9000,
  [int]$GoodThreshold = 2000
)
$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $PSScriptRoot
if (-not $Exe)  { $Exe = Join-Path $here 'build\ShadowrunRecomp.exe' }
if (-not $Rom)  { $Rom = Join-Path $here 'build\shadowrun.bin' }
if (-not $InputScript) { $InputScript = Join-Path $PSScriptRoot 'phase-2100.input' }
if (-not (Test-Path $Exe)) { throw "exe not found: $Exe" }
if (-not (Test-Path $Rom)) { throw "rom not found: $Rom" }

$work = Join-Path $here 'build\autotest'
New-Item -ItemType Directory -Force -Path $work | Out-Null
$results = @()
for ($i = 1; $i -le $Runs; $i++) {
  Get-ChildItem $work -Filter 'a_*' -ErrorAction SilentlyContinue | Remove-Item -Force
  $env:GENESIS_AUDIO_PREDRC = Join-Path $work 'a_'
  $err = Join-Path $work "run$i.err"
  $p = Start-Process -FilePath $Exe -ArgumentList @("`"$Rom`"", '--input-script', "`"$InputScript`"", '--max-frames', "$MaxFrames") -PassThru -RedirectStandardError $err
  if (-not $p.WaitForExit(1800000)) { try { $p.Kill() } catch {} }
  Remove-Item Env:\GENESIS_AUDIO_PREDRC -ErrorAction SilentlyContinue

  $fm = Join-Path $work 'a_.fm.s16'
  $peak = 0
  if (Test-Path $fm) {
    $bytes = [IO.File]::ReadAllBytes($fm)
    $count = [int]($bytes.Length / 2)
    $third = [int]($count * 2 / 3)
    for ($k = $third; $k -lt $count; $k++) {
      $v = [BitConverter]::ToInt16($bytes, $k*2)
      if ($v -lt 0) { $v = -$v }
      if ($v -gt $peak) { $peak = $v }
    }
  }
  $good = $peak -ge $GoodThreshold
  $results += [pscustomobject]@{ Run = $i; FmLastThird = $peak; Verdict = $(if ($good) { 'good' } else { 'BAD' }) }
  Write-Output ("  run {0}: fm_last_third={1,-6} {2}" -f $i, $peak, $(if ($good) { 'good' } else { 'BAD' }))
}
Get-ChildItem $work -Filter 'a_*' -ErrorAction SilentlyContinue | Remove-Item -Force
$goodCount = ($results | Where-Object Verdict -eq 'good').Count
Write-Output ""
Write-Output ("RESULT: {0}/{1} good, {2}/{1} bad" -f $goodCount, $Runs, ($Runs - $goodCount))
$results | Format-Table -AutoSize | Out-String | Write-Output