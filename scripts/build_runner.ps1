# build_runner.ps1 - build the headless framework runner for Shadowrun.
#
# Compiles the framework's real runtime (glue, VDP, bus, machine, Z80, 68000
# interpreter, fibers) plus the generated game code and the headless adapter,
# and links shadowrun_runner.exe. No SDL, no window, no audio device.
param(
    [string]$Out = "",
    # Uninitialised-read check: build twice, once with zero and once with pattern
    # stack initialisation, then compare outputs. Empty = leave the compiler default.
    [string]$AutoInit = ""
)

$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$repo = Split-Path -Parent $here
if (-not $Out) { $Out = Join-Path $repo "build\shadowrun_runner.exe" }
$gcc  = Join-Path $root "build\w64devkit\w64devkit\bin\gcc.exe"
$gpp  = Join-Path $root "build\w64devkit\w64devkit\bin\g++.exe"
$fw   = Join-Path $root "build\segagenesisrecomp-master"
$gen  = Join-Path $root "recomp\generated"
$mk   = Join-Path $root "build\sub_m68k-recomp-core"
$zk   = Join-Path $root "build\sub_z80-recomp-core"
$ext  = Join-Path $fw "runner\external"
$obj  = Join-Path $root "build\runnerobj$AutoInit"
$gobj = Join-Path $root "build\genobj$AutoInit"
$ai = if ($AutoInit) { @("-ftrivial-auto-var-init=$AutoInit") } else { @() }

$inc = @(
    "-I$fw\runner", "-I$fw\runner\include", "-I$fw\runner\video", "-I$fw\runner\audio",
    "-I$mk\common", "-I$mk\profiles\genesis", "-I$zk\include",
    "-I$fw\recompiler", "-I$fw\recompiler\src",
    "-I$ext\clowncommon", "-I$ext\ymfm\src", "-I$ext\minicoro", "-I$ext\superzazu",
    "-I$ext\xxhash", "-I$ext\SDL2\SDL2-2.28.5\include", "-I$gen"
)
$cflags = @("-c", "-O1", "-std=c11") + $inc + $ai

New-Item -ItemType Directory -Force -Path $obj, $gobj | Out-Null
Get-ChildItem "$obj\*.o" -ErrorAction SilentlyContinue | Remove-Item -Force
Get-ChildItem "$gobj\*.o" -ErrorAction SilentlyContinue | Remove-Item -Force

$runner = Get-ChildItem "$fw\runner" -File -Filter *.c | Where-Object {
    $_.Name -notin @('main.c','cmd_server.c','local_states.c','rb_probe.c','rb_state.c',
                     'reverse_debug.c','overlay_draw.c','diagnostic_replay.c',
                     'engine_worker.c','gamepad.c','host_wait.c','persist_writer.c',
                     'rb_capture.c','replay_writer.c','cosim.c','cosim_state.c',
                     'cosim_visible.c','cosim_cycles.c')
}
foreach ($f in $runner) {
    & $gcc @cflags $f.FullName -o "$obj\$($f.BaseName).o"
    if ($LASTEXITCODE -ne 0) { throw "compile failed: $($f.Name)" }
}
# genesis_hd_gpu.c is the SDL GPU/HD renderer; the headless adapter uses the
# scanline sink and our SDL stubs do not cover the renderer API.
foreach ($f in (Get-ChildItem "$fw\runner\video" -Filter *.c | Where-Object { $_.Name -ne 'genesis_hd_gpu.c' })) {
    & $gcc @cflags $f.FullName -o "$obj\v_$($f.BaseName).o"
}
foreach ($f in @("$fw\runner\audio\event_queue.c", "$fw\runner\audio\mixer.c",
                 "$fw\runner\audio\sn76489.c", "$fw\runner\audio\observability.c",
                 "$fw\runner\audio\audio_shadow.c", "$ext\superzazu\z80.c",
                 "$mk\common\m68k_decoder.c")) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($f)
    & $gcc @cflags $f -o "$obj\$name.o"
}
# audio: the YM2612 is a C++ implementation on top of ymfm
$ymfm = Join-Path $ext "ymfm\src"
foreach ($f in @("ymfm_opn.cpp","ymfm_adpcm.cpp","ymfm_ssg.cpp")) {
    & $gpp -c -O2 -std=c++17 @inc (Join-Path $ymfm $f) -o "$obj\$([IO.Path]::GetFileNameWithoutExtension($f)).o"
    if ($LASTEXITCODE -ne 0) { throw "compile failed: $f" }
}
foreach ($f in @("ym2612_ymfm.cpp","fm_shadow.cpp")) {
    & $gpp -c -O2 -std=c++17 @inc (Join-Path $fw "runner\audio\$f") -o "$obj\$([IO.Path]::GetFileNameWithoutExtension($f)).o"
    if ($LASTEXITCODE -ne 0) { throw "compile failed: $f" }
}

foreach ($f in @("adapter.c","host_stubs.c","sdl_stubs.c","bmp.c","leak_probe.c")) {
    & $gcc @cflags (Join-Path $root "game\$f") -o "$obj\$([IO.Path]::GetFileNameWithoutExtension($f)).o"
}
foreach ($f in (Get-ChildItem $gen -Filter *.c)) {
    & $gcc @cflags $f.FullName -o "$gobj\$($f.BaseName).o"
}

$objs = (Get-ChildItem "$obj\*.o").FullName + (Get-ChildItem "$gobj\*.o").FullName
& $gpp -o $Out @objs -lws2_32 `
    '-Wl,--wrap=malloc' '-Wl,--wrap=free' '-Wl,--wrap=calloc' '-Wl,--wrap=realloc'
if ($LASTEXITCODE -ne 0) { throw "link failed" }
Write-Host "built $Out"
Write-Host "run:  $Out `"Shadowrun (U) [!].bin`" 300 frame.bmp"
