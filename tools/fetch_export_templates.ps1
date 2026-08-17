# Installs the Godot export templates needed to build FocusGarden.exe.
#
#   powershell -File tools/fetch_export_templates.ps1
#
# The published archive is 1.2 GB and holds every platform Godot supports.
# Extracting all of it needs roughly 3 GB of free space, and this project ships
# Windows only — so this pulls the Windows entries straight out of the archive
# and never unpacks the rest. That is not a micro-optimisation: doing it the
# obvious way filled the disk on the machine this was first run on.

$ErrorActionPreference = "Stop"
$version = "4.7.1-stable"
$templateDir = "$env:APPDATA\Godot\export_templates\4.7.1.stable"
$url = "https://github.com/godotengine/godot-builds/releases/download/$version/Godot_v${version}_export_templates.tpz"
$archive = Join-Path $PSScriptRoot "templates.tpz"

if (Test-Path (Join-Path $templateDir "windows_release_x86_64.exe")) {
    Write-Host "Windows templates for $version are already installed."
    exit 0
}

Write-Host "Downloading export templates (1.2 GB)..."
$ProgressPreference = 'SilentlyContinue'
Invoke-WebRequest -Uri $url -OutFile $archive -TimeoutSec 3600

Write-Host "Extracting Windows templates..."
Add-Type -AssemblyName System.IO.Compression.FileSystem
New-Item -ItemType Directory -Force -Path $templateDir | Out-Null

$zip = [System.IO.Compression.ZipFile]::OpenRead($archive)
try {
    $wanted = $zip.Entries | Where-Object { $_.Name -like "windows*" -or $_.Name -eq "version.txt" }
    foreach ($entry in $wanted) {
        $out = Join-Path $templateDir $entry.Name
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $out, $true)
        Write-Host ("  " + $entry.Name)
    }
} finally {
    $zip.Dispose()
}

Remove-Item $archive -Force
Write-Host ""
Write-Host "Installed to $templateDir"
