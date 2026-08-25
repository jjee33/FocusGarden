#!/usr/bin/env bash
# Installs the Godot export templates needed to build the Linux release.
#
#   ./tools/fetch_export_templates.sh
#
# The published archive is 1.2 GB and holds every platform Godot supports.
# Unpacking all of it needs roughly 3 GB of free space, and this script is only
# ever asked for Linux — so it pulls the Linux entries straight out of the
# archive and never unpacks the rest. The Windows counterpart,
# tools/fetch_export_templates.ps1, does the same for its own platform, and for
# the same reason: doing it the obvious way filled the disk.
set -euo pipefail

version="4.7.1-stable"
template_dir="${HOME}/.local/share/godot/export_templates/4.7.1.stable"
url="https://github.com/godotengine/godot-builds/releases/download/${version}/Godot_v${version}_export_templates.tpz"

if [[ -f "$template_dir/linux_release.x86_64" ]]; then
    echo "Linux templates for $version are already installed."
    exit 0
fi

archive="$(mktemp -t godot-templates-XXXXXX.tpz)"
trap 'rm -f "$archive"' EXIT

echo "Downloading export templates (1.2 GB)..."
curl -fL --retry 3 -o "$archive" "$url"

echo "Extracting Linux templates..."
mkdir -p "$template_dir"
# The archive stores everything under templates/; -j drops that prefix so the
# files land directly in the version directory, which is where Godot looks.
unzip -q -o -j "$archive" 'templates/linux*' 'templates/version.txt' -d "$template_dir"

if [[ ! -f "$template_dir/linux_release.x86_64" ]]; then
    echo "error: linux_release.x86_64 is missing after extraction." >&2
    echo "The upstream archive layout may have changed." >&2
    exit 1
fi

ls -1 "$template_dir"
echo
echo "Installed to $template_dir"
