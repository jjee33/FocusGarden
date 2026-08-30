class_name SaveBundle
extends RefCounted
## A whole garden in one file: the profile AND the session history (§35).
##
## THE FAILURE THIS FIXES. The save is two things on disk — `profile.json` and
## the year-sharded `sessions/` folder — because the session history is the
## authoritative analytics dataset and grows forever, so a routine save must not
## rewrite years of it (see SAVE_FORMAT.md). Export only ever knew about the
## first half. The result did not look like a missing file, it looked like
## selective data loss: everything CACHED on the profile came across, and
## everything DERIVED from sessions did not. Statistics read zero, and every
## still-growing plant redrew itself as a seed while its label still said
## "Young", because a plant's progress is evaluated from its own session rows
## rather than stored as a ratio.
##
## THE ENVELOPE is the profile dictionary exactly as `SaveData.to_dict()` writes
## it, plus a `sessions` array and an `export` metadata block. A superset rather
## than a wrapper, and the difference matters:
##
##   - `SaveMigrations` applies to it unchanged, because `save_version` and every
##     key a step touches are still exactly where they were. The chain copies the
##     dictionary and rewrites only what it recognises, so the extra keys ride
##     through untouched — this is the assumption the whole format rests on, and
##     `test_save_migrations` pins it.
##   - A build OLDER than this one still imports the profile. It ignores the key
##     it does not recognise, rather than failing on a shape it cannot parse.
##   - The file stays one readable, diffable, inert JSON object, which is the
##     whole reason player data is not a `.tres` (see DATA_MODEL.md).
##
## This is why adding sessions to an export needed no `SaveData.CURRENT_VERSION`
## bump: the on-disk save shape did not change. Only the export gained keys, and
## `SaveData.from_dict` has always ignored keys it does not know. Bumping would
## have been worse than useless — every shipped build would classify every new
## save as FUTURE_VERSION and refuse to write, over a change none of them can see.
##
## Nothing here touches an autoload, so it stays exercisable from the test runner
## and from tool scripts — the same constraint `AtomicFile` and `SaveBackup` work
## under.

## Top-level key holding the session rows. Deliberately the same word the shard
## files use for their own array, so the two are obviously the same records.
const SESSIONS_KEY: String = "sessions"

## Top-level key holding provenance. Never read back into gameplay — it exists so
## a file someone emails in can be identified, and so the import confirmation can
## say which version wrote it.
const META_KEY: String = "export"


## What a bundle contains, for the confirmation shown before it replaces a garden.
##
## Computed here rather than in the settings screen: a lifetime focus total is a
## figure this app defines exactly once, and a UI file is not where that belongs.
class Summary extends RefCounted:
	var plant_count: int = 0
	var session_count: int = 0
	var break_count: int = 0
	var focus_minutes: float = 0.0
	var days_focused: int = 0
	## Local date keys of the earliest and latest day with credited focus, or ""
	## when there are none. Stored keys, never recomputed — see FocusSession's
	## daylight-saving policy.
	var first_date_key: String = ""
	var last_date_key: String = ""
	var app_version: String = ""

	## False for a bare `profile.json`, and for anything written by a build from
	## before sessions travelled with a save. The difference matters to the
	## player: an empty history and a missing one look identical afterwards, and
	## only one of them is something they did.
	var has_sessions: bool = false

	## Rows that could not be read at all, and rows dropped as duplicates. Both
	## are reported rather than swallowed — a silently smaller history is exactly
	## the class of bug this whole change exists to fix.
	var skipped_count: int = 0
	var duplicate_count: int = 0

	## "3 Jan 2025 – 25 Aug 2026", or "" when the bundle carries no history.
	func describe_range() -> String:
		if first_date_key.is_empty() or last_date_key.is_empty():
			return ""
		if first_date_key == last_date_key:
			return TimeUtil.format_date_key(first_date_key)
		return "%s – %s" % [
			TimeUtil.format_date_key(first_date_key), TimeUtil.format_date_key(last_date_key)
		]


## Everything a bundle file turned out to hold, read but NOT adopted.
##
## Import validates completely before it destroys anything, so this carries the
## whole answer back to the caller while the player's own garden is still
## untouched (§36).
class Imported extends RefCounted:
	var save: SaveData = null
	var sessions: Array[FocusSession] = []
	var summary: Summary = null


