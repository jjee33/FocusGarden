extends SceneTree
## End-to-end timer verification against §59's acceptance criteria.
##
##     ... --headless --path . --script res://tools/verify_timer.gd
##
## Runs real sessions against the real system clock, because the things §59 asks
## us to prove — "does not noticeably drift", "pause time is excluded",
## "finished sessions create valid session records" — are properties of the whole
## timer, not of any one class. The unit tests use injected clocks and cannot
## observe drift at all.
##
## Takes about 25 seconds. Exits non-zero on failure.

## Drift tolerance over the measured run. The timer derives elapsed time from
## timestamps, so real drift should be microseconds; this is loose enough not to
## be flaky on a busy machine and tight enough to catch delta-accumulation.
const DRIFT_TOLERANCE_SECONDS: float = 0.25
const STALL_SECONDS: float = 2.0

var _app_state: Node
var _timer_manager: Node
var _problems: PackedStringArray = PackedStringArray()


func _init() -> void:
	await process_frame
	_app_state = root.get_node("/root/AppState")
	_timer_manager = root.get_node("/root/TimerManager")

	print("\n=== Timer verification ===\n")
	await _check_drift()
	await _check_stall_resilience()
	await _check_pause_excluded()
	await _check_completed_session_record()
	_cleanup()

	print("\n--------------------------------------------")
	if _problems.is_empty():
		print("RESULT: PASS")
		print("--------------------------------------------\n")
		quit(0)
		return
	print("RESULT: FAIL")
	for problem: String in _problems:
		print("  - %s" % problem)
	print("--------------------------------------------\n")
	quit(1)


## Accuracy against an independent wall-clock reading.
func _check_drift() -> void:
	print("• drift over a 10 second run")
	var started := Time.get_unix_time_from_system()
	_timer_manager.start_focus("verify", "", 5.0)
	await _wait(10.0)

	var observed: float = _timer_manager.get_elapsed_seconds()
	var actual := Time.get_unix_time_from_system() - started
	var drift: float = absf(observed - actual)
	print("    measured %.3fs, wall %.3fs, drift %.4fs" % [observed, actual, drift])
	if drift > DRIFT_TOLERANCE_SECONDS:
		_problems.append("drift of %.3fs exceeds the %.2fs tolerance" % [drift, DRIFT_TOLERANCE_SECONDS])

	_timer_manager.cancel("verification")


## A blocked main thread is the same class of failure as a minimized window: no
## frames are processed. A delta-accumulating timer loses this time entirely.
func _check_stall_resilience() -> void:
	print("• a %.0f second main-thread stall" % STALL_SECONDS)
	_timer_manager.start_focus("verify", "", 5.0)
	await _wait(1.0)

	var before: float = _timer_manager.get_elapsed_seconds()
	# Busy-wait: deliberately starves the frame loop rather than yielding to it.
	var stall_until := Time.get_ticks_msec() + int(STALL_SECONDS * 1000.0)
	while Time.get_ticks_msec() < stall_until:
		pass
	var after: float = _timer_manager.get_elapsed_seconds()

	var counted := after - before
	print("    counted %.3fs across the stall" % counted)
	if absf(counted - STALL_SECONDS) > DRIFT_TOLERANCE_SECONDS:
		_problems.append(
			"stalled time was mismeasured: counted %.3fs of %.1fs" % [counted, STALL_SECONDS]
		)

	_timer_manager.cancel("verification")


## §12: paused time must not count toward focus time.
func _check_pause_excluded() -> void:
	print("• pause exclusion")
	_timer_manager.start_focus("verify", "", 5.0)
	await _wait(2.0)
	_timer_manager.pause()

	var at_pause: float = _timer_manager.get_elapsed_seconds()
	await _wait(3.0)
	var after_pause: float = _timer_manager.get_elapsed_seconds()

	var leaked := after_pause - at_pause
	print("    %.3fs elapsed while paused (should be ~0)" % leaked)
	if leaked > DRIFT_TOLERANCE_SECONDS:
		_problems.append("%.3fs leaked into focus time while paused" % leaked)

	_timer_manager.resume()
	await _wait(1.0)
	if _timer_manager.get_elapsed_seconds() <= after_pause:
		_problems.append("the clock did not resume counting after resume()")

	_timer_manager.cancel("verification")


## §59: finished sessions create valid session records.
func _check_completed_session_record() -> void:
	print("• a session that runs to completion")
	var before: int = _app_state.sessions.size()
	# 0.05 minutes = 3 seconds, so the run completes on its own.
	_timer_manager.start_focus("verify", "", 0.05)
	await _wait(5.0)

	if _timer_manager.is_active():
		_problems.append("the session did not finish on its own")
		_timer_manager.cancel("verification")
		return

	if _app_state.sessions.size() != before + 1:
		_problems.append("no session record was created")
		return

	var session: FocusSession = _app_state.sessions[_app_state.sessions.size() - 1]
	print("    recorded %.3f min, completion %d, xp %d" % [
		session.actual_focus_minutes, int(session.completion), session.xp_earned
	])

	if session.completion != FocusSession.Completion.COMPLETED:
		_problems.append("completion state was %d, expected COMPLETED" % int(session.completion))
	if not is_equal_approx(session.actual_focus_minutes, 0.05):
		_problems.append(
			"credited %.4f min, expected exactly the intended 0.05" % session.actual_focus_minutes
		)
	if not session.awards_applied:
		_problems.append("awards_applied was not set; a reload could double-award")
	if session.date_key.is_empty():
		_problems.append("the session has no date key and cannot appear on the calendar")
	if session.id.is_empty():
		_problems.append("the session has no id")


func _wait(seconds: float) -> void:
	var deadline := Time.get_unix_time_from_system() + seconds
	while Time.get_unix_time_from_system() < deadline:
		await process_frame


## Removes everything this probe wrote, so it never pollutes a real save.
func _cleanup() -> void:
	var save_manager := root.get_node("/root/SaveManager")
	var save_dir: String = save_manager.get_save_dir()
	_purge_dir(save_manager.get_backup_dir())
	_purge_dir(SessionStore.sessions_dir(save_dir))
	_purge_dir(save_dir)


func _purge_dir(dir_path: String) -> void:
	if not DirAccess.dir_exists_absolute(dir_path):
		return
	for file_name: String in DirAccess.get_files_at(dir_path):
		DirAccess.remove_absolute(dir_path.path_join(file_name))
	DirAccess.remove_absolute(dir_path)
