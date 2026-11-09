# compare-reference.ps1 - diff our frames against BizHawk (the reference emulator).
#
# Captures the same frame numbers from both, then compares them structurally:
# our DAC ladder (hardware-accurate, {0,49,87,119,146,174,206,255}) differs from
# BizHawk's naive x34 expansion, so a raw pixel diff is misleading. The check
# instead builds the colour mapping ours -> reference and reports the share of
# pixels that agree after that mapping. 100% means the image is identical apart
# from the colour ladder.
#
# A boot-time offset is applied: our frame N corresponds to reference frame N+4
# (measured; see docs/MILESTONE8.md).
param(
    [int[]]$Frames = @(300, 600, 900, 1200, 1500, 1800, 2100, 2400, 3000, 3600, 4500, 6000),
    [int]$Offset = 4,
    [string]$Rom = "",
    [string]$BizHawk = ""
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe  = Join-Path $root "build\shadowrun_runner.exe"
if (-not $Rom)     { $Rom     = Join-Path (Split-Path -Parent $root) "Shadowrun (U) [!].bin" }
if (-not $BizHawk) { $BizHawk = Join-Path $root "build\bizhawk\EmuHawk.exe" }
if (-not (Test-Path -LiteralPath $exe))     { throw "runner missing: run build_runner.ps1" }
if (-not (Test-Path -LiteralPath $BizHawk)) { throw "BizHawk missing: put it at build\bizhawk (see MILESTONE8.md)" }

$work = Join-Path $root "build\refcmp"
New-Item -ItemType Directory -Force -Path $work | Out-Null
# BizHawk chokes on '[' in paths: use a plain-named copy
$romCopy = Join-Path $work "shadowrun.bin"
Copy-Item -LiteralPath $Rom -Destination $romCopy -Force

# --- reference capture (one BizHawk run for all frames) ---------------------
$targets = $Frames | ForEach-Object { $_ + $Offset } | Sort-Object -Unique
$lua = "local targets = {" + (($targets | ForEach-Object { "[" + $_ + "]=true" }) -join ",") + "}`n"
$lua += @'
local dir = [=[__DIR__]=]
local maxf = 0
for k, _ in pairs(targets) do if k > maxf then maxf = k end end
for i = 1, maxf do
    emu.frameadvance()
    if targets[i] then client.screenshot(dir .. string.format("%05d", i) .. ".png") end
end
'@
$lua = $lua.Replace("__DIR__", "$work\")
$luaPath = Join-Path $work "capture.lua"
$lua | Out-File -Encoding ascii $luaPath

# Clear BOTH naming schemes (capture writes bare NNNNN.png, the rename step
# produces ref_*.png). Leaving stale numeric files behind silently mis-attributes
# frames to earlier runs.
Get-ChildItem $work -Filter '*.png' -ErrorAction SilentlyContinue | Remove-Item -Force
# A previous EmuHawk instance keeps the ROM busy and can produce stale captures.
Get-Process EmuHawk -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500
$p = Start-Process -FilePath $BizHawk -ArgumentList "`"$romCopy`"","--lua=`"$luaPath`"" -PassThru
$last = $targets[-1]
$deadline = (Get-Date).AddMinutes(15)
while ((Get-Date) -lt $deadline) {
    if (Test-Path (Join-Path $work ("{0:D5}.png" -f $last))) { break }
    Start-Sleep -Milliseconds 700
}
try { if ($p -and -not $p.HasExited) { $p.Kill() } } catch { }
Get-ChildItem $work -Filter '*.png' | Where-Object { $_.BaseName -match '^\d{5}$' } |
    ForEach-Object { Move-Item -LiteralPath $_.FullName -Destination (Join-Path $work ("ref_" + $_.Name)) -Force }

# --- our capture -----------------------------------------------------------
foreach ($n in $Frames) {
    & $exe $Rom $n (Join-Path $work ("ours_{0:D5}.bmp" -f $n)) | Out-Null
}

# --- compare ---------------------------------------------------------------
# comparison helper lives in tests/, like the other game projects
$script = Join-Path (Split-Path -Parent $here) "tools\compare_frames.py"
$pyCmd = Get-Command python -ErrorAction SilentlyContinue
if (-not $pyCmd) { $pyCmd = Get-Command python3 -ErrorAction SilentlyContinue }
if (-not $pyCmd) { throw "python not found on PATH (needed for the frame comparison)" }
$py = $pyCmd.Source
Push-Location $work
& $py $script $work ($Frames -join ',') $Offset
$rc = $LASTEXITCODE
Pop-Location
if ($rc -ne 0) { Write-Host "reference comparison FAILED" -ForegroundColor Red; exit 1 }
Write-Host "reference comparison passed (100% structural match at offset +$Offset)" -ForegroundColor Green
exit 0
