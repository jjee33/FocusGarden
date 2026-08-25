# Release

How Focus Garden is built, packaged and published, and what to check before
calling a release done.

Shipping is one command. Everything after it is automatic.

```bash
powershell -File tools/release.ps1 0.2.0 -PromoteUnreleased
```

That bumps the version everywhere, runs the fast gates, commits, tags `v0.2.0`,
and pushes. Pushing the tag starts `.github/workflows/release.yml`, which runs
every gate on both platforms, builds the Windows installer and the Linux
AppImage, and publishes a GitHub Release with `latest.json` attached — which is
what running copies of the app update themselves from
([UPDATES.md](UPDATES.md)).

## What ships

| Artifact | Platform | Built by |
|---|---|---|
| `FocusGarden-Setup-<version>.exe` | Windows 10+, x86-64 | Inno Setup, `tools/build_installer.ps1` |
| `FocusGarden-<version>-x86_64.AppImage` | Linux, x86-64 | `tools/build_appimage.sh` |
| `latest.json` | — | `tools/make_manifest.py` |
| `SHA256SUMS` | — | the `publish` job |

The Windows install is **per-user**, into `%LOCALAPPDATA%\Programs\Focus Garden`.
No admin prompt, which is what lets the in-app updater install silently. The
AppImage is a single file with no install step at all.

Both are one self-contained executable — `embed_pck` is on, so there is no
separate `.pck` and nothing else to ship. **Godot does not need to be installed
on the player's machine.**

`exclude_filter` in `export_presets.cfg` drops `tools/`, `tests/`, `docs/`,
`packaging/` and all Markdown. This matters beyond tidiness:
`tools/simulate_progress.gd` overwrites the player's save, and it must not be
reachable in a shipped build.

## Versions

The version lives in three places that must agree:

- `project.godot` → `config/version`
- `export_presets.cfg` → `application/file_version` and `application/product_version`
- `CHANGELOG.md` → the heading for the release

Nothing should ever set these by hand. `tools/set_version.ps1` owns all three,
`tools/verify_version.ps1` checks them, and the `verify` job fails the release
before anything is built if they disagree with the tag. A mislabelled build is
worse than a failed one, because it looks finished.

The CHANGELOG section is published verbatim as the release notes, so an empty one
fails the release too.

## Building locally

Neither of these publishes anything. Use them to test a build before tagging.

### Windows

Prerequisites, both one-time:

```bash
powershell -File tools/fetch_godot.ps1
powershell -File tools/fetch_export_templates.ps1
```

The engine is gitignored (180 MB). The templates archive is 1.2 GB and holds
every platform; the script extracts **only the Windows templates** directly from
it, because unpacking the whole thing needs about 3 GB of free space. They must
match the engine version exactly — a 4.7.0 set will not work with a 4.7.1 editor.

Inno Setup is needed for the installer:

```bash
winget install --id JRSoftware.InnoSetup --accept-source-agreements
```

Then:

```bash
powershell -File tools/build_release.ps1
powershell -File tools/build_installer.ps1
```

`build_release.ps1` regenerates content, bakes the theme, runs every gate and
exports, stopping at the first failure rather than packaging a broken build.
`build_installer.ps1` refuses to package an executable whose embedded version
does not match, so a stale export cannot be shipped under a new label.

### Linux

```bash
bash tools/fetch_godot.sh
bash tools/fetch_export_templates.sh
bash tools/build_appimage.sh
```

The scripts are invoked through `bash` rather than directly because the repo is
developed on Windows, where git does not record the executable bit.

`build_appimage.sh` downloads `appimagetool` on demand and runs it with
`--appimage-extract-and-run`, so no FUSE is required.

### The icon

`packaging/windows/app_icon.ico` and `packaging/linux/focus-garden.png` are
committed build artifacts of `assets/ui/app_icon.svg`. After editing the SVG:

```bash
tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tools/render_icons.gd
python tools/pack_ico.py
```

Godot rasterises; `pack_ico.py` assembles the `.ico` container, which Godot cannot
write. Every size is stored as an uncompressed DIB, including 256 — GDI+ throws
outright on PNG-compressed icon entries, and an installer icon is worth more as
universally readable than as 40 KB smaller.

## Where player data lives

