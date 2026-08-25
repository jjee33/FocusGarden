# Checks that every place the version is recorded agrees, and optionally that it
# matches an expected value (a git tag, in CI).
#
#   powershell -File tools/verify_version.ps1
#   powershell -File tools/verify_version.ps1 -Expected v0.2.0
#   powershell -File tools/verify_version.ps1 -Quiet     # prints just the version
#
# Read-only. Runs before anything is built in the release workflow, because a
# mislabelled build is worse than a failed one: it looks finished.

param(
    [string]$Expected = "",
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$problems = @()

function Get-Match($path, $pattern, $label) {
    $text = [System.IO.File]::ReadAllText($path)
    $match = [regex]::Match($text, $pattern)
    if (-not $match.Success) {
        throw "Could not find $label in $path."
    }
    return $match.Groups[1].Value
}

$projectVersion = Get-Match (Join-Path $root "project.godot") `
    '(?m)^config/version="([^"]*)"$' "config/version"

$fileVersion = Get-Match (Join-Path $root "export_presets.cfg") `
    '(?m)^application/file_version="([^"]*)"$' "application/file_version"

$productVersion = Get-Match (Join-Path $root "export_presets.cfg") `
    '(?m)^application/product_version="([^"]*)"$' "application/product_version"

if ($projectVersion -notmatch '^\d+\.\d+\.\d+$') {
    $problems += "project.godot config/version is '$projectVersion', not MAJOR.MINOR.PATCH."
}

# Windows resource versions are four-part; ours is the project version plus .0.
$windowsVersion = "$projectVersion.0"
if ($fileVersion -ne $windowsVersion) {
    $problems += "export_presets.cfg file_version is '$fileVersion', expected '$windowsVersion'."
}
if ($productVersion -ne $windowsVersion) {
    $problems += "export_presets.cfg product_version is '$productVersion', expected '$windowsVersion'."
}

$changelog = [System.IO.File]::ReadAllText((Join-Path $root "CHANGELOG.md"))
$heading = "(?m)^## \[" + [regex]::Escape($projectVersion) + "\]"
if ($changelog -notmatch $heading) {
    $problems += "CHANGELOG.md has no '## [$projectVersion]' section."
}

if ($Expected -ne "") {
    $wanted = $Expected -replace '^v', ''
    if ($wanted -ne $projectVersion) {
        $problems += "Expected version '$wanted' but the project says '$projectVersion'."
    }
}

if ($problems.Count -gt 0) {
    Write-Host "Version check FAILED" -ForegroundColor Red
    foreach ($problem in $problems) { Write-Host "  - $problem" }
    Write-Host ""
    Write-Host "Fix with: powershell -File tools/set_version.ps1 <version>"
    exit 1
}

if ($Quiet) {
    Write-Output $projectVersion
} else {
    Write-Host "Version $projectVersion is consistent across project.godot, export_presets.cfg and CHANGELOG.md." -ForegroundColor Green
}
