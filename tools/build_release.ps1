# Builds a release of Focus Garden, running every gate first.
#
#   powershell -File tools/build_release.ps1
#
# Stops at the first failure. A build that skipped a gate is worse than no build,
# because it looks finished.

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$godot = Join-Path $root "tools\godot\Godot_v4.7.1-stable_win64_console.exe"
$output = Join-Path $root "builds\windows\FocusGarden.exe"

if (-not (Test-Path $godot)) {
    Write-Error "Engine not found. Run tools/fetch_godot.ps1 first."
}
if (-not (Test-Path "$env:APPDATA\Godot\export_templates\4.7.1.stable\windows_release_x86_64.exe")) {
    Write-Error "Export templates not installed. Run tools/fetch_export_templates.ps1 first."
}

# Windows PowerShell 5.1 turns native stderr into an ErrorRecord when 2>&1 is
# used. With ErrorActionPreference=Stop, even an expected Godot test warning
# aborts the release before its exit code can be checked. Capture both streams
# as text, then restore strict error handling before inspecting the exit code.
function Invoke-Godot {
    param([string[]]$Arguments, [switch]$Quiet)
    $preference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "Continue"
        $lines = & $godot @Arguments 2>&1 | ForEach-Object { $_.ToString() }
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $preference
    }
    if (-not $Quiet) { $lines | ForEach-Object { Write-Host $_ } }
    return @{ Code = $code; Output = ($lines -join "`n") }
}

function Invoke-Gate($name, $scriptPath) {
    Write-Host ""
    Write-Host "=== $name ===" -ForegroundColor Cyan
    $result = Invoke-Godot -Arguments @("--headless", "--path", $root, "--script", $scriptPath)
    if ($result.Code -ne 0) { Write-Error "$name FAILED (exit $($result.Code))" }
}

Write-Host "=== Regenerating content and theme ===" -ForegroundColor Cyan
foreach ($argsForRun in @(
    @("--headless", "--path", $root, "--import"),
    @("--headless", "--path", $root, "--script", "res://tools/generate_content.gd"),
    @("--headless", "--path", $root, "--script", "res://tools/generate_audio.gd"),
    @("--headless", "--path", $root, "--script", "res://tools/bake_theme.gd"),
    @("--headless", "--path", $root, "--import")
)) {
    $result = Invoke-Godot -Arguments $argsForRun -Quiet
    if ($result.Code -ne 0) { Write-Host $result.Output; Write-Error "Content generation FAILED (exit $($result.Code))" }
}

Write-Host ""
Write-Host "=== Clean boot ===" -ForegroundColor Cyan
$bootResult = Invoke-Godot -Arguments @("--headless", "--path", $root, "--quit") -Quiet
if ($bootResult.Code -ne 0) { Write-Host $bootResult.Output; Write-Error "Boot FAILED (exit $($bootResult.Code))" }
$boot = $bootResult.Output
$bad = ($boot -split "`n") | Where-Object { $_ -match 'SCRIPT ERROR|Parse Error|ERROR|WARNING' }
if ($bad) { $bad | Write-Host; Write-Error "Boot produced errors or warnings." }
Write-Host "clean"

Invoke-Gate "Engine API probe" "res://tests/api_probe.gd"
Invoke-Gate "Unit tests"       "res://tests/cli_test_runner.gd"
Invoke-Gate "Timer accuracy"   "res://tools/verify_timer.gd"
Invoke-Gate "Reliability"      "res://tools/verify_reliability.gd"

# The save probe is inherently two runs: one writes, the next verifies it
# survived a real process restart.
Write-Host ""
Write-Host "=== Save persistence ===" -ForegroundColor Cyan
$saveArgs = @("--headless", "--path", $root, "--script", "res://tools/verify_save_roundtrip.gd")
$firstSave = Invoke-Godot -Arguments $saveArgs -Quiet
if ($firstSave.Code -ne 0) { Write-Host $firstSave.Output; Write-Error "Save persistence first run FAILED" }
$secondSave = Invoke-Godot -Arguments $saveArgs
if ($secondSave.Code -ne 0) { Write-Error "Save persistence second run FAILED" }

Invoke-Gate "Save transfer" "res://tools/verify_save_transfer.gd"

Write-Host ""
Write-Host "=== Exporting ===" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path (Split-Path $output -Parent) | Out-Null
$exportResult = Invoke-Godot -Arguments @("--headless", "--path", $root, "--export-release", "Windows Desktop", $output) -Quiet
if ($exportResult.Code -ne 0) { Write-Host $exportResult.Output; Write-Error "Export FAILED (exit $($exportResult.Code))" }
if (-not (Test-Path $output)) { Write-Error "Export produced no executable." }

$mb = [math]::Round((Get-Item $output).Length / 1MB, 1)
Write-Host ""
Write-Host "Built $output ($mb MB)" -ForegroundColor Green
Write-Host "Now run the manual checklist in docs/RELEASE.md."
