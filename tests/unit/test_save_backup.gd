extends TestCase
## SaveBackup (§53, §36).
##
## Like the AtomicFile tests, these write real files under user://, because the
## whole point of the class is what ends up on disk. A backup that passes a mock
## and fails on a real filesystem is worse than no test at all — it is the exact
## thing a player would only discover on the day they needed it.

const SAVE_DIR: String = "user://test_backup/save"
const BACKUP_DIR: String = "user://test_backup/backups"
const SESSIONS_FILE: String = "2026.json"


func before_each() -> void:
	_purge()
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)


func after_each() -> void:
	_purge()


func test_a_snapshot_copies_the_profile_and_the_sessions() -> void:
	_write_save({"save_version": 2, "plants": ["one", "two"]})

	assert_true(SaveBackup.create(SAVE_DIR, BACKUP_DIR), "a snapshot was written")
	var snapshots := SaveBackup.list(BACKUP_DIR)
	assert_eq(snapshots.size(), 1, "exactly one snapshot exists")

	var copied := AtomicFile.read_json_with_recovery(snapshots[0].path.path_join("profile.json"))
	assert_true(copied.exists(), "the profile was copied")
	assert_eq(copied.data["plants"].size(), 2, "with its contents intact")

	var shard := snapshots[0].path.path_join("sessions").path_join(SESSIONS_FILE)
	assert_true(FileAccess.file_exists(shard), "the session shard was copied too")


func test_nothing_to_back_up_is_not_a_failure() -> void:
	# A first launch has no save yet. Writing an empty dated folder would be
	# noise, and reporting an error would be a lie.
	assert_false(SaveBackup.create(SAVE_DIR, BACKUP_DIR), "no snapshot was written")
	assert_eq(SaveBackup.list(BACKUP_DIR).size(), 0, "and no folder was left behind")


func test_snapshots_are_listed_newest_first() -> void:
	_write_save({"save_version": 2, "marker": "oldest"})
	SaveBackup.create(SAVE_DIR, BACKUP_DIR, 1_700_000_000.0)
	_write_save({"save_version": 2, "marker": "newest"})
	SaveBackup.create(SAVE_DIR, BACKUP_DIR, 1_800_000_000.0)

	var snapshots := SaveBackup.list(BACKUP_DIR)
	assert_eq(snapshots.size(), 2, "both snapshots are there")
	var newest := AtomicFile.read_json_with_recovery(snapshots[0].path.path_join("profile.json"))
	assert_eq(newest.data["marker"], "newest", "the newest snapshot is first")


## One day in seconds, for building histories that span days.
const DAY: float = 86400.0


## Midnight UTC on a known date. Timestamps here are built from a real date
## rather than a raw unix number, because a raw one that happens to fall at 22:13
## puts "two hours later" on the following calendar day — which is exactly the
## boundary these tests are about.
func _midnight() -> float:
	return Time.get_unix_time_from_datetime_dict({
		"year": 2026, "month": 3, "day": 2, "hour": 0, "minute": 0, "second": 0,
	})


func test_pruning_keeps_a_days_first_snapshot_however_many_follow_it() -> void:
	# THE INCIDENT THIS EXISTS FOR. Twenty snapshots written inside six minutes
	# once evicted the one taken that morning, which was the only copy of a real
	# save. Recency alone is a volume cap, not a retention policy.
	var morning := _midnight() + 8.0 * 3600.0
	_write_save({"save_version": 2, "marker": "the morning save"})
	SaveBackup.create(SAVE_DIR, BACKUP_DIR, morning)

	_write_save({"save_version": 2, "marker": "later rubbish"})
	for i in 25:
		SaveBackup.create(SAVE_DIR, BACKUP_DIR, morning + 60.0 + float(i))

	SaveBackup.prune(BACKUP_DIR, 5)

	var survivors := SaveBackup.list(BACKUP_DIR)
	var kept_the_morning := false
	for snapshot: SaveBackup.Snapshot in survivors:
		var profile := AtomicFile.read_json_with_recovery(snapshot.path.path_join("profile.json"))
		if profile.data.get("marker", "") == "the morning save":
			kept_the_morning = true
	assert_true(kept_the_morning, "the day's first snapshot survived the burst that followed it")


func test_each_day_keeps_its_oldest_snapshot() -> void:
	var start := _midnight() + 3600.0
	for day in 4:
		for hour in 3:
			_write_save({"save_version": 2, "day": day, "hour": hour})
			SaveBackup.create(SAVE_DIR, BACKUP_DIR, start + float(day) * DAY + float(hour) * 3600.0)

	# Keep only two by recency, so anything else surviving is there on merit.
	SaveBackup.prune(BACKUP_DIR, 2)

	# JSON has no integers, so everything read back is a float. Coerced explicitly
	# rather than compared across types, which is the sort of thing that makes a
	# test fail for a reason that has nothing to do with what it is testing.
	var days_present := {}
	for snapshot: SaveBackup.Snapshot in SaveBackup.list(BACKUP_DIR):
		var profile := AtomicFile.read_json_with_recovery(snapshot.path.path_join("profile.json"))
		var day := int(profile.data.get("day", -1))
		var hour := int(profile.data.get("hour", -1))
		if not days_present.has(day):
			days_present[day] = PackedInt32Array()
		var hours: PackedInt32Array = days_present[day]
		hours.append(hour)
		days_present[day] = hours

	assert_eq(days_present.size(), 4, "every day is still represented")
	for day: int in days_present:
		var hours: PackedInt32Array = days_present[day]
		assert_true(
			hours.has(0),
			"day %d kept the snapshot taken before that day's play changed anything" % day
		)


