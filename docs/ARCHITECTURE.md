# Architecture

Documents the system as it exists after Milestone 0. Anything not built yet is
marked **(not implemented)** rather than described as if it works.

## The one rule

**UI displays state. Services change state.**

A screen may read anything and call service methods. A screen may never contain a
formula, a threshold, or a persistence decision. Every autoload owns exactly one
responsibility and is forbidden from the others'.

## Layers

```
scenes/ + ui/        Screens and components. Read state, call services, render.
   |                 May not contain game formulas.
   v
autoload/            Narrow singletons. Own runtime state and orchestration.
   |                 May not contain UI logic.
   v
systems/             Pure logic classes. No autoload references, no scene tree.
   |                 This is where every formula lives, and why they are testable.
   v
models/              Data. Serialization and validation only.
```

`systems/` deliberately does not reference autoloads. That is what lets 100 unit
tests run headless with no save file, no scene tree, and no singletons.

`ui/theme/motion.gd` is the one intentional exception — it reads `AppState` to
honour the reduced-motion setting. `design_tokens.gd` stays pure so tools and
tests can read it.

## Autoload ownership

Registered in `project.godot`, in dependency order.

| Autoload | Owns | Must never |
|---|---|---|
| `GameLog` | Levelled logging by category | Contain game logic |
| `EventBus` | Signal declarations only — no state, no methods | Do any work |
| `ContentDB` | Loading/indexing authored `.tres` content | Touch player data |
| `SaveManager` | Serialization, atomic writes, backups, migrations | Know gameplay rules |
| `AppState` | The live `SaveData` + session list, and app lifecycle | Render UI, know file formats |
| `TimerManager` | Session lifecycle and elapsed-time truth | Award XP or grow plants |
| `ProgressionManager` | XP, levels, unlocks | Evaluate achievements |
| `AchievementManager` | Achievement evaluation | Do XP math |
| `StatisticsManager` | Aggregation over session records | Mutate sessions |
| `AudioManager` | Buses, volumes, playback | Anything else |

`ContentDB` is an addition to the originally specified autoload list. Loading the
content that ships with the game is genuinely a different responsibility from
holding one player's data, and merging them is how a narrow manager becomes a
god-object.

> **Naming note:** the logger is `GameLog`, not `Logger`. Godot 4.7 has a
> built-in `Logger` class, and an autoload of that name silently resolves to the
> engine class instead — every call fails to compile with a confusing error.

## Why session completion is a pipeline

`systems/progression/session_pipeline.gd` runs the nine completion steps in an
explicit order.

The obvious alternative — every manager subscribing to a `session_completed`
signal — breaks two guarantees. Signal handler order is unspecified, so
achievements could evaluate before the XP that satisfies them is awarded. And any
handler that runs twice double-awards.

So the pipeline is an ordered function, and it is **idempotent**: the guard is
`FocusSession.awards_applied`, stored on the session record and persisted with
it. Re-running the pipeline for a processed session is a no-op, whatever caused
the re-run. "XP cannot double-award" is therefore a structural property, not a
convention.

Order: record → settle credited minutes → grow plant → award XP → invalidate
statistics → update streak → evaluate achievements → reconcile unlocks → save.

## The single-implementation rule

Exactly one implementation of each of these exists. Nothing else may re-derive
them.

| Calculation | Home |
|---|---|
| Elapsed / credited focus time | `systems/time/game_clock.gd` |
| XP and level | `systems/progression/xp_formula.gd` |
| Plant growth stage and maturity | `systems/plant_growth/plant_growth_service.gd` |
| Streaks | `systems/analytics/streak_calculator.gd` |
| Pomodoro cycle placement | `systems/progression/session_cycle.gd` |
| How much of a session counts | `systems/progression/session_credit.gd` |
| Every unlock condition | `systems/requirements/requirement_evaluator.gd` |
| Save read/write | `systems/save/atomic_file.gd` |
| Date keys and durations | `systems/util/time_util.gd` |

