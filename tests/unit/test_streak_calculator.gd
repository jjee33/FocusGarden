extends TestCase
## StreakCalculator (§53, §27).
##
## §27's promise is that a missed day resets a number and does nothing else, and
## that the player is never made anxious. The "today is not a miss" rule is the
## load-bearing part of that, so it gets the most coverage here.

const THRESHOLD: float = 25.0


func test_no_sessions_means_no_streak() -> void:
	var result := StreakCalculator.calculate(_sessions([]), THRESHOLD, "2026-05-10")
	assert_eq(result.current, 0, "no sessions, no streak")
	assert_eq(result.longest, 0, "no sessions, no record")


func test_consecutive_days_build_a_streak() -> void:
	var result := StreakCalculator.calculate(
		_sessions([["2026-05-08", 30.0], ["2026-05-09", 30.0], ["2026-05-10", 30.0]]),
		THRESHOLD, "2026-05-10"
	)
	assert_eq(result.current, 3, "three days in a row")
	assert_eq(result.longest, 3, "longest matches")


func test_yesterday_keeps_the_streak_alive() -> void:
	# THE ANXIETY RULE (§3, §27): a day the player has not finished yet is not a
	# day they skipped. Opening the app at 9am must not show a broken streak.
	var result := StreakCalculator.calculate(
		_sessions([["2026-05-08", 30.0], ["2026-05-09", 30.0]]), THRESHOLD, "2026-05-10"
	)
	assert_eq(result.current, 2, "a streak survives an unfinished today")


func test_two_day_gap_resets_the_current_streak() -> void:
	var result := StreakCalculator.calculate(
		_sessions([["2026-05-05", 30.0], ["2026-05-06", 30.0]]), THRESHOLD, "2026-05-10"
	)
	assert_eq(result.current, 0, "a real gap resets the count")
	assert_eq(result.longest, 2, "but the record is never lost")


func test_days_below_the_threshold_do_not_count() -> void:
	var result := StreakCalculator.calculate(
		_sessions([["2026-05-09", 5.0], ["2026-05-10", 30.0]]), THRESHOLD, "2026-05-10"
	)
	assert_eq(result.current, 1, "a 5-minute day is below the 25-minute threshold")


func test_multiple_sessions_in_a_day_are_summed() -> void:
	var result := StreakCalculator.calculate(
		_sessions([["2026-05-10", 15.0], ["2026-05-10", 15.0]]), THRESHOLD, "2026-05-10"
	)
	assert_eq(result.current, 1, "two short sessions together clear the threshold")


func test_longest_streak_survives_later_gaps() -> void:
	var result := StreakCalculator.calculate(
		_sessions([
			["2026-04-01", 30.0], ["2026-04-02", 30.0], ["2026-04-03", 30.0], ["2026-04-04", 30.0],
			["2026-05-10", 30.0],
		]),
		THRESHOLD, "2026-05-10"
	)
	assert_eq(result.current, 1, "the current run restarted")
	assert_eq(result.longest, 4, "the four-day record is preserved")


func test_breaks_do_not_build_a_focus_streak() -> void:
	var sessions: Array[FocusSession] = []
	var rest := FocusSession.new()
	rest.kind = FocusSession.Kind.SHORT_BREAK
	rest.date_key = "2026-05-10"
	rest.actual_focus_minutes = 60.0
	rest.completion = FocusSession.Completion.COMPLETED
	sessions.append(rest)

	var result := StreakCalculator.calculate(sessions, THRESHOLD, "2026-05-10")
	assert_eq(result.current, 0, "an hour of breaks is not an hour of focus")


func test_cancelled_sessions_are_ignored() -> void:
	var sessions: Array[FocusSession] = []
	var cancelled := FocusSession.new()
	cancelled.date_key = "2026-05-10"
	cancelled.actual_focus_minutes = 60.0
	cancelled.completion = FocusSession.Completion.CANCELLED
	sessions.append(cancelled)

	var result := StreakCalculator.calculate(sessions, THRESHOLD, "2026-05-10")
	assert_eq(result.current, 0, "cancelled sessions earn no streak credit")


func test_month_and_year_boundaries() -> void:
	# Calendar arithmetic across a month end, where naive day-number maths breaks.
	var result := StreakCalculator.calculate(
		_sessions([["2026-01-30", 30.0], ["2026-01-31", 30.0], ["2026-02-01", 30.0]]),
		THRESHOLD, "2026-02-01"
	)
	assert_eq(result.current, 3, "the streak crosses into February")


func test_leap_day_is_handled() -> void:
	var result := StreakCalculator.calculate(
		_sessions([["2028-02-28", 30.0], ["2028-02-29", 30.0], ["2028-03-01", 30.0]]),
		THRESHOLD, "2028-03-01"
	)
	assert_eq(result.current, 3, "2028 is a leap year and Feb 29 is a real day")


func _sessions(entries: Array) -> Array[FocusSession]:
	var out: Array[FocusSession] = []
	for entry: Array in entries:
		var session := FocusSession.new()
		session.kind = FocusSession.Kind.FOCUS
		session.date_key = entry[0]
		session.actual_focus_minutes = entry[1]
		session.completion = FocusSession.Completion.COMPLETED
		out.append(session)
	return out
