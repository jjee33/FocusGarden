# Downloads the pinned Godot engine into tools/godot/.
#
# The engine is gitignored (~180 MB extracted), so this script is how a fresh
# clone becomes runnable. The version is PINNED deliberately: a build that works
# today should still work after upstream ships 4.8, and an engine upgrade should
# be a deliberate commit that changes this line and re-runs the API probe.

$ErrorActionPreference = "Stop"

$Version = "4.7.1-stable"
$Archive = "Godot_v4.7.1-stable_win64.exe.zip"
$Url = "https://github.com/godotengine/godot-builds/releases/download/$Version/$Archive"

$ToolsDir = Join-Path $PSScriptRoot "godot"
$Executable = Join-Path $ToolsDir "Godot_v4.7.1-stable_win64.exe"

if (Test-Path $Executable) {
    Write-Output "Godot $Version is already present at $ToolsDir"
    exit 0
}

New-Item -ItemType Directory -Force -Path $ToolsDir | Out-Null
$ZipPath = Join-Path $ToolsDir "godot.zip"

Write-Output "Downloading Godot $Version ..."
# Progress rendering makes Invoke-WebRequest dramatically slower on large files.
$ProgressPreference = "SilentlyContinue"
Invoke-WebRequest -Uri $Url -OutFile $ZipPath -TimeoutSec 600

Write-Output "Extracting ..."
Expand-Archive -Path $ZipPath -DestinationPath $ToolsDir -Force
Remove-Item $ZipPath

if (-not (Test-Path $Executable)) {
    throw "Extraction finished but $Executable is missing. The upstream archive layout may have changed."
}

Write-Output "Godot $Version ready at $ToolsDir"
& (Join-Path $ToolsDir "Godot_v4.7.1-stable_win64_console.exe") --version
