class_name FocusSession
extends RefCounted
## One recorded focus or break session (§37).
##
## This is the authoritative analytics record. Statistics are always derived from
## these rows, never stored only as aggregates (§37), so any total can be
## recomputed from scratch if a cached rollup is ever wrong.
##
## Player data — serialized as plain JSON, never as a .tres (see DATA_MODEL.md).

enum Kind { FOCUS, SHORT_BREAK, LONG_BREAK }

enum Completion {
	COMPLETED,   ## Ran to the intended duration. Full credit.
	ENDED_EARLY, ## Player finished manually. Credit for actual focus time.
	CANCELLED,   ## Player discarded it. No growth credit.
	ABANDONED,   ## App closed or crashed mid-session; recovered on next launch.
}

## Divergence between the monotonic and wall clocks means the machine slept or
## the clock moved. We keep the session and flag it rather than punishing the
## player or corrupting statistics (§55).
enum Anomaly { NONE, SUSPEND, CLOCK_JUMP, NEGATIVE_DURATION }

var id: String = ""
var kind: Kind = Kind.FOCUS
var started_at_utc: float = 0.0
var ended_at_utc: float = 0.0
## Local date the session STARTED, captured at record time and never recomputed
## (see TimeUtil's daylight-saving policy).
var date_key: String = ""
## Local hour 0-23 at start, stored so time-of-day requirements never have to
## re-derive an offset for a historical timestamp.
var start_hour: int = 0

var intended_duration_minutes: float = 0.0
## Credited focus time. Excludes paused time (§12) and is capped by the monotonic
## clock when an anomaly is detected.
var actual_focus_minutes: float = 0.0
var paused_minutes: float = 0.0

var completion: Completion = Completion.COMPLETED
var anomaly: Anomaly = Anomaly.NONE
var interruption_reason: String = ""

var project_id: String = ""
var plant_uid: String = ""
var xp_earned: int = 0

## Idempotency guard for SessionPipeline. Once the nine completion steps have run
## for this session, they can never run again — this is what makes "XP cannot
## double-award" (§63) a structural property rather than a hope.
var awards_applied: bool = false


static func create(
	session_kind: Kind, intended_minutes: float, project: String, plant: String
) -> FocusSession:
	var session := FocusSession.new()
	session.id = Uid.generate("s")
	session.kind = session_kind
	session.intended_duration_minutes = intended_minutes
	session.project_id = project
	session.plant_uid = plant
	session.started_at_utc = Time.get_unix_time_from_system()
	session.date_key = TimeUtil.local_date_key(session.started_at_utc)
	session.start_hour = TimeUtil.local_hour(session.started_at_utc)
	return session


func is_focus() -> bool:
	return kind == Kind.FOCUS


func is_break() -> bool:
	return kind == Kind.SHORT_BREAK or kind == Kind.LONG_BREAK


## Whether this session should contribute growth, XP, and streak credit.
## Cancelled sessions and anything with no credited time never count.
func counts_toward_progress() -> bool:
	return completion != Completion.CANCELLED and actual_focus_minutes > 0.0


func to_dict() -> Dictionary:
	return {
		"id": id,
		"kind": int(kind),
		"started_at_utc": started_at_utc,
		"ended_at_utc": ended_at_utc,
		"date_key": date_key,
		"start_hour": start_hour,
		"intended_duration_minutes": intended_duration_minutes,
		"actual_focus_minutes": actual_focus_minutes,
		"paused_minutes": paused_minutes,
		"completion": int(completion),
		"anomaly": int(anomaly),
		"interruption_reason": interruption_reason,
		"project_id": project_id,
		"plant_uid": plant_uid,
		"xp_earned": xp_earned,
		"awards_applied": awards_applied,
	}


static func from_dict(data: Dictionary) -> FocusSession:
	var session := FocusSession.new()
	session.id = DictUtil.get_string(data, "id")
	session.kind = _safe_kind(DictUtil.get_int(data, "kind", int(Kind.FOCUS)))
	session.started_at_utc = DictUtil.get_float(data, "started_at_utc")
	session.ended_at_utc = DictUtil.get_float(data, "ended_at_utc")
	session.date_key = DictUtil.get_string(data, "date_key")
	session.start_hour = clampi(DictUtil.get_int(data, "start_hour"), 0, 23)
	session.intended_duration_minutes = maxf(
		0.0, DictUtil.get_float(data, "intended_duration_minutes")
	)
	# Negative durations are impossible and would poison every total that sums
	# them, so they are clamped here at the boundary (§55).
	session.actual_focus_minutes = maxf(0.0, DictUtil.get_float(data, "actual_focus_minutes"))
	session.paused_minutes = maxf(0.0, DictUtil.get_float(data, "paused_minutes"))
	session.completion = _safe_completion(
		DictUtil.get_int(data, "completion", int(Completion.COMPLETED))
	)
	session.anomaly = _safe_anomaly(DictUtil.get_int(data, "anomaly", int(Anomaly.NONE)))
	session.interruption_reason = DictUtil.get_string(data, "interruption_reason")
	session.project_id = DictUtil.get_string(data, "project_id")
	session.plant_uid = DictUtil.get_string(data, "plant_uid")
	session.xp_earned = maxi(0, DictUtil.get_int(data, "xp_earned"))
	session.awards_applied = DictUtil.get_bool(data, "awards_applied")

	# A record with no usable date key cannot be placed on the calendar. Rebuild
	# it from the timestamp rather than dropping the session entirely.
	if not TimeUtil.is_valid_date_key(session.date_key) and session.started_at_utc > 0.0:
		session.date_key = TimeUtil.local_date_key(session.started_at_utc)
	return session


# Enum values arriving from JSON are untrusted; an out-of-range int would make
# later `match` statements fall through in surprising ways.
static func _safe_kind(value: int) -> Kind:
	return value as Kind if value >= 0 and value <= int(Kind.LONG_BREAK) else Kind.FOCUS


static func _safe_completion(value: int) -> Completion:
	return (
		value as Completion
		if value >= 0 and value <= int(Completion.ABANDONED)
		else Completion.COMPLETED
	)


static func _safe_anomaly(value: int) -> Anomaly:
	return (
		value as Anomaly
		if value >= 0 and value <= int(Anomaly.NEGATIVE_DURATION)
		else Anomaly.NONE
	)
