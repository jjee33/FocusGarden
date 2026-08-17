class_name GameClock
extends RefCounted
## Authoritative elapsed-time measurement for focus sessions (§8, §54, §55).
##
## THE RULE: elapsed time is derived from timestamps, never accumulated frame
## deltas. §8 forbids delta accumulation outright, and it is also why the timer
## survives a minimized window, a stalled frame, or a dropped frame rate — none
## of those touch a timestamp.
##
## THE DUAL CLOCK: two clocks run at once.
##   * monotonic (Time.get_ticks_usec) — cannot be changed by the user or the OS,
##     but does not advance while the machine is asleep.
##   * wall (Time.get_unix_time_from_system) — survives sleep and app restarts,
##     but moves when the clock is set, when NTP corrects, and at DST boundaries.
##     Godot's own docs warn it must never be used for precise timing.
##
## THE RULE: credited time is ALWAYS the monotonic elapsed time. The wall clock
## is used only to DETECT anomalies and to survive restarts — never to decide
## how much credit a session earns. Working through the cases:
##   * machine slept 3 hours mid-session -> wall advances 3h, monotonic does not
##     advance while suspended, so credit is the couple of minutes actually spent
##     awake. The player was asleep, not focusing.
##   * user winds the clock forward to farm plants -> wall inflates, monotonic is
##     untouched, credit stays honest. That is §55's "detect obviously invalid
##     data" without building invasive anti-cheat.
##   * clock corrected backwards mid-session (NTP, DST, manual fix) -> wall goes
##     backwards, monotonic keeps counting, credit is unaffected.
##
## An earlier draft credited min(monotonic, wall). That is wrong for the third
## case: a backwards clock correction would silently delete real focus time the
## player had earned, which §12 forbids outright.
##
## Divergence is never punished. The session is kept and flagged (§55).

## Divergence beyond this is treated as an anomaly rather than clock jitter.
## Generous enough that ordinary NTP drift never trips it.
const ANOMALY_THRESHOLD_SECONDS: float = 5.0

enum State { IDLE, RUNNING, PAUSED }

## Result of a measurement. Not a Dictionary so callers get typed fields and a
## typo becomes a parse error.
class Sample extends RefCounted:
	var credited_seconds: float = 0.0
	var paused_seconds: float = 0.0
	var anomaly: FocusSession.Anomaly = FocusSession.Anomaly.NONE
	var wall_elapsed_seconds: float = 0.0
	var monotonic_elapsed_seconds: float = 0.0


var state: State = State.IDLE

var _wall_start: float = 0.0
var _mono_start: float = 0.0
## Paused time accumulated across all previous pauses, measured monotonically —
## pauses must not count toward focus time (§12).
var _paused_accumulated: float = 0.0
var _pause_began_mono: float = 0.0
## Set when the clock is rebuilt from a persisted session after an app restart.
## Monotonic history is gone in that case, so measurement falls back to wall time.
var _recovered_from_save: bool = false

var _mono_provider: Callable = _default_monotonic
var _wall_provider: Callable = _default_wall


static func _default_monotonic() -> float:
	return float(Time.get_ticks_usec()) / 1000000.0


static func _default_wall() -> float:
	return Time.get_unix_time_from_system()


## Injects clock sources so tests can simulate sleep, clock jumps, and long
## sessions without waiting or touching the system clock.
func set_time_providers(monotonic: Callable, wall: Callable) -> void:
	_mono_provider = monotonic
	_wall_provider = wall


## Restores the real system clocks.
##
## Callers that injected a lambda capturing an object which also holds this clock
## have created a reference cycle, and GDScript's RefCounted cannot collect one.
## Calling this when finished breaks it. Tests must do so in teardown.
func reset_time_providers() -> void:
	_mono_provider = _default_monotonic
	_wall_provider = _default_wall


func start() -> void:
	_wall_start = _wall_provider.call()
	_mono_start = _mono_provider.call()
	_paused_accumulated = 0.0
	_pause_began_mono = 0.0
	_recovered_from_save = false
	state = State.RUNNING


