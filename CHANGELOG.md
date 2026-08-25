# Changelog

## [Unreleased]

Installers for Windows and Linux, a release pipeline that runs on a pushed tag,
and updates the app can install itself. Plus an interface refresh, a rebuilt
garden, staged plant maturity, and backups a player can find.

### Added — installers

- **Windows installer.** `FocusGarden-Setup-<version>.exe`, built with Inno
  Setup. Installs per-user into `%LOCALAPPDATA%\Programs`, so there is no admin
  prompt, and adds a Start Menu shortcut, an optional desktop icon, and a real
  uninstaller. Installing over an older version upgrades it rather than leaving
  two entries in Add/Remove Programs. Saves live outside the install directory
  and are never touched by an install, an update or an uninstall.
- **Linux AppImage.** `FocusGarden-<version>-x86_64.AppImage` — one file, no
  install step, any distribution. The `Linux/X11` export preset had existed
  since Milestone 10 but had never been built or run; it has now been both.
- The app icon is rendered from `assets/ui/app_icon.svg` into the `.ico` and
  `.png` the two packagers need, by `tools/render_icons.gd` and
  `tools/pack_ico.py`, rather than kept as hand-exported files that drift.

### Added — updates

- Focus Garden now notices when a newer version exists, downloads it, verifies
  its SHA-256 against a signed-over-TLS manifest, and installs it on one click.
  On Windows it runs the new installer silently and reopens itself; on Linux it
  replaces the running AppImage in place. See `docs/UPDATES.md`.
- **It never interrupts a focus session.** A check that finds something during a
  session holds the notice until the session ends (§3).
- **One toggle turns it off completely** — Settings → Updates. Off means no
  request is ever made. This is the first and only network call in the codebase:
  one HTTPS GET to GitHub, sending nothing about the player.
- Nothing runs from the editor. Development runs and every headless gate stay
  offline, so the test suite has no dependency on GitHub being up.
- `VersionUtil` compares versions numerically rather than as strings, so 0.10.0
  is correctly newer than 0.9.0, and treats anything unparseable as 0.0.0 so a
  malformed manifest can never trigger a download.

### Added — releasing

- `tools/release.ps1 <version>` is now the whole of shipping: it bumps the
  version everywhere it is recorded, runs the fast gates, commits, tags and
  pushes. `.github/workflows/release.yml` does the rest — every gate on both
  platforms, both packages, checksums, and a GitHub Release.
- `.github/workflows/ci.yml` runs the full gate suite on every push.
- The version had lived in three places that "must agree" with nothing enforcing
  it. `tools/set_version.ps1` now owns all three and `tools/verify_version.ps1`
  checks them; the release fails before anything is built if they disagree with
  the tag.
- Release notes are published from the CHANGELOG rather than retyped into the
  GitHub form, which is how the two used to end up disagreeing.

### Changed — build layout

- Exports write to `builds/` inside the repo rather than `../builds/` beside it.
  The old path put build output in a sibling directory that no `.gitignore`
  covered and that CI had no reason to expect.

### Added — appearance

- **Dark mode**, with a light/dark toggle in Settings. Colour tokens moved out of
  `DesignTokens` into a new `Palette` with a getter per token, so both modes are
  the same structure with a different palette bound and a variation cannot exist
  in one and not the other. `tools/bake_theme.gd` now writes both themes.
- Real typography. The interface resolves a system UI face through a fallback
  chain instead of using Godot's default, headings carry a semibold weight, and
  the countdown and stat figures use tabular digits so a running timer stops
  jittering as it counts.
- A two-layer elevation scale, hairline card borders, a tonal `SecondaryButton`
  between the filled primary and the ghost, `Eyebrow` and `Badge` text roles, and
  themed separators.
- Navigation rail: the selected section is a filled pill with an accent bar down
  its leading edge, the brand block is aligned to the same optical edge as the
  entries, and dividers separate it from the list and the version footer.

### Added — garden

- **Drag and drop.** Pick a plant or an ornament up and put it down; drop onto an
  occupied square to swap; drag off the plot to lift something out, and a plant
  goes back to the collection with everything it has grown intact.
- **Rotation.** Ornaments turn in quarter turns; plants take one of four facings,
  which mirror and lean them rather than tipping them over, so a row of one
  species stops looking like the same plant stamped four times. `R` while
  hovering, or right-click.
- Redrawn ground, beds and all eight ornament shapes: mown bands rather than a
  chequerboard, a stone lip around the plot, dug beds with contact shadows, and
  ornaments built in a unit-square space so a rotation is one transform rather
  than eight special cases.

### Added — backups

- Dated, self-contained snapshots in `Documents/Focus Garden/Backups`, written on
  launch, hourly during play, and on close, keeping the newest 20. Files are
  copied rather than re-serialised, so a snapshot preserves what was on disk.
- Settings → Your data gains **Back up now**, **Open folder** and **Restore a
  backup**. Restoring snapshots the current save first, so picking the wrong date
  is not how someone loses a garden.

### Changed — growth

