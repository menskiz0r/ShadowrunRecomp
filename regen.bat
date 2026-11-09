@echo off
rem Regenerate the translated C from game\game.toml. The ROM is never committed;
rem set SHADOWRUN_ROM or pass it as the first argument.
setlocal
set ROM=%~1
if "%ROM%"=="" set ROM=%SHADOWRUN_ROM%
if "%ROM%"=="" (
  echo usage: regen.bat "path\to\Shadowrun (U) [!].bin"
  exit /b 1
)
if not exist "build\GenesisRecomp_fixed.exe" (
  echo recompiler missing - run scripts\build_recompiler.ps1 first
  exit /b 1
)
"build\GenesisRecomp_fixed.exe" "%ROM%" --game game\game.toml --output-dir generated
if errorlevel 1 exit /b 1
echo.
echo regenerated generated\*.c