func pause() -> void:
	if state != State.RUNNING:
		return
	_pause_began_mono = _mono_provider.call()
	state = State.PAUSED


func resume() -> void:
	if state != State.PAUSED:
		return
	# Pause length is measured monotonically. Using wall time here would let a
	# clock change while paused silently add or remove focus credit.
	_paused_accumulated += maxf(0.0, _mono_provider.call() - _pause_began_mono)
	_pause_began_mono = 0.0
	state = State.RUNNING


func stop() -> void:
	state = State.IDLE


## Current measurement. Safe to call every frame — it is pure arithmetic over
## four floats and allocates one small object (§44).
func sample() -> Sample:
	var result := Sample.new()
	if state == State.IDLE and _wall_start == 0.0:
		return result

	var now_mono: float = _mono_provider.call()
	var now_wall: float = _wall_provider.call()

	# A pause still in progress is not yet in the accumulator.
	var paused := _paused_accumulated
	if state == State.PAUSED:
		paused += maxf(0.0, now_mono - _pause_began_mono)

	var mono_elapsed := (now_mono - _mono_start) - paused
	var wall_elapsed := (now_wall - _wall_start) - paused
	result.monotonic_elapsed_seconds = mono_elapsed
	result.wall_elapsed_seconds = wall_elapsed
	result.paused_seconds = paused

	if _recovered_from_save:
		# Monotonic history did not survive the restart, so it would read as
		# near-zero and wrongly zero out a legitimate session. Wall time is all
		# we have; the session is already flagged as recovered by the caller.
		result.credited_seconds = maxf(0.0, wall_elapsed)
		return result

	var divergence := wall_elapsed - mono_elapsed
	if divergence > ANOMALY_THRESHOLD_SECONDS:
		# Wall ran ahead of monotonic. Overwhelmingly the common cause is system
		# suspend; a forward clock change looks identical from here. We label it
		# SUSPEND because that is the honest most-likely explanation, and either
		# way the credited figure is the same conservative one.
		result.anomaly = FocusSession.Anomaly.SUSPEND
	elif divergence < -ANOMALY_THRESHOLD_SECONDS:
		# Wall went backwards relative to monotonic: the clock was set back,
		# NTP corrected, or DST rolled. Monotonic cannot do this.
		result.anomaly = FocusSession.Anomaly.CLOCK_JUMP

	# Monotonic is the credited figure. See the class comment for why wall time
	# must not participate in this decision.
	var credited := mono_elapsed
	if credited < 0.0:
		# Monotonic time cannot decrease, so this means the accumulated pause
		# exceeds the elapsed time — a bookkeeping impossibility. Preserve the
		# session, credit nothing, flag it (§55).
		result.anomaly = FocusSession.Anomaly.NEGATIVE_DURATION
		credited = 0.0
	result.credited_seconds = credited
	return result


## Serializes the in-flight clock so a session survives the app closing (§54).
## Only wall time is stored: monotonic values are meaningless across a restart.
func to_dict() -> Dictionary:
	return {
		"wall_start": _wall_start,
		"paused_accumulated": _paused_accumulated,
		"state": int(state),
	}


## Rebuilds a clock from a persisted in-flight session. The result measures with
## wall time only and callers must flag the session ABANDONED/recovered, because
## we cannot know whether the machine was asleep while the app was closed.
static func from_dict(data: Dictionary) -> GameClock:
	var clock := GameClock.new()
	clock._wall_start = DictUtil.get_float(data, "wall_start")
	clock._paused_accumulated = maxf(0.0, DictUtil.get_float(data, "paused_accumulated"))
	var raw_state := DictUtil.get_int(data, "state", int(State.IDLE))
	clock.state = (
		raw_state as State if raw_state >= 0 and raw_state <= int(State.PAUSED) else State.IDLE
	)
	clock._mono_start = clock._mono_provider.call()
	clock._recovered_from_save = true
	return clock
