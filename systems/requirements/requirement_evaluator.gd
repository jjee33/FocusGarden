class_name RequirementEvaluator
extends RefCounted
## The ONE condition engine (§48).
##
## §48 is explicit: plant unlocks, achievements, expeditions, garden upgrades and
## cosmetic unlocks must not each grow their own evaluator. They all call
## `evaluate()` here with a Requirement and a RequirementContext.
##
## Every requirement returns a 0..1 RATIO rather than a boolean. That single
## choice is what lets one engine serve both "is this unlocked yet" and "how full
## is this progress bar", and it is what drives plant growth stages: a plant's
## stage is its maturity requirement's ratio quantized to the species' stage count
## (§14), so growth thresholds are never duplicated anywhere.


## 0..1 progress toward the requirement. Never returns NaN or a value outside the
## range, because callers feed it straight into progress bars and stage indices.
static func evaluate(requirement: Requirement, context: RequirementContext) -> float:
	if requirement == null or context == null:
		return 0.0
	var params := requirement.params
	var plant_scoped := requirement.scope == Requirement.Scope.ACTIVE_PLANT

	match requirement.type:
		Requirement.Type.TOTAL_FOCUS_MINUTES:
			var target := DictUtil.get_float(params, "amount", 1.0)
			var actual := context.plant_focus_minutes if plant_scoped else context.total_focus_minutes
			return _ratio(actual, target)

		Requirement.Type.COMPLETED_SESSIONS:
			var target := float(DictUtil.get_int(params, "count", 1))
			var actual := float(
				context.plant_session_count if plant_scoped else context.completed_focus_sessions
			)
			return _ratio(actual, target)

		Requirement.Type.UNIQUE_FOCUS_DAYS:
			var target := float(DictUtil.get_int(params, "count", 1))
			var days := context.plant_unique_days if plant_scoped else context.unique_focus_days
			return _ratio(float(days.size()), target)

		Requirement.Type.CONSECUTIVE_DAYS:
			var target := float(DictUtil.get_int(params, "count", 1))
			return _ratio(float(context.longest_consecutive_day_run()), target)

		Requirement.Type.SESSIONS_IN_TIME_WINDOW:
			var target := float(DictUtil.get_int(params, "count", 1))
			var start_hour := clampi(DictUtil.get_int(params, "start_hour", 0), 0, 23)
			var end_hour := clampi(DictUtil.get_int(params, "end_hour", 23), 0, 23)
			var histogram := (
				context.plant_sessions_by_start_hour if plant_scoped else context.sessions_by_start_hour
			)
			return _ratio(float(_count_in_hour_window(histogram, start_hour, end_hour)), target)

		Requirement.Type.SESSION_LENGTH_AT_LEAST:
			var minutes := DictUtil.get_float(params, "minutes", 1.0)
			var target := float(DictUtil.get_int(params, "count", 1))
			var lengths := (
				context.plant_session_lengths if plant_scoped else context.focus_session_lengths
			)
			var qualifying := 0
			for length: float in lengths:
				if length >= minutes:
					qualifying += 1
			return _ratio(float(qualifying), target)

		Requirement.Type.BREAK_SESSIONS:
			var target := float(DictUtil.get_int(params, "count", 1))
			return _ratio(float(context.completed_break_sessions), target)

		Requirement.Type.PLANTS_MATURED:
			var target := float(DictUtil.get_int(params, "count", 1))
			return _ratio(float(context.plants_matured), target)

		Requirement.Type.SPECIES_DISCOVERED:
			var target := float(DictUtil.get_int(params, "count", 1))
			return _ratio(float(context.species_discovered), target)

		Requirement.Type.PLAYER_LEVEL:
			var target := float(DictUtil.get_int(params, "level", 1))
			return _ratio(float(context.player_level), target)

		Requirement.Type.CATALOGUE_COMPLETION:
			var target := DictUtil.get_float(params, "ratio", 1.0)
			if context.species_total <= 0:
				return 0.0
			var actual := float(context.species_discovered) / float(context.species_total)
			return _ratio(actual, target)

		Requirement.Type.ACHIEVEMENT_UNLOCKED:
			var needed := DictUtil.get_string(params, "achievement_id")
			return 1.0 if context.unlocked_achievement_ids.has(needed) else 0.0

		Requirement.Type.EXPEDITION_COMPLETED:
			var needed := DictUtil.get_string(params, "expedition_id")
			return 1.0 if context.completed_expedition_ids.has(needed) else 0.0

	return 0.0


