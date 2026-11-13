@echo off
rem Play Shadowrun.
rem
rem GENESIS_FORCE_INTERP=1 runs the game on the framework's interpreter instead of
rem the recompiled code. The recompiled path currently stalls after the SEGA logo
rem (see docs/VALIDATION-REPORT.md); the interpreter path plays the game, slower.
rem Remove the set line once the native path is fixed.
set GENESIS_FORCE_INTERP=1
start "" "%~dp0ShadowrunRecomp.exe" "%~dp0shadowrun.bin" %*
