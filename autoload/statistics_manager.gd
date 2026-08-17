extends Node
## Session aggregation and analytics (§40).
##
## Owns: deriving every statistic from the raw session records.
## Must never: mutate a session, a plant, or the profile. It reads and summarizes.
##
## Everything here is DERIVED. §37 keeps the full session history precisely so no
## total is ever authoritative on its own — if a cached figure and the session
## rows disagree, the rows win and the cache is rebuilt. That is what makes §64's
## "totals match underlying session records" verifiable rather than aspirational.
##
## Aggregates are cached and invalidated on change rather than recomputed per
## frame or per screen open (§44).

class Summary extends RefCounted:
	var focus_today: float = 0.0
	var focus_week: float = 0.0
	var focus_month: float = 0.0
	var focus_year: float = 0.0
	var focus_lifetime: float = 0.0
	var session_count: int = 0
	var break_count: int = 0
	var average_session_minutes: float = 0.0
	var longest_session_minutes: float = 0.0
	var days_focused: int = 0
	var current_streak: int = 0
	var longest_streak: int = 0
	var plants_matured: int = 0
	var species_discovered: int = 0
	var total_xp: int = 0


var _summary_dirty: bool = true
var _summary: Summary = Summary.new()


func _ready() -> void:
	EventBus.save_loaded.connect(_on_state_changed)
	EventBus.focus_time_recorded.connect(_on_focus_recorded)


## Marks caches stale. Cheap: the recompute happens on the next read, so a burst
## of changes costs one rebuild rather than one per change.
func invalidate() -> void:
	_summary_dirty = true


func get_summary() -> Summary:
	if _summary_dirty:
		_rebuild_summary()
	return _summary


## Credited focus minutes on one local date.
func get_focus_minutes_for_day(date_key: String) -> float:
	var total := 0.0
	for session: FocusSession in AppState.sessions:
		if session.date_key == date_key and session.counts_toward_progress() and session.is_focus():
			total += session.actual_focus_minutes
	return total


## Focus minutes per day across a date range, for the §30 calendar heatmap.
## Returns { date_key -> minutes }, omitting days with no focus so a full year
## stays a small dictionary rather than 365 zero entries.
func get_daily_totals() -> Dictionary:
	return StreakCalculator.minutes_by_day(AppState.sessions)


## Credited focus minutes grouped by project id (§29 breakdowns).
func get_totals_by_project() -> Dictionary:
	var totals := {}
	for session: FocusSession in AppState.sessions:
		if not session.counts_toward_progress() or not session.is_focus():
			continue
		var key := session.project_id
		totals[key] = float(totals.get(key, 0.0)) + session.actual_focus_minutes
	return totals


func get_streak() -> StreakCalculator.Result:
	return StreakCalculator.calculate(
		AppState.sessions, AppState.get_settings().streak_threshold_minutes
	)


## A context covering ONE plant only, for evaluating that plant's growth.
##
## `build_context` aggregates every session in the save and recomputes the streak,
## which walks the whole history and parses date strings. Plant growth needs none
## of that: a species' growth requirement is ACTIVE_PLANT-scoped by construction,
## so only that plant's own sessions matter.
##
## This is not a micro-optimisation. Growth is evaluated on every session
## completion, and the full context is O(all sessions); using it here made
## progression cost grow with the size of the player's history for no reason
## (§44's "no constant expensive analytics recalculation"). `plant_sessions` is
## accepted directly so callers that already hold the list do not rescan for it.
func build_plant_context(
	plant_uid: String, plant_sessions: Array[FocusSession] = []
) -> RequirementContext:
	var context := RequirementContext.new()
	var sessions := (
		plant_sessions if not plant_sessions.is_empty()
		else AppState.get_sessions_for_plant(plant_uid)
	)
	context.ingest_plant_sessions(sessions)
	return context


## Builds the snapshot that RequirementEvaluator measures against.
##
## This is the seam between "what the player has done" and "what conditions are
## satisfied". Passing `plant_uid` additionally fills the ACTIVE_PLANT scope, so
## a species' growth requirement and a global achievement can be evaluated
## against the same object in one pass.
func build_context(plant_uid: String = "") -> RequirementContext:
	var context := RequirementContext.new()
	context.ingest_sessions(AppState.sessions)

	if not plant_uid.is_empty():
		context.ingest_plant_sessions(AppState.get_sessions_for_plant(plant_uid))

	var streak := get_streak()
	context.current_streak = streak.current
	context.longest_streak = streak.longest

	context.player_level = XpFormula.level_for_xp(AppState.data.profile.total_xp)
	context.species_total = ContentDB.get_species_count()

	for plant: PlantInstance in AppState.data.plants:
		if plant.is_mature():
			context.plants_matured += 1
	for entry: CatalogueEntry in AppState.data.catalogue:
		if entry.discovered:
			context.species_discovered += 1
	for state: AchievementState in AppState.data.achievements:
		if state.unlocked:
			context.unlocked_achievement_ids.append(String(state.achievement_id))
	for expedition_id: String in AppState.data.expeditions:
		var progress: Dictionary = AppState.data.expeditions[expedition_id]
		if DictUtil.get_bool(progress, "completed"):
			context.completed_expedition_ids.append(expedition_id)

	return context


func _rebuild_summary() -> void:
	var summary := Summary.new()
	var today := TimeUtil.today_key()
	var week_start := TimeUtil.shift_date_key(today, -6)
	var month_start := TimeUtil.shift_date_key(today, -29)
	var year_start := TimeUtil.shift_date_key(today, -364)

	var focus_total := 0.0
	for session: FocusSession in AppState.sessions:
		if not session.counts_toward_progress():
			continue
		if session.is_break():
			summary.break_count += 1
			continue

		var minutes := session.actual_focus_minutes
		summary.session_count += 1
		focus_total += minutes
		summary.longest_session_minutes = maxf(summary.longest_session_minutes, minutes)

		if session.date_key == today:
			summary.focus_today += minutes
		if TimeUtil.days_between(week_start, session.date_key) >= 0:
			summary.focus_week += minutes
		if TimeUtil.days_between(month_start, session.date_key) >= 0:
			summary.focus_month += minutes
		if TimeUtil.days_between(year_start, session.date_key) >= 0:
			summary.focus_year += minutes

	summary.focus_lifetime = focus_total
	if summary.session_count > 0:
		summary.average_session_minutes = focus_total / float(summary.session_count)

	var streak := get_streak()
	summary.current_streak = streak.current
	summary.longest_streak = streak.longest
	summary.days_focused = StreakCalculator.minutes_by_day(AppState.sessions).size()

	for plant: PlantInstance in AppState.data.plants:
		if plant.is_mature():
			summary.plants_matured += 1
	for entry: CatalogueEntry in AppState.data.catalogue:
		if entry.discovered:
			summary.species_discovered += 1
	summary.total_xp = AppState.data.profile.total_xp

	_summary = summary
	_summary_dirty = false


func _on_state_changed() -> void:
	invalidate()


func _on_focus_recorded(_session_id: String, _credited_minutes: float) -> void:
	invalidate()
