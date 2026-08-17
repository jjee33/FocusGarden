extends TestCase
## GameClock: the elapsed-time rules that everything else depends on (§53).
##
## Clock sources are injected, so sleep, clock tampering and multi-hour sessions
## are all simulated instantly instead of being untestable in practice.

var _mono: Array[float] = [0.0]
var _wall: Array[float] = [0.0]
var _clock: GameClock


func before_each() -> void:
	# Arrays are reference types, so the lambdas below read the CURRENT value
	# rather than capturing a copy — that is what makes time advanceable.
	_mono = [1000.0]
	_wall = [1_700_000_000.0]
	_clock = GameClock.new()
	_clock.set_time_providers(
		func() -> float: return _mono[0],
		func() -> float: return _wall[0]
	)


func after_each() -> void:
	# The injected lambdas capture `self`, and this test case holds the clock —
	# a reference cycle GDScript cannot collect. Breaking it here keeps the suite
	# leak-free at exit.
	if _clock != null:
		_clock.reset_time_providers()
		_clock = null


func _advance(seconds: float) -> void:
	_mono[0] += seconds
	_wall[0] += seconds


func test_credits_elapsed_time() -> void:
	_clock.start()
	_advance(60.0)
	var sample := _clock.sample()
	assert_almost_eq(sample.credited_seconds, 60.0, "one minute of running time")
	assert_eq(sample.anomaly, FocusSession.Anomaly.NONE, "no anomaly on a normal run")


func test_idle_clock_credits_nothing() -> void:
	var sample := _clock.sample()
	assert_almost_eq(sample.credited_seconds, 0.0, "an unstarted clock credits nothing")


func test_pause_excludes_time() -> void:
	# §12: paused time must not count toward focus time.
	_clock.start()
	_advance(30.0)
	_clock.pause()
	_advance(600.0)
	_clock.resume()
	_advance(30.0)

	var sample := _clock.sample()
	assert_almost_eq(sample.credited_seconds, 60.0, "only unpaused time is credited")
	assert_almost_eq(sample.paused_seconds, 600.0, "pause duration is recorded")


func test_time_while_still_paused_is_excluded() -> void:
	# The in-progress pause is not yet in the accumulator, so this catches a
	# clock that only subtracts pauses after they end.
	_clock.start()
	_advance(30.0)
	_clock.pause()
	_advance(120.0)

	var sample := _clock.sample()
	assert_almost_eq(sample.credited_seconds, 30.0, "an open pause is excluded immediately")


func test_system_suspend_is_not_credited() -> void:
	# The machine slept for an hour: wall time jumps, monotonic does not.
	_clock.start()
	_advance(120.0)
	_wall[0] += 3600.0

	var sample := _clock.sample()
	assert_almost_eq(sample.credited_seconds, 120.0, "sleeping is not focusing")
	assert_eq(sample.anomaly, FocusSession.Anomaly.SUSPEND, "suspend is flagged")


func test_clock_wound_forward_is_not_credited() -> void:
	# §55: obviously invalid data is detected without invasive anti-cheat.
	_clock.start()
	_advance(60.0)
	_wall[0] += 86_400.0

	var sample := _clock.sample()
	assert_almost_eq(sample.credited_seconds, 60.0, "winding the clock earns nothing")
	assert_gt(float(sample.wall_elapsed_seconds), 86_000.0, "wall time did move")


func test_clock_set_backwards_preserves_earned_time() -> void:
	# The regression this exists to prevent: crediting min(monotonic, wall) would
	# throw away 100 real seconds because an NTP correction moved the clock back.
	_clock.start()
	_advance(100.0)
	_wall[0] -= 90.0

	var sample := _clock.sample()
	assert_almost_eq(sample.credited_seconds, 100.0, "a backwards clock cannot delete focus time")
	assert_eq(sample.anomaly, FocusSession.Anomaly.CLOCK_JUMP, "backwards jump is flagged")


func test_small_drift_is_not_an_anomaly() -> void:
	# Ordinary NTP slew must not spam anomaly flags on every tick.
	_clock.start()
	_advance(300.0)
	_wall[0] += 2.0

	var sample := _clock.sample()
	assert_eq(sample.anomaly, FocusSession.Anomaly.NONE, "2s of drift is tolerated")


func test_resume_without_pause_is_ignored() -> void:
	_clock.start()
	_advance(10.0)
	_clock.resume()
	_advance(10.0)
	assert_almost_eq(_clock.sample().credited_seconds, 20.0, "a stray resume changes nothing")


func test_recovered_clock_uses_wall_time() -> void:
	# After a restart the monotonic origin is gone, so a recovered session must
	# fall back to wall time or it would credit zero for real work.
	_clock.start()
	_advance(45.0)

	var restored := GameClock.from_dict(_clock.to_dict())
	# Re-inject the simulated clocks: from_dict installs the real system ones,
	# which would make this assert against wall-clock "now" and pass for the
	# wrong reason.
	restored.set_time_providers(
		func() -> float: return _mono[0],
		func() -> float: return _wall[0]
	)
	var sample := restored.sample()
	assert_almost_eq(sample.credited_seconds, 45.0, "recovered sessions measure from the stored wall anchor")
