# Save format

Current save version: **1**

## Location

Default `user://saves`, which on Windows resolves to:

```
%APPDATA%\Godot\app_userdata\Focus Garden\saves\
```

A relocated save directory is recorded in `user://save_location.cfg` — outside
the save itself, because the path has to be known before anything can be read.

```
saves/
  profile.json              Everything except session history
  sessions/
    2026.json               Session records, sharded by year
    unknown.json            Records whose date key could not be parsed
  backups/
    profile.json.<stamp>.bak    Newest 3 kept
```

## Why sessions are separate

The full session history is the authoritative analytics dataset and grows
forever — no statistic is stored as a bare total, so any figure can be recomputed
from the rows. Keeping that history inside `profile.json` would mean rewriting
years of records every time a 25-minute pomodoro ends.

Sharding is in the format from day one because adding it later would cost a
migration. The shard key is the session's stored `date_key`, so a record never
moves between shards even if the machine's timezone changes.

## Atomic writes

The naive implementation opens the save file and writes over it. If the process
dies partway — power loss, a crash, the user killing the app — the player's file
is now truncated JSON and their entire garden is gone. That is unrecoverable and
it is the worst bug this application could ship.

`systems/save/atomic_file.gd` instead does:

1. Write the new content to `<path>.tmp`
2. Read `.tmp` back and parse it; if it does not parse, abort with the real file
   still untouched
3. Copy the existing real file to a timestamped backup
4. Remove the real file, then rename `.tmp` into place

At every instant at least one of {real file, `.tmp`, newest backup} is complete
and parseable. Step 4 uses remove-then-rename rather than an overwriting rename
because rename-over-existing semantics differ across platforms; the backup from
step 3 covers the brief window where the real path is absent.

**Do not reorder these steps.**

## Recovery

`read_json_with_recovery` falls back in order:

1. `profile.json`
2. `profile.json.tmp` — a crash between steps 4a and 4b; already verified before
   the swap started, so it is the freshest complete data
3. Newest parseable backup, oldest last

The result carries a `recovered` flag and the source filename so the player can
be told what happened, rather than silently getting older data.

Parsing uses `JSON.new().parse()` rather than `JSON.parse_string()`, because the
latter pushes a raw engine error into the log. Corrupt saves are a case this code
handles deliberately; users get a friendly message and the technical detail goes
through `GameLog`.

## Migrations

`systems/save/save_migrations.gd` holds an ordered chain of
`{from, to, apply}` steps, applied in version order regardless of declaration
order. Steps are pure `Dictionary -> Dictionary` transforms, so they are tested
with no file IO.

The chain is **empty at version 1** — nothing is older than the first release.
The framework around it is fully tested with injected chains, so it is proven
before the first real migration exists rather than after players already depend
on it.

### Adding a migration

1. Bump `SaveData.CURRENT_VERSION`
2. Append one step to `SaveMigrations.get_chain()`
3. Add a test upgrading an old fixture

Never reuse a version number. Never delete data a step does not understand — an
unknown key from a newer build is harmless; deleting it is not.

### Refusal cases

| Situation | Behaviour |
|---|---|
| Save version > build version | **Refused.** File untouched, a fresh save is returned in memory, and `AppState.save_blocked` is set so nothing can overwrite it. |
| Gap in the migration chain | Same — reported as `MIGRATION_FAILED`, nothing written. |
| Corrupt JSON | Recovered from `.tmp` or a backup, flagged to the user. |
| No file at all | New game. |

A save is never silently erased.

## Validation on load

Save files are JSON on the player's disk. They can be truncated, hand-edited, or
written by a different version. Every field is read through `DictUtil`, which
returns a sane default for a missing or wrong-typed key. Beyond that:

- Negative durations, XP and counts are clamped to zero
- Out-of-range enum values fall back to their defaults
- Duplicate ids are dropped, first occurrence wins
- Entries with no id are skipped — losing one malformed plant is recoverable,
  losing the save is not
- A plant claiming both a shelf slot and a garden cell is repaired; `location`
  wins
- `longest_streak` is raised to at least `current_streak`
- A missing `date_key` is rebuilt from the session's timestamp

## Top-level shape

```jsonc
{
  "save_version": 1,
  "player":    { "display_name", "total_xp", "active_plant_uid", "unlocked_ids",
                 "current_streak", "longest_streak", "onboarding_completed", ... },
  "settings":  { timer, appearance, audio, notification, gameplay, data },
  "plants":    [ PlantInstance ],
  "projects":  [ ProjectCategory ],
  "catalogue": [ CatalogueEntry ],
  "achievements": [ AchievementState ],
  "journal":   [ JournalEntry ],
  "shelf":     ShelfLayout,
  "garden":    GardenLayout,
  "expeditions": { },          // opaque to SaveData
  "in_flight_session": { }     // set while a session is running
}
```

`in_flight_session` holds the running session plus its wall-clock anchor, so a
session interrupted by a crash can be offered back to the player on next launch
instead of being silently lost. It is written on state changes, not on every
tick — a tick-rate write would hammer the disk for hours.

Field-by-field descriptions are in [DATA_MODEL.md](DATA_MODEL.md).
