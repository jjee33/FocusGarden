# Release

How to produce a Windows build of Focus Garden, and what to check before calling
one done. A build has been produced and verified with this process.

## Prerequisites

- The pinned engine at `tools/godot/Godot_v4.7.1-stable_win64_console.exe`.
  Fetch it with `tools/fetch_godot.ps1` if the folder is empty — it is gitignored
  because it is 180 MB.
- **Export templates for exactly 4.7.1-stable.** Without them the export fails
  with "No export template found". Installed to:

  ```
  %APPDATA%\Godot\export_templates\4.7.1.stable\
  ```

  ```bash
  powershell -File tools/fetch_export_templates.ps1
  ```

  The archive is 1.2 GB and contains every platform. The script extracts **only
  the Windows templates** (~600 MB) directly from it, because unpacking the whole
  thing needs about 3 GB of free space and the other platforms are not shipped.

  The templates must match the engine version exactly. A 4.7.0 set will not work
  with a 4.7.1 editor.

## Building

```bash
powershell -File tools/build_release.ps1
```

That regenerates content, bakes the theme, runs every gate, and exports — and
stops at the first failure rather than packaging a broken build.

To export alone:

```bash
tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless --path . --export-release "Windows Desktop" ../builds/windows/FocusGarden.exe
```

The output is a single self-contained `FocusGarden.exe` of about 105 MB.
`embed_pck` is on, so there is no separate `.pck` and nothing else to ship.
**Godot does not need to be installed on the player's machine.**

## What ships and what does not

`exclude_filter` in `export_presets.cfg` drops `tools/`, `tests/`, `docs/` and all
Markdown. This matters beyond tidiness: `tools/simulate_progress.gd` overwrites
the player's save, and it must not be reachable in a shipped build.

## Where player data lives

```
%APPDATA%\Godot\app_userdata\Focus Garden\saves\
```

Saves are plain JSON, and are **not** stored next to the executable. The build
can be deleted or replaced without touching anyone's garden.

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

Run every gate. All must pass.

| Gate | Command | Expect |
|---|---|---|
| Clean boot | `--headless --quit` | no errors, no warnings |
| Engine APIs | `--script res://tests/api_probe.gd` | 0 missing |
| Unit tests | `--script res://tests/cli_test_runner.gd` | 0 failures |
| Timer accuracy | `--script res://tools/verify_timer.gd` | PASS |
| Reliability | `--script res://tools/verify_reliability.gd` | all checks pass |
| Save persistence | `--script res://tools/verify_save_roundtrip.gd` (twice) | PASS 2 |

Then, by hand, in the built executable:

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

## Version numbers

Set in three places, which must agree:

- `project.godot` → `config/version`
- `export_presets.cfg` → `application/file_version` and `application/product_version`
- `CHANGELOG.md` → the heading for the release

## Known limitations to state in release notes

- **No system notifications.** Godot 4 has no cross-platform desktop notification
  API. Session completion shows an in-app message and flashes the taskbar icon.
  See ARCHITECTURE.md.
- **Unsigned executable.** Windows SmartScreen will warn on first run. Signing
  needs a certificate; `codesign/enable` is wired in the preset for when there is
  one.
- **Windows only so far.** No platform-specific code exists, so Linux and macOS
  presets should mostly be a matter of adding and testing them. Neither has been
  built, so neither is claimed.

## Other platforms

Nothing in the codebase is Windows-specific: no native calls, no path assumptions
beyond `user://`, no platform branches. Adding a Linux or macOS preset should
mostly work. Until someone builds and runs one, that is an expectation rather
than a fact, and the README says so.
