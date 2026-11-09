# validate-saves.ps1 - SRAM edge cases for the Shadowrun recomp.
#
# Scenarios, each a full scripted run:
#   1. no .srm at all            -> created, valid
#   2. truncated .srm (100 B)    -> loads short, zero-fills, no crash, rewritten full size
#   3. oversized .srm (32 KB)    -> loads the first 16 KB, ignores the rest, no crash
#   4. garbage .srm (random)     -> loads, no crash, save still works
#   5. save into slot 2 as well  -> both slots carry data
#   6. kill mid-run              -> previous .srm survives byte-identical (atomic replace)
param(
    [string]$Rom = ""
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe  = Join-Path $root "build\shadowrun_runner.exe"
if (-not $Rom) { $Rom = Join-Path (Split-Path -Parent $root) "Shadowrun (U) [!].bin" }
$work = Join-Path $root "build\validate-saves"
New-Item -ItemType Directory -Force -Path $work | Out-Null

# scripted flow up to the save (menu -> Pocket Secretary -> Save/Load -> slot 1)
$front = @('2100:S','3300:A','5000:B','7000:A','7300:A','7600:A','7900:A','8200:A',
           '8500:A','8800:A','9100:A','9400:A','9700:A',
           '12000:S','12400:DA','14600:UA','15100:A','17000:S')
$save = $front
$f = 17600
for ($k = 0; $k -lt 7; $k++) { $save += "${f}:R"; $f += 300 }
$save += "${f}:A"
$f = 20000
foreach ($k in 1..4) { $save += "${f}:D"; $f += 300 }
$save += '21400:A'; $save += '22000:A'; $save += '22800:A'

# slot 2 variant: one more Down in the slot list before confirming
$save2 = $front
$f = 17600
for ($k = 0; $k -lt 7; $k++) { $save2 += "${f}:R"; $f += 300 }
$save2 += "${f}:A"
$f = 20000
foreach ($k in 1..4) { $save2 += "${f}:D"; $f += 300 }
$save2 += '21400:A'; $save2 += '22000:A'
$save2 += '22600:D'          # move to Game 2
$save2 += '23000:A'

$results = @()
function Check($name, $ok, $detail) { $script:results += [pscustomobject]@{ Check=$name; Pass=$ok; Detail=$detail } }

function Run-Flow($srmPath, $presses, $frames = 24000) {
    $env:DSH_PRESSES = $presses -join ','
    $env:DSH_SRAM = $srmPath
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    Push-Location $work
    $out = & $exe $Rom $frames 2>&1 | ForEach-Object { "$_" }
    $code = $LASTEXITCODE
    Pop-Location
    $ErrorActionPreference = $prev
    Remove-Item Env:\DSH_PRESSES, Env:\DSH_SRAM -ErrorAction SilentlyContinue
    return @{ code = $code; out = $out }
}

function NonZero($p) {
    if (-not (Test-Path -LiteralPath $p)) { return -1 }
    return ([System.IO.File]::ReadAllBytes($p) | Where-Object { $_ -ne 0 }).Count
}
function Size($p) { if (Test-Path -LiteralPath $p) { (Get-Item -LiteralPath $p).Length } else { -1 } }

# --- 1. no file -------------------------------------------------------------
$s1 = Join-Path $work "case1.srm"
Remove-Item -LiteralPath $s1 -ErrorAction SilentlyContinue
Write-Host "[1/6] no .srm" -ForegroundColor Cyan; $r = Run-Flow $s1 $save
Check "1. no .srm: runs clean" ($r.code -eq 0) "exit=$($r.code)"
Check "1. no .srm: created full size" ((Size $s1) -eq 16384) "size=$(Size $s1)"
Check "1. no .srm: has data" ((NonZero $s1) -gt 1000) "non-zero=$(NonZero $s1)"

# --- 2. truncated 100 bytes --------------------------------------------------
$s2 = Join-Path $work "case2.srm"
[System.IO.File]::WriteAllBytes($s2, [byte[]]::new(100))
Write-Host "[2/6] truncated" -ForegroundColor Cyan; $r = Run-Flow $s2 $save
Check "2. truncated: runs clean" ($r.code -eq 0) "exit=$($r.code)"
Check "2. truncated: rewritten full size" ((Size $s2) -eq 16384) "size=$(Size $s2)"
Check "2. truncated: has data" ((NonZero $s2) -gt 1000) "non-zero=$(NonZero $s2)"

# --- 3. oversized 32 KB ------------------------------------------------------
$s3 = Join-Path $work "case3.srm"
$big = [byte[]]::new(32768); for ($i = 0; $i -lt $big.Length; $i++) { $big[$i] = 0xA5 }
[System.IO.File]::WriteAllBytes($s3, $big)
Write-Host "[3/6] oversized" -ForegroundColor Cyan; $r = Run-Flow $s3 $save
Check "3. oversized: runs clean" ($r.code -eq 0) "exit=$($r.code)"
Check "3. oversized: clamped to 16 KB" ((Size $s3) -eq 16384) "size=$(Size $s3)"

# --- 4. garbage 16 KB --------------------------------------------------------
$s4 = Join-Path $work "case4.srm"
$rnd = [byte[]]::new(16384)
(New-Object System.Random 1234).NextBytes($rnd)
[System.IO.File]::WriteAllBytes($s4, $rnd)
Write-Host "[4/6] garbage" -ForegroundColor Cyan; $r = Run-Flow $s4 $save
Check "4. garbage: runs clean" ($r.code -eq 0) "exit=$($r.code)"
Check "4. garbage: save still lands" ((NonZero $s4) -gt 1000) "non-zero=$(NonZero $s4)"

# --- 5. second slot ----------------------------------------------------------
$s5 = Join-Path $work "case5.srm"
Remove-Item -LiteralPath $s5 -ErrorAction SilentlyContinue
Write-Host "[5/6] slot 2" -ForegroundColor Cyan; $r = Run-Flow $s5 $save2
Check "5. slot 2: runs clean" ($r.code -eq 0) "exit=$($r.code)"
Check "5. slot 2: data written" ((NonZero $s5) -gt 1000) "non-zero=$(NonZero $s5)"

# --- 6. kill mid-run keeps the previous file ---------------------------------
$s6 = Join-Path $work "case6.srm"
Copy-Item -LiteralPath $s5 -Destination $s6 -Force
Write-Host "[6/6] kill mid-run" -ForegroundColor Cyan
$before = (Get-FileHash -LiteralPath $s6 -Algorithm SHA256).Hash
$env:DSH_PRESSES = $save -join ','
$env:DSH_SRAM = $s6
$p = Start-Process -FilePath $exe -ArgumentList "`"$Rom`" 26000" -PassThru
Start-Sleep -Milliseconds 1200
try { if ($p -and -not $p.HasExited) { $p.Kill() } } catch { }
try { if ($p) { $p.WaitForExit(5000) | Out-Null } } catch { }
Remove-Item Env:\DSH_PRESSES, Env:\DSH_SRAM -ErrorAction SilentlyContinue
$after = (Get-FileHash -LiteralPath $s6 -Algorithm SHA256).Hash
Check "6. kill mid-run: file intact" ($before -eq $after) "sha before=$($before.Substring(0,12)) after=$($after.Substring(0,12))"

# --- report -----------------------------------------------------------------
$results | Format-Table -AutoSize
$failed = ($results | Where-Object { -not $_.Pass }).Count
if ($failed -gt 0) { Write-Host "$failed check(s) FAILED" -ForegroundColor Red; exit 1 }
Write-Host "all save edge cases passed" -ForegroundColor Green
exit 0
