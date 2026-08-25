class_name SaveBackup
extends RefCounted
## Dated snapshots of the whole save, in a folder the player can actually find.
##
## WHAT THIS IS NOT. `AtomicFile` already keeps three rotating `.bak` files beside
## the save, and those are what recover a write interrupted by a crash. They are
## not a backup in the sense a person means it: they live under
## %APPDATA%\Godot\app_userdata, they only exist because a write happened, and
## three of them can all be produced within one minute of a bad session. If a
## player deletes something, or a save goes wrong in a way that is written
## through cleanly, rotation cannot help.
##
## So this writes a full, dated, self-contained copy — profile and every session
## shard — into Documents\Focus Garden\Backups, where it can be seen, copied to a
## drive, and restored from inside the app. Hundreds of hours of someone's real
## focus time live in that file. It is worth the folder.
##
## Everything here is best-effort and non-fatal. A snapshot that cannot be
## written must never stop the game saving normally, so every entry point returns
## a bool rather than propagating an error.
##
## Nothing here touches an autoload — not even GameLog. AtomicFile makes the same
## choice for the same reason: these classes have to be exercisable from the test
## runner and from tool scripts, neither of which has autoloads. SaveManager owns
## the logging.

const ROOT_FOLDER: String = "Focus Garden"
const BACKUPS_FOLDER: String = "Backups"
const SNAPSHOT_PREFIX: String = "focus-garden-"
const PROFILE_FILE: String = "profile.json"

## How many of the most recent snapshots to keep, regardless of when they were
## taken. Covers "undo the last few hours".
const MAX_SNAPSHOTS: int = 20

## How many days to keep a daily anchor for, on top of MAX_SNAPSHOTS. Covers
## "undo last week", which recency alone does not.
##
## WHY BOTH. Recency on its own is not a retention policy, it is a volume cap,
## and it fails the moment something writes quickly: twenty automated runs inside
## six minutes once evicted the snapshot holding a player's real save. A day's
## first snapshot is written before that day's play has changed anything, so it
## is the copy of that day worth keeping.
const MAX_DAILY_ANCHORS: int = 60

## Where the last successful snapshot went, for the caller to log or show. Set by
## `create`, and only meaningful immediately after it returns true.
static var last_snapshot_path: String = ""


## One snapshot on disk.
class Snapshot extends RefCounted:
	var path: String = ""
	var name: String = ""
	## Unix seconds parsed back out of the folder name, or 0 when unreadable.
	var taken_at_utc: float = 0.0

	func describe() -> String:
		if taken_at_utc <= 0.0:
			return name
		return TimeUtil.format_datetime(taken_at_utc)


## Where snapshots go: Documents\Focus Garden\Backups.
##
## Returns "" when the OS cannot tell us where Documents is, which is the signal
## for callers to fall back to the save directory rather than inventing a path.
static func default_directory() -> String:
	var documents := OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS)
	if documents.is_empty():
		return ""
	return documents.path_join(ROOT_FOLDER).path_join(BACKUPS_FOLDER)


## Writes a dated snapshot of everything in `save_dir` into `backup_dir`.
##
## Copies the files rather than re-serialising the in-memory state: a backup is
## meant to preserve what is ON DISK, including a save this build only partly
## understands. Re-serialising would quietly rewrite it into the current format
## and destroy the very thing worth keeping.
static func create(save_dir: String, backup_dir: String, now_utc: float = -1.0) -> bool:
	if backup_dir.is_empty():
		return false

	var profile_path := save_dir.path_join(PROFILE_FILE)
	if not FileAccess.file_exists(profile_path):
		# Nothing has been saved yet. Not a failure — there is simply nothing to
		# copy, and writing an empty folder would only be confusing.
		return false

	var stamp := _stamp(now_utc if now_utc >= 0.0 else Time.get_unix_time_from_system())
	var destination := backup_dir.path_join(SNAPSHOT_PREFIX + stamp)
	if DirAccess.make_dir_recursive_absolute(destination) != OK:
		return false
	if DirAccess.copy_absolute(profile_path, destination.path_join(PROFILE_FILE)) != OK:
		return false

	_copy_sessions(save_dir, destination)
	prune(backup_dir)
	last_snapshot_path = destination
	return true


## Snapshots in `backup_dir`, newest first.
static func list(backup_dir: String) -> Array[Snapshot]:
	var out: Array[Snapshot] = []
	if backup_dir.is_empty() or not DirAccess.dir_exists_absolute(backup_dir):
		return out

	var names := DirAccess.get_directories_at(backup_dir)
	# The stamp is zero-padded and ordered largest unit first, so a reverse
	# lexical sort is a reverse chronological one without parsing anything.
	var matching: Array[String] = []
	for name: String in names:
		if name.begins_with(SNAPSHOT_PREFIX):
			matching.append(name)
	matching.sort()
	matching.reverse()

	for name: String in matching:
		var snapshot := Snapshot.new()
		snapshot.name = name
		snapshot.path = backup_dir.path_join(name)
		snapshot.taken_at_utc = _parse_stamp(name)
		out.append(snapshot)
	return out


