# Testing

## Running

```bash
tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/cli_test_runner.gd
```

Exits non-zero on failure, so it can gate a commit or a build.

As of Milestone 1: **116 tests, 931 assertions, 0 failures.**

## The API probe

```bash
tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/api_probe.gd
```

Asserts that every engine API the project calls actually exists — 54 checks
covering `Time`, `DirAccess`, `FileAccess`, `JSON`, `DisplayServer`,
`AudioServer`, `ResourceSaver`/`ResourceLoader`, `Theme`, `Tween` and
`StyleBoxFlat` properties.

Some checks are behavioural rather than presence-only: that `get_ticks_usec` is
actually monotonic, that `JSON.parse` rejects malformed input, that
`linear_to_db(1.0)` is 0 dB.

This exists because writing code against a remembered API is how invented method
names get shipped. It earns its keep on an engine upgrade: if Godot 4.8 renames
something, this names the exact call to fix in seconds instead of the failure
surfacing later as a runtime error on a screen nobody opened.

**Add a line to the probe whenever the project starts depending on a new engine
API.**

## Writing a test

Create `tests/unit/test_<subject>.gd`, extend `TestCase`, and name methods
`test_*`. The runner finds them by reflection.

```gdscript
extends TestCase

func test_credits_elapsed_time() -> void:
    assert_almost_eq(actual, 60.0, "one minute of running time")
```

Available: `assert_true`, `assert_false`, `assert_eq`, `assert_ne`,
`assert_almost_eq`, `assert_null`, `assert_not_null`, `assert_gt`, `fail`.
Optional `before_each()` / `after_each()`.

Assertions record failures rather than halting, so one broken expectation does
not hide the other twenty results in the same file.

The last argument is a message describing **what should be true**, not what is
being called. It is the only thing a failure report shows.

## What is covered

| File | Subject |
|---|---|
| `test_game_clock.gd` | Elapsed time, pauses, suspend, clock tampering, recovery |
| `test_xp_formula.gd` | Level boundaries, monotonicity, cap, session XP |
| `test_requirement_evaluator.gd` | All 13 requirement types, scopes, edge cases |
| `test_streak_calculator.gd` | Streaks, the "today is not a miss" rule, calendar edges |
| `test_save_migrations.gd` | Chain ordering, future-version refusal, gaps |
| `test_atomic_file.gd` | Round trips, corruption recovery, backup rotation |
| `test_models.gd` | Serialization, hostile input, invariants |
| `test_plant_growth.gd` | Stage quantization, one-time maturity, no regression |
| `test_session_cycle.gd` | Pomodoro cycle, long-break placement, what advances it |
| `test_session_credit.gd` | Credit policy per completion state, recovery caps |

## Testing philosophy

**`systems/` has no autoload references.** That is deliberate and it is what
makes these tests possible — they run headless with no save file, no scene tree
and no singletons.

**Inject time, never wait for it.** `GameClock.set_time_providers()` lets a test
simulate a three-hour system sleep or a backwards NTP correction instantly.
Anything that waits on a real clock is not a test.

**Test the rule, not the implementation.** `test_clock_set_backwards_preserves_earned_time`
exists because an earlier draft credited `min(monotonic, wall)`, which silently
deleted real focus time when the clock moved back. The test names the rule so a
future refactor cannot quietly undo it.

**Feed models hostile input.** Save files can be truncated, hand-edited or
written by another version. `test_models.gd` asserts that negative durations,
out-of-range enums, duplicate ids and contradictory placements all fail safe.

### Watch for reference cycles

An injected lambda that captures an object which also holds the injected target
creates a reference cycle, and GDScript's `RefCounted` cannot collect one. It
shows up as `ObjectDB instances were leaked at exit`. `test_game_clock.gd` breaks
its cycle in `after_each()` via `reset_time_providers()`. Treat that warning as a
failure, not noise.

## End-to-end checks

Unit tests use injected clocks and therefore cannot observe drift at all. Two
scripts cover what they structurally cannot:

```bash
tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tools/verify_timer.gd
```

Runs real sessions against the real system clock for about 25 seconds and checks
§59's acceptance criteria directly: drift over a 10-second run, a deliberately
stalled main thread, pause exclusion, and the shape of the recorded session. The
stall test busy-waits to starve the frame loop — the same failure class as a
minimized window, and the one a delta-accumulating timer fails outright.

```bash
tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tools/verify_save_roundtrip.gd
```

Run twice. Proves autoload wiring, migration and deserialization work together on
a cold start, which is the only path a player ever takes.

```bash
tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tools/verify_save_transfer.gd
```

Run once. Proves a garden survives being exported and imported somewhere else —
the sessions travel with it, the receiving machine's own history is replaced
rather than merged into it, and a still-growing plant comes back at the progress
it had. That last assertion is the one that matters: export used to carry the
plants without the sessions behind them, so every statistic arrived blank and
every growing plant redrew itself as a seed. Unit tests cannot see it, because
the fault lives in the wiring between the bundle, the session store and the save
directory.

It runs on its own relocated save directory under `user://verify_transfer` and
refuses to start if that relocation did not take effect — it resets a garden and
deletes a session history, and doing that to a real save would be unforgivable.

All three scripts clean up after themselves and exit non-zero on failure.

> **Tool scripts and autoloads.** A script run via `--script` is compiled
> *before* autoloads are registered, so referencing `AppState` by name is a
> compile error. Fetch them at runtime instead:
> `root.get_node("/root/AppState")`, after one `await process_frame`. Values read
> off a dynamically-fetched Node have no static type, so annotate them
> explicitly — `:=` on them is an error.

## Not covered by automation

Visual layout and animation feel. Use the screenshot harness:

```bash
tools/godot/Godot_v4.7.1-stable_win64_console.exe --path . --script res://tools/capture_screens.gd
```

It renders all nine screens at both supported resolutions plus the running timer,
which navigation alone cannot reach.

Also unautomated: real multi-hour sessions, genuine machine sleep, and true
system clock changes. The clock logic is unit-tested against simulated versions
of all three; confirming the real thing is a Milestone 9 task.