## Wraps a save and its sessions into one exportable object.
##
## Works from `save.to_dict()`, so nothing here can mutate the live in-memory
## state — a player pressing "Export a copy" is not asking to change anything.
static func build(
	save: SaveData, sessions: Array[FocusSession], app_version: String, now_utc: float = -1.0
) -> Dictionary:
	var bundle := save.to_dict()

	# Stamped explicitly rather than trusting whatever the in-memory object was
	# carrying, exactly as `save_game` does before every write.
	bundle["save_version"] = SaveData.CURRENT_VERSION

	# An interrupted session does NOT travel between machines. This holds a
	# running session plus its wall-clock anchor so a crash can be offered back
	# on next launch; offering to resume a pomodoro that was interrupted on a
	# different computer three weeks ago is nonsense. The key is emptied rather
	# than removed, so the bundle's shape stays identical to `to_dict()`.
	bundle["in_flight_session"] = {}

	var rows: Array = []
	for session: FocusSession in sessions:
		rows.append(session.to_dict())
	bundle[SESSIONS_KEY] = rows

	bundle[META_KEY] = {
		"app_version": app_version,
		"exported_at_utc": now_utc if now_utc >= 0.0 else Time.get_unix_time_from_system(),
		# Informational only. Import counts the array; a header is never trusted
		# to describe the body it travelled with.
		"session_count": rows.size(),
	}
	return bundle


## Reads an ALREADY-MIGRATED bundle dictionary into its parts.
##
## Migration stays the caller's job so this class holds no version knowledge and
## remains a pure shape transform.
static func read(bundle: Dictionary) -> Imported:
	var imported := Imported.new()
	# The bundle IS the save dictionary, with extra keys. `SaveData.from_dict`
	# ignores the ones it does not know, which is exactly why the envelope is a
	# superset rather than a wrapper.
	imported.save = SaveData.from_dict(bundle)

	var summary := Summary.new()
	imported.sessions = _read_sessions(bundle, summary)
	_summarize(imported.save, imported.sessions, bundle, summary)
	imported.summary = summary
	return imported


## Whether this file carries session history at all.
##
## Checks for an ARRAY at the key, not for a non-empty one: a real bundle from a
## player who has never finished a session is a legitimate export of an empty
## history and must not be reported as the truncated kind of file. A key holding
## something that is not an array is a corrupt bundle, and reading that as "no
## history" is the honest answer.
static func has_sessions(bundle: Dictionary) -> bool:
	return bundle.get(SESSIONS_KEY) is Array


# --- Internals ----------------------------------------------------------------

## Session rows out of a bundle, defensively, recording what was dropped.
##
## DEDUPLICATION IS MANDATORY HERE, not defensive tidiness. `SessionStore.append`
## replaces a row with a matching id, but `save_all` — which is what writes an
## import — does not. A bundle carrying one repeated id would therefore be
## written as two identical rows and would permanently double every figure
## derived from them: lifetime focus, session counts, day totals and the streak,
## all at once, in the one dataset this project says has to stay exactly true.
static func _read_sessions(bundle: Dictionary, summary: Summary) -> Array[FocusSession]:
	var out: Array[FocusSession] = []
	var seen := {}
	for entry: Variant in DictUtil.get_array(bundle, SESSIONS_KEY):
		if not (entry is Dictionary):
			summary.skipped_count += 1
			continue
		var session := FocusSession.from_dict(entry)
		# An id-less row cannot be de-duplicated, credited to a plant, or replaced
		# by a later write. Losing one malformed record is recoverable; letting it
		# through is what corrupts the totals.
		if session.id.is_empty():
			summary.skipped_count += 1
			continue
		if seen.has(session.id):
			summary.duplicate_count += 1
			continue
		seen[session.id] = true
		out.append(session)
	return out


## Describes a bundle without adopting any of it.
##
## The aggregates come from `RequirementContext.ingest_sessions`, which is this
## app's one implementation of "which sessions count, and for how much". The
## figure quoted before an import has to be the figure the statistics screen
## shows afterwards, or the confirmation was a lie — and it would drift the first
## time either rule was tuned if this counted them itself.
static func _summarize(
	save: SaveData, sessions: Array[FocusSession], bundle: Dictionary, summary: Summary
) -> void:
	summary.plant_count = save.plants.size() if save != null else 0
	summary.has_sessions = has_sessions(bundle)
	summary.app_version = DictUtil.get_string(DictUtil.get_dict(bundle, META_KEY), "app_version")

	var context := RequirementContext.new()
	context.ingest_sessions(sessions)
	summary.session_count = context.completed_focus_sessions
	summary.break_count = context.completed_break_sessions
	summary.focus_minutes = context.total_focus_minutes

	# Already sorted ascending, so the ends are the range.
	var days := context.unique_focus_days
	summary.days_focused = days.size()
	if not days.is_empty():
		summary.first_date_key = days[0]
		summary.last_date_key = days[days.size() - 1]
