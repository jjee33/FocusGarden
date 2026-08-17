extends Node
## Focus timer state and system-time calculations (§40).
##
## Owns: the session lifecycle (start/pause/resume/cancel/finish) and the truth
## about how much time has elapsed.
## Must never: award XP, grow a plant, or evaluate an achievement. When a session
## ends it hands the record to SessionPipeline and stops caring.
##
## All elapsed time comes from GameClock, which derives it from timestamps rather
## than frame deltas (§8). Nothing here accumulates a delta, which is why a
## minimized window, a stalled frame, or a dropped frame rate cannot affect the
## result.
##
## MILESTONE STATUS: the lifecycle and timing below are complete and tested.
## Presets, auto-start chaining, ambient audio and notifications are Milestone 1
## and are deliberately absent rather than stubbed.

## How often the countdown is republished. A repeating timer rather than
## _process, so an idle app does no per-frame work (§44). The displayed value is
## still exact — it is recomputed from timestamps on every tick.
const TICK_INTERVAL_SECONDS: float = 0.1

## Gap between a session finishing and an auto-started one beginning. Long enough
## that the completion summary is read rather than flashing past, short enough
## that it does not feel like a stall.
const AUTO_START_DELAY_SECONDS: float = 4.0

enum State { IDLE, RUNNING, PAUSED }

var state: State = State.IDLE
var current_session: FocusSession = null

var _clock: GameClock = GameClock.new()
var _tick_timer: Timer = null
var _auto_start_timer: Timer = null

## Context carried between chained sessions, so an auto-started break knows which
## project it belongs to without the UI having to re-supply it.
var _last_project_id: String = ""
var _last_plant_uid: String = ""
## Set while an auto-start is counting down, so the UI can show what is coming
## and offer to cancel it.
var _pending_kind: FocusSession.Kind = FocusSession.Kind.FOCUS
var _auto_start_pending: bool = false


func _ready() -> void:
	_tick_timer = Timer.new()
	_tick_timer.wait_time = TICK_INTERVAL_SECONDS
	_tick_timer.one_shot = false
	_tick_timer.timeout.connect(_on_tick)
	add_child(_tick_timer)

	_auto_start_timer = Timer.new()
	_auto_start_timer.one_shot = true
	_auto_start_timer.timeout.connect(_on_auto_start_elapsed)
	add_child(_auto_start_timer)


## Begins a session. Returns false when one is already running, so a double-click
## on Start cannot create two concurrent sessions.
func start_session(
	kind: FocusSession.Kind, duration_minutes: float, project_id: String, plant_uid: String
) -> bool:
	if state != State.IDLE:
		GameLog.warn(GameLog.Category.TIMER, "Refused to start: a session is already active.")
		return false

	# Any deliberate start supersedes a queued one, however it was reached.
	cancel_auto_start()
	current_session = FocusSession.create(kind, duration_minutes, project_id, plant_uid)
	_clock.start()
	state = State.RUNNING
	_tick_timer.start()
	_persist_in_flight()

	GameLog.info(
		GameLog.Category.TIMER,
		"Started %s session %s." % [TimeUtil.format_duration(duration_minutes), current_session.id]
	)
	EventBus.session_started.emit(current_session.id)
	return true


# --- Presets and the pomodoro cycle (§8) -------------------------------------

## Configured length for a session kind. The one place preset durations are read,
## so changing a setting changes every entry point at once.
func get_duration_for_kind(kind: FocusSession.Kind) -> float:
	var settings := AppState.get_settings()
	match kind:
		FocusSession.Kind.SHORT_BREAK:
			return settings.short_break_minutes
		FocusSession.Kind.LONG_BREAK:
			return settings.long_break_minutes
		_:
			return settings.focus_duration_minutes


## Starts a focus session. A duration of -1 uses the configured default.
func start_focus(project_id: String, plant_uid: String = "", duration_minutes: float = -1.0) -> bool:
	cancel_auto_start()
	_last_project_id = project_id
	_last_plant_uid = plant_uid
	var duration := (
		duration_minutes if duration_minutes > 0.0
		else get_duration_for_kind(FocusSession.Kind.FOCUS)
	)
	return start_session(FocusSession.Kind.FOCUS, duration, project_id, plant_uid)


## Starts whichever break is due, short or long.
func start_break(duration_minutes: float = -1.0) -> bool:
	cancel_auto_start()
	var kind := get_next_break_kind()
	var duration := duration_minutes if duration_minutes > 0.0 else get_duration_for_kind(kind)
	return start_session(kind, duration, _last_project_id, "")


