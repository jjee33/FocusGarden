#!/usr/bin/env bash
# Downloads the pinned Godot engine for Linux into tools/godot/.
#
#   ./tools/fetch_godot.sh
#
# The Linux counterpart to tools/fetch_godot.ps1, and pinned for the same reason:
# a build that works today should still work after upstream ships 4.8, and an
# engine upgrade should be a deliberate commit that changes this line and re-runs
# the API probe.
#
# Prints the path to the binary on the last line, so callers can do:
#   GODOT_BIN="$(./tools/fetch_godot.sh | tail -1)"
set -euo pipefail

version="4.7.1-stable"
archive="Godot_v${version}_linux.x86_64.zip"
url="https://github.com/godotengine/godot-builds/releases/download/${version}/${archive}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
tools_dir="$repo_root/tools/godot"
binary="$tools_dir/Godot_v${version}_linux.x86_64"

if [[ -x "$binary" ]]; then
    echo "Godot $version is already present at $tools_dir" >&2
    echo "$binary"
    exit 0
fi

mkdir -p "$tools_dir"
echo "Downloading Godot $version ..." >&2
curl -fL --retry 3 -o "$tools_dir/godot.zip" "$url"

echo "Extracting ..." >&2
unzip -q -o "$tools_dir/godot.zip" -d "$tools_dir"
rm -f "$tools_dir/godot.zip"

if [[ ! -f "$binary" ]]; then
    echo "error: extraction finished but $binary is missing." >&2
    echo "The upstream archive layout may have changed." >&2
    exit 1
fi
chmod +x "$binary"

"$binary" --version >&2
echo "$binary"
