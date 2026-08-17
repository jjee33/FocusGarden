# Changelog

## [Unreleased] — Milestone 1: Core Timer

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