## Whether the next break is the long one. The cycle counter advances only on
## COMPLETED focus sessions, so cancelling out of a session does not push the
## player toward an unearned long break.
func get_next_break_kind() -> FocusSession.Kind:
	return SessionCycle.next_break_kind(
		AppState.data.profile.focus_sessions_in_cycle,
		AppState.get_settings().sessions_before_long_break
	)


## What would naturally come next: a break after focus, focus after a break.
func get_next_session_kind() -> FocusSession.Kind:
	if current_session != null and current_session.is_break():
		return FocusSession.Kind.FOCUS
	return get_next_break_kind()


## Position within the current cycle, 1-based, for a "3 of 4" indicator.
func get_cycle_position() -> int:
	return SessionCycle.position(
		AppState.data.profile.focus_sessions_in_cycle,
		AppState.get_settings().sessions_before_long_break
	)


# --- Auto-start chaining (§8) ------------------------------------------------

func is_auto_start_pending() -> bool:
	return _auto_start_pending


func get_pending_kind() -> FocusSession.Kind:
	return _pending_kind


## Seconds until the queued session begins, for the countdown on the completion
## screen. Zero when nothing is queued.
func get_auto_start_remaining() -> float:
	return _auto_start_timer.time_left if _auto_start_pending else 0.0


## Stops a queued auto-start. Called whenever the player takes any deliberate
## action — §3 rules out the app starting something the player has moved on from.
func cancel_auto_start() -> void:
	if not _auto_start_pending:
		return
	_auto_start_timer.stop()
	_auto_start_pending = false
	EventBus.auto_start_cancelled.emit()


func _schedule_auto_start(kind: FocusSession.Kind) -> void:
	var settings := AppState.get_settings()
	var wanted := (
		settings.auto_start_breaks if kind != FocusSession.Kind.FOCUS else settings.auto_start_focus
	)
	if not wanted:
		return

	_pending_kind = kind
	_auto_start_pending = true
	_auto_start_timer.start(AUTO_START_DELAY_SECONDS)
	EventBus.auto_start_scheduled.emit(AUTO_START_DELAY_SECONDS)


func _on_auto_start_elapsed() -> void:
	if not _auto_start_pending:
		return
	_auto_start_pending = false

	if _pending_kind == FocusSession.Kind.FOCUS:
		start_focus(_last_project_id, _last_plant_uid)
	else:
		start_break()


func pause() -> bool:
	if state != State.RUNNING:
		return false
	_clock.pause()
	state = State.PAUSED
	_persist_in_flight()
	EventBus.session_paused.emit(current_session.id)
	return true


func resume() -> bool:
	if state != State.PAUSED:
		return false
	_clock.resume()
	state = State.RUNNING
	_persist_in_flight()
	EventBus.session_resumed.emit(current_session.id)
	return true


## Discards the session. The record is still written with CANCELLED so the
## interruption appears in analytics (§12) — it simply earns no credit.
func cancel(reason: String = "") -> void:
	cancel_auto_start()
	if state == State.IDLE or current_session == null:
		return
	var session := _finalize(FocusSession.Completion.CANCELLED)
	session.interruption_reason = reason
	session.actual_focus_minutes = 0.0
	EventBus.session_cancelled.emit(session.id)
	SessionPipeline.apply(session)
	_reset()


## Ends the session early, crediting the time actually focused (§12: never
## silently lose time the user legitimately focused).
func finish_early() -> SessionPipeline.Outcome:
	return _complete(FocusSession.Completion.ENDED_EARLY)


## Seconds left in the intended duration. Negative values are clamped, so a
## session that overran while the app was busy reads as 0 rather than counting up.
func get_remaining_seconds() -> float:
	if current_session == null:
		return 0.0
	var total := current_session.intended_duration_minutes * TimeUtil.SECONDS_PER_MINUTE
	return maxf(0.0, total - _clock.sample().credited_seconds)


func get_elapsed_seconds() -> float:
	return _clock.sample().credited_seconds if current_session != null else 0.0


## 0..1 through the intended duration, for the progress ring.
func get_progress_ratio() -> float:
	if current_session == null or current_session.intended_duration_minutes <= 0.0:
		return 0.0
	var total := current_session.intended_duration_minutes * TimeUtil.SECONDS_PER_MINUTE
	return clampf(_clock.sample().credited_seconds / total, 0.0, 1.0)


