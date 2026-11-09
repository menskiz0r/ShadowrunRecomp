@echo off
rem Build the headless runner. Needs w64devkit in build\w64devkit and the
rem framework submodule initialised.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\build_runner.ps1"
if errorlevel 1 exit /b 1
echo.
echo built build\shadowrun_runner.exe
