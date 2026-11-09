# validate-all.ps1 - run every check in one go.
#
#   validate.ps1         8 checks: boot, leak, coverage, save, rendering
#   validate-saves.ps1  14 checks: missing/truncated/oversized/garbage/slot 2/kill
#   compare-reference    frame diff against BizHawk (skipped if it is not installed)
param(
    [string]$Rom = "",
    [switch]$SkipReference
)
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$failed = 0

function Run-Step($name, $script, $extra) {
    Write-Host ""
    Write-Host "=== $name ===" -ForegroundColor Cyan
    $args = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $script)
    if ($extra) { $args += $extra }
    & powershell @args
    if ($LASTEXITCODE -ne 0) { Write-Host "$name FAILED" -ForegroundColor Red; $script:failed++ }
}

$romArg = @()
if ($Rom) { $romArg = @("-Rom", $Rom) }

Run-Step "core validation" (Join-Path $here "validate.ps1") $romArg
Run-Step "save edge cases" (Join-Path $here "validate-saves.ps1") $romArg

$bizhawk = Join-Path (Split-Path -Parent $here) "build\bizhawk\EmuHawk.exe"
if (-not $SkipReference -and (Test-Path -LiteralPath $bizhawk)) {
    Run-Step "reference comparison" (Join-Path $here "compare-reference.ps1") $romArg
} else {
    Write-Host ""
    Write-Host "=== reference comparison: skipped (BizHawk not installed) ===" -ForegroundColor Yellow
}

Write-Host ""
if ($failed -gt 0) { Write-Host "$failed suite(s) FAILED" -ForegroundColor Red; exit 1 }
Write-Host "all suites passed" -ForegroundColor Green
exit 0
