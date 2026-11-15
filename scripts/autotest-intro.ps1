<#
  autotest-intro.ps1 - randomised-timing intro autotest.

  Every launch randomises the frame on which START/A are pressed (human-like
  timing), records a framebuffer hash per frame, and reports the "scene
  timeline": consecutive runs of an identical frame hash, which is how a static
  cutscene scene appears. A skipped scene is a short run where a good launch has
  a long one.

  -Analyze <err file> re-parses an existing run without launching the game.
#>
param(
  [int]$Runs = 8,
  [string]$Repo = 'D:\git\shrn\port\repo',
  [int]$MaxFrames = 9000,
  [int]$Seed = 1,
  [string]$Analyze = ''
)

function Get-Scenes([string]$errPath) {
  $hits = Select-String -Path $errPath -Pattern '\[FBHASH\] frame=(\d+) w=\d+ h=\d+ hash=(0x[0-9A-Fa-f]+)' -AllMatches
  $list = @()
  foreach ($m in $hits) { foreach ($x in $m.Matches) { $list += [pscustomobject]@{ F = [int]$x.Groups[1].Value; H = $x.Groups[2].Value } } }
  $segs = @()
  if ($list.Count -gt 1) {
    $start = 0
    for ($k = 1; $k -lt $list.Count; $k++) {
      if ($list[$k].H -ne $list[$k-1].H) {
        $len = $list[$k].F - $list[$start].F
        if ($len -ge 8) { $segs += [pscustomobject]@{ Start = $list[$start].F; Len = $len; Hash = $list[$start].H } }
        $start = $k
      }
    }
    $len = $list[$list.Count-1].F - $list[$start].F
    if ($len -ge 8) { $segs += [pscustomobject]@{ Start = $list[$start].F; Len = $len; Hash = $list[$start].H } }
  }
  return $segs
}

if ($Analyze) {
  $segs = Get-Scenes $Analyze
  Write-Output ("scenes={0}" -f $segs.Count)
  $segs | ForEach-Object { "  start={0,5} len={1,5} hash={2}" -f $_.Start, $_.Len, $_.Hash }
  return
}

$ErrorActionPreference = 'Stop'
$exe = Join-Path $Repo 'build\ShadowrunRecomp.exe'
$rom = Join-Path $Repo 'build\shadowrun.bin'
$work = Join-Path $Repo 'build\introtest'
New-Item -ItemType Directory -Force -Path $work | Out-Null
$log = Join-Path $work 'results.txt'
"intro autotest $(Get-Date -Format o) launches=$Runs seed=$Seed" | Out-File $log -Encoding utf8

$rand = [Random]::new($Seed)
for ($i = 1; $i -le $Runs; $i++) {
  $w1 = 2100 + $rand.Next(0, 41)
  $w2 = 1400 + $rand.Next(0, 41)
  $w3 = 1600 + $rand.Next(0, 41)
  $inp = Join-Path $work "in$i.input"
  @("WAIT $w1", "PRESS START 6", "WAIT $w2", "PRESS A 6", "WAIT $w3", "PRESS A 6", "WAIT 6000", "EXIT 0") |
    Out-File -Encoding ascii $inp
  $err = Join-Path $work "run$i.err"
  $p = Start-Process -FilePath $exe -ArgumentList @("`"$rom`"", '--input-script', "`"$inp`"", '--max-frames', "$MaxFrames", '--hash-frames', '1') -PassThru -RedirectStandardError $err
  if (-not $p.WaitForExit(1800000)) { try { $p.Kill() } catch {} }
  $segs = Get-Scenes $err
  $timeline = ($segs | ForEach-Object { "$($_.Start)+$($_.Len)" }) -join ' '
  $longest = 0
  if ($segs.Count -gt 0) { $longest = ($segs | Measure-Object Len -Maximum).Maximum }
  "launch $i w=$w1/$w2/$w3 scenes=$($segs.Count) longest=$longest timeline=$timeline" | Out-File $log -Append -Encoding utf8
  Write-Output ("launch {0}: scenes={1} longest={2} w={3}/{4}/{5}" -f $i, $segs.Count, $longest, $w1, $w2, $w3)
}
Write-Output "INTROTEST DONE"