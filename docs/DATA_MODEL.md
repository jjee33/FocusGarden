# Data model

## The split

| | Authored content | Player data |
|---|---|---|
| Type | Godot `Resource` (`.tres`) | Plain Dictionary → JSON |
| Lives in | `data/` in the repo | `user://saves/` |
| Same for every player | Yes | No |
| Examples | `PlantSpecies`, `AchievementDef`, `Requirement` | `PlantInstance`, `FocusSession`, `PlayerProfile` |

Player data is deliberately **not** stored as `.tres`. Godot's resource loader
can execute code embedded in a resource file, so loading a user-supplied or
imported save as a resource is a genuine code-execution risk. Binary resources
also make migrations painful. JSON is inert, diffable and migratable.

Every player-data model implements `to_dict()` and `static from_dict()`, and
`from_dict` is defensive — see [SAVE_FORMAT.md](SAVE_FORMAT.md#validation-on-load).

## Authored content

### `PlantSpecies` — `models/plant_species.gd`

Identity (`id`, `display_name`, `scientific_name`, `description`),
classification (`rarity`, `biome_id`, `tags`), growth (`growth_requirement`,
`stage_textures`, `catalogue_texture`, `icon_texture`), presentation
(`botanical`, `preferred_pot_ids`, `allowed_mutation_ids`), availability
(`hidden_until_discovered`, `unlock_requirement`, `seasonal_months`).

Two deliberate derivations rather than stored fields:

- **No `required_focus_minutes`.** The maturity rule lives in
  `growth_requirement`, so varied patterns all work through one mechanism — 100
  minutes, 4 sessions, 5 separate days, morning sessions. A plain minute count is
  just the commonest shape of that. `get_display_focus_minutes()` derives it for
  the UI and returns `-1` when the requirement is not minute-shaped, so the
  interface shows the requirement's own wording instead of a fabricated number.
- **No `growth_stage_count`.** Derived from `stage_textures.size()`, so a species
  can never claim more stages than it has art for.

### `BotanicalInfo` — `models/botanical_info.gd`

Real-world facts: family, native region, light, watering, care difficulty, an
interesting fact. A separate resource so factual text can be corrected without
touching anything gameplay reads. **Nothing here may ever influence growth, XP or
unlocks.**

### `AchievementDef` — `models/achievement_def.gd`

`id`, `title`, `description`, `category`, `rarity`, `icon_texture`, `hidden`,
`track_progress`, and a `requirement`. Adding an achievement is authoring data,
never writing code.

### `Requirement` — `models/requirement.gd`

`type` + `params` + `scope`, plus an optional `description_override`. Thirteen
types, all implemented and tested. See
[ARCHITECTURE.md](ARCHITECTURE.md#the-requirement-engine).

## Player data

### `PlayerProfile` — `models/player_profile.gd`

`display_name`, `created_at_utc`, `total_xp`, `active_plant_uid`,
`active_project_id`, `unlocked_ids`, streak cache, `onboarding_completed`.

**Level is not stored.** It is derived from `total_xp` by `XpFormula`, the single
authoritative level calculation. Storing a level alongside the XP that determines
it would let the two disagree after any formula change.

**Streaks are stored, as a cache.** Recomputing a streak means walking every
session; the cache avoids doing that on every screen open, and
`StatisticsManager` can rebuild it from sessions at any time.

`grant_unlock()` returns `true` only on the first grant, so celebrations fire
exactly once.

### `PlantInstance` — `models/plant_instance.gd`

`uid`, `species_id`, `nickname`, `planted_at_utc`, `matured_at_utc`,
`accumulated_focus_minutes`, `growth_stage`, `maturity`,
`contributing_session_ids`, `primary_project_id`, `mutation_ids`, `pot_id`,
`favorite`, placement, and mystery-seed state.

**Placement invariant:** a plant is in exactly one place, expressed by a single
`location` enum (`INVENTORY` / `SHELF` / `GARDEN`). Shelf and garden positions are
not independent fields, so "placed in two spots at once" cannot be represented.
Use `move_to_inventory()` / `move_to_shelf()` / `move_to_garden()` — assigning
the fields directly is what would reintroduce the bug. `from_dict` re-asserts the
invariant on load.

`is_species_hidden()` gates mystery seeds: while unrevealed, the UI must not show
the species.

### `FocusSession` — `models/focus_session.gd`

`id`, `kind`, `started_at_utc`, `ended_at_utc`, `date_key`, `start_hour`,
`intended_duration_minutes`, `actual_focus_minutes`, `paused_minutes`,
`completion`, `anomaly`, `interruption_reason`, `project_id`, `plant_uid`,
`xp_earned`, `awards_applied`.

`awards_applied` is the idempotency guard `SessionPipeline` keys on.

`date_key` and `start_hour` are captured **at record time** and never recomputed.
Recomputing later would apply today's UTC offset to a historical timestamp and
silently shift sessions across midnight whenever DST flipped in between.

Completion states: `COMPLETED`, `ENDED_EARLY`, `CANCELLED`, `ABANDONED`.
Anomalies: `NONE`, `SUSPEND`, `CLOCK_JUMP`, `NEGATIVE_DURATION`.

### Others

| Model | Notes |
|---|---|
| `GameSettings` | All preferences. Every numeric field is clamped on load — a corrupted 0-minute focus duration would make the timer unusable with no way to fix it in-app. |
| `ProjectCategory` | User-created. Colour is a **theme token name**, never a hex value, so categories stay re-themeable. |
| `CatalogueEntry` | Per-species collection record. `discover()` returns true once. |
| `AchievementState` | Per-achievement progress. `unlock()` returns true once. |
| `JournalEntry` | Append-only. Stores composed `body` text rather than a template, so future wording changes cannot retroactively alter the player's history. |
| `ShelfLayout` / `GardenLayout` | Styling and decorations only — plant placement lives on `PlantInstance`, so the two can never disagree. |
| `SaveData` | The container. Drops duplicate ids and skips malformed entries on load. |

## Date and time conventions

- Timestamps are **UTC unix seconds** (`float`).
- `date_key` is a **local** `"YYYY-MM-DD"` string, captured once at record time.
- A session spanning midnight is credited entirely to the local date it
  **started** on. Sessions are not split, so one session equals one row of
  history and a 23:50 start belongs to the day the player sat down.
- All formatting goes through `TimeUtil`, so the app never shows two different
  formats for the same quantity.
