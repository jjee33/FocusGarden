#!/usr/bin/env bash
# Builds the Focus Garden Linux export and packages it as an AppImage.
# Run from anywhere; it works out the repo root itself:
#
#   ./tools/build_appimage.sh
#
# An AppImage is one file that runs on any distribution with no install step,
# which is what makes it the Linux counterpart to the Windows installer — and the
# only Linux format the in-app updater can replace in place.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

version="$(sed -n 's/^config\/version="\(.*\)"$/\1/p' project.godot)"
if [[ -z "$version" ]]; then
    echo "error: could not read config/version from project.godot" >&2
    exit 1
fi
echo "==> Focus Garden $version"

echo "==> Locating Godot"
GODOT_BIN="${GODOT_BIN:-}"
# The pinned copy first. A distribution's 'godot' may be any version, and the
# whole point of pinning is that the build does not change under us.
pinned="$repo_root/tools/godot/Godot_v4.7.1-stable_linux.x86_64"
if [[ -z "$GODOT_BIN" && -x "$pinned" ]]; then
    GODOT_BIN="$pinned"
fi
if [[ -z "$GODOT_BIN" ]]; then
    for candidate in godot4 godot; do
        if command -v "$candidate" >/dev/null 2>&1; then
            GODOT_BIN="$candidate"
            break
        fi
    done
fi
if [[ -z "$GODOT_BIN" ]]; then
    echo "error: no Godot found." >&2
    echo "Run ./tools/fetch_godot.sh, put 'godot4' on PATH, or set GODOT_BIN." >&2
    exit 1
fi
echo "    using: $GODOT_BIN"

echo "==> Running unit tests"
if ! "$GODOT_BIN" --headless --path . --script res://tests/cli_test_runner.gd; then
    echo "error: unit tests failed; aborting package build." >&2
    exit 1
fi

echo "==> Exporting Linux/X11 build"
build_dir="$repo_root/builds/linux"
mkdir -p "$build_dir"
export_log="$(mktemp)"
if ! "$GODOT_BIN" --headless --path . --export-release "Linux/X11" "builds/linux/FocusGarden" >"$export_log" 2>&1; then
    echo "error: export failed. Output:" >&2
    cat "$export_log" >&2
    rm -f "$export_log"
    echo >&2
    echo "Install the Linux export templates for Godot 4.7.1 (Editor > Manage" >&2
    echo "Export Templates, or unpack the .tpz into" >&2
    echo "~/.local/share/godot/export_templates/4.7.1.stable/)." >&2
    exit 1
fi
rm -f "$export_log"

if [[ ! -f "$build_dir/FocusGarden" ]]; then
    echo "error: export did not produce $build_dir/FocusGarden" >&2
    exit 1
fi
chmod +x "$build_dir/FocusGarden"
echo "    built: $build_dir/FocusGarden"

echo "==> Assembling AppDir"
appdir="$repo_root/builds/appdir"
rm -rf "$appdir"
mkdir -p "$appdir/usr/bin" "$appdir/usr/share/applications"
mkdir -p "$appdir/usr/share/icons/hicolor/256x256/apps"

install -m755 "$build_dir/FocusGarden" "$appdir/usr/bin/FocusGarden"
install -m755 "$repo_root/packaging/linux/AppRun" "$appdir/AppRun"
install -m644 "$repo_root/packaging/linux/focus-garden.desktop" \
    "$appdir/usr/share/applications/focus-garden.desktop"
install -m644 "$repo_root/packaging/linux/focus-garden.png" \
    "$appdir/usr/share/icons/hicolor/256x256/apps/focus-garden.png"

# The runtime reads these three from the AppDir root, not from usr/share.
install -m644 "$repo_root/packaging/linux/focus-garden.desktop" "$appdir/focus-garden.desktop"
install -m644 "$repo_root/packaging/linux/focus-garden.png" "$appdir/focus-garden.png"
cp "$repo_root/packaging/linux/focus-garden.png" "$appdir/.DirIcon"

echo "==> Fetching appimagetool"
tool="$repo_root/tools/appimagetool-x86_64.AppImage"
if [[ ! -x "$tool" ]]; then
    urls=(
        "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage"
        "https://github.com/AppImage/AppImageKit/releases/download/continuous/appimagetool-x86_64.AppImage"
    )
    fetched=false
    for url in "${urls[@]}"; do
        if curl -fsSL -o "$tool" "$url"; then
            fetched=true
            break
        fi
    done
    if [[ "$fetched" != true ]]; then
        echo "error: could not download appimagetool." >&2
        rm -f "$tool"
        exit 1
    fi
    chmod +x "$tool"
fi

echo "==> Packaging"
out_dir="$repo_root/builds/installer"
mkdir -p "$out_dir"
output="$out_dir/FocusGarden-$version-x86_64.AppImage"
rm -f "$output"

# --appimage-extract-and-run because CI runners have no FUSE, and requiring it
# would make the build machine-dependent for no benefit.
ARCH=x86_64 "$tool" --appimage-extract-and-run "$appdir" "$output"

if [[ ! -f "$output" ]]; then
    echo "error: appimagetool reported success but produced no file." >&2
    exit 1
fi
chmod +x "$output"

size_mb=$(( $(stat -c%s "$output") / 1048576 ))
echo "==> Done"
echo "    ${output} (${size_mb} MB)"