func test_daily_anchors_do_not_accumulate_forever() -> void:
	var start := _midnight() + 3600.0
	for day in 8:
		_write_save({"save_version": 2, "day": day})
		SaveBackup.create(SAVE_DIR, BACKUP_DIR, start + float(day) * DAY)

	# Two by recency plus three days of anchors. The two newest ARE their own
	# days' anchors here, so the ceiling is the anchor count.
	SaveBackup.prune(BACKUP_DIR, 2, 3)
	assert_eq(SaveBackup.list(BACKUP_DIR).size(), 3, "history is bounded, not unbounded")


func test_a_day_key_is_read_back_out_of_the_name() -> void:
	assert_eq(
		SaveBackup.day_key("focus-garden-2026-08-21_040852"), "2026-08-21",
		"the day comes from the name, so a copied folder keeps the day it was written"
	)
	assert_eq(SaveBackup.day_key("something-else"), "", "an unrecognisable name has no day")


func test_pruning_keeps_the_newest() -> void:
	# The recency rule on its own, with daily anchors switched off. Both rules
	# together are covered by the day tests above; this is the half that answers
	# "undo the last few hours".
	var start := _midnight() + 3600.0
	for i in 5:
		_write_save({"save_version": 2, "index": i})
		SaveBackup.create(SAVE_DIR, BACKUP_DIR, start + float(i) * 3600.0)
	assert_eq(SaveBackup.list(BACKUP_DIR).size(), 5, "five were written")

	assert_eq(SaveBackup.prune(BACKUP_DIR, 2, 0), 3, "three were removed")
	var remaining := SaveBackup.list(BACKUP_DIR)
	assert_eq(remaining.size(), 2, "two were kept")
	var kept := AtomicFile.read_json_with_recovery(remaining[0].path.path_join("profile.json"))
	assert_eq(kept.data["index"], 4, "and the newest is one of them")


func test_restoring_replaces_the_live_save() -> void:
	_write_save({"save_version": 2, "marker": "backed up"})
	SaveBackup.create(SAVE_DIR, BACKUP_DIR, 1_700_000_000.0)

	_write_save({"save_version": 2, "marker": "current"})
	var snapshot := SaveBackup.list(BACKUP_DIR)[0]
	assert_true(SaveBackup.restore(snapshot.path, SAVE_DIR, BACKUP_DIR), "restore succeeded")

	var live := AtomicFile.read_json_with_recovery(SAVE_DIR.path_join("profile.json"))
	assert_eq(live.data["marker"], "backed up", "the backup is now the live save")


func test_restoring_backs_up_what_it_is_about_to_replace() -> void:
	# The undo path. Choosing the wrong date must not be how someone loses a
	# garden, so the state being replaced is copied before it is overwritten.
	_write_save({"save_version": 2, "marker": "backed up"})
	SaveBackup.create(SAVE_DIR, BACKUP_DIR, 1_700_000_000.0)
	_write_save({"save_version": 2, "marker": "current"})

	var snapshot := SaveBackup.list(BACKUP_DIR)[0]
	SaveBackup.restore(snapshot.path, SAVE_DIR, BACKUP_DIR)

	var snapshots := SaveBackup.list(BACKUP_DIR)
	assert_eq(snapshots.size(), 2, "a snapshot of the replaced save was taken")
	var rescued := AtomicFile.read_json_with_recovery(snapshots[0].path.path_join("profile.json"))
	assert_eq(rescued.data["marker"], "current", "and it holds what was about to be lost")


func test_restoring_something_that_is_not_a_snapshot_fails_safely() -> void:
	_write_save({"save_version": 2, "marker": "current"})
	assert_false(
		SaveBackup.restore(BACKUP_DIR.path_join("not-a-snapshot"), SAVE_DIR, BACKUP_DIR),
		"restoring a folder with no profile is refused"
	)
	var live := AtomicFile.read_json_with_recovery(SAVE_DIR.path_join("profile.json"))
	assert_eq(live.data["marker"], "current", "and the live save is untouched")


func test_a_snapshot_name_carries_its_date() -> void:
	_write_save({"save_version": 2})
	SaveBackup.create(SAVE_DIR, BACKUP_DIR, 1_700_000_000.0)
	var snapshot := SaveBackup.list(BACKUP_DIR)[0]
	assert_true(snapshot.name.begins_with(SaveBackup.SNAPSHOT_PREFIX), "named for the app")
	assert_true(snapshot.taken_at_utc > 0.0, "the timestamp is readable back out of the name")
	assert_false(snapshot.describe().is_empty(), "and it renders as something a person can read")


# --- Helpers ------------------------------------------------------------------

func _write_save(profile: Dictionary) -> void:
	AtomicFile.write_json(SAVE_DIR.path_join("profile.json"), profile)
	AtomicFile.write_json(
		SessionStore.sessions_dir(SAVE_DIR).path_join(SESSIONS_FILE), {"sessions": []}
	)


func _purge() -> void:
	_remove_tree("user://test_backup")


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for sub_name: String in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(sub_name))
	for file_name: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	DirAccess.remove_absolute(path)
