class_name RequirementContext
extends RefCounted
## Read-only snapshot of progress that RequirementEvaluator measures against.
##
## Deliberately a dumb data holder with no reference to AppState or any autoload.
## That is what lets every requirement type be unit-tested by filling in a few
## fields, with no save file, no scene tree, and no engine singletons (§53).
##
## Aggregates are precomputed by the caller once per evaluation batch rather than
## recomputed per requirement, so evaluating thirty achievements walks the session
## list once instead of thirty times (§44).

# --- Global scope ---
var total_focus_minutes: float = 0.0
var completed_focus_sessions: int = 0
var completed_break_sessions: int = 0
## Distinct local date keys with any credited focus. Sorted ascending.
var unique_focus_days: PackedStringArray = PackedStringArray()
var current_streak: int = 0
var longest_streak: int = 0
## 24 buckets counting focus sessions by local start hour, for time-of-day rules.
var sessions_by_start_hour: PackedInt32Array = PackedInt32Array()
## Credited lengths of every focus session, for "complete a 90-minute session".
var focus_session_lengths: PackedFloat32Array = PackedFloat32Array()

var player_level: int = 1
var plants_matured: int = 0
var species_discovered: int = 0
var species_total: int = 0
var unlocked_achievement_ids: PackedStringArray = PackedStringArray()
var completed_expedition_ids: PackedStringArray = PackedStringArray()

# --- ACTIVE_PLANT scope: the same measures, narrowed to one plant's sessions ---
var plant_focus_minutes: float = 0.0
var plant_session_count: int = 0
var plant_unique_days: PackedStringArray = PackedStringArray()
var plant_sessions_by_start_hour: PackedInt32Array = PackedInt32Array()
var plant_session_lengths: PackedFloat32Array = PackedFloat32Array()


func _init() -> void:
	sessions_by_start_hour.resize(24)
	plant_sessions_by_start_hour.resize(24)


## Builds the global aggregates from raw session records. One pass over the list.
func ingest_sessions(sessions: Array[FocusSession]) -> void:
	var seen_days := {}
	for session: FocusSession in sessions:
		if not session.counts_toward_progress():
			continue
		if session.is_break():
			completed_break_sessions += 1
			continue
		total_focus_minutes += session.actual_focus_minutes
		completed_focus_sessions += 1
		focus_session_lengths.append(session.actual_focus_minutes)
		sessions_by_start_hour[clampi(session.start_hour, 0, 23)] += 1
		if not seen_days.has(session.date_key):
			seen_days[session.date_key] = true
	var days: Array = seen_days.keys()
	days.sort()
	for day: String in days:
		unique_focus_days.append(day)


## Builds the ACTIVE_PLANT aggregates from the sessions that grew one plant.
func ingest_plant_sessions(sessions: Array[FocusSession]) -> void:
	var seen_days := {}
	for session: FocusSession in sessions:
		if not session.counts_toward_progress() or session.is_break():
			continue
		plant_focus_minutes += session.actual_focus_minutes
		plant_session_count += 1
		plant_session_lengths.append(session.actual_focus_minutes)
		plant_sessions_by_start_hour[clampi(session.start_hour, 0, 23)] += 1
		if not seen_days.has(session.date_key):
			seen_days[session.date_key] = true
	var days: Array = seen_days.keys()
	days.sort()
	for day: String in days:
		plant_unique_days.append(day)


## Longest run of consecutive calendar days present in `unique_focus_days`.
## Computed here rather than trusting the cached streak, so CONSECUTIVE_DAYS
## requirements stay correct even if the cache is stale.
func longest_consecutive_day_run() -> int:
	if unique_focus_days.is_empty():
		return 0
	var best := 1
	var run := 1
	for i in range(1, unique_focus_days.size()):
		if TimeUtil.days_between(unique_focus_days[i - 1], unique_focus_days[i]) == 1:
			run += 1
			best = maxi(best, run)
		else:
			run = 1
	return best