static func is_met(requirement: Requirement, context: RequirementContext) -> bool:
	return evaluate(requirement, context) >= 1.0


## All requirements must pass. An empty list is met — a species with no unlock
## requirement is available from the start, which is the sane default.
static func all_met(requirements: Array[Requirement], context: RequirementContext) -> bool:
	for requirement: Requirement in requirements:
		if not is_met(requirement, context):
			return false
	return true


## Human-readable text for catalogue and achievement cards. Authors can override
## per requirement; this generates sensible copy for everything else so no
## requirement ever renders as blank (§74).
static func describe(requirement: Requirement) -> String:
	if requirement == null:
		return ""
	if not requirement.description_override.is_empty():
		return requirement.description_override

	var params := requirement.params
	match requirement.type:
		Requirement.Type.TOTAL_FOCUS_MINUTES:
			return "Focus for %s" % TimeUtil.format_duration(
				DictUtil.get_float(params, "amount", 0.0)
			)
		Requirement.Type.COMPLETED_SESSIONS:
			return "Complete %d focus sessions" % DictUtil.get_int(params, "count", 1)
		Requirement.Type.UNIQUE_FOCUS_DAYS:
			return "Focus on %d separate days" % DictUtil.get_int(params, "count", 1)
		Requirement.Type.CONSECUTIVE_DAYS:
			return "Focus %d days in a row" % DictUtil.get_int(params, "count", 1)
		Requirement.Type.SESSIONS_IN_TIME_WINDOW:
			return "Complete %d sessions between %s and %s" % [
				DictUtil.get_int(params, "count", 1),
				_format_hour(DictUtil.get_int(params, "start_hour", 0)),
				_format_hour(DictUtil.get_int(params, "end_hour", 23)),
			]
		Requirement.Type.SESSION_LENGTH_AT_LEAST:
			return "Complete %d sessions of at least %s" % [
				DictUtil.get_int(params, "count", 1),
				TimeUtil.format_duration(DictUtil.get_float(params, "minutes", 0.0)),
			]
		Requirement.Type.BREAK_SESSIONS:
			return "Take %d breaks" % DictUtil.get_int(params, "count", 1)
		Requirement.Type.PLANTS_MATURED:
			return "Grow %d plants to maturity" % DictUtil.get_int(params, "count", 1)
		Requirement.Type.SPECIES_DISCOVERED:
			return "Discover %d species" % DictUtil.get_int(params, "count", 1)
		Requirement.Type.PLAYER_LEVEL:
			return "Reach level %d" % DictUtil.get_int(params, "level", 1)
		Requirement.Type.CATALOGUE_COMPLETION:
			return "Complete %d%% of the catalogue" % int(
				round(DictUtil.get_float(params, "ratio", 1.0) * 100.0)
			)
		Requirement.Type.ACHIEVEMENT_UNLOCKED:
			return "Unlock a required achievement"
		Requirement.Type.EXPEDITION_COMPLETED:
			return "Complete a required expedition"
	return ""


static func _ratio(actual: float, target: float) -> float:
	if target <= 0.0:
		# A zero or negative target is already satisfied. Returning 0/0 here would
		# produce NaN and poison every progress bar downstream.
		return 1.0
	return clampf(actual / target, 0.0, 1.0)


## Counts a start..end hour window inclusive. Windows are allowed to wrap past
## midnight (e.g. 20:00-02:00 for evening plants), which a naive range would miss.
static func _count_in_hour_window(
	histogram: PackedInt32Array, start_hour: int, end_hour: int
) -> int:
	var total := 0
	if start_hour <= end_hour:
		for hour in range(start_hour, end_hour + 1):
			total += histogram[hour]
	else:
		for hour in range(start_hour, 24):
			total += histogram[hour]
		for hour in range(0, end_hour + 1):
			total += histogram[hour]
	return total


static func _format_hour(hour: int) -> String:
	var clamped := clampi(hour, 0, 23)
	if clamped == 0:
		return "12 AM"
	if clamped < 12:
		return "%d AM" % clamped
	if clamped == 12:
		return "12 PM"
	return "%d PM" % (clamped - 12)
