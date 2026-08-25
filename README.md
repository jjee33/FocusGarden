# Focus Garden

A cozy desktop productivity game. Every plant you grow represents real time you
spent focusing — hundreds of hours of study or work, turned into something you
can look at.

Built with **Godot 4.7.1** and GDScript. Windows-first, fully offline, no
accounts, no ads, no monetization.

> **Status: Milestone 10 — Windows build produced and verified**, plus an
> unreleased interface refresh: dark mode, a rebuilt garden with drag-and-drop
> and rotation, staged plant maturity, and visible backups. See
> [Current state](#current-state) for the detail and
> [CHANGELOG.md](CHANGELOG.md) for what changed.

---

## Requirements

- Windows 11 (Windows 10 should work; not yet tested)
- Godot 4.7.1 — the repo expects a portable copy at `tools/godot/`

No installer, no runtime dependencies, no network access required.

## Getting the engine

The pinned engine is gitignored because of its size. Fetch it once:

```bash
pwsh -File tools/fetch_godot.ps1
```

That downloads the official Godot 4.7.1 win64 build into `tools/godot/`.

## Running

Open the project in the editor:

```bash
tools/godot/Godot_v4.7.1-stable_win64.exe --path .
```

Or run it directly without the editor:

```bash
tools/godot/Godot_v4.7.1-stable_win64.exe --path . --quit-after 100000
```

## Verifying a change

Three gates, all runnable from the command line. All three must pass before any
milestone is called done.

Boot cleanly (no errors, no missing resources):

```bash
tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless --path . --quit
```

Confirm every engine API the project uses actually exists:

```bash
tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/api_probe.gd
```

Run the unit tests (168 tests, 1084 assertions):

```bash
tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/cli_test_runner.gd
```

Verify the timer end-to-end against the real system clock (~25 seconds):

```bash
tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tools/verify_timer.gd
```

Verify a save survives a real process restart (run it twice):

```bash
tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tools/verify_save_roundtrip.gd
```

Render every screen to PNG for visual review (must NOT be headless):

```bash
tools/godot/Godot_v4.7.1-stable_win64_console.exe --path . --script res://tools/capture_screens.gd
```

After changing any design token, re-bake both themes and commit the results:

```bash
tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tools/bake_theme.gd
```

## Building a release

```bash
powershell -File tools/build_release.ps1
```

Runs every gate, then exports a self-contained `FocusGarden.exe` (~105 MB).
Needs the export templates first — see [RELEASE.md](docs/RELEASE.md).

## Current state

**Working and tested**

- **Focus timer**: project and duration selection, presets plus a custom length,
  pause/resume, finish early, discard with confirmation, and a Focus Mode that
  hides the navigation rail
- **Pomodoro cycle**: short breaks, a long break every N sessions, and optional
  auto-start chaining between them
- **Session recording**: every session written to durable history with its
  credited minutes, XP, completion state and anomaly flag
- **Interrupted sessions**: a session running when the app closed is offered back
  to you on next launch rather than silently lost or silently credited
- **Projects**: five starters seeded on first launch, plus create and archive
- **Settings**: timer lengths, cycle length, auto-start, notifications, daily
  goal and streak threshold — all persisted immediately
- Application shell with all nine sections and persistent navigation
- Cozy botanical theme in light and dark, generated from a single token file
- Save system: atomic writes, rotating backups, corruption recovery, versioned
  migrations, refusal to overwrite a save from a newer build
- **Backups**: dated snapshots of the whole save in `Documents/Focus Garden/
  Backups`, written on launch, hourly, and on close, with restore from inside the
  app
- Session timing: dual-clock elapsed measurement immune to sleep, clock changes
  and frame-rate drops. Measured drift is **0.0001s over 10 seconds**, and a
  2-second main-thread stall is counted exactly
- XP and level curve, streak calculation, plant growth staging
- One requirement engine covering all thirteen condition types

- **Plants**: 16 species with real botanical data, drawn procedurally through
  eight growth forms and seven leaf shapes. Three growth stages in equal thirds,
  and maturity scaled by rarity from three hours to ten. A plant can go on the
  shelf or into the ground from its first stage and finish growing there
- **Catalogue**: discovery silhouettes, rarity and biome filters, sort, search,
  favourites, and per-species history
- **Shelf**: timber-and-metal shelving, twelve slots, six pot designs, and a
  permanent per-plant record of the focus that grew it
- **Garden**: a plot that expands at 10/25/50/100/250/500 hours, with nine
  placeable ornaments earned along the way. Arrange it by dragging or by clicking;
  turn anything in quarter turns with `R` or a right-click
- **Progression**: XP, levels, 24 achievements with progress tracking and hidden
  entries, streaks, and a daily goal
- **Statistics**: period totals, per-project breakdown, and a yearly heatmap with
  per-day detail
- **Journal**: a dated, append-only record of everything the garden has been
  through
- **Audio**: seven synthesised cues on five independently controllable buses
- **Onboarding**: five questions on first launch, answerable in about fifteen
  seconds, every one with a working default
- 131 unit tests, an engine API probe, end-to-end timer and reliability probes

## Performance

Measured on the built executable, against an empty Godot project as the baseline
for what the engine costs before any of this project's code runs.

| | Focus Garden | Empty project |
|---|---|---|
| Private memory | 213 MB | 153 MB |
| CPU, focused | 21% of one core | 5.2% |
| CPU, minimised | 5.5% of one core | — |

The first build measured 799 MB and a pinned core. See
[RELEASE.md](docs/RELEASE.md#measured-performance) for what caused it and what
fixed it — worth reading before optimising anything here.

## Known limitations

- **No system notifications.** Godot 4 has no cross-platform desktop
  notification API. Session completion shows an in-app message and flashes the
  taskbar icon. True OS toasts would need a GDExtension.
- **All artwork is procedural.** Plants, pots, shelving, ornaments and particles
  are drawn from parameters rather than painted. Every asset is referenced
  through a resource, so a commissioned art set could replace them without
  touching gameplay code — see `docs/ASSET_PLACEHOLDERS.md`.
- **No bundled typeface.** The interface asks the OS for a modern UI face and
  falls back through a chain ending at something every system has, rather than
  shipping a licensed font.
- **Unsigned executable.** Windows SmartScreen warns on first run.
- **Windows only.** No platform-specific code exists, so Linux and macOS presets
  should mostly be a matter of adding and testing them — but neither has been
  built, so neither is claimed.
- **Expeditions are architectural only.** §32's challenge system has a data model
  and save slot but no content or UI.
- **Mystery seeds and mutations** are modelled in the data and persist correctly,
  but nothing generates them yet.

## Documentation

| Document | Contents |
|---|---|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | System ownership, layering, signal flow |
| [DATA_MODEL.md](docs/DATA_MODEL.md) | Every model, and the content/player-data split |
| [SAVE_FORMAT.md](docs/SAVE_FORMAT.md) | On-disk layout, atomic writes, migrations |
| [GAME_DESIGN.md](docs/GAME_DESIGN.md) | Core loop, progression, design rules |
| [UI_GUIDELINES.md](docs/UI_GUIDELINES.md) | Theme, components, screen quality gate |
| [TESTING.md](docs/TESTING.md) | How to run and write tests |
| [CODING_CONVENTIONS.md](docs/CODING_CONVENTIONS.md) | GDScript style and rules |
| [ASSET_PLACEHOLDERS.md](docs/ASSET_PLACEHOLDERS.md) | What art is missing |
| [RELEASE.md](docs/RELEASE.md) | Windows export process |

## Licence

Not yet chosen. All code and assets are original; no third-party game assets are
used.
