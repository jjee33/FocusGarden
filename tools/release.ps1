# Cuts a release. This is the whole manual part of shipping an update.
#
#   powershell -File tools/release.ps1 0.2.0
#   powershell -File tools/release.ps1 0.2.0 -PromoteUnreleased
#   powershell -File tools/release.ps1 0.2.0 -DryRun
#
# Bumps the version everywhere, commits, tags v<version>, and pushes. Pushing the
# tag is what starts .github/workflows/release.yml, which runs every gate, builds
# the Windows installer and the Linux AppImage, and publishes the GitHub Release
# that running copies of the app update themselves from.
#
# Nothing after `git push` is manual. See docs/RELEASE.md.

param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$Version,

    # Rename the CHANGELOG's [Unreleased] section to this version.
    [switch]$PromoteUnreleased,

    # Skip the local gates. CI runs them all anyway; this is for when the pinned
    # engine is not installed on this machine.
    [switch]$SkipGates,

    # Bump and verify, then stop and report what would have been pushed.
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$tag = "v$Version"

if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    Write-Error "Version must be MAJOR.MINOR.PATCH (got '$Version')."
}

function Invoke-Git {
    param([string[]]$Arguments, [switch]$AllowFailure)
    $output = & git -C $root @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0 -and -not $AllowFailure) {
        Write-Error "git $($Arguments -join ' ') failed:`n$output"
    }
    return $output.Trim()
}

# --- Preflight ------------------------------------------------------------
Write-Host "=== Preflight ===" -ForegroundColor Cyan

$dirty = Invoke-Git @("status", "--porcelain")
if ($dirty -ne "") {
    Write-Host $dirty
    Write-Error "Working tree is not clean. Commit or stash first — a release commit should contain nothing but the version bump."
}

$branch = Invoke-Git @("rev-parse", "--abbrev-ref", "HEAD")
Write-Host "  branch: $branch"

$existingTag = Invoke-Git @("tag", "--list", $tag)
if ($existingTag -ne "") {
    Write-Error "Tag $tag already exists. Versions are never re-tagged — publish a higher one instead (docs/UPDATES.md)."
}

Invoke-Git @("fetch", "--tags", "--quiet") | Out-Null
$remoteTag = Invoke-Git @("ls-remote", "--tags", "origin", $tag)
if ($remoteTag -ne "") {
    Write-Error "Tag $tag already exists on origin. Publish a higher version instead."
}

# --- Gates ----------------------------------------------------------------
$godot = Join-Path $root "tools\godot\Godot_v4.7.1-stable_win64_console.exe"
if ($SkipGates) {
    Write-Host "  gates skipped (-SkipGates); CI will still run them"
} elseif (-not (Test-Path $godot)) {
    Write-Host "  engine not present, skipping local gates; CI will run them"
} else {
    Write-Host ""
    Write-Host "=== Local gates ===" -ForegroundColor Cyan
    # The fast subset. The full suite, including the export, runs in CI — this is
    # here to catch the breakage that would otherwise be found after the tag
    # exists, which is the expensive moment to find it.
    $boot = & $godot --headless --path $root --quit 2>&1 | Out-String
    $bad = ($boot -split "`n") | Where-Object { $_ -match 'SCRIPT ERROR|Parse Error|ERROR|WARNING' }
    if ($bad) { $bad | Write-Host; Write-Error "Boot produced errors or warnings." }
    Write-Host "  clean boot"

    & $godot --headless --path $root --script "res://tests/cli_test_runner.gd" 2>&1 | Write-Host
    if ($LASTEXITCODE -ne 0) { Write-Error "Unit tests FAILED (exit $LASTEXITCODE)" }
}

# --- Bump -----------------------------------------------------------------
Write-Host ""
Write-Host "=== Version ===" -ForegroundColor Cyan
$setArgs = @("-File", (Join-Path $PSScriptRoot "set_version.ps1"), $Version)
if ($PromoteUnreleased) { $setArgs += "-PromoteUnreleased" }
& powershell @setArgs
if ($LASTEXITCODE -ne 0) { Write-Error "Version bump failed." }

& powershell -File (Join-Path $PSScriptRoot "verify_version.ps1") -Expected $Version
if ($LASTEXITCODE -ne 0) { Write-Error "Version verification failed." }

# --- Commit, tag, push ----------------------------------------------------
$changed = Invoke-Git @("status", "--porcelain")
if ($changed -eq "") {
    Write-Host ""
    Write-Host "Nothing to commit — the version was already $Version." -ForegroundColor Yellow
}

if ($DryRun) {
    Write-Host ""
    Write-Host "=== Dry run ===" -ForegroundColor Yellow
    Write-Host "Would commit:"
    Write-Host ($changed -replace '(?m)^', '  ')
    Write-Host "Would tag:  $tag"
    Write-Host "Would push: origin $branch and $tag"
    Write-Host ""
    Write-Host "Undo the version bump with: git checkout -- project.godot export_presets.cfg CHANGELOG.md"
    exit 0
}

Write-Host ""
Write-Host "=== Publishing ===" -ForegroundColor Cyan

if ($changed -ne "") {
    Invoke-Git @("add", "project.godot", "export_presets.cfg", "CHANGELOG.md") | Out-Null
    Invoke-Git @("commit", "-m", "Release $Version") | Out-Null
    Write-Host "  committed Release $Version"
}

Invoke-Git @("tag", "-a", $tag, "-m", "Focus Garden $Version") | Out-Null
Write-Host "  tagged $tag"

Invoke-Git @("push", "origin", $branch) | Out-Null
Invoke-Git @("push", "origin", $tag) | Out-Null
Write-Host "  pushed"

$remote = Invoke-Git @("remote", "get-url", "origin")
$slug = $remote -replace '^.*github\.com[:/]', '' -replace '\.git$', ''

Write-Host ""
Write-Host "Release $Version is building." -ForegroundColor Green
Write-Host "  https://github.com/$slug/actions"
Write-Host "  https://github.com/$slug/releases/tag/$tag"
