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

function Invoke-Gate($name, $scriptPath) {
    Write-Host ""
    Write-Host "=== $name ===" -ForegroundColor Cyan
    & $godot --headless --path $root --script $scriptPath 2>&1 | Write-Host
    if ($LASTEXITCODE -ne 0) { Write-Error "$name FAILED (exit $LASTEXITCODE)" }
}

Write-Host "=== Regenerating content and theme ===" -ForegroundColor Cyan
& $godot --headless --path $root --import 2>&1 | Out-Null
& $godot --headless --path $root --script "res://tools/generate_content.gd" 2>&1 | Write-Host
& $godot --headless --path $root --script "res://tools/generate_audio.gd" 2>&1 | Write-Host
& $godot --headless --path $root --script "res://tools/bake_theme.gd" 2>&1 | Write-Host
& $godot --headless --path $root --import 2>&1 | Out-Null

Write-Host ""
Write-Host "=== Clean boot ===" -ForegroundColor Cyan
$boot = & $godot --headless --path $root --quit 2>&1 | Out-String
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
& $godot --headless --path $root --script "res://tools/verify_save_roundtrip.gd" 2>&1 | Out-Null
& $godot --headless --path $root --script "res://tools/verify_save_roundtrip.gd" 2>&1 | Write-Host
if ($LASTEXITCODE -ne 0) { Write-Error "Save persistence FAILED" }

Write-Host ""
Write-Host "=== Exporting ===" -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path (Split-Path $output -Parent) | Out-Null
& $godot --headless --path $root --export-release "Windows Desktop" $output 2>&1 | Out-Null
if (-not (Test-Path $output)) { Write-Error "Export produced no executable." }

$mb = [math]::Round((Get-Item $output).Length / 1MB, 1)
Write-Host ""
Write-Host "Built $output ($mb MB)" -ForegroundColor Green
Write-Host "Now run the manual checklist in docs/RELEASE.md."
