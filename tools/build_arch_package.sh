#!/usr/bin/env bash
# Builds the Focus Garden Linux export and packages it as an Arch Linux
# package (focus-garden). Intended to run on Arch Linux from the repo root:
#   ./tools/build_arch_package.sh
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

echo "==> Locating Godot"
GODOT_BIN=""
for candidate in godot4 godot; do
    if command -v "$candidate" >/dev/null 2>&1; then
        GODOT_BIN="$candidate"
        break
    fi
done
if [[ -z "$GODOT_BIN" ]]; then
    echo "error: no 'godot4' or 'godot' command found on PATH." >&2
    echo "Install the godot package (or an AUR variant) and try again." >&2
    exit 1
fi
echo "    using: $GODOT_BIN"

if ! command -v makepkg >/dev/null 2>&1; then
    echo "error: 'makepkg' not found. Install base-devel." >&2
    exit 1
fi

echo "==> Importing resources"
# A fresh clone has no .godot/ cache, so no global class_name is registered yet
# and every script that references one fails to parse.
"$GODOT_BIN" --headless --path . --import >/dev/null 2>&1 || true

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
    echo "Make sure the Linux export templates are installed for Godot 4.7.1" >&2
    echo "(Editor > Manage Export Templates) and that the 'Linux/X11' preset" >&2
    echo "exists in export_presets.cfg." >&2
    exit 1
fi
rm -f "$export_log"

if [[ ! -f "$build_dir/FocusGarden" ]]; then
    echo "error: export did not produce $build_dir/FocusGarden" >&2
    exit 1
fi
chmod +x "$build_dir/FocusGarden"
echo "    built: $build_dir/FocusGarden"

echo "==> Preparing package work directory"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

cp "$build_dir/FocusGarden" "$work_dir/FocusGarden"
cp "$repo_root/packaging/arch/PKGBUILD" "$work_dir/PKGBUILD"
cp "$repo_root/packaging/arch/focus-garden.desktop" "$work_dir/focus-garden.desktop"
cp "$repo_root/packaging/arch/focus-garden.install" "$work_dir/focus-garden.install"
cp "$repo_root/assets/ui/app_icon.svg" "$work_dir/app_icon.svg"

echo "==> Running makepkg"
(
    cd "$work_dir"
    makepkg -f
)

echo "==> Collecting package"
out_dir="$repo_root/builds/arch"
mkdir -p "$out_dir"
found_pkg=false
for pkg in "$work_dir"/focus-garden-*.pkg.tar.*; do
    [[ -e "$pkg" ]] || continue
    cp "$pkg" "$out_dir/"
    echo "    package: $out_dir/$(basename "$pkg")"
    found_pkg=true
done
if [[ "$found_pkg" != true ]]; then
    echo "error: makepkg did not produce a package file." >&2
    exit 1
fi

echo "==> Done"
