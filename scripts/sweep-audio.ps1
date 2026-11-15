param([string]$Repo = 'D:\git\shrn\port\repo')
$ErrorActionPreference = 'Stop'
$exe = Join-Path $Repo 'build\ShadowrunRecomp.exe'
$rom = Join-Path $Repo 'build\shadowrun.bin'
$script = Join-Path $Repo 'scripts\phase-2100.input'
$work = Join-Path $Repo 'build\sweep'; New-Item -ItemType Directory -Force -Path $work | Out-Null
$log = Join-Path $Repo 'build\sweep-results.txt'
"theory sweep $(Get-Date -Format o)" | Out-File $log -Encoding utf8

function RunCfg([string]$name, [hashtable]$envs, [string[]]$extraArgs) {
  $good = 0; $bad = 0; $peaks = @()
  for ($i = 1; $i -le 3; $i++) {
    Get-ChildItem $work -Filter 'a_*' -ErrorAction SilentlyContinue | Remove-Item -Force
    $env:GENESIS_AUDIO_PREDRC = Join-Path $work 'a_'
    foreach ($k in $envs.Keys) { Set-Item -Path "Env:$k" -Value $envs[$k] }
    $p = Start-Process -FilePath $exe -ArgumentList (@("`"$rom`"", '--input-script', "`"$script`"", '--max-frames', '9000') + $extraArgs) -PassThru -RedirectStandardError (Join-Path $work "r$i.err")
    if (-not $p.WaitForExit(1500000)) { try { $p.Kill() } catch {} }
    foreach ($k in $envs.Keys) { Remove-Item "Env:$k" -ErrorAction SilentlyContinue }
    Remove-Item Env:\GENESIS_AUDIO_PREDRC -ErrorAction SilentlyContinue
    $fm = Join-Path $work 'a_.fm.s16'; $peak = 0
    if (Test-Path $fm) {
      $b = [IO.File]::ReadAllBytes($fm); $c = [int]($b.Length/2); $t = [int]($c*2/3)
      for ($k2 = $t; $k2 -lt $c; $k2++) { $v = [BitConverter]::ToInt16($b,$k2*2); if ($v -lt 0) { $v = -$v }; if ($v -gt $peak) { $peak = $v } }
    }
    $peaks += $peak
    if ($peak -ge 2000) { $good++ } else { $bad++ }
    "$name run $i peak=$peak $($(if ($peak -ge 2000) {'good'} else {'BAD'}))" | Out-File $log -Append -Encoding utf8
  }
  $line = "RESULT $name : good=$good bad=$bad peaks=$($peaks -join ',')"
  $line | Out-File $log -Append -Encoding utf8
  Write-Output $line
}
RunCfg 'baseline'        @{}                                    @()
RunCfg 'device-dummy'    @{ SDL_AUDIODRIVER='dummy' }          @()
RunCfg 'buffer-8192'     @{ GENESIS_AUDIO_SAMPLES='8192' }     @()
RunCfg 'driver-winmm'    @{ SDL_AUDIODRIVER='winmm' }          @()
RunCfg 'audio-shadow'    @{ GENESIS_AUDIO_SHADOW='1' }         @()
RunCfg 'interpreter'     @{ GENESIS_FORCE_INTERP='1' }         @()
Get-ChildItem $work -Filter 'a_*' -ErrorAction SilentlyContinue | Remove-Item -Force
Write-Output "SWEEP DONE"