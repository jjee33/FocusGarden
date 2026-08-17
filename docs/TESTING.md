# Testing

## Running

```bash
tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless --path . --script res://tests/cli_test_runner.gd
```

Exits non-zero on failure, so it can gate a commit or a build.

As of Milestone 0: **100 tests, 896 assertions, 0 failures.**

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

## Not covered by automation

Visual layout, animation feel, and anything requiring a rendered window. Use the
screenshot harness for those:

```bash
tools/godot/Godot_v4.7.1-stable_win64_console.exe --path . --script res://tools/capture_screens.gd
```

Also unautomated: real multi-hour sessions, genuine machine sleep, and true
system clock changes. The clock logic is unit-tested against simulated versions
of all three; confirming the real thing is a Milestone 9 task.