```
Windows   %APPDATA%\Godot\app_userdata\Focus Garden\saves\
Linux     ~/.local/share/godot/app_userdata/Focus Garden/saves/
```

Saves are plain JSON, and are **not** stored next to the executable. There is no
`[UninstallDelete]` in the installer for the same reason: an update, a
reinstall, or a full uninstall never touches anyone's garden.

## Measured performance

Taken from the built executable on an RTX 5070 Ti, against an empty Godot project
as the baseline for what the engine costs before any of our code runs.

| | Focus Garden | Empty project |
|---|---|---|
| Private memory | 213 MB | 153 MB |
| CPU, window focused | 21% of one core | 5.2% |
| CPU, minimised | 5.5% of one core | — |

Getting here mattered. The first build measured **799 MB and a pinned core**, and
three things were responsible:

1. **Forward+ renderer.** The game is entirely 2D Controls and custom `_draw`
   calls — no 3D, no lights, no shadows. Forward+ allocated its clustered
   renderer buffers anyway. Switching to `gl_compatibility` cut memory by more
   than half.
2. **One draw call per triangle.** `PlantPainter` triangulated each leaf and
   issued a `draw_colored_polygon` per triangle — tens of thousands of calls a
   second. `RenderingServer.canvas_item_add_triangle_array` draws the same
   geometry in one call.
3. **Every plant animating at once.** A shelf of twelve swaying plants is both a
   §43 violation and half a core. Only the plant a screen is featuring animates
   now, and animation stops entirely when the window is not focused.

If a future change makes the app feel heavy, measure against the empty-project
baseline before optimising — otherwise engine cost gets mistaken for app cost.

## Release checklist

The gates below run automatically in CI on every push, and again in the release
workflow before anything is packaged. They are listed so they can be run by hand.

| Gate | Command | Expect |
|---|---|---|
| Version | `tools/verify_version.ps1` | consistent |
| Clean boot | `--headless --quit` | no errors, no warnings |
| Engine APIs | `--script res://tests/api_probe.gd` | 0 missing |
| Unit tests | `--script res://tests/cli_test_runner.gd` | 0 failures |
| Timer accuracy | `--script res://tools/verify_timer.gd` | PASS |
| Reliability | `--script res://tools/verify_reliability.gd` | all checks pass |
| Save persistence | `--script res://tools/verify_save_roundtrip.gd` (twice) | PASS 2 |

Then, by hand, in the built executable. CI cannot replace this part.

- [ ] First launch shows onboarding; finishing it lands on Home
- [ ] A session runs, pauses, resumes, and is recorded
- [ ] Closing mid-session and reopening offers the session back
- [ ] All nine screens navigate without error
- [ ] Resize to 1280×720 and 1920×1080: no clipped text, no overlap
- [ ] F11 toggles fullscreen and the choice survives a restart
- [ ] Audio plays and the volume sliders change it
- [ ] Reduced motion stops the plants swaying
- [ ] Export a save, reset, import it back
- [ ] Version in the navigation footer matches the tag

Installers:

- [ ] **Windows:** Setup runs with no UAC prompt; Start Menu shortcut launches it
- [ ] **Windows:** installing over an older version leaves *one* entry in Add/Remove Programs
- [ ] **Windows:** the uninstaller removes the app and leaves the saves
- [ ] **Linux:** the AppImage runs on a clean machine after `chmod +x`
- [ ] **Linux:** the icon and name appear correctly if it is integrated into a menu

Updates — see [UPDATES.md](UPDATES.md) for the full pass:

- [ ] An older build offers the new one and installs it on one click
- [ ] A corrupted checksum in the manifest refuses the install
- [ ] With no network, launch is silent and unblocked

## Known limitations to state in release notes

- **No system notifications.** Godot 4 has no cross-platform desktop notification
  API. Session completion shows an in-app message and flashes the taskbar icon.
  See ARCHITECTURE.md.
- **Unsigned executables.** Windows SmartScreen will warn on first run, for both
  the installer and the app. Signing needs a certificate; `codesign/enable` is
  wired in the preset for when there is one.
- **x86-64 only.** No ARM build on either platform.
- **No macOS build.** Nothing in the codebase is platform-specific — no native
  calls, no path assumptions beyond `user://`, no platform branches — so a macOS
  preset should mostly work. Until someone builds, signs, notarises and runs one,
  that is an expectation rather than a fact.
