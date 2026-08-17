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

enum State { IDLE, RUNNING, PAUSED }

var state: State = State.IDLE
var current_session: FocusSession = null

var _clock: GameClock = GameClock.new()
var _tick_timer: Timer = null


func _ready() -> void:
	_tick_timer = Timer.new()
	_tick_timer.wait_time = TICK_INTERVAL_SECONDS
	_tick_timer.one_shot = false
	_tick_timer.timeout.connect(_on_tick)
	add_child(_tick_timer)


## Begins a session. Returns false when one is already running, so a double-click
## on Start cannot create two concurrent sessions.
func start_session(
	kind: FocusSession.Kind, duration_minutes: float, project_id: String, plant_uid: String
) -> bool:
	if state != State.IDLE:
		GameLog.warn(GameLog.Category.TIMER, "Refused to start: a session is already active.")
		return false

	current_session = FocusSession.create(kind, duration_minutes, project_id, plant_uid)
	_clock.start()
	state = State.RUNNING
	_tick_timer.start()
	_persist_in_flight()

	GameLog.info(
		GameLog.Category.TIMER,
		"Started %.0f-minute session %s." % [duration_minutes, current_session.id]
	)
	EventBus.session_started.emit(current_session.id)
	return true


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
	# Capped at the intended duration: the app may have been closed for days, and
	# a 3-day "focus session" is obviously not real time focused.
	session.actual_focus_minutes = minf(
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
	EventBus.session_completed.emit(session.id)
	var outcome := SessionPipeline.apply(session)
	_reset()
	return outcome


func _finalize(completion: FocusSession.Completion) -> FocusSession:
	var sample := _clock.sample()
	var session := current_session
	session.ended_at_utc = Time.get_unix_time_from_system()
	session.completion = completion
	session.paused_minutes = sample.paused_seconds / TimeUtil.SECONDS_PER_MINUTE
	session.anomaly = sample.anomaly

	var credited := sample.credited_seconds / TimeUtil.SECONDS_PER_MINUTE
	if completion == FocusSession.Completion.COMPLETED:
		# A completed session is worth its intended duration exactly. Using the
		# raw sample would credit the fraction of a tick past the finish line and
		# make a "25 minute" session record as 25.02.
		credited = minf(credited, session.intended_duration_minutes)
	session.actual_focus_minutes = maxf(0.0, credited)

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