Player level is **not stored** — it is derived from `total_xp`. Storing both would
let them disagree after any formula change.

## The requirement engine

One `Requirement` resource and one evaluator serve plant unlocks, plant maturity,
achievements, expeditions, garden expansions and cosmetic unlocks.

Requirements return a **0..1 ratio**, not a boolean. That single choice is what
lets one engine answer both "is this unlocked" and "how full is this bar", and it
is what drives plant growth: a plant's stage is its maturity requirement's ratio
quantized to the species' stage count. Growth thresholds exist in exactly one
place as a result.

Thirteen types are implemented and each is unit-tested: total focus minutes,
completed sessions, unique focus days, consecutive days, sessions in a time
window, session length, break sessions, plants matured, species discovered,
player level, catalogue completion, achievement unlocked, expedition completed.

A `Requirement` has a **scope**: `GLOBAL` or `ACTIVE_PLANT`. That is how "Monstera
needs 250 minutes" means 250 minutes grown into *that plant*, while "Century
Garden" means 100 hours across everything.

## Timing

Elapsed time is derived from timestamps, never from accumulated frame deltas.
Two clocks run at once:

- **monotonic** (`Time.get_ticks_usec`) — cannot be changed by the user, does not
  advance while the machine sleeps
- **wall** (`Time.get_unix_time_from_system`) — survives restarts, but moves with
  NTP, DST and manual clock changes

**Credited time is always the monotonic figure.** The wall clock is used only to
detect anomalies and to recover a session across a restart. An earlier draft
credited `min(monotonic, wall)`; that is wrong when the clock moves backward,
because it would silently delete real focus time the player earned. There is a
regression test for exactly that case.

Divergence between the clocks flags the session (`SUSPEND`, `CLOCK_JUMP`,
`NEGATIVE_DURATION`) and is never punished — the session is always kept.

## Signals

`EventBus` declares signals and holds no state. Systems emit; screens listen.
Nothing reaches into an unrelated scene to manipulate it, and no system holds a
reference to another system purely to be notified by it.

Navigation is a signal too: `EventBus.navigation_requested` is emitted by anything
that wants to move the player, and the main scene is the only listener. Routing
lives in `scenes/main/main.gd`, not an autoload, because routing is UI logic.

## Notifications

`NotificationRouter` (a UI-layer node, not an autoload) decides which events the
player hears about. Systems emit facts; this decides whether they are announced,
which keeps a presentation decision out of the singletons.

Godot 4 has **no cross-platform desktop notification API**. The workarounds are a
GDExtension or shelling out to PowerShell, which flashes a console window and
depends on a module that is not installed by default. Neither suits a calm
offline app, so the implementation is an in-app toast plus
`DisplayServer.window_request_attention()` — a real engine API that flashes the
taskbar icon when the window is in the background. This is a documented
limitation, not a claim that §34 is fully met.

## Content vs player data

- **Authored content** → Godot `Resource` (`.tres`) in `data/`. Identical for
  every player, never written to a save.
- **Player data** → plain Dictionaries → JSON in `user://saves/`.

Player data is deliberately not `.tres`. Godot's resource loader can execute code
embedded in a resource file, so loading a user-supplied or imported save as a
resource is a real code-execution risk. JSON is inert, diffable and migratable.

## Directory layout

```
autoload/     Ten narrow singletons
models/       Data models; player data has to_dict/from_dict
systems/      Pure logic — save/, time/, requirements/, progression/,
              plant_growth/, analytics/, util/
data/         Authored .tres content (empty until Milestone 2)
scenes/       main/ plus one directory per section
ui/           theme/ (tokens, builder, generated .tres) and components/
assets/       Art, audio, fonts (app icon only so far)
tests/        Runner, API probe, and unit/
tools/        Engine fetch, theme bake, screenshot capture
docs/         This directory
```
