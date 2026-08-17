# Changelog

## [Unreleased] — Milestone 0: Foundation

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
