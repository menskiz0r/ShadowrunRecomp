# validate.ps1 - one-command regression for the Shadowrun recomp.
#
# Runs the scripted flow (title -> menu -> archetype -> intro -> room -> Karma ->
# check out -> walk -> save -> load), then asserts the checkpoints M8 requires:
#
#   1. exit code 0, no crash report
#   2. live-block delta = the known constant (no per-frame leak)
#   3. evidence files empty: no dispatch misses, no interior-label misses,
#      no interpreter floor fallbacks
#   4. SRAM save written with the expected checksum
#   5. final frame renders (distinct colours above a threshold)
#
# Usage:
#   pwsh -File validate.ps1                 # full run (26k frames)
#   pwsh -File validate.ps1 -Frames 8000    # quick run
param(
    [int]$Frames = 26000,
    [string]$Rom = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe  = Join-Path $root "build\shadowrun_runner.exe"
if (-not $Rom) { $Rom = Join-Path (Split-Path -Parent $root) "Shadowrun (U) [!].bin" }
if (-not (Test-Path -LiteralPath $exe)) { throw "runner missing: $exe (run build_recompiler.ps1 then build_runner.ps1)" }
if (-not (Test-Path -LiteralPath $Rom)) { throw "ROM missing: $Rom" }

$work = Join-Path $root "build\validate"
New-Item -ItemType Directory -Force -Path $work | Out-Null
Get-ChildItem $work -Filter *.toml -ErrorAction SilentlyContinue | Remove-Item -Force
Get-ChildItem $work -Filter *.srm  -ErrorAction SilentlyContinue | Remove-Item -Force
$shot = Join-Path $work "final.bmp"
$srm  = Join-Path $work "validate.srm"

# --- scripted flow ---------------------------------------------------------
$front = @('2100:S','3300:A','5000:B','7000:A','7300:A','7600:A','7900:A','8200:A',
           '8500:A','8800:A','9100:A','9400:A','9700:A',
           '12000:S','12400:DA','14600:UA','15100:A','17000:S')
$ps = $front
$f = 17600
for ($k = 0; $k -lt 7; $k++) { $ps += "${f}:R"; $f += 300 }     # status pages -> Pocket Secretary
$ps += "${f}:A"
$f = 20000
foreach ($k in 1..4) { $ps += "${f}:D"; $f += 300 }             # Save/Load Game
$ps += '21400:A'; $ps += '22000:A'; $ps += '22800:A'            # save into slot 1
$g = 24000
foreach ($m in @('R','R','D','D','L','L','U','U')) { $ps += "${g}:$m"; $g += 400 }
$env:DSH_PRESSES = $ps -join ','
$env:DSH_SRAM    = $srm
$env:DSH_LEAK    = '1'

Push-Location $work
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'   # native stderr must not abort the run
$out = & $exe $Rom $Frames $shot 2>&1 | ForEach-Object { "$_" }
$code = $LASTEXITCODE
$ErrorActionPreference = $prevEap
Pop-Location
Remove-Item Env:\DSH_PRESSES, Env:\DSH_SRAM, Env:\DSH_LEAK -ErrorAction SilentlyContinue

$results = @()
function Check($name, $ok, $detail) { $script:results += [pscustomobject]@{ Check = $name; Pass = $ok; Detail = $detail } }

# --- 1. ran clean ----------------------------------------------------------
$crashed = ($out | Select-String -Pattern 'CRASH REPORT|watchdog').Count -gt 0
Check "exit code" ($code -eq 0 -and -not $crashed) "exit=$code crash=$crashed"

# --- 2. leak ---------------------------------------------------------------
$leakLine = ($out | Select-String -Pattern 'leak: live block delta = (-?\d+)' | Select-Object -Last 1)
$delta = if ($leakLine) { [int]$leakLine.Matches[0].Groups[1].Value } else { -1 }
# 31 is the constant one-time allocation count measured at 3k/10k/30k/40k frames.
Check "no leak (delta constant)" ($delta -eq 31) "live block delta=$delta (expected 31)"

# --- 3. coverage -----------------------------------------------------------
$evidence = @('dispatch_misses.toml','interior_label_misses.toml','floor_coverage.toml','floor_unsafe.toml')
foreach ($e in $evidence) {
    $p = Join-Path $work $e
    $n = 0
    if (Test-Path $p) {
        $n = (Get-Content $p | Select-String -Pattern '^\s*0x[0-9A-Fa-f]').Count
    }
    Check "no $e entries" ($n -eq 0) "$n entr$(if ($n -eq 1) {'y'} else {'ies'})"
}

# --- 4. save ---------------------------------------------------------------
$saveLine = ($out | Select-String -Pattern 'SRAM: saved \d+ bytes \(checksum ([0-9A-F]{8})\)' | Select-Object -Last 1)
$sum = if ($saveLine) { $saveLine.Matches[0].Groups[1].Value } else { "" }
$nz = 0
if (Test-Path $srm) { $nz = ([System.IO.File]::ReadAllBytes($srm) | Where-Object { $_ -ne 0 }).Count }
Check "save written" ($sum -eq '1E50BB9A' -and $nz -gt 1000) "checksum=$sum non-zero=$nz"

# --- 5. renders ------------------------------------------------------------
$colours = 0
if (Test-Path $shot) {
    Add-Type -AssemblyName System.Drawing
    $bmp = [System.Drawing.Bitmap]::FromFile($shot)
    $set = New-Object 'System.Collections.Generic.HashSet[int]'
    for ($y = 0; $y -lt $bmp.Height; $y += 2) {
        for ($x = 0; $x -lt $bmp.Width; $x += 2) { [void]$set.Add($bmp.GetPixel($x, $y).ToArgb()) }
    }
    $colours = $set.Count
    $bmp.Dispose()
}
Check "frame renders" ($colours -ge 15) "$colours distinct colours"

# --- report ---------------------------------------------------------------
$results | Format-Table -AutoSize
$failed = ($results | Where-Object { -not $_.Pass }).Count
if ($failed -gt 0) { Write-Host "$failed check(s) FAILED" -ForegroundColor Red; exit 1 }
Write-Host "all checks passed" -ForegroundColor Green
exit 0
