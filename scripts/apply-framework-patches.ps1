# apply-framework-patches.ps1 - apply the patches this game needs on top of the
# framework submodule. Safe to re-run.
param(
    [string]$Root = "",
    [string]$PatchTool = ""
)
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Root) { $Root = Split-Path -Parent $here }
if (-not $PatchTool) {
    foreach ($c in @("patch.exe", "patch")) {
        $p = Get-Command $c -ErrorAction SilentlyContinue
        if ($p) { $PatchTool = $p.Source; break }
    }
}
if (-not $PatchTool) {
    throw "patch.exe not found. Install Git for Windows (it ships one) or pass -PatchTool."
}

$core = Join-Path $Root "segagenesisrecomp\external\m68k-recomp-core"
if (-not (Test-Path (Join-Path $core "profiles\genesis\return_capture.c"))) {
    throw "framework submodule not found at $core - run: git submodule update --init --recursive"
}

$failed = 0
Get-ChildItem (Join-Path $Root "patches") -Filter '*.patch' | Sort-Object Name | ForEach-Object {
    $patchFile = $_.FullName
    Write-Host "== $($_.Name)"
    Push-Location $core
    & $PatchTool -p1 --dry-run --forward -i $patchFile *> $null
    $check = $LASTEXITCODE
    if ($check -ne 0) {
        Write-Host "   already applied or not applicable - skipping" -ForegroundColor Yellow
    } else {
        & $PatchTool -p1 --forward -i $patchFile | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "   FAILED to apply" -ForegroundColor Red
            $failed++
        } else {
            Write-Host "   applied" -ForegroundColor Green
        }
    }
    Pop-Location
}
if ($failed -gt 0) { exit 1 }
Write-Host "framework patches up to date"
