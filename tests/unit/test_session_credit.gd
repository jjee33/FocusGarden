extends TestCase
## SessionCredit: how much of a measured session counts (§12).


func test_completed_session_credits_exactly_the_intended_duration() -> void:
	# The raw measurement overshoots by part of a tick past the finish line.
	# Without the clamp a "25 minute" session records as 25.02 and every total
	# derived from it drifts upward.
	assert_almost_eq(
		SessionCredit.settle(FocusSession.Completion.COMPLETED, 25.03, 25.0), 25.0,
		"overshoot is trimmed"
	)


func test_completed_session_is_not_inflated() -> void:
	# If the clock somehow measured less, credit the smaller honest figure rather
	# than handing out the full duration.
	assert_almost_eq(
		SessionCredit.settle(FocusSession.Completion.COMPLETED, 20.0, 25.0), 20.0,
		"a short measurement is not rounded up to the intended length"
	)


func test_ending_early_credits_time_actually_focused() -> void:
	# §12: never silently lose time the user legitimately focused.
	assert_almost_eq(
		SessionCredit.settle(FocusSession.Completion.ENDED_EARLY, 11.5, 25.0), 11.5,
		"the real focused time is kept"
	)


func test_cancelling_credits_nothing() -> void:
	assert_almost_eq(
		SessionCredit.settle(FocusSession.Completion.CANCELLED, 20.0, 25.0), 0.0,
		"a discarded session earns no credit"
	)


func test_negative_measurements_clamp_to_zero() -> void:
	assert_almost_eq(
		SessionCredit.settle(FocusSession.Completion.ENDED_EARLY, -5.0, 25.0), 0.0,
		"an impossible duration credits nothing rather than subtracting"
	)


func test_abandoned_session_keeps_its_measured_time() -> void:
	assert_almost_eq(
		SessionCredit.settle(FocusSession.Completion.ABANDONED, 8.0, 25.0), 8.0,
		"an interrupted session keeps what it measured"
	)


func test_recovered_session_is_capped_at_the_intended_length() -> void:
	# The app may have been closed for days. Three days of wall time is obviously
	# not three days of focus.
	assert_almost_eq(
		SessionCredit.settle_recovered(4320.0, 25.0), 25.0,
		"a multi-day gap is capped at the session length"
	)
	assert_almost_eq(
		SessionCredit.settle_recovered(12.0, 25.0), 12.0,
		"a plausible figure passes through"
	)
	assert_almost_eq(
		SessionCredit.settle_recovered(-3.0, 25.0), 0.0, "a negative figure clamps to zero"
	)


func test_growth_threshold() -> void:
	assert_true(
		SessionCredit.earns_plant_growth(FocusSession.Kind.FOCUS, 5.0, 1.0),
		"a five-minute session clears a one-minute threshold"
	)
	assert_false(
		SessionCredit.earns_plant_growth(FocusSession.Kind.FOCUS, 0.5, 1.0),
		"a thirty-second session does not"
	)
	assert_true(
		SessionCredit.earns_plant_growth(FocusSession.Kind.FOCUS, 1.0, 1.0),
		"exactly the threshold counts"
	)


func test_breaks_never_grow_plants() -> void:
	assert_false(
		SessionCredit.earns_plant_growth(FocusSession.Kind.SHORT_BREAK, 30.0, 1.0),
		"resting is not growing"
	)
	assert_false(
		SessionCredit.earns_plant_growth(FocusSession.Kind.LONG_BREAK, 30.0, 1.0),
		"a long break does not grow plants either"
	)


func test_threshold_can_be_disabled() -> void:
	assert_true(
		SessionCredit.earns_plant_growth(FocusSession.Kind.FOCUS, 0.1, 0.0),
		"a zero threshold lets any focus time count"
	)
