# Prints the CHANGELOG section for a version, for use as GitHub release notes.
#
#   powershell -File tools/release_notes.ps1 -Version 0.2.0
#   powershell -File tools/release_notes.ps1 -Version 0.2.0 -OutFile notes.md
#
# Release notes are written once, in the CHANGELOG, and published from there.
# Retyping them into the GitHub release form is how the two end up disagreeing.

param(
    [string]$Version = "",
    [string]$OutFile = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent

if ($Version -eq "") {
    $Version = (& powershell -File (Join-Path $PSScriptRoot "verify_version.ps1") -Quiet).Trim()
    if ($LASTEXITCODE -ne 0) { Write-Error "Version check failed." }
}
$Version = $Version -replace '^v', ''

$changelog = [System.IO.File]::ReadAllText((Join-Path $root "CHANGELOG.md"))
$lines = $changelog -split "`r?`n"

$heading = '^## \[' + [regex]::Escape($Version) + '\]'
$collected = New-Object System.Collections.Generic.List[string]
$inside = $false

foreach ($line in $lines) {
    if ($line -match $heading) {
        $inside = $true
        continue
    }
    if ($inside -and $line -match '^## ') {
        break
    }
    if ($inside) {
        $collected.Add($line)
    }
}

if (-not $inside) {
    Write-Error "CHANGELOG.md has no '## [$Version]' section."
}

# Trim the blank lines that bracket a section, so the published notes do not
# start with an empty paragraph.
$notes = ($collected -join "`n").Trim()
if ($notes -eq "") {
    Write-Error "The [$Version] section in CHANGELOG.md is empty. Release notes nobody can read are worse than none."
}

if ($OutFile -ne "") {
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($OutFile, $notes + "`n", $utf8)
    Write-Host "Wrote $OutFile ($($collected.Count) lines)"
} else {
    Write-Output $notes
}
