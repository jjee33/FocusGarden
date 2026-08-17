class_name StreakCalculator
extends RefCounted
## The one authoritative streak calculation (§27, §38).
##
## §27 is emphatic that a missed day resets a number and nothing else: no plants
## die, no XP is removed, no garden is damaged, and the player is never shamed.
## Accordingly this class only ever RETURNS integers. It has no ability to modify
## anything, which makes the "never punish" rule structural rather than a
## convention someone could break later.
##
## TODAY IS NOT COUNTED AS A MISS. A streak stays alive while the most recent
## qualifying day is today OR yesterday, because a day the player has not
## finished yet is not a day they skipped. Without this, opening the app at 9am
## would show a broken streak every single morning — precisely the anxiety
## mechanic §3 rules out.

class Result extends RefCounted:
	var current: int = 0
	var longest: int = 0
	var qualifying_days: PackedStringArray = PackedStringArray()
	var last_qualifying_day: String = ""


## Credited focus minutes per local date key. Breaks do not count toward a
## focus streak.
static func minutes_by_day(sessions: Array[FocusSession]) -> Dictionary:
	var totals := {}
	for session: FocusSession in sessions:
		if not session.counts_toward_progress() or not session.is_focus():
			continue
		if session.date_key.is_empty():
			continue
		totals[session.date_key] = (
			float(totals.get(session.date_key, 0.0)) + session.actual_focus_minutes
		)
	return totals


## Computes both streaks. `today_key` is injectable so tests can pin "today"
## instead of depending on when the suite happens to run.
static func calculate(
	sessions: Array[FocusSession], threshold_minutes: float, today_key: String = ""
) -> Result:
	var result := Result.new()
	var today := today_key if not today_key.is_empty() else TimeUtil.today_key()
	var totals := minutes_by_day(sessions)

	var days: Array = []
	for day: String in totals:
		if float(totals[day]) >= threshold_minutes:
			days.append(day)
	days.sort()
	for day: String in days:
		result.qualifying_days.append(day)

	if days.is_empty():
		return result

	result.last_qualifying_day = days[days.size() - 1]

	# Longest run of consecutive calendar days.
	var run := 1
	result.longest = 1
	for i in range(1, days.size()):
		if TimeUtil.days_between(days[i - 1], days[i]) == 1:
			run += 1
			result.longest = maxi(result.longest, run)
		else:
			run = 1

	# Current streak: walk backwards from the most recent qualifying day, but
	# only if that day is today or yesterday.
	var gap_to_today := TimeUtil.days_between(result.last_qualifying_day, today)
	if gap_to_today > 1:
		result.current = 0
		return result

	result.current = 1
	for i in range(days.size() - 1, 0, -1):
		if TimeUtil.days_between(days[i - 1], days[i]) == 1:
			result.current += 1
		else:
			break
	return result
