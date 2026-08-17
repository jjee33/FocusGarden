# Focus Garden

A cozy desktop productivity game. Every plant you grow represents real time you
spent focusing — hundreds of hours of study or work, turned into something you
can look at.

Built with **Godot 4.7.1** and GDScript. Windows-first, fully offline, no
accounts, no ads, no monetization.

> **Status: Milestone 1 (core timer).** The focus timer is complete and working:
> you can pick a project, choose a length, run a session with pause and resume,
> and have it recorded. Plants, catalogue, shelf, garden, statistics and journal
> are scheduled for later milestones and are marked as such in-app. See
> [Current state](#current-state) for exactly what does and does not work today.

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

Run the unit tests (116 tests, 931 assertions as of Milestone 1):

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

After changing any design token, re-bake the theme and commit the result:

```bash
tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tools/bake_theme.gd
```

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
- Cozy botanical theme generated from a single design-token file
- Save system: atomic writes, rotating backups, corruption recovery, versioned
  migrations, refusal to overwrite a save from a newer build
- Session timing: dual-clock elapsed measurement immune to sleep, clock changes
  and frame-rate drops. Measured drift is **0.0001s over 10 seconds**, and a
  2-second main-thread stall is counted exactly
- XP and level curve, streak calculation, plant growth staging
- One requirement engine covering all thirteen condition types
- 116 unit tests, headless test runner, engine API probe, end-to-end timer check

**Not built yet** (each screen says so in the app)

| Area | Milestone |
|---|---|
| Plant selection during session setup | 2 |
| Plant species content and growth visuals | 2 |
| Catalogue | 3 |
| Shelf | 4 |
| Achievement content, unlock UI | 5 |
| Statistics, heatmap, journal | 6 |
| Garden | 7 |
| Audio content, particles, onboarding, appearance/audio/data settings | 8 |
| Windows executable | 10 |

## Known limitations

- **Desktop notifications.** Godot 4 has no cross-platform notification API. The
  planned approach is an in-app toast plus `DisplayServer.window_request_attention()`
  (a taskbar flash). True OS toasts would need a GDExtension.
- **Placeholder art.** Only the app icon exists. All plant, pot and decoration
  artwork is outstanding — see `docs/ASSET_PLACEHOLDERS.md`.
- **No audio files.** Buses and volume control work; there are no clips yet.

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