## The most recent snapshot, or null when there is none.
static func latest(backup_dir: String) -> Snapshot:
	var snapshots := list(backup_dir)
	return snapshots[0] if not snapshots.is_empty() else null


## Deletes snapshots that neither rule protects. Returns how many went.
##
## A snapshot survives if it is one of the newest `keep`, OR if it is the oldest
## one taken on a day inside the last `keep_daily` days that has any snapshots.
static func prune(
	backup_dir: String, keep: int = MAX_SNAPSHOTS, keep_daily: int = MAX_DAILY_ANCHORS
) -> int:
	var snapshots := list(backup_dir)
	var protected := {}

	for i in mini(maxi(0, keep), snapshots.size()):
		protected[snapshots[i].path] = true

	# `snapshots` is newest first, so the LAST entry seen for a day is that day's
	# oldest — which is the one each day nominates.
	var anchors := {}
	var day_order: Array[String] = []
	for snapshot: Snapshot in snapshots:
		var day := day_key(snapshot.name)
		if day.is_empty():
			continue
		if not anchors.has(day):
			day_order.append(day)
		anchors[day] = snapshot.path
	for i in mini(maxi(0, keep_daily), day_order.size()):
		protected[anchors[day_order[i]]] = true

	var removed := 0
	for snapshot: Snapshot in snapshots:
		if not protected.has(snapshot.path):
			if _remove_recursive(snapshot.path):
				removed += 1
	return removed


## The "YYYY-MM-DD" a snapshot folder belongs to, or "" if unreadable. Taken from
## the name rather than the filesystem so a folder copied between machines keeps
## the day it was actually written.
static func day_key(folder_name: String) -> String:
	var stamp := folder_name.substr(SNAPSHOT_PREFIX.length())
	var parts := stamp.split("_")
	return parts[0] if parts.size() == 2 and parts[0].length() == 10 else ""


## Copies a snapshot back over the live save.
##
## The CURRENT save is snapshotted first, under its own timestamp. Restoring is
## the one operation here that destroys something, and a player who restores the
## wrong date must have a way back — without this, "restore" would be a way to
## lose a garden rather than a way to recover one.
static func restore(snapshot_path: String, save_dir: String, backup_dir: String) -> bool:
	var source_profile := snapshot_path.path_join(PROFILE_FILE)
	if not FileAccess.file_exists(source_profile):
		return false

	create(save_dir, backup_dir)

	if DirAccess.make_dir_recursive_absolute(save_dir) != OK:
		return false
	if DirAccess.copy_absolute(source_profile, save_dir.path_join(PROFILE_FILE)) != OK:
		return false

	# Session shards are replaced wholesale rather than merged. A half-merged
	# history would double-count sessions, and §37's dataset is the one thing in
	# the app that has to stay exactly true.
	_remove_recursive(SessionStore.sessions_dir(save_dir))
	_copy_sessions(snapshot_path, save_dir)
	return true


# --- Internals ----------------------------------------------------------------

static func _copy_sessions(from_dir: String, to_dir: String) -> void:
	var source := SessionStore.sessions_dir(from_dir)
	if not DirAccess.dir_exists_absolute(source):
		return
	var target := SessionStore.sessions_dir(to_dir)
	if DirAccess.make_dir_recursive_absolute(target) != OK:
		return
	for file_name: String in DirAccess.get_files_at(source):
		if file_name.ends_with(".json"):
			DirAccess.copy_absolute(source.path_join(file_name), target.path_join(file_name))


## Folder-name timestamp: YYYY-MM-DD_HHMMSS, local time, because the player reads
## it and their own clock is the one that means anything to them.
static func _stamp(unix_seconds: float) -> String:
	var t := Time.get_datetime_dict_from_unix_time(int(unix_seconds))
	return "%04d-%02d-%02d_%02d%02d%02d" % [
		t["year"], t["month"], t["day"], t["hour"], t["minute"], t["second"]
	]


static func _parse_stamp(folder_name: String) -> float:
	var stamp := folder_name.substr(SNAPSHOT_PREFIX.length())
	var parts := stamp.split("_")
	if parts.size() != 2 or parts[1].length() != 6:
		return 0.0
	var date := parts[0].split("-")
	if date.size() != 3:
		return 0.0
	return Time.get_unix_time_from_datetime_dict({
		"year": int(date[0]), "month": int(date[1]), "day": int(date[2]),
		"hour": int(parts[1].substr(0, 2)),
		"minute": int(parts[1].substr(2, 2)),
		"second": int(parts[1].substr(4, 2)),
	})


## DirAccess.remove_absolute refuses a non-empty directory, so contents go first.
## One level of subdirectory is all a snapshot ever has, which is why this does
## not need to be recursive in the general sense.
static func _remove_recursive(path: String) -> bool:
	if not DirAccess.dir_exists_absolute(path):
		return false
	for sub_name: String in DirAccess.get_directories_at(path):
		_remove_recursive(path.path_join(sub_name))
	for file_name: String in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file_name))
	return DirAccess.remove_absolute(path) == OK
