extends TestCase
## SessionCycle: the pomodoro cycle rules (§8).

const SPAN: int = 4


func test_first_break_is_short() -> void:
	# The guard that matters: 0 % 4 == 0, so without an explicit check a player's
	# very first break would be the long one.
	assert_eq(
		SessionCycle.next_break_kind(0, SPAN), FocusSession.Kind.SHORT_BREAK,
		"the first break of all is short"
	)


func test_break_kind_across_a_full_cycle() -> void:
	assert_eq(SessionCycle.next_break_kind(1, SPAN), FocusSession.Kind.SHORT_BREAK, "after 1")
	assert_eq(SessionCycle.next_break_kind(2, SPAN), FocusSession.Kind.SHORT_BREAK, "after 2")
	assert_eq(SessionCycle.next_break_kind(3, SPAN), FocusSession.Kind.SHORT_BREAK, "after 3")
	assert_eq(SessionCycle.next_break_kind(4, SPAN), FocusSession.Kind.LONG_BREAK, "after 4")
	assert_eq(SessionCycle.next_break_kind(5, SPAN), FocusSession.Kind.SHORT_BREAK, "after 5")
	assert_eq(SessionCycle.next_break_kind(8, SPAN), FocusSession.Kind.LONG_BREAK, "after 8")


func test_cycle_position_wraps() -> void:
	assert_eq(SessionCycle.position(0, SPAN), 1, "a fresh cycle starts at 1")
	assert_eq(SessionCycle.position(3, SPAN), 4, "the fourth session")
	assert_eq(SessionCycle.position(4, SPAN), 1, "and then it wraps")
	assert_eq(SessionCycle.position(9, SPAN), 2, "wraps repeatedly")


func test_cycle_span_of_one() -> void:
	# A player who sets one session per cycle should get a long break every time.
	assert_eq(
		SessionCycle.next_break_kind(1, 1), FocusSession.Kind.LONG_BREAK,
		"every break is long when the cycle is one session"
	)
	assert_eq(SessionCycle.position(5, 1), 1, "position is always 1")


func test_invalid_span_does_not_divide_by_zero() -> void:
	# A corrupted setting must not crash the timer.
	assert_eq(SessionCycle.position(3, 0), 1, "a zero span is treated as one")
	assert_ne(SessionCycle.next_break_kind(3, 0), null, "a zero span still returns a kind")


func test_only_completed_focus_advances_the_cycle() -> void:
	assert_true(
		SessionCycle.should_advance(
			FocusSession.Kind.FOCUS, FocusSession.Completion.COMPLETED
		),
		"a completed focus session advances the cycle"
	)
	assert_false(
		SessionCycle.should_advance(
			FocusSession.Kind.FOCUS, FocusSession.Completion.ENDED_EARLY
		),
		"ending early does not"
	)
	assert_false(
		SessionCycle.should_advance(
			FocusSession.Kind.FOCUS, FocusSession.Completion.CANCELLED
		),
		"cancelling does not"
	)
	assert_false(
		SessionCycle.should_advance(
			FocusSession.Kind.FOCUS, FocusSession.Completion.ABANDONED
		),
		"an abandoned session does not earn a long break"
	)
	assert_false(
		SessionCycle.should_advance(
			FocusSession.Kind.SHORT_BREAK, FocusSession.Completion.COMPLETED
		),
		"breaks never advance the focus cycle"
	)
