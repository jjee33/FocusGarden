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
- Session rows in an import with no id, or that are not objects at all, are
  skipped and counted, and the count is shown to the player — a silently smaller
  history is the exact fault this format exists to prevent

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

## Export bundles

Settings → Your data → **Export a copy** writes one file containing the whole
garden. That file is `profile.json`'s exact shape, plus two keys:

```jsonc
{
  "save_version": 2,
  "player": { }, "settings": { }, "plants": [ ], ...   // exactly as profile.json
  "in_flight_session": { },      // always emptied on export
  "sessions": [ FocusSession, ... ],
  "export": { "app_version", "exported_at_utc", "session_count" }
}
```

**Why the sessions have to be in there.** No statistic is stored as a bare total
and no plant stores a progress ratio — both are derived from the session rows on
demand. An export carrying only `profile.json` therefore looked like *selective*
data loss rather than a missing file: XP, plant count and species discovered
arrived, while lifetime focus, streaks, the heatmap and every still-growing
plant's progress did not. A garden of half-grown plants redrew itself as a tray
of seeds with each label still naming the stage it had reached.

**Why a superset and not a wrapper.** The migration chain applies to the bundle
unchanged, because `save_version` and every key a step touches are still at the
top level. A build older than the one that wrote it still imports the profile,
ignoring the key it does not recognise. And the file stays one readable, inert
JSON object.

**Why `save_version` was not bumped.** The on-disk save shape did not change —
only the export gained keys, and `SaveData.from_dict` has always ignored keys it
does not know. A bump would have made every shipped build classify every new save
as `FUTURE_VERSION` and refuse to write, over a change none of them can observe.
The additive key is safe only because migration steps preserve what they do not
understand; `test_save_bundle` pins that rule as an executable assertion rather
than leaving it as a comment.

`in_flight_session` is emptied because it holds a running session and its
wall-clock anchor, offered back on the next launch. Resuming a pomodoro that was
interrupted on a different machine three weeks ago is nonsense. The key is kept,
so the bundle's shape stays identical to `to_dict()`.

`export.session_count` is informational. Import counts the array; a header is
never trusted to describe the body it travelled with.

### Importing

`SaveManager.read_bundle` parses, migrates and validates **without touching
anything on disk**, so the player is shown what the file actually holds — real
session count, real lifetime focus, the date range it spans — and confirms before
their own garden is at risk. `apply_bundle` then does the destructive half, in
this order:

1. Force a snapshot of the current save, so the garden being replaced survives a
   wrong choice of file.
2. **Stage** the incoming shards into `saves/.incoming/sessions/`. If any of them
   cannot be written, delete the staging folder and abort — nothing of the
   player's has been touched. This is `AtomicFile`'s rule: verify before going
   near the real file.
3. Only now clear `saves/sessions/` and rename the staged folder into place.
4. Write `profile.json` through the ordinary atomic save path.

**Do not reorder these steps**, and in particular do not move 3 before 2. Steps 3
and 4 cannot be one transaction, so a crash between them leaves a real garden
beside a real history that did not grow together — an honest, visible state
rather than a corrupt one, with step 1's snapshot taken seconds earlier. Writing
the profile first would instead produce a new garden silently attached to the old
machine's history, which is plausible-looking and permanently wrong.

The staged folder is created even when the bundle has no sessions at all, so a
legacy export still has something to rename into place. A file with no `sessions`
key imports fine and says up front that statistics will be blank.

Session shards are **replaced wholesale, never merged**. `SessionStore.save_all`
only writes the years present in the data it is handed, so without clearing
first, a garden spanning fewer years than the one it replaces would keep the
previous garden's records for every year it does not mention — and every total
would silently be a sum of two different people's work. `SessionStore.clear`
removes every file in the folder, including the `.bak` beside each shard: leaving
those lets `read_json_with_recovery` restore history from a shard that was
supposed to be gone.

Duplicate session ids in a bundle are dropped, first occurrence wins. `save_all`
does not deduplicate — only `append` does — so one repeated id would be written
twice and would permanently double lifetime focus, session counts, day totals and
the streak all at once.

Import reads with `AtomicFile.read_json`, which is **strict**:
`read_json_with_recovery` scans the target's folder for a `.tmp` or a `.bak`,
which is right for our save directory and wrong for a folder the player picked.
Quietly substituting a different, older export sitting beside the one they chose
is not recovery, and the import would then report success having replaced their
garden with the wrong file.

Exports also do not rotate backups: they write into a folder the player chose, and
`focus-garden-2026-08-26.json.000001756….bak` appearing beside their file every
time they re-export is litter in someone else's folder rather than insurance in
ours.

**Session records are not versioned and never pass through the migration chain** —
shards are read raw and rely on `FocusSession.from_dict` being defensive. A
bundle's `sessions` array inherits exactly that. A future change needing to
migrate session fields would have to migrate shards *and* bundles.

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