- **Three growth stages, in equal thirds**, and maturity is now purely
  time-based, scaled by rarity: 3h common, 4h30 uncommon, 6h rare, 8h epic, 10h
  legendary. The per-species figures had drifted into eleven arbitrary numbers
  between 100 and 420 minutes that no player could predict from a plant's badge.
  Five species lose their "8 morning sessions" and "focus on 5 separate days"
  growth rules; those requirement types remain in use by achievements, expansions
  and unlocks.
- **A plant can go on the shelf or into the garden from its first stage** — about
  a third of the way — and finishes growing where it can be seen. It stays
  selectable as the growth target, and the shelf and the plot repaint as it
  advances rather than only when it finishes.
- Flowers are now the reward for finishing rather than for getting close, so the
  final third of a plant's life has something to look forward to.
- Save format **2**: ornaments and planted specimens gained a facing, and the
  appearance mode became a setting.

### Added — reach and clarity

- **A keyboard cursor on the shelf and the garden.** Tab reaches either one, the
  arrow keys walk it square by square, Enter acts exactly as a click would, and R
  turns whatever is under it. Everything a drag can do is now reachable without a
  pointer: placing goes through the side panel, and returning a plant to the
  collection is a button in the story dialog. A focus ring shows which of the two
  the arrow keys currently belong to.
- **A Turn action in the plant story dialog**, so a facing can be changed by
  plain clicking rather than only by right-click or R over the right square.
- **Catalogue cards state what a species costs** — "3h to grow", "10h to grow".
  Maturity is derived from rarity now, so the figure is predictable and worth
  showing before you commit three hours to it rather than after.
- Reset and import both write a dated backup before replacing anything, and say
  so. Reset's copy no longer claims there is no undo, because there now is one.
- Focus Mode is a chip rather than a ghost button. As a fully transparent toggle
  it read as a line of plain text, with no hint that it could be pressed and none
  that it had two states.

### Changed — backup retention

- **Retention is two rules now, not one.** "Keep the newest 20" is a volume cap,
  not a policy about history, and it fails the moment something writes quickly:
  twenty automated runs inside six minutes evicted the snapshot holding a real
  save. Snapshots now survive if they are among the newest 20 OR if they are the
  oldest taken on a given day, for the last 60 days. A day's first snapshot is
  written before that day's play has changed anything, which makes it the copy of
  that day worth keeping.
- **`tools/simulate_progress.gd` refuses to overwrite a save it did not write.**
  Every save it produces is stamped with its own player name; anything else is
  treated as somebody's real garden and the run stops, naming what is in the save
  it declined to destroy. `-- --force` overrides. The file has always said
  DESTRUCTIVE in capitals at the top, and that was worth nothing at the moment it
  mattered — the line had been read days earlier, and the tool said nothing at
  all as it ran.

### Fixed

- **The interface scale no longer pushes the top-left of the app off screen.**
  `content_scale_factor` shrinks the logical viewport rather than resizing the
  window, so at 200% a 1280×720 window is a 640×360 layout — half the supported
  minimum. Controls wider than that were repositioned to make room, and
  `GROW_DIRECTION_BOTH` on the shell split the overflow evenly, half of it past
  the origin where no scrollbar could reach it. The enforced minimum window size
  now scales with the factor, the shell grows toward the end, and `AppScreen`
  scrolls horizontally when something genuinely does not fit.
- A finished plant reads as finished whatever the requirement says today, so
  retuning a species upward cannot re-open every specimen already grown — or
  visibly shrink them on a shelf the player had already arranged.
- The garden and the shelf letterbox their scene instead of stretching to fill
  their card, which had been turning square garden cells into strips.
- Growing plants on the shelf and in the garden were drawn at full size
  regardless of their actual progress.
- Two plants on one garden square left an orphaned view parented and drawing
  forever. The screen cannot produce that, but a tool or a hand-edited save can.
- **The test runner reported a crashed test as a pass.** A test whose body errors
  part-way records no assertions and appended no failure, so it printed green;
  eight genuinely broken tests once passed this way. A test that asserts nothing
  now fails.
- Home's active plant said "8h 20m of focus grown in" — a sentence that was never
  finished. It now names the project the time went into, which is the whole point
  of it.
- Every "how far along is this plant" string goes through `PlantStageText`. The
  shelf, the garden, the picker, the focus screen, the plant card and the story
  dialog had drifted into five different phrasings of the same number.
- A whole number of hours formats as "3h" rather than "3h 00m". The padded
  minutes keep a column aligned when there are minutes; they had nothing to say
  in a catalogue of costs that are all whole hours. `TimeUtil`'s display
  formatting had no test at all, and now has ten.
- A plant whose species this build cannot find still occupies its garden square
  (§54). It could not be dragged and the square could not be reused, because the
  plot only counted a cell occupied if it had managed to draw something there.
- Dragging an ornament off the plot now says what happened, as dragging a plant
  off already did.
- `tools/simulate_progress.gd` is finally as destructive as its own header
  claimed. Sessions were replaced but plants, catalogue entries and journal rows
  were appended, so a second run left two of every plant stacked on the same
  squares and reported "plants matured: 32" for a sixteen-species game.

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
