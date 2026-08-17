class_name SessionStore
extends RefCounted
## Year-sharded persistence for session records (§37).
##
## Session history is the authoritative analytics dataset and grows forever —
## §37 explicitly forbids storing only aggregate totals. Sharding by year means a
## save after a 25-minute pomodoro rewrites only the current year's file, not a
## decade of history, which is what keeps §64's "large session datasets remain
## responsive" true as the dataset grows.
##
## The shard key is the session's stored `date_key`, so a session never moves
## between shards even if the machine's timezone changes later.

const SESSIONS_SUBDIR: String = "sessions"
const FALLBACK_YEAR: String = "unknown"


static func sessions_dir(save_dir: String) -> String:
	return save_dir.path_join(SESSIONS_SUBDIR)


static func shard_path(save_dir: String, year: String) -> String:
	return sessions_dir(save_dir).path_join("%s.json" % year)


## Year portion of a date key. Falls back to a dedicated shard rather than
## dropping a record whose key is malformed.
static func year_for_session(session: FocusSession) -> String:
	if session.date_key.length() >= 4 and session.date_key.substr(0, 4).is_valid_int():
		return session.date_key.substr(0, 4)
	return FALLBACK_YEAR


## Every session across every shard, sorted oldest first.
static func load_all(save_dir: String) -> Array[FocusSession]:
	var sessions: Array[FocusSession] = []
	var dir := sessions_dir(save_dir)
	if not DirAccess.dir_exists_absolute(dir):
		return sessions

	for file_name: String in DirAccess.get_files_at(dir):
		if not file_name.ends_with(".json"):
			continue
		var result := AtomicFile.read_json_with_recovery(dir.path_join(file_name), dir)
		if not result.exists():
			continue
		for entry: Variant in DictUtil.get_array(result.data, "sessions"):
			if entry is Dictionary:
				var session := FocusSession.from_dict(entry)
				if not session.id.is_empty():
					sessions.append(session)

	sessions.sort_custom(
		func(a: FocusSession, b: FocusSession) -> bool: return a.started_at_utc < b.started_at_utc
	)
	return sessions


## Writes every shard touched by `sessions`. Shards not represented are left
## alone, so rewriting the current year never risks older history.
static func save_all(save_dir: String, sessions: Array[FocusSession]) -> Error:
	var by_year := {}
	for session: FocusSession in sessions:
		var year := year_for_session(session)
		if not by_year.has(year):
			by_year[year] = []
		by_year[year].append(session.to_dict())

	var dir := sessions_dir(save_dir)
	for year: String in by_year:
		var payload := {"year": year, "sessions": by_year[year]}
		var error := AtomicFile.write_json(shard_path(save_dir, year), payload, dir)
		if error != OK:
			return error
	return OK


## Appends one session to its year shard, rewriting only that shard.
## Replaces an existing record with the same id rather than duplicating it, so a
## re-save of an updated session (for example after awards are applied) does not
## double the row and double every total derived from it.
static func append(save_dir: String, session: FocusSession) -> Error:
	var year := year_for_session(session)
	var path := shard_path(save_dir, year)
	var dir := sessions_dir(save_dir)

	var existing := AtomicFile.read_json_with_recovery(path, dir)
	var rows: Array = DictUtil.get_array(existing.data, "sessions")

	var replaced := false
	for i in rows.size():
		var row: Variant = rows[i]
		if row is Dictionary and DictUtil.get_string(row, "id") == session.id:
			rows[i] = session.to_dict()
			replaced = true
			break
	if not replaced:
		rows.append(session.to_dict())

	return AtomicFile.write_json(path, {"year": year, "sessions": rows}, dir)
