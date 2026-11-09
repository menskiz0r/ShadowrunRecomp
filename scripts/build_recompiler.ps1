# build_recompiler.ps1 — build GenesisRecomp (and the patched copy) from source.
#
# The shipped release contains only the binary; the sources are in this tree, so
# code-generation fixes can be made and rebuilt.
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$gcc  = Join-Path $root "build\w64devkit\w64devkit\bin\gcc.exe"
$fw   = Join-Path $root "build\segagenesisrecomp-master"
$rc   = Join-Path $fw "recompiler"
$core = Join-Path $root "build\sub_m68k-recomp-core"
$ext  = Join-Path $fw "external\m68k-recomp-core"

# The recompiler's src/*.h forwarding stubs expect the core here.
if (-not (Test-Path (Join-Path $ext "common\m68k_decoder.h"))) {
    New-Item -ItemType Directory -Force -Path $ext | Out-Null
    foreach ($d in "common", "profiles") {
        robocopy (Join-Path $core $d) (Join-Path $ext $d) /E /NFL /NDL /NJH /NJS /NP | Out-Null
    }
}

$rsp = Join-Path $root "build\recomp.rsp"
$lines = @(
    "-O2", "-std=c11",
    "-I$($rc -replace '\\','/')/src",
    "-I$($ext -replace '\\','/')/common",
    "-I$($ext -replace '\\','/')/profiles/genesis",
    "`"$($rc -replace '\\','/')/src/main_genesis.c`"",
    "`"$($rc -replace '\\','/')/src/rom_parser.c`"",
    "`"$($rc -replace '\\','/')/src/game_config.c`"",
    "`"$($rc -replace '\\','/')/src/toml.c`"",
    "`"$($ext -replace '\\','/')/common/annotations.c`"",
    "`"$($ext -replace '\\','/')/common/m68k_decoder.c`"",
    "`"$($ext -replace '\\','/')/common/m68k_timing.c`"",
    "`"$($ext -replace '\\','/')/common/m68k_validator.c`"",
    "`"$($ext -replace '\\','/')/profiles/genesis/codegen_diag.c`"",
    "`"$($ext -replace '\\','/')/profiles/genesis/code_generator.c`"",
    "`"$($ext -replace '\\','/')/profiles/genesis/function_finder.c`"",
    "`"$($ext -replace '\\','/')/profiles/genesis/return_capture.c`"",
    "-o", "`"$($root -replace '\\','/')/build/GenesisRecomp_fixed.exe`""
)
$lines | Out-File -Encoding ascii $rsp
& $gcc "@$rsp"
if ($LASTEXITCODE -ne 0) { throw "recompiler build failed" }
Write-Host "built $root\build\GenesisRecomp_fixed.exe"

# regenerate the game with the patched recompiler
& (Join-Path $root "build\GenesisRecomp_fixed.exe") `
    (Join-Path $root "Shadowrun (U) [!].bin") `
    --game (Join-Path $root "recomp\game.toml") `
    --output-dir (Join-Path $root "recomp\generated")
