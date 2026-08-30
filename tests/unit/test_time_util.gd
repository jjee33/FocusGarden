extends TestCase
## TimeUtil's display formatting (§53, §18).
##
## These strings are the ones the player actually reads — every figure on Home,
## the catalogue, the shelf and the plant story goes through `format_duration`,
## and the countdown through `format_countdown`. They had no test at all, which
## is how "3h 00m" ended up in a column of maturity costs that are all whole
## hours without anyone noticing until it was rendered and looked at.
##
## §18 is the reason the edge cases matter: the app must never imply a precision
## it does not have, and must never show a figure that reads as broken.


func test_zero_reads_as_no_minutes_not_no_seconds() -> void:
	# A stat tile showing "0s" for a day with no focus implies a stopwatch is
	# running. "0m" reads as "none yet", which is what it means.
	assert_eq(TimeUtil.format_duration(0.0), "0m", "nothing focused")
	assert_eq(TimeUtil.format_duration(-5.0), "0m", "a negative duration cannot be shown")


func test_under_a_minute_falls_back_to_seconds() -> void:
	assert_eq(TimeUtil.format_duration(0.5), "30s", "half a minute")
	assert_eq(TimeUtil.format_duration(0.05), "3s", "a few seconds")


func test_minutes_only() -> void:
	assert_eq(TimeUtil.format_duration(1.0), "1m", "exactly a minute")
	assert_eq(TimeUtil.format_duration(45.0), "45m", "under an hour")
	assert_eq(TimeUtil.format_duration(59.4), "59m", "rounds down")


func test_whole_hours_drop_the_minutes() -> void:
	# The maturity costs are all whole hours, so this is most of the catalogue.
	assert_eq(TimeUtil.format_duration(180.0), "3h", "a common species")
	assert_eq(TimeUtil.format_duration(600.0), "10h", "the legendary one")
	assert_eq(TimeUtil.format_duration(60.0), "1h", "exactly one hour")


func test_hours_and_minutes_stay_padded() -> void:
	# The padding is what keeps a column of durations aligned, so it survives
	# wherever there are minutes to show.
	assert_eq(TimeUtil.format_duration(65.0), "1h 05m", "single-digit minutes are padded")
	assert_eq(TimeUtil.format_duration(270.0), "4h 30m", "an uncommon species")
	assert_eq(TimeUtil.format_duration(85.0), "1h 25m", "a long session")


func test_countdown_grows_a_field_only_when_needed() -> void:
	assert_eq(TimeUtil.format_countdown(1500.0), "25:00", "a standard pomodoro")
	assert_eq(TimeUtil.format_countdown(65.0), "1:05", "just over a minute")
	assert_eq(TimeUtil.format_countdown(3900.0), "1:05:00", "past an hour")


func test_countdown_never_shows_negative_time() -> void:
	# A timer that overshoots by a frame must not print "-0:01" at the player.
	assert_eq(TimeUtil.format_countdown(0.0), "0:00", "exactly finished")
	assert_eq(TimeUtil.format_countdown(-3.0), "0:00", "overshot")


func test_countdown_rounds_up_so_the_last_second_is_shown() -> void:
	# Rounding down would make the clock read 0:00 for a whole second before the
	# session actually ends, which looks like the timer has stalled.
	assert_eq(TimeUtil.format_countdown(0.2), "0:01", "part of a second is still a second")


func test_datetime_is_written_the_way_a_person_reads_one() -> void:
	var stamp := Time.get_unix_time_from_datetime_dict({
		"year": 2026, "month": 8, "day": 14, "hour": 9, "minute": 42, "second": 0,
	})
	var formatted := TimeUtil.format_datetime(stamp)
	assert_true(formatted.contains("2026"), "the year is there")
	assert_true(formatted.contains("Aug"), "the month is a name, not a number")
	assert_false(formatted.is_empty(), "and it produced something")


## The assertions above pass whether or not the offset is applied, which is why
## they did not notice that it never was. These pin the actual number.
func test_a_moment_is_rendered_in_local_time_not_utc() -> void:
	# 2026-08-14 09:42:00 UTC.
	var stamp := 1786700520.0

	assert_eq(
		TimeUtil.format_datetime(stamp, 0),
		"14 Aug 2026, 09:42",
		"at UTC the stamp renders as itself",
	)
	assert_eq(
		TimeUtil.format_datetime(stamp, 2 * 3600),
		"14 Aug 2026, 11:42",
		"two hours east reads two hours later",
	)
	assert_eq(
		TimeUtil.format_datetime(stamp, -5 * 3600),
		"14 Aug 2026, 04:42",
		"five hours west reads five hours earlier",
	)


func test_a_moment_near_midnight_moves_day_with_the_offset() -> void:
	# 2026-08-14 23:30:00 UTC — the case where getting this wrong shows the
	# player the wrong DATE, not merely the wrong hour.
	var stamp := 1786750200.0

	assert_eq(
		TimeUtil.format_datetime(stamp, 2 * 3600),
		"15 Aug 2026, 01:30",
		"east of UTC it is already tomorrow",
	)
	assert_eq(
		TimeUtil.format_datetime(stamp, -5 * 3600),
		"14 Aug 2026, 18:30",
		"west of UTC it is still the same evening",
	)


func test_an_unset_timestamp_stays_empty_whatever_the_offset() -> void:
	assert_eq(TimeUtil.format_datetime(0.0, 5 * 3600), "", "no offset rescues an unset stamp")
	assert_eq(TimeUtil.format_datetime(-1.0, -5 * 3600), "", "nor does a negative one")


func test_a_missing_timestamp_formats_to_nothing() -> void:
	# Rather than to 1 Jan 1970, which is what a bare conversion would give and
	# would read as a real date the player had never seen before.
	assert_eq(TimeUtil.format_datetime(0.0), "", "an unset timestamp shows nothing")


func test_a_date_key_renders_the_way_a_person_reads_a_date() -> void:
	assert_eq(TimeUtil.format_date_key("2026-08-14"), "14 Aug 2026", "a full date")
	assert_eq(TimeUtil.format_date_key("2025-01-03"), "3 Jan 2025", "no leading zero on the day")
	assert_eq(TimeUtil.format_date_key("2026-12-31"), "31 Dec 2026", "the last month resolves")


func test_an_unreadable_date_key_is_returned_as_it_came() -> void:
	# Better a raw key on screen than a fabricated date. These come off disk and
	# can be anything.
	assert_eq(TimeUtil.format_date_key(""), "", "an empty key stays empty")
	assert_eq(TimeUtil.format_date_key("nonsense"), "nonsense", "junk is not invented over")
