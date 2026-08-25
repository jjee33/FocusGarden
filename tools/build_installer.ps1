# Wraps the exported executable in the Windows installer.
#
#   powershell -File tools/build_installer.ps1
#   powershell -File tools/build_installer.ps1 -Version 0.2.0
#
# Expects tools/build_release.ps1 to have run first — this packages, it does not
# build, and it refuses to package an executable whose embedded version does not
# match the one being stamped on the installer.

param(
    # Defaults to the version in project.godot.
    [string]$Version = "",

    [string]$Iscc = ""
)

$ErrorActionPreference = "Stop"
$root = Split-Path $PSScriptRoot -Parent
$script = Join-Path $root "packaging\windows\FocusGarden.iss"
$exe = Join-Path $root "builds\windows\FocusGarden.exe"
$outputDir = Join-Path $root "builds\installer"

# --- Version --------------------------------------------------------------
if ($Version -eq "") {
    $Version = & powershell -File (Join-Path $PSScriptRoot "verify_version.ps1") -Quiet
    if ($LASTEXITCODE -ne 0) { Write-Error "Version check failed; not packaging." }
    $Version = $Version.Trim()
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') {
    Write-Error "Version must be MAJOR.MINOR.PATCH (got '$Version')."
}

# --- Inputs ---------------------------------------------------------------
if (-not (Test-Path $exe)) {
    Write-Error "No executable at $exe. Run tools/build_release.ps1 first."
}
if (-not (Test-Path (Join-Path $root "packaging\windows\app_icon.ico"))) {
    Write-Error "Missing packaging/windows/app_icon.ico. Regenerate it with tools/render_icons.gd then tools/pack_ico.py."
}

# Godot stamps the export preset's file_version onto the executable. If it does
# not agree with what we are about to label the installer, the build is stale.
$embedded = (Get-Item $exe).VersionInfo.FileVersion
if ($embedded) {
    $normalised = ($embedded -replace ',\s*', '.').Trim()
    if ($normalised -ne "$Version.0") {
        Write-Error @"
Executable version mismatch.

  builds\windows\FocusGarden.exe reports $normalised
  packaging this installer as        $Version.0

The export is from a different version. Re-run tools/build_release.ps1.
"@
    }
}

# --- Compiler -------------------------------------------------------------
if ($Iscc -eq "") {
    # Inno registers its install location, which is the only lookup that survives
    # the installer being run per-user (winget) or machine-wide (choco) — they
    # land in entirely different places.
    $registered = ""
    foreach ($hive in @("HKCU:", "HKLM:")) {
        $key = "$hive\Software\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1"
        try {
            $location = (Get-ItemProperty -Path $key -ErrorAction Stop).InstallLocation
            if ($location) { $registered = Join-Path $location "ISCC.exe"; break }
        } catch {
            # Not installed through that hive; try the next.
        }
    }

    $candidates = @(
        (Get-Command "ISCC.exe" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
        $registered,
        "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
        "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
        "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
    )
    $Iscc = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}
if (-not $Iscc) {
    Write-Error @"
Inno Setup not found.

Install it and re-run:

  winget install --id JRSoftware.InnoSetup --accept-source-agreements

Or pass the compiler explicitly with -Iscc <path to ISCC.exe>.
"@
}

# --- Build ----------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null

Write-Host "=== Building installer $Version ===" -ForegroundColor Cyan
Write-Host "  compiler: $Iscc"

& $Iscc "/DAppVersion=$Version" $script
if ($LASTEXITCODE -ne 0) { Write-Error "ISCC failed (exit $LASTEXITCODE)." }

$installer = Join-Path $outputDir "FocusGarden-Setup-$Version.exe"
if (-not (Test-Path $installer)) {
    Write-Error "ISCC reported success but $installer is missing."
}

$mb = [math]::Round((Get-Item $installer).Length / 1MB, 1)
Write-Host ""
Write-Host "Built $installer ($mb MB)" -ForegroundColor Green
