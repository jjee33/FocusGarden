# Changelog

## [0.1.0] — Milestone 10: Windows Release

First packaged build. `FocusGarden.exe`, 105 MB, self-contained.

### Added

- Windows export preset and a `build_release.ps1` that runs every gate before
  packaging, stopping at the first failure
- `fetch_export_templates.ps1`, which pulls only the Windows templates out of the
  1.2 GB archive rather than unpacking 3 GB of platforms that are not shipped
- Application icon in the app's own palette
- Appearance, audio and data settings: window mode, interface scale, reduced
  motion, five volume sliders, save export and import, and a two-step reset
- Seven synthesised audio cues and playback wired to game events
- First-launch onboarding: five questions, all with working defaults
- Completion particles, honouring reduced motion
- Shelf preview on Home
- Garden expansion and placement tests; plant placement invariant tests
- `verify_reliability.gd`: 26 checks against real files — truncated saves,
  orphaned temp files, garbage input, future versions, migration chains, and a
  5000-session dataset

### Fixed — performance

The first build measured **799 MB and a pinned CPU core**, which is a plain §44
failure. Three causes, all found by measuring rather than guessing:

- **Forward+ renderer** on a game that is entirely 2D Controls. Switched to
  `gl_compatibility`: 799 MB → 335 MB
- **One draw call per triangle** in the plant painter — tens of thousands per
  second. `canvas_item_add_triangle_array` draws the same geometry in one call:
  100% → 50% of a core
- **Every plant animating at once.** A shelf of twelve swaying plants is also a
  §43 violation. Only the featured plant animates, and animation stops when the
  window is not focused: 50% → 21% focused, 5.5% minimised

Final: **213 MB, 21% of one core focused, 5.5% minimised**, against an empty
Godot project baseline of 153 MB and 5.2%.

The comparison against an empty project mattered — without it, the engine's own
cost would have been mistaken for the application's.

### Verified

- 131 unit tests, 967 assertions, 0 failures
- Timer drift 0.0004s over 10 seconds; a 2-second main-thread stall counted exactly
- 26 reliability checks; 5000 sessions load in 184 ms and aggregate in 13 ms
- Save survives a real process restart
- Built executable launches, runs, and exits cleanly

## Milestone 1: Core Timer

The focus timer, end to end. A session can be configured, run, paused, finished
early, discarded, recovered after a crash, and is recorded in full.

### Added

- Focus screen with three modes: setup, running, and completion summary
- Project and duration selection, with presets plus a custom stepper; the chosen
  length becomes the persisted default
- Pause and resume, finish early (credits real focused time), and discard
  (confirmed first, credits nothing but still records the interruption)
- Pomodoro cycle with short breaks and a long break every N sessions, plus
  optional auto-start chaining with a visible countdown that any action cancels
- Focus Mode, collapsing the navigation rail so a running session has the screen
- Interrupted-session recovery: a session running when the app closed is offered
  back on next launch, capped at its intended length and flagged
- Five starter project categories seeded on first launch; create and archive
  (never hard-delete, since sessions reference the id forever)
- Working Settings screen for timer, notifications, gameplay and projects
- In-app toast notifications with a taskbar flash via
  `DisplayServer.window_request_attention()`
- `ProgressRing`, `ChoiceRow`, `ConfirmDialog`, `NewProjectDialog`, `SettingRow`,
  `ToastLayer`, `NotificationRouter` components
- `SessionCycle` and `SessionCredit` in `systems/`, plus 16 tests for them
- `tools/verify_timer.gd`: end-to-end timer verification against the real clock

### Verified

- Drift of **0.0001s over a 10 second run**
- A **2 second main-thread stall counted exactly** — the frame-starvation case
  that breaks delta-accumulating timers, and the same failure class as a
  minimized window
- **0.000s leaked** into focus time while paused
- A completed session credits exactly its intended duration, with the
  double-award guard persisted

### Changed

- Cycle and credit rules moved out of `TimerManager` into `systems/`, so they are
  testable without autoloads — the convention the rest of the codebase follows
- Session log lines format durations properly instead of rounding a 3-second
  session to "0 minutes"

## Milestone 0: Foundation

The architectural groundwork. The application runs, navigates and saves; the
gameplay systems are built and tested at the logic layer but have no UI yet.

### Added

- Godot 4.7.1 project with a pinned portable engine (`tools/fetch_godot.ps1`)
- Application shell: nine sections, persistent navigation rail, screen
  transitions that honour reduced motion
- Cozy botanical theme generated from a single design-token file, baked to a
  committed `.tres` so the editor previews real styling
- Save system: atomic writes with verify-before-swap, rotating backups,
  corruption recovery, year-sharded session history, versioned migrations, and
  refusal to overwrite a save written by a newer build
- `GameClock`: dual monotonic/wall-clock timing immune to sleep, clock changes
  and frame-rate drops
- `SessionPipeline`: the nine completion steps as an ordered, idempotent function
- One requirement engine covering thirteen condition types, shared by plant
  unlocks, achievements, expeditions and garden expansions
- XP and level curve, streak calculation, plant growth staging
- Ten narrow autoloads with documented ownership boundaries
- 100 unit tests, headless test runner, engine API probe, screenshot harness,
  and a two-pass save-persistence check
- Full documentation set under `docs/`

### Notes

- The logger autoload is named `GameLog`. Godot 4.7 has a built-in `Logger`
  class, and an autoload of that name silently resolves to the engine class.
- Credited focus time is the monotonic clock, never `min(monotonic, wall)`. The
  latter silently deletes real focus time when the system clock moves backward;
  there is a regression test for it.

### Known limitations

- No desktop notifications — Godot 4 has no cross-platform API for them
- No plant, pot or decoration artwork; navigation glyphs are placeholder emoji
- No audio clips (buses and volume control work)
- No Windows executable yet
