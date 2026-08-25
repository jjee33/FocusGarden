# Arch Linux packaging

Builds and installs Focus Garden as a local Arch package (`focus-garden`).

## Prerequisites

- Arch Linux with `base-devel` (for `makepkg`)
- Godot 4.7.1 available on `PATH` as `godot4` or `godot`, with Linux/X11
  export templates installed (Editor > Manage Export Templates)

## Build

From the repo root:

```sh
./tools/build_arch_package.sh
```

This runs the unit test suite, exports the Linux binary to
`builds/linux/FocusGarden` using the `Linux/X11` preset in
`export_presets.cfg`, then builds the package with `makepkg` and copies the
result to `builds/arch/`.

## Install

```sh
sudo pacman -U builds/arch/focus-garden-*.pkg.tar.*
```

This installs the binary to `/opt/focus-garden/FocusGarden`, links
`/usr/bin/focus-garden`, and registers a desktop entry and icon. Launch with
`focus-garden` or from your application menu.

## Manual package build

If you already have a Linux export at `builds/linux/FocusGarden`, you can
build the package directly:

```sh
cp builds/linux/FocusGarden packaging/arch/FocusGarden
cp assets/ui/app_icon.svg packaging/arch/app_icon.svg
cd packaging/arch
makepkg -f
```
