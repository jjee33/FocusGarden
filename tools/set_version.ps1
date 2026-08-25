# Sets the release version everywhere it is recorded.
#
#   powershell -File tools/set_version.ps1 0.2.0
#   powershell -File tools/set_version.ps1 0.2.0 -PromoteUnreleased
#
# The version lives in three places that must agree: project.godot, the two
# Windows fields in export_presets.cfg, and the CHANGELOG heading. Keeping them
# in sync by hand is how a build ends up labelled with the previous release, so
# this script owns all three and tools/verify_version.ps1 checks its work.

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Version,

    # Rename "## [Unreleased]" to this version rather than requiring the heading
    # to have been written by hand first.
    [switch]$PromoteUnreleased
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent

if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    Write-Error "Version must be MAJOR.MINOR.PATCH (got '$Version')."
}
$windowsVersion = "$Version.0"

# Read and write raw so line endings survive. .gitattributes pins these files to
# LF, and PowerShell's Set-Content would quietly rewrite every line.
function Read-Raw($path) {
    return [System.IO.File]::ReadAllText($path)
}
function Write-Raw($path, $text) {
    # UTF-8 without a BOM: Godot's .cfg parser and the CHANGELOG's em dashes both
    # depend on it.
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($path, $text, $utf8)
}

function Set-Field($path, $pattern, $replacement, $label) {
    $text = Read-Raw $path
    if ($text -notmatch $pattern) {
        Write-Error "Could not find $label in $path."
    }
    $updated = [regex]::Replace($text, $pattern, $replacement)
    if ($updated -ne $text) {
        Write-Raw $path $updated
        Write-Host "  $label -> $Version"
    } else {
        Write-Host "  $label already correct"
    }
}

# --- Check the CHANGELOG before writing anything -------------------------
# A missing release section is the likely failure, and discovering it after two
# of the three files have been rewritten leaves the tree half-bumped.
$changelogPath = Join-Path $root "CHANGELOG.md"
$changelog = Read-Raw $changelogPath
$heading = "(?m)^## \[" + [regex]::Escape($Version) + "\]"
$hasSection = $changelog -match $heading
$hasUnreleased = $changelog -match '(?m)^## \[Unreleased\]'

if (-not $hasSection -and -not ($PromoteUnreleased -and $hasUnreleased)) {
    $hint = if ($PromoteUnreleased) {
        "There is no [Unreleased] section to promote either."
    } else {
        "Re-run with -PromoteUnreleased to rename the [Unreleased] section."
    }
    Write-Error @"
CHANGELOG.md has no '## [$Version]' section.

$hint

Release notes are published verbatim to GitHub, so an empty section is a release
nobody can read. Nothing has been changed.
"@
}

Write-Host "Setting version to $Version" -ForegroundColor Cyan

Set-Field (Join-Path $root "project.godot") `
    '(?m)^config/version=".*"$' "config/version=`"$Version`"" `
    "project.godot config/version"

Set-Field (Join-Path $root "export_presets.cfg") `
    '(?m)^application/file_version=".*"$' "application/file_version=`"$windowsVersion`"" `
    "export_presets.cfg file_version"

Set-Field (Join-Path $root "export_presets.cfg") `
    '(?m)^application/product_version=".*"$' "application/product_version=`"$windowsVersion`"" `
    "export_presets.cfg product_version"

# --- CHANGELOG ------------------------------------------------------------
if ($hasSection) {
    Write-Host "  CHANGELOG.md already has a [$Version] section"
} else {
    $today = (Get-Date).ToString("yyyy-MM-dd")
    $changelog = [regex]::Replace(
        $changelog, '(?m)^## \[Unreleased\].*$', "## [$Version] - $today", 1)
    Write-Raw $changelogPath $changelog
    Write-Host "  CHANGELOG.md [Unreleased] -> [$Version] - $today"
}

Write-Host "Done." -ForegroundColor Green
