# build-windows.ps1 - configure and build the playable target (mirrors the naming
# other game projects use).
param(
    [string]$BuildDir = "",
    [int]$Jobs = 8,
    [string]$Generator = "MinGW Makefiles"
)
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = Split-Path -Parent $here
if (-not $BuildDir) { $BuildDir = Join-Path $repo "build" }

if (-not (Get-Command cmake -ErrorAction SilentlyContinue)) { throw "cmake not found on PATH" }
if (-not (Test-Path (Join-Path $repo "game\shadowrun.bin"))) {
    throw "put your own USA ROM at game\shadowrun.bin (CRC32 FBB92909)"
}

& cmake -S $repo -B $BuildDir -G $Generator
if ($LASTEXITCODE -ne 0) { throw "configure failed" }
& cmake --build $BuildDir -j $Jobs
if ($LASTEXITCODE -ne 0) { throw "build failed" }
Write-Host "built $BuildDir\ShadowrunRecomp.exe"
