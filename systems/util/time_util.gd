class_name TimeUtil
extends RefCounted
## Calendar helpers for streaks, heatmaps, and daily goals.
##
## DAYLIGHT SAVING POLICY (§54): a session's local date key is captured at the
## moment the session is recorded and then stored permanently on the record.
## Aggregation reads the stored key and never recomputes it from the UTC stamp.
## Recomputing later would apply today's UTC offset to a historical timestamp and
## silently shift sessions across midnight whenever DST flipped in between.
##
## MIDNIGHT POLICY (§54): a session that spans midnight is credited entirely to
## the local date it STARTED on. Sessions are not split. This keeps one session
## record equal to one row of history and keeps streaks intuitive — a 23:50 start
## belongs to the day the player sat down.

const SECONDS_PER_DAY: int = 86400
const SECONDS_PER_MINUTE: int = 60


## Current UTC offset in seconds, as reported by the OS right now.
static func local_offset_seconds() -> int:
	var zone: Dictionary = Time.get_time_zone_from_system()
	return DictUtil.get_int(zone, "bias", 0) * SECONDS_PER_MINUTE


## "YYYY-MM-DD" in local time for a UTC unix timestamp.
## Capture this once, at record time, then store it.
static func local_date_key(unix_utc: float) -> String:
	var shifted := int(unix_utc) + local_offset_seconds()
	var parts: Dictionary = Time.get_datetime_dict_from_unix_time(shifted)
	return "%04d-%02d-%02d" % [
		DictUtil.get_int(parts, "year"),
		DictUtil.get_int(parts, "month"),
		DictUtil.get_int(parts, "day"),
	]


static func today_key() -> String:
	return local_date_key(Time.get_unix_time_from_system())


## Local hour 0-23, for the time-of-day requirements in §47 (morning sunflowers,
## evening moon cacti) and the Night Owl / Early Bird achievements.
static func local_hour(unix_utc: float) -> int:
	var shifted := int(unix_utc) + local_offset_seconds()
	var parts: Dictionary = Time.get_datetime_dict_from_unix_time(shifted)
	return DictUtil.get_int(parts, "hour")


## Whole days from `from_key` to `to_key`. Negative when `to_key` is earlier.
## Returns 0 for unparseable input rather than throwing, so one bad record cannot
## break a whole streak calculation.
static func days_between(from_key: String, to_key: String) -> int:
	var from_unix := _date_key_to_unix(from_key)
	var to_unix := _date_key_to_unix(to_key)
	if from_unix < 0 or to_unix < 0:
		return 0
	return int(round(float(to_unix - from_unix) / float(SECONDS_PER_DAY)))


## Date key `offset` days away from `key`.
static func shift_date_key(key: String, offset: int) -> String:
	var base := _date_key_to_unix(key)
	if base < 0:
		return key
	var parts: Dictionary = Time.get_datetime_dict_from_unix_time(base + offset * SECONDS_PER_DAY)
	return "%04d-%02d-%02d" % [
		DictUtil.get_int(parts, "year"),
		DictUtil.get_int(parts, "month"),
		DictUtil.get_int(parts, "day"),
	]


static func is_valid_date_key(key: String) -> bool:
	return _date_key_to_unix(key) >= 0


## "1h 25m" / "45m" / "30s". Used everywhere focus time is displayed, so the app
## never shows two different formats for the same quantity.
static func format_duration(total_minutes: float) -> String:
	# Exactly zero reads as "0m", not "0s". A stat tile showing "0s" for a day
	# with no focus implies a stopwatch is running; "0m" reads as "none yet".
	if total_minutes <= 0.0:
		return "0m"
	if total_minutes < 1.0:
		return "%ds" % int(round(total_minutes * SECONDS_PER_MINUTE))
	var whole := int(round(total_minutes))
	var hours := whole / 60
	var minutes := whole % 60
	if hours <= 0:
		return "%dm" % minutes
	return "%dh %02dm" % [hours, minutes]


## Countdown clock: "25:00", or "1:05:00" once past an hour.
static func format_countdown(total_seconds: float) -> String:
	var remaining := maxi(0, int(ceil(total_seconds)))
	var hours := remaining / 3600
	var minutes := (remaining % 3600) / 60
	var seconds := remaining % 60
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, seconds]
	return "%d:%02d" % [minutes, seconds]


# Date keys are interpreted at UTC midnight purely as a stable day index. The key
# already encodes local time, so no further offset may be applied here — doing so
# would double-shift and break days_between across timezone changes.
static func _date_key_to_unix(key: String) -> int:
	if key.length() != 10:
		return -1
	var parsed := Time.get_unix_time_from_datetime_string(key + "T00:00:00")
	# Godot returns 0 both for the epoch itself and for unparseable strings.
	# A save can never legitimately contain 1970-01-01, so treat it as invalid.
	if parsed == 0 and key != "1970-01-01":
		return -1
	return parsed
