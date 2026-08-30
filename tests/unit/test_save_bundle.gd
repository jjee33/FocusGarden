extends TestCase
## SaveBundle (§53, §35, §37).
##
## The bug these exist to prevent: an export that carries the plants but not the
## sessions behind them. It did not look like a missing file — it looked like
## selective data loss, because everything cached on the profile arrived and
## everything derived from sessions did not. The round-trip assertions below are
## the cheap version of that discovery.
##
## Pure dictionary work, so none of this needs a file or a scene tree.

const APP_VERSION: String = "9.9.9"
const EXPORT_MOMENT: float = 1_800_000_000.0


func test_a_bundle_carries_the_sessions_with_the_garden() -> void:
	var save := _save_with_a_plant()
	var sessions: Array[FocusSession] = [
		_session("s_one", "2026-03-01", 25.0), _session("s_two", "2026-03-02", 40.0)
	]

	var bundle := SaveBundle.build(save, sessions, APP_VERSION, EXPORT_MOMENT)
	var read := SaveBundle.read(bundle)

	assert_eq(read.save.plants.size(), 1, "the plant came across")
	assert_eq(read.sessions.size(), 2, "and so did both sessions")
	assert_almost_eq(read.sessions[0].actual_focus_minutes, 25.0, "with credited minutes intact")
	assert_eq(read.sessions[0].date_key, "2026-03-01", "and their stored date keys")


func test_the_awards_guard_survives_the_round_trip() -> void:
	# Losing `awards_applied` would let SessionPipeline re-run its nine steps for
	# every imported session and double a player's whole XP history (§63).
	var session := _session("s_awarded", "2026-03-01", 25.0)
	session.awards_applied = true
	var sessions: Array[FocusSession] = [session]

	var read := SaveBundle.read(SaveBundle.build(_save_with_a_plant(), sessions, APP_VERSION))
	assert_true(read.sessions[0].awards_applied, "the idempotency guard came across")


func test_a_file_without_sessions_is_reported_as_such() -> void:
	# What a build from before bundles produced, and what a bare profile.json is.
	# Importable, but the player has to be told the history is not in there —
	# "0 sessions" would read as their data being gone rather than never present.
	var bundle := _save_with_a_plant().to_dict()

	var read := SaveBundle.read(bundle)
	assert_false(read.summary.has_sessions, "the missing history is detected")
	assert_eq(read.sessions.size(), 0, "and nothing was invented to fill it")
	assert_eq(read.save.plants.size(), 1, "while the garden still imports")


func test_an_empty_history_is_not_a_missing_one() -> void:
	# A real export from someone who has never finished a session. The key is
	# there, so this is a complete file and must not be described as truncated.
	var empty: Array[FocusSession] = []
	var read := SaveBundle.read(SaveBundle.build(_save_with_a_plant(), empty, APP_VERSION))

	assert_true(read.summary.has_sessions, "an empty array still counts as a history")
	assert_eq(read.summary.session_count, 0, "there is simply nothing in it")


func test_a_sessions_key_that_is_not_an_array_reads_as_no_history() -> void:
	var bundle := _save_with_a_plant().to_dict()
	bundle[SaveBundle.SESSIONS_KEY] = "nonsense"

	var read := SaveBundle.read(bundle)
	assert_false(read.summary.has_sessions, "a corrupt key is not a history")
	assert_eq(read.sessions.size(), 0, "and yields no sessions")


func test_unreadable_rows_are_skipped_and_counted() -> void:
	# Losing one malformed record is recoverable; aborting the import is not. But
	# a quietly smaller history is the exact bug class this change exists to fix,
	# so what was dropped has to be countable and sayable.
	var good: Array[FocusSession] = [_session("s_good", "2026-03-01", 25.0)]
	var bundle := SaveBundle.build(_save_with_a_plant(), good, APP_VERSION)
	var rows: Array = bundle[SaveBundle.SESSIONS_KEY]
	rows.append("not a dictionary")
	rows.append({"date_key": "2026-03-03"})

	var read := SaveBundle.read(bundle)
	assert_eq(read.sessions.size(), 1, "the readable session survived")
	assert_eq(read.summary.skipped_count, 2, "and both bad rows were counted")


func test_duplicate_session_ids_collapse_to_one() -> void:
	# MANDATORY, not tidiness. `SessionStore.save_all` writes what it is handed
	# without deduplicating — only `append` replaces a matching id — so a repeated
	# id would be written as two rows and would permanently double lifetime focus,
	# session counts, day totals and the streak all at once.
	var bundle := SaveBundle.build(
		_save_with_a_plant(), [_session("s_dupe", "2026-03-01", 25.0)] as Array[FocusSession],
		APP_VERSION
	)
	var rows: Array = bundle[SaveBundle.SESSIONS_KEY]
	rows.append(rows[0].duplicate(true))

	var read := SaveBundle.read(bundle)
	assert_eq(read.sessions.size(), 1, "only one row survived")
	assert_eq(read.summary.duplicate_count, 1, "and the drop was counted")
	assert_almost_eq(read.summary.focus_minutes, 25.0, "so the total was not doubled")