func is_active() -> bool:
	return state != State.IDLE


## Restores a session that was interrupted by the app closing or crashing (§54).
##
## Returns the recovered session WITHOUT applying it: only the player knows
## whether they were actually focusing while the app was shut, so the UI asks
## before crediting. Returns null when there is nothing to recover.
func recover_in_flight_session() -> FocusSession:
	var stored := AppState.data.in_flight_session
	if stored.is_empty():
		return null

	var session := FocusSession.from_dict(DictUtil.get_dict(stored, "session"))
	if session.id.is_empty() or session.awards_applied:
		AppState.data.in_flight_session = {}
		return null

	var clock := GameClock.from_dict(DictUtil.get_dict(stored, "clock"))
	var sample := clock.sample()
	session.completion = FocusSession.Completion.ABANDONED
	session.ended_at_utc = Time.get_unix_time_from_system()
	session.paused_minutes = sample.paused_seconds / TimeUtil.SECONDS_PER_MINUTE
	session.actual_focus_minutes = SessionCredit.settle_recovered(
		sample.credited_seconds / TimeUtil.SECONDS_PER_MINUTE,
		session.intended_duration_minutes
	)
	session.anomaly = sample.anomaly
	session.interruption_reason = "Application closed during the session."

	GameLog.info(GameLog.Category.TIMER, "Recovered interrupted session %s." % session.id)
	return session


## Clears a recovered session the player chose not to keep.
func discard_in_flight_session() -> void:
	AppState.data.in_flight_session = {}
	AppState.save_now()


func _on_tick() -> void:
	if state != State.RUNNING or current_session == null:
		return

	var sample := _clock.sample()
	if sample.anomaly != FocusSession.Anomaly.NONE:
		# Surfaced immediately so the UI can note it, but the session continues —
		# §55 says preserve and flag, never interrupt or punish.
		EventBus.session_anomaly_detected.emit(
			current_session.id, _anomaly_name(sample.anomaly)
		)

	var total := current_session.intended_duration_minutes * TimeUtil.SECONDS_PER_MINUTE
	EventBus.session_tick.emit(maxf(0.0, total - sample.credited_seconds))

	if sample.credited_seconds >= total:
		_complete(FocusSession.Completion.COMPLETED)


func _complete(completion: FocusSession.Completion) -> SessionPipeline.Outcome:
	if current_session == null:
		return SessionPipeline.Outcome.new()

	var session := _finalize(completion)
	# Captured before _reset clears current_session, since the next kind depends
	# on what just finished.
	var was_focus := session.is_focus()

	EventBus.session_completed.emit(session.id)
	var outcome := SessionPipeline.apply(session)

	if SessionCycle.should_advance(session.kind, completion):
		AppState.data.profile.focus_sessions_in_cycle += 1
		AppState.save_now()

	_reset()
	_schedule_auto_start(FocusSession.Kind.FOCUS if not was_focus else get_next_break_kind())
	return outcome


func _finalize(completion: FocusSession.Completion) -> FocusSession:
	var sample := _clock.sample()
	var session := current_session
	session.ended_at_utc = Time.get_unix_time_from_system()
	session.completion = completion
	session.paused_minutes = sample.paused_seconds / TimeUtil.SECONDS_PER_MINUTE
	session.anomaly = sample.anomaly

	session.actual_focus_minutes = SessionCredit.settle(
		completion,
		sample.credited_seconds / TimeUtil.SECONDS_PER_MINUTE,
		session.intended_duration_minutes
	)

	_tick_timer.stop()
	_clock.stop()
	AppState.data.in_flight_session = {}
	return session


func _reset() -> void:
	current_session = null
	state = State.IDLE
	_clock = GameClock.new()


## Writes the running session to the save so it survives an unexpected exit.
## Called on every state change rather than every tick: a tick-rate write would
## hammer the disk for hours (§44).
func _persist_in_flight() -> void:
	if current_session == null:
		return
	AppState.data.in_flight_session = {
		"session": current_session.to_dict(),
		"clock": _clock.to_dict(),
	}
	AppState.save_now()


static func _anomaly_name(anomaly: FocusSession.Anomaly) -> String:
	match anomaly:
		FocusSession.Anomaly.SUSPEND:
			return "suspend"
		FocusSession.Anomaly.CLOCK_JUMP:
			return "clock_jump"
		FocusSession.Anomaly.NEGATIVE_DURATION:
			return "negative_duration"
		_:
			return "none"
