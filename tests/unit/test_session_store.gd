extends TestCase
## SessionStore (§53, §37).
##
## The session history is the one dataset in this app that has to stay exactly
## true — every statistic is a sum over these rows, so a record duplicated or a
## shard left behind is not a cosmetic fault, it is a permanently wrong number on
## the statistics screen.
##
## Real files under user://, like the other save-layer tests: the sharding, the
## replace-don't-duplicate rule and the clear are all things that only mean
## anything on a filesystem.

const SAVE_DIR: String = "user://test_sessions/save"


func before_each() -> void:
	_purge()
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func after_each() -> void:
	_purge()


func test_append_then_load_round_trip() -> void:
	assert_eq(SessionStore.append(SAVE_DIR, _session("s_one", "2026-03-01", 25.0)), OK, "written")

	var loaded := SessionStore.load_all(SAVE_DIR)
	assert_eq(loaded.size(), 1, "the record came back")
	assert_eq(loaded[0].id, "s_one", "with its id")
	assert_almost_eq(loaded[0].actual_focus_minutes, 25.0, "and its credited minutes")


func test_appending_the_same_id_replaces_rather_than_duplicates() -> void:
	# A session is re-saved after its awards are applied. Appending a second row
	# would double every total derived from it.
	SessionStore.append(SAVE_DIR, _session("s_one", "2026-03-01", 25.0))
	var updated := _session("s_one", "2026-03-01", 25.0)
	updated.awards_applied = true
	SessionStore.append(SAVE_DIR, updated)

	var loaded := SessionStore.load_all(SAVE_DIR)
	assert_eq(loaded.size(), 1, "there is still exactly one row")
	assert_true(loaded[0].awards_applied, "and it is the updated one")


func test_sessions_are_sharded_by_the_year_they_were_recorded_in() -> void:
	# Sharding is what keeps a save after a 25-minute pomodoro from rewriting a
	# decade of history. The key is the session's STORED date, so a record never
	# moves between shards even if the machine's timezone changes later.
	SessionStore.append(SAVE_DIR, _session("s_old", "2025-11-02", 25.0))
	SessionStore.append(SAVE_DIR, _session("s_new", "2026-03-01", 40.0))

	assert_true(FileAccess.file_exists(SessionStore.shard_path(SAVE_DIR, "2025")), "2025 shard")
	assert_true(FileAccess.file_exists(SessionStore.shard_path(SAVE_DIR, "2026")), "2026 shard")
	assert_eq(SessionStore.load_all(SAVE_DIR).size(), 2, "and both load back together")


func test_a_record_with_no_usable_date_still_survives() -> void:
	# A malformed key is not a reason to drop a session. It goes to a dedicated
	# shard rather than being lost or silently filed under this year.
	var stray := _session("s_stray", "", 25.0)
	SessionStore.append(SAVE_DIR, stray)

	assert_true(
		FileAccess.file_exists(SessionStore.shard_path(SAVE_DIR, SessionStore.FALLBACK_YEAR)),
		"it landed in the fallback shard"
	)
	assert_eq(SessionStore.load_all(SAVE_DIR).size(), 1, "and it loads back")


func test_clear_removes_the_backups_as_well_as_the_shards() -> void:
	# `append` passes the sessions folder as its own backup directory, so a
	# `2026.json.<stamp>.bak` sits beside each shard. Deleting only the .json
	# files would leave `read_json_with_recovery` able to restore history from a
	# backup of a shard that was supposed to be gone — that is how a wiped
	# history comes back from the dead.
	SessionStore.append(SAVE_DIR, _session("s_one", "2026-03-01", 25.0))
	SessionStore.append(SAVE_DIR, _session("s_two", "2026-03-02", 25.0))
	var shard := SessionStore.shard_path(SAVE_DIR, "2026")
	assert_gt(
		float(AtomicFile.list_backups(shard, SessionStore.sessions_dir(SAVE_DIR)).size()), 0.0,
		"a shard backup exists to begin with"
	)

	SessionStore.clear(SAVE_DIR)

	assert_false(
		DirAccess.dir_exists_absolute(SessionStore.sessions_dir(SAVE_DIR)), "the folder is gone"
	)
	assert_eq(SessionStore.load_all(SAVE_DIR).size(), 0, "and nothing loads back")


func test_replacing_a_history_leaves_none_of_the_old_one_behind() -> void:
	# THE CROSS-CONTAMINATION CASE, and the reason `clear` exists. `save_all`
	# only writes the years present in the data it is handed, so importing a
	# garden that spans fewer years than the one it replaces would otherwise keep
	# the previous garden's records for every year the new one does not mention —
	# and every statistic would silently be a sum of two different people's work.
	SessionStore.append(SAVE_DIR, _session("s_local", "2019-06-01", 90.0))
	SessionStore.append(SAVE_DIR, _session("s_local_two", "2026-01-05", 30.0))

	SessionStore.clear(SAVE_DIR)
	var incoming: Array[FocusSession] = [_session("s_imported", "2026-03-01", 25.0)]
	assert_eq(SessionStore.save_all(SAVE_DIR, incoming), OK, "the incoming history was written")

	var loaded := SessionStore.load_all(SAVE_DIR)
	assert_eq(loaded.size(), 1, "only the imported record is present")
	assert_eq(loaded[0].id, "s_imported", "and it is the imported one")
	assert_false(
		FileAccess.file_exists(SessionStore.shard_path(SAVE_DIR, "2019")),
		"the year the import never mentioned did not survive"
	)


func test_clearing_a_history_that_was_never_written_is_not_an_error() -> void:
	# A first launch, or an import onto a fresh install.
	SessionStore.clear(SAVE_DIR)
	assert_eq(SessionStore.load_all(SAVE_DIR).size(), 0, "nothing there, nothing broken")


func test_loaded_sessions_come_back_oldest_first() -> void:
	# Streaks and day-run calculations walk this list in order.
	SessionStore.append(SAVE_DIR, _session("s_later", "2026-03-05", 25.0, 500.0))
	SessionStore.append(SAVE_DIR, _session("s_earlier", "2026-03-01", 25.0, 100.0))

	var loaded := SessionStore.load_all(SAVE_DIR)
	assert_eq(loaded[0].id, "s_earlier", "the earliest session is first")
	assert_eq(loaded[1].id, "s_later", "and the latest is last")


# --- Helpers ------------------------------------------------------------------

## A session with a pinned id and date key, so assertions do not depend on the
## clock the test happens to run under.
func _session(
	id: String, date_key: String, minutes: float, started_at: float = 100.0
) -> FocusSession:
	var session := FocusSession.new()
	session.id = id
	session.kind = FocusSession.Kind.FOCUS
	session.date_key = date_key
	session.started_at_utc = started_at
	session.actual_focus_minutes = minutes
	session.intended_duration_minutes = minutes
	session.completion = FocusSession.Completion.COMPLETED
	return session


func _purge() -> void:
	SessionStore.clear(SAVE_DIR)
	_purge_dir(SAVE_DIR)
	_purge_dir("user://test_sessions")


func _purge_dir(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	for file_name: String in DirAccess.get_files_at(dir_path):
		DirAccess.remove_absolute(dir_path.path_join(file_name))
	DirAccess.remove_absolute(dir_path)