func test_an_interrupted_session_does_not_travel_between_machines() -> void:
	# `in_flight_session` is offered back on the next launch as a session to
	# resume. Resuming a pomodoro that was interrupted on another computer three
	# weeks ago is nonsense, so export empties it — while keeping the key, so the
	# bundle's shape stays identical to `to_dict()`.
	var save := _save_with_a_plant()
	save.in_flight_session = {"session": {"id": "s_running"}, "clock": {"state": 1}}

	var empty: Array[FocusSession] = []
	var bundle := SaveBundle.build(save, empty, APP_VERSION)
	assert_true(bundle.has("in_flight_session"), "the key is still there")
	assert_eq((bundle["in_flight_session"] as Dictionary).size(), 0, "but it is empty")


func test_the_summary_matches_what_statistics_will_show() -> void:
	# The figure quoted before an import has to be the figure the statistics
	# screen shows afterwards. Breaks and cancelled sessions are excluded from
	# focus time, exactly as StatisticsManager excludes them.
	var cancelled := _session("s_cancelled", "2026-03-04", 60.0)
	cancelled.completion = FocusSession.Completion.CANCELLED
	var rest := _session("s_break", "2026-03-04", 5.0)
	rest.kind = FocusSession.Kind.SHORT_BREAK

	var sessions: Array[FocusSession] = [
		_session("s_one", "2026-03-01", 25.0), _session("s_two", "2026-03-03", 35.0),
		cancelled, rest,
	]
	var read := SaveBundle.read(SaveBundle.build(_save_with_a_plant(), sessions, APP_VERSION))

	assert_almost_eq(read.summary.focus_minutes, 60.0, "cancelled time and breaks do not count")
	assert_eq(read.summary.session_count, 2, "nor do they count as focus sessions")
	assert_eq(read.summary.break_count, 1, "the break is counted as a break")
	assert_eq(read.summary.days_focused, 2, "two distinct days had credited focus")
	assert_eq(read.summary.first_date_key, "2026-03-01", "the range starts at the earliest day")
	assert_eq(read.summary.last_date_key, "2026-03-03", "and ends at the latest")
	assert_eq(read.summary.plant_count, 1, "the plant count comes from the profile")


func test_the_export_block_records_where_the_file_came_from() -> void:
	var sessions: Array[FocusSession] = [_session("s_one", "2026-03-01", 25.0)]
	var bundle := SaveBundle.build(_save_with_a_plant(), sessions, APP_VERSION, EXPORT_MOMENT)

	var meta: Dictionary = bundle[SaveBundle.META_KEY]
	assert_eq(meta["app_version"], APP_VERSION, "the writing version is recorded")
	assert_almost_eq(meta["exported_at_utc"], EXPORT_MOMENT, "and when it was written")
	assert_eq(meta["session_count"], 1, "the header agrees with the body")
	assert_eq(SaveBundle.read(bundle).summary.app_version, APP_VERSION, "and reads back")


func test_the_bundle_is_stamped_with_the_current_format() -> void:
	# Exactly as `save_game` stamps every write, rather than trusting whatever
	# the in-memory object happened to be carrying.
	var save := _save_with_a_plant()
	save.save_version = 1

	var empty: Array[FocusSession] = []
	var bundle := SaveBundle.build(save, empty, APP_VERSION)
	assert_eq(bundle["save_version"], SaveData.CURRENT_VERSION, "the export declares this format")


func test_the_sessions_key_rides_through_a_migration_untouched() -> void:
	# THE ASSUMPTION THE WHOLE FORMAT RESTS ON. The envelope is a superset of the
	# profile rather than a wrapper around it, which is only safe as long as the
	# migration chain preserves keys it does not recognise. If a future step ever
	# rebuilds the dictionary from a known key list instead of copying it, this
	# fails here rather than silently dropping a player's history on import.
	var save := _save_with_a_plant()
	save.save_version = 1
	var sessions: Array[FocusSession] = [
		_session("s_one", "2026-03-01", 25.0), _session("s_two", "2026-03-02", 40.0)
	]
	var bundle := SaveBundle.build(save, sessions, APP_VERSION)
	bundle["save_version"] = 1

	var migration := SaveMigrations.migrate(bundle)
	assert_true(migration.is_ok(), "the bundle migrated")
	assert_eq(migration.data["save_version"], SaveData.CURRENT_VERSION, "up to the current format")
	assert_true(migration.data.has(SaveBundle.SESSIONS_KEY), "and the sessions key survived")
	assert_eq(SaveBundle.read(migration.data).sessions.size(), 2, "with both records intact")


# --- Helpers ------------------------------------------------------------------

func _save_with_a_plant() -> SaveData:
	var save := SaveData.create_new()
	save.plants.append(PlantInstance.create(&"test_fern", "p_project"))
	return save


## A session with a pinned id and date key, so assertions do not depend on the
## clock the test happens to run under.
func _session(id: String, date_key: String, minutes: float) -> FocusSession:
	var session := FocusSession.new()
	session.id = id
	session.kind = FocusSession.Kind.FOCUS
	session.date_key = date_key
	session.actual_focus_minutes = minutes
	session.intended_duration_minutes = minutes
	session.completion = FocusSession.Completion.COMPLETED
	return session
