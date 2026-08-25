# Save format

Current save version: **2**

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

There is also a second, quite different backup folder — see
[Dated snapshots](#dated-snapshots).

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

### The chain

| Step | Change |
|---|---|
| 1 → 2 | Ornaments and planted specimens gained a facing, and the appearance mode became a setting. |

**1 → 2** rewrites each garden cell from a bare decoration id string to
`{"id", "rotation"}`, and defaults `settings.theme_mode` to `"light"`. Rotation
defaults to 0, which is exactly how every existing garden already looks, so the
step cannot change what a player sees — it only makes the shape writable. The
model still reads the format-1 bare string directly, so a save that somehow
skipped the migration renders rather than crashes.

The framework around the chain was written and fully tested with injected chains
at version 1, before there was anything to migrate — which is the only time it
could have been designed calmly.

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
  wins, and a facing is cleared with the placement it belonged to
- An out-of-range facing is wrapped into 0-3 rather than trusted
- A decoration entry with no id at all is dropped, rather than kept as an
  invisible occupant of a cell the player then cannot use
- `longest_streak` is raised to at least `current_streak`
- A missing `date_key` is rebuilt from the session's timestamp

## Top-level shape

```jsonc
{
  "save_version": 2,
  "player":    { "display_name", "total_xp", "active_plant_uid", "unlocked_ids",
                 "current_streak", "longest_streak", "onboarding_completed", ... },
  "settings":  { timer, appearance, audio, notification, gameplay, data },
  "plants":    [ PlantInstance ],
  "projects":  [ ProjectCategory ],
  "catalogue": [ CatalogueEntry ],
  "achievements": [ AchievementState ],
  "journal":   [ JournalEntry ],
  "shelf":     ShelfLayout,
  "garden":    GardenLayout,     // decorations: { "2,1": { "id", "rotation" } }
  "expeditions": { },          // opaque to SaveData
  "in_flight_session": { }     // set while a session is running
}
```

`in_flight_session` holds the running session plus its wall-clock anchor, so a
session interrupted by a crash can be offered back to the player on next launch
instead of being silently lost. It is written on state changes, not on every
tick — a tick-rate write would hammer the disk for hours.

Field-by-field descriptions are in [DATA_MODEL.md](DATA_MODEL.md).

## Dated snapshots

The rotating `.bak` files above are crash insurance: they exist because a write
happened, they live somewhere no player will ever look, and three of them can all
be produced within a minute of a bad session. They cannot help if someone deletes
something, or if a save goes wrong in a way that is written through cleanly.

So `systems/save/save_backup.gd` also keeps dated, self-contained snapshots
somewhere a person can actually find:

```
Documents/Focus Garden/Backups/
  focus-garden-2026-08-21_094233/
    profile.json
    sessions/
      2026.json
```

- Written on launch (a copy of what was on disk before this run touches it),
  hourly during play, and on close. A two-minute floor stops a quick open-and-
  close leaving three folders.
- A snapshot survives if it is among the newest 20, OR if it is the oldest taken
  on a given day, for the last 60 days. Recency alone is a volume cap rather than
  a policy about history, and it fails whenever something writes quickly: twenty
  automated runs inside six minutes once evicted the snapshot holding a real
  save. A day's first snapshot is written before that day's play has changed
  anything, which makes it the copy of that day worth keeping. A save is tens of
  kilobytes, so the whole folder stays smaller than a few screenshots.
- Files are COPIED, never re-serialised. A backup should preserve what is on
  disk, including a save this build only partly understands — re-serialising
  would quietly rewrite it into the current format and destroy the one thing
  worth keeping.
- **Restoring snapshots the current save first**, under its own timestamp.
  Restore is the only operation here that destroys anything, and picking the
  wrong date must not be how someone loses a garden.
- Session shards are replaced wholesale on restore rather than merged. A
  half-merged history would double-count sessions, and that dataset is the one
  thing in the app that has to stay exactly true.
- Everything is best-effort. A snapshot that cannot be written is logged and
  never blocks a normal save; if the OS cannot say where Documents is, it falls
  back to the rotating-backup folder. A relocated snapshot folder is recorded in
  `user://backup_location.cfg`.
- A save the build has refused (newer version, or a gap in the migration chain)
  is not snapshotted, so the folder does not fill with copies of a file the
  player cannot open here anyway.

Settings → Your data shows the folder and offers **Back up now**, **Open folder**
and **Restore a backup**.
