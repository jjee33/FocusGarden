extends SceneTree
## Sweeps every pure domain function and records {input -> output} as JSON, so
## the TypeScript port can be proved identical rather than assumed identical.
##
##     ... --headless --path . --script res://tools/export_domain_fixtures.gd
##
## WHY THIS EXISTS: the web client re-implements systems/ and models/ in another
## language. The failure that matters is not a crash — it is a silent divergence.
## `posmod` is not `%` for negative numbers. `int(floor(x))` is not `Math.trunc(x)`
## below zero. A rounding difference in `level_for_xp` puts a player on the wrong
## side of a threshold. None of that shows up as an error; it shows up as a
## garden that is subtly wrong on one client and right on the other, in the one
## dataset this project insists has to stay exactly true.
##
## Hand-porting the GDScript tests catches the cases somebody thought of twice.
## This catches the ones nobody thought of, by brute force over a wide input grid.
## The web suite asserts against these files; both layers are kept.
##
## The output IS committed, so `npm test` never needs Godot present. Re-run this
## whenever a formula changes — a fixture that moves is either a deliberate
## behaviour change or the bug you were looking for.
##
## FIXTURES ARE BUILT FROM SYNTHETIC CONTENT, never from data/. A fixture that
## drifted every time a species was retuned would pin nothing.

const OUTPUT_DIR: String = "res://web/src/domain/__fixtures__"

var _files_written: int = 0
var _cases_written: int = 0


func _init() -> void:
	await process_frame
	await process_frame

	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)

	_write("gd_semantics", _sweep_gd_semantics())
	_write("xp_formula", _sweep_xp())
	_write("session_credit", _sweep_session_credit())
	_write("session_cycle", _sweep_session_cycle())
	_write("time_util", _sweep_time_util())
	_write("plant_growth", _sweep_plant_growth())
	_write("requirements", _sweep_requirements())
	_write("streak", _sweep_streak())
	_write("models", _sweep_models())
	_write("persistence", _sweep_persistence())

	print("Wrote %d fixture files, %d cases, to %s" % [
		_files_written, _cases_written, OUTPUT_DIR
	])
	quit(0)


# --- GDScript primitives ------------------------------------------------------

## The language differences themselves, measured against the real engine.
##
## These are swept SEPARATELY from the formulas that use them, because every
## current call site happens to pass non-negative values — where floor and trunc
## agree, and where the two rounding rules agree. The divergence is unreachable
## today, so porting `floorToInt` as `Math.trunc` would pass the whole suite. The
## first call site that ever passes a negative number would then be silently
## wrong, and it would be wrong in save data.
##
## Pinning the primitives directly means the port's foundation is verified even
## where the callers do not currently reach it.
func _sweep_gd_semantics() -> Dictionary:
	var ints: Array[int] = [-9, -8, -7, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 7, 8, 9, 13]
	var floats: Array[float] = [
		-3.5, -2.7, -2.5, -2.0, -1.5, -1.0, -0.7, -0.5, -0.1, 0.0,
		0.1, 0.5, 0.7, 1.0, 1.5, 2.0, 2.5, 2.7, 3.5,
	]

	var posmod_cases: Array = []
	var intdiv_cases: Array = []
	for a: int in ints:
		for b: int in [1, 2, 3, 4, 5, 60]:
			posmod_cases.append({"a": a, "b": b, "out": posmod(a, b)})
			intdiv_cases.append({"a": a, "b": b, "out": a / b})

	var int_cast: Array = []
	var floor_cases: Array = []
	var ceil_cases: Array = []
	var round_cases: Array = []
	for v: float in floats:
		int_cast.append({"value": v, "out": int(v)})
		floor_cases.append({"value": v, "out": int(floor(v))})
		ceil_cases.append({"value": v, "out": int(ceil(v))})
		round_cases.append({"value": v, "out": round(v)})

	return {
		"posmod": posmod_cases,
		"int_division": intdiv_cases,
		"int_cast": int_cast,
		"floor_to_int": floor_cases,
		"ceil_to_int": ceil_cases,
		"round": round_cases,
	}


# --- XpFormula ----------------------------------------------------------------

func _sweep_xp() -> Dictionary:
	var cumulative: Array = []
	for level in range(-3, 106):
		cumulative.append({"level": level, "out": XpFormula.cumulative_xp_for_level(level)})

	# Dense near the low thresholds where the quadratic is steepest, then sparse,
	# plus every exact boundary and each side of it — that is where a closed-form
	# inverse with a floating-point correction is most likely to disagree.
	var xp_values: Array = []
	for xp in range(-5, 400):
		xp_values.append(xp)
	for level in range(1, 101):
		var edge := XpFormula.cumulative_xp_for_level(level)
		for delta in [-2, -1, 0, 1, 2]:
			xp_values.append(edge + delta)
	for xp in [5000, 12345, 99999, 250000, 1000000, 2147483647]:
		xp_values.append(xp)

	var seen := {}
	var level_for: Array = []
	var progress: Array = []
	for xp: int in xp_values:
		if seen.has(xp):
			continue
		seen[xp] = true
		level_for.append({"total_xp": xp, "out": XpFormula.level_for_xp(xp)})
		var p := XpFormula.level_progress(xp)
		progress.append({
			"total_xp": xp,
			"earned_in_level": p[0],
			"level_span": p[1],
			"ratio": XpFormula.level_progress_ratio(xp),
		})

	var sessions: Array = []
	for kind in [FocusSession.Kind.FOCUS, FocusSession.Kind.SHORT_BREAK, FocusSession.Kind.LONG_BREAK]:
		for completion in [
			FocusSession.Completion.COMPLETED, FocusSession.Completion.ENDED_EARLY,
			FocusSession.Completion.CANCELLED, FocusSession.Completion.ABANDONED,
		]:
			for minutes in [0.0, 0.4, 1.0, 12.5, 25.0, 25.9, 90.0, 600.0]:
				var s := FocusSession.new()
				s.kind = kind
				s.completion = completion
				s.actual_focus_minutes = minutes
				sessions.append({
					"kind": int(kind), "completion": int(completion),
					"actual_focus_minutes": minutes,
					"out": XpFormula.xp_for_session(s),
				})

	return {
		"constants": {
			"XP_PER_FOCUS_MINUTE": XpFormula.XP_PER_FOCUS_MINUTE,
			"XP_PER_BREAK_MINUTE": XpFormula.XP_PER_BREAK_MINUTE,
			"LINEAR_TERM": XpFormula.LINEAR_TERM,
			"QUADRATIC_TERM": XpFormula.QUADRATIC_TERM,
			"MAX_LEVEL": XpFormula.MAX_LEVEL,
		},
		"cumulative_xp_for_level": cumulative,
		"level_for_xp": level_for,
		"level_progress": progress,
		"xp_for_session": sessions,
	}


# --- SessionCredit ------------------------------------------------------------

func _sweep_session_credit() -> Dictionary:
	var settle: Array = []
	for completion in [
		FocusSession.Completion.COMPLETED, FocusSession.Completion.ENDED_EARLY,
		FocusSession.Completion.CANCELLED, FocusSession.Completion.ABANDONED,
	]:
		for raw in [-10.0, -0.001, 0.0, 0.5, 24.98, 25.0, 25.02, 40.0]:
			for intended in [0.0, -5.0, 5.0, 25.0, 50.0]:
				settle.append({
					"completion": int(completion), "raw_minutes": raw,
					"intended_minutes": intended,
					"out": SessionCredit.settle(completion, raw, intended),
				})

	var recovered: Array = []
	for raw in [-1.0, 0.0, 3.5, 25.0, 4320.0]:
		for intended in [-5.0, 0.0, 25.0, 90.0]:
			recovered.append({
				"raw_minutes": raw, "intended_minutes": intended,
				"out": SessionCredit.settle_recovered(raw, intended),
			})

	var growth: Array = []
	for kind in [FocusSession.Kind.FOCUS, FocusSession.Kind.SHORT_BREAK, FocusSession.Kind.LONG_BREAK]:
		for credited in [0.0, 0.9, 1.0, 4.999, 5.0, 5.001, 60.0]:
			for minimum in [-1.0, 0.0, 1.0, 5.0]:
				growth.append({
					"kind": int(kind), "credited_minutes": credited, "minimum_minutes": minimum,
					"out": SessionCredit.earns_plant_growth(kind, credited, minimum),
				})

	return {"settle": settle, "settle_recovered": recovered, "earns_plant_growth": growth}


# --- SessionCycle -------------------------------------------------------------

func _sweep_session_cycle() -> Dictionary:
	var next_break: Array = []
	var position: Array = []
	for completed in range(-2, 26):
		for span in [-1, 0, 1, 2, 3, 4, 5, 8]:
			next_break.append({
				"completed_in_cycle": completed, "sessions_before_long": span,
				"out": int(SessionCycle.next_break_kind(completed, span)),
			})
			position.append({
				"completed_in_cycle": completed, "sessions_before_long": span,
				"out": SessionCycle.position(completed, span),
			})

	var advance: Array = []
	for kind in [FocusSession.Kind.FOCUS, FocusSession.Kind.SHORT_BREAK, FocusSession.Kind.LONG_BREAK]:
		for completion in [
			FocusSession.Completion.COMPLETED, FocusSession.Completion.ENDED_EARLY,
			FocusSession.Completion.CANCELLED, FocusSession.Completion.ABANDONED,
		]:
			advance.append({
				"kind": int(kind), "completion": int(completion),
				"out": SessionCycle.should_advance(kind, completion),
			})

	return {"next_break_kind": next_break, "position": position, "should_advance": advance}


# --- TimeUtil -----------------------------------------------------------------

func _sweep_time_util() -> Dictionary:
	var durations: Array = []
	for m in [
		-100.0, -0.5, 0.0, 0.004, 0.008, 0.4, 0.5, 0.9, 0.999, 1.0, 1.4, 1.5, 2.0,
		9.5, 30.0, 59.0, 59.5, 59.9, 60.0, 60.4, 61.0, 65.0, 90.0, 119.5, 120.0,
		125.0, 180.0, 185.0, 599.0, 600.0, 1440.0, 6000.0,
	]:
		durations.append({"total_minutes": m, "out": TimeUtil.format_duration(m)})

	var countdowns: Array = []
	for s in [
		-30.0, -0.1, 0.0, 0.1, 0.5, 1.0, 1.4, 9.0, 59.0, 59.5, 60.0, 61.0, 90.0,
		599.0, 600.0, 1500.0, 3599.0, 3600.0, 3601.0, 7325.0, 86399.0,
	]:
		countdowns.append({"total_seconds": s, "out": TimeUtil.format_countdown(s)})

	# Deliberately includes malformed keys, the epoch sentinel, leap days and
	# year boundaries — days_between must return 0 rather than throw for junk,
	# because one bad record must not break a whole streak calculation.
	var keys: Array[String] = [
		"2026-08-29", "2026-08-30", "2026-08-28", "2026-09-01", "2026-12-31",
		"2027-01-01", "2024-02-28", "2024-02-29", "2024-03-01", "2025-02-28",
		"2025-03-01", "1970-01-01", "1970-01-02", "2000-01-01",
		"", "not-a-date", "2026-8-9", "20260829", "2026-13-01", "2026-02-30",
	]
	var between: Array = []
	for a: String in keys:
		for b: String in keys:
			between.append({"from_key": a, "to_key": b, "out": TimeUtil.days_between(a, b)})

	var validity: Array = []
	var formatted: Array = []
	for k: String in keys:
		validity.append({"key": k, "out": TimeUtil.is_valid_date_key(k)})
		formatted.append({"key": k, "out": TimeUtil.format_date_key(k)})

	var shifted: Array = []
	for k: String in keys:
		for offset in [-400, -366, -31, -1, 0, 1, 31, 365, 400]:
			shifted.append({"key": k, "offset": offset, "out": TimeUtil.shift_date_key(k, offset)})

	# format_datetime was not swept until the offset bug was found in it, and the
	# omission is why: it was the one TimeUtil function the two implementations
	# could disagree about without anything noticing. The offset is passed in
	# explicitly so the fixtures are the same on every machine that regenerates
	# them - reading the system zone here would bake this laptop's timezone into
	# a file that CI then compares against.
	var moments: Array = []
	for stamp in [
		-1.0, 0.0, 1.0, 1786700520.0, 1786750200.0, 1786752000.0,
		1735689599.0, 1735689600.0, 946684800.0, 4102444800.0,
	]:
		for offset in [-50400, -18000, -3600, 0, 3600, 7200, 19800, 50400]:
			moments.append({
				"unix_seconds": stamp, "offset_seconds": offset,
				"out": TimeUtil.format_datetime(stamp, offset),
			})

	return {
		"format_duration": durations,
		"format_countdown": countdowns,
		"days_between": between,
		"is_valid_date_key": validity,
		"format_date_key": formatted,
		"shift_date_key": shifted,
		"format_datetime": moments,
	}


# --- PlantGrowthService -------------------------------------------------------

func _sweep_plant_growth() -> Dictionary:
	var stage_for_ratio: Array = []
	for ratio in [
		-1.0, -0.001, 0.0, 0.0001, 0.32, 0.333, 0.3333333, 0.334, 0.5, 0.66, 0.6666666,
		0.667, 0.9, 0.999, 0.9999999, 1.0, 1.0001, 2.0,
	]:
		for count in [-3, 0, 1, 2, 3, 4, 5, 10]:
			stage_for_ratio.append({
				"ratio": ratio, "stage_count": count,
				"out": PlantGrowthService.stage_for_ratio(ratio, count),
			})

	var stage_name: Array = []
	for stage in range(-2, 8):
		for count in [2, 3, 4, 5]:
			stage_name.append({
				"stage": stage, "stage_count": count,
				"out": PlantGrowthService.stage_name(stage, count),
			})

	# progress_ratio's reached-stage FLOOR is the subtle part: a stored stage can
	# raise the ratio above what the requirement evaluates to, and an out-of-range
	# stored stage must be clamped or every plant in a hand-edited save matures.
	var species := _synthetic_species(180.0)
	var progress: Array = []
	for stored_stage in [0, 1, 2, 3, 99, -5]:
		for mature in [false, true]:
			for plant_minutes in [0.0, 30.0, 60.0, 90.0, 179.0, 180.0, 400.0]:
				var plant := PlantInstance.new()
				plant.uid = "pl_fixture"
				plant.species_id = species.id
				plant.growth_stage = stored_stage
				plant.maturity = (
					PlantInstance.Maturity.MATURE if mature else PlantInstance.Maturity.GROWING
				)
				plant.accumulated_focus_minutes = plant_minutes
				var context := RequirementContext.new()
				context.plant_focus_minutes = plant_minutes
				progress.append({
					"stored_stage": stored_stage, "mature": mature,
					"plant_focus_minutes": plant_minutes,
					"species_maturity_minutes": 180.0, "species_stage_count": 3,
					"out": PlantGrowthService.progress_ratio(plant, species, context),
				})

	var estimate: Array = []
	for accumulated in [0.0, 60.0, 179.0, 180.0, 400.0]:
		for typical in [-5.0, 0.0, 1.0, 25.0, 50.0, 200.0]:
			var plant := PlantInstance.new()
			plant.accumulated_focus_minutes = accumulated
			estimate.append({
				"accumulated_focus_minutes": accumulated, "typical_session_minutes": typical,
				"species_display_focus_minutes": 180.0,
				"out": PlantGrowthService.estimated_sessions_remaining(plant, species, typical),
			})

	# apply_growth is the stateful one: it must never regress a stage and must
	# report just_matured exactly once. Running it twice pins both.
	var apply: Array = []
	for stored_stage in [0, 1, 2]:
		for plant_minutes in [0.0, 90.0, 180.0, 500.0]:
			var plant := PlantInstance.new()
			plant.growth_stage = stored_stage
			plant.accumulated_focus_minutes = plant_minutes
			var ctx := RequirementContext.new()
			ctx.plant_focus_minutes = plant_minutes
			var first := PlantGrowthService.apply_growth(plant, species, ctx)
			var second := PlantGrowthService.apply_growth(plant, species, ctx)
			apply.append({
				"stored_stage": stored_stage, "plant_focus_minutes": plant_minutes,
				"first": {
					"previous_stage": first.previous_stage, "new_stage": first.new_stage,
					"progress_ratio": first.progress_ratio, "stage_changed": first.stage_changed,
					"just_matured": first.just_matured,
				},
				"second": {
					"previous_stage": second.previous_stage, "new_stage": second.new_stage,
					"progress_ratio": second.progress_ratio, "stage_changed": second.stage_changed,
					"just_matured": second.just_matured,
				},
			})

	return {
		"constants": {
			"DISPLAY_STAGE": PlantGrowthService.DISPLAY_STAGE,
			"STAGE_NAMES": PlantGrowthService.STAGE_NAMES,
		},
		"stage_for_ratio": stage_for_ratio,
		"stage_name": stage_name,
		"progress_ratio": progress,
		"estimated_sessions_remaining": estimate,
		"apply_growth_twice": apply,
	}


# --- RequirementEvaluator -----------------------------------------------------

func _sweep_requirements() -> Dictionary:
	var context := _synthetic_context()
	var context_dump := {
		"total_focus_minutes": context.total_focus_minutes,
		"completed_focus_sessions": context.completed_focus_sessions,
		"completed_break_sessions": context.completed_break_sessions,
		"unique_focus_days": context.unique_focus_days,
		"sessions_by_start_hour": context.sessions_by_start_hour,
		"focus_session_lengths": context.focus_session_lengths,
		"player_level": context.player_level,
		"plants_matured": context.plants_matured,
		"species_discovered": context.species_discovered,
		"species_total": context.species_total,
		"unlocked_achievement_ids": context.unlocked_achievement_ids,
		"completed_expedition_ids": context.completed_expedition_ids,
		"plant_focus_minutes": context.plant_focus_minutes,
		"plant_session_count": context.plant_session_count,
		"plant_unique_days": context.plant_unique_days,
		"plant_sessions_by_start_hour": context.plant_sessions_by_start_hour,
		"plant_session_lengths": context.plant_session_lengths,
	}

	# One param set per type, plus the degenerate zero/negative targets that must
	# come back 1.0 rather than NaN, plus a midnight-wrapping hour window.
	var param_sets := {
		Requirement.Type.TOTAL_FOCUS_MINUTES: [
			{"amount": 0.0}, {"amount": -10.0}, {"amount": 100.0}, {"amount": 500.0}, {},
		],
		Requirement.Type.COMPLETED_SESSIONS: [{"count": 0}, {"count": 3}, {"count": 40}, {}],
		Requirement.Type.UNIQUE_FOCUS_DAYS: [{"count": 1}, {"count": 4}, {"count": 90}, {}],
		Requirement.Type.CONSECUTIVE_DAYS: [{"count": 1}, {"count": 3}, {"count": 30}, {}],
		Requirement.Type.SESSIONS_IN_TIME_WINDOW: [
			{"count": 1, "start_hour": 5, "end_hour": 9},
			{"count": 2, "start_hour": 20, "end_hour": 2},
			{"count": 3, "start_hour": 0, "end_hour": 23},
			{"count": 1, "start_hour": -4, "end_hour": 99},
			{"count": 1, "start_hour": 13, "end_hour": 13},
			{},
		],
		Requirement.Type.SESSION_LENGTH_AT_LEAST: [
			{"minutes": 25.0, "count": 1}, {"minutes": 90.0, "count": 2},
			{"minutes": 0.0, "count": 1}, {},
		],
		Requirement.Type.BREAK_SESSIONS: [{"count": 1}, {"count": 10}, {}],
		Requirement.Type.PLANTS_MATURED: [{"count": 1}, {"count": 7}, {}],
		Requirement.Type.SPECIES_DISCOVERED: [{"count": 2}, {"count": 16}, {}],
		Requirement.Type.PLAYER_LEVEL: [{"level": 1}, {"level": 13}, {"level": 40}, {}],
		Requirement.Type.CATALOGUE_COMPLETION: [
			{"ratio": 0.25}, {"ratio": 1.0}, {"ratio": 0.0}, {},
		],
		Requirement.Type.ACHIEVEMENT_UNLOCKED: [
			{"achievement_id": "first_sprout"}, {"achievement_id": "nope"}, {},
		],
		Requirement.Type.EXPEDITION_COMPLETED: [
			{"expedition_id": "north_ridge"}, {"expedition_id": "nope"}, {},
		],
	}

	var evaluate: Array = []
	var describe: Array = []
	for type_value: int in param_sets:
		for params: Dictionary in param_sets[type_value]:
			for scope in [Requirement.Scope.GLOBAL, Requirement.Scope.ACTIVE_PLANT]:
				var r := Requirement.make(type_value, params, scope)
				evaluate.append({
					"type": int(type_value), "scope": int(scope), "params": params.duplicate(true),
					"out": RequirementEvaluator.evaluate(r, context),
					"is_met": RequirementEvaluator.is_met(r, context),
				})
			var described := Requirement.make(type_value, params, Requirement.Scope.GLOBAL)
			describe.append({
				"type": int(type_value), "params": params.duplicate(true),
				"out": RequirementEvaluator.describe(described),
			})

	# An author override must win over the generated copy, always.
	var override := Requirement.make(
		Requirement.Type.TOTAL_FOCUS_MINUTES, {"amount": 60.0}, Requirement.Scope.GLOBAL
	)
	override.description_override = "Sit with it for an hour"
	describe.append({
		"type": int(Requirement.Type.TOTAL_FOCUS_MINUTES), "params": {"amount": 60.0},
		"description_override": "Sit with it for an hour",
		"out": RequirementEvaluator.describe(override),
	})

	return {"context": context_dump, "evaluate": evaluate, "describe": describe}


# --- StreakCalculator ---------------------------------------------------------

func _sweep_streak() -> Dictionary:
	var scenarios: Array = []

	# [label, [[date_key, minutes, kind, completion], ...], threshold, today]
	var cases: Array = [
		["empty", [], 20.0, "2026-08-29"],
		["single_today", [["2026-08-29", 30.0, 0, 0]], 20.0, "2026-08-29"],
		["single_yesterday", [["2026-08-28", 30.0, 0, 0]], 20.0, "2026-08-29"],
		["gap_of_two_days", [["2026-08-26", 30.0, 0, 0]], 20.0, "2026-08-29"],
		["three_in_a_row_to_today", [
			["2026-08-27", 25.0, 0, 0], ["2026-08-28", 25.0, 0, 0], ["2026-08-29", 25.0, 0, 0],
		], 20.0, "2026-08-29"],
		["broken_run_keeps_longest", [
			["2026-08-01", 25.0, 0, 0], ["2026-08-02", 25.0, 0, 0], ["2026-08-03", 25.0, 0, 0],
			["2026-08-04", 25.0, 0, 0], ["2026-08-20", 25.0, 0, 0], ["2026-08-29", 25.0, 0, 0],
		], 20.0, "2026-08-29"],
		["below_threshold_does_not_qualify", [
			["2026-08-28", 19.9, 0, 0], ["2026-08-29", 20.0, 0, 0],
		], 20.0, "2026-08-29"],
		["minutes_accumulate_across_sessions", [
			["2026-08-29", 11.0, 0, 0], ["2026-08-29", 10.0, 0, 0],
		], 20.0, "2026-08-29"],
		["breaks_do_not_count", [
			["2026-08-29", 60.0, 1, 0], ["2026-08-29", 60.0, 2, 0],
		], 20.0, "2026-08-29"],
		["cancelled_does_not_count", [["2026-08-29", 60.0, 0, 2]], 20.0, "2026-08-29"],
		["zero_threshold", [["2026-08-29", 0.5, 0, 0]], 0.0, "2026-08-29"],
		["month_boundary", [
			["2026-07-31", 25.0, 0, 0], ["2026-08-01", 25.0, 0, 0],
		], 20.0, "2026-08-01"],
		["leap_day", [
			["2024-02-28", 25.0, 0, 0], ["2024-02-29", 25.0, 0, 0], ["2024-03-01", 25.0, 0, 0],
		], 20.0, "2024-03-01"],
		["missing_date_key_ignored", [["", 60.0, 0, 0], ["2026-08-29", 25.0, 0, 0]], 20.0, "2026-08-29"],
	]

	for entry: Array in cases:
		var sessions: Array[FocusSession] = []
		for row: Array in entry[1]:
			var s := FocusSession.new()
			s.id = "s_%d" % sessions.size()
			s.date_key = row[0]
			s.actual_focus_minutes = row[1]
			s.kind = row[2]
			s.completion = row[3]
			sessions.append(s)
		var result := StreakCalculator.calculate(sessions, entry[2], entry[3])
		scenarios.append({
			"label": entry[0],
			"sessions": entry[1],
			"threshold_minutes": entry[2],
			"today_key": entry[3],
			"out": {
				"current": result.current,
				"longest": result.longest,
				"qualifying_days": result.qualifying_days,
				"last_qualifying_day": result.last_qualifying_day,
			},
		})

	return {"calculate": scenarios}


# --- Defensive from_dict ------------------------------------------------------

func _sweep_models() -> Dictionary:
	# Every entry is a save a hostile or buggy writer could produce. The port has
	# to repair each one identically, because these are the paths that decide
	# whether a damaged file loses one record or the whole garden.
	var session_inputs: Array = [
		{},
		{"id": "s1", "kind": 99, "completion": -4, "anomaly": 77},
		{"id": "s2", "actual_focus_minutes": -50.0, "paused_minutes": -3.0,
		 "intended_duration_minutes": -25.0, "xp_earned": -100},
		{"id": "s3", "start_hour": 47},
		{"id": "s4", "start_hour": -9},
		{"id": "s5", "date_key": "garbage", "started_at_utc": 1787000000.0},
		{"id": "s6", "date_key": "2026-08-29", "started_at_utc": 1787000000.0},
		{"id": "s7", "kind": 2, "completion": 3, "anomaly": 1, "awards_applied": true,
		 "actual_focus_minutes": 12.5, "project_id": "p", "plant_uid": "pl"},
		{"id": "s8", "kind": "not-an-int", "actual_focus_minutes": "nope"},
	]
	var sessions: Array = []
	for data: Dictionary in session_inputs:
		sessions.append({"in": data.duplicate(true), "out": FocusSession.from_dict(data).to_dict()})

	var plant_inputs: Array = [
		{},
		{"uid": "p1", "growth_stage": -4, "accumulated_focus_minutes": -10.0, "maturity": 9},
		# location wins over a contradictory placement — the §62 invariant
		{"uid": "p2", "location": 0, "shelf_slot": 5, "garden_cell_x": 2, "garden_cell_y": 3,
		 "garden_rotation": 2},
		{"uid": "p3", "location": 1, "shelf_slot": 5, "garden_cell_x": 2, "garden_cell_y": 3,
		 "garden_rotation": 2},
		{"uid": "p4", "location": 2, "shelf_slot": 5, "garden_cell_x": 2, "garden_cell_y": 3,
		 "garden_rotation": 2},
		{"uid": "p5", "location": 77},
		# posmod, not % — the trap JavaScript gets wrong for negatives
		{"uid": "p6", "location": 2, "garden_rotation": -1},
		{"uid": "p7", "location": 2, "garden_rotation": -7},
		{"uid": "p8", "location": 2, "garden_rotation": 9},
		{"uid": "p9", "pot_id": ""},
		{"uid": "p10", "mutation_ids": ["a", "b"], "contributing_session_ids": ["s1", "s2"]},
		{"uid": "p11", "is_mystery": true, "mystery_revealed": false, "species_id": "secret"},
	]
	var plants: Array = []
	for data: Dictionary in plant_inputs:
		plants.append({"in": data.duplicate(true), "out": PlantInstance.from_dict(data).to_dict()})

	var profile_inputs: Array = [
		{},
		{"total_xp": -500, "current_streak": -3, "longest_streak": -9},
		# longest can never sit below current
		{"current_streak": 12, "longest_streak": 4},
		{"current_streak": 4, "longest_streak": 12},
		{"display_name": "", "focus_sessions_in_cycle": -2},
		{"display_name": "Joshua", "total_xp": 4200, "unlocked_ids": ["a", "b"],
		 "onboarding_completed": true, "last_focus_date_key": "2026-08-29"},
	]
	var profiles: Array = []
	for data: Dictionary in profile_inputs:
		profiles.append({"in": data.duplicate(true), "out": PlayerProfile.from_dict(data).to_dict()})

	return {
		"focus_session_from_dict": sessions,
		"plant_instance_from_dict": plants,
		"player_profile_from_dict": profiles,
	}


# --- Persistence --------------------------------------------------------------

## Settings clamping, the container's defensive load, the migration chain, and
## the bundle envelope.
##
## This is the layer where "probably right" is least acceptable: SaveBundle is the
## wire format BETWEEN the two clients, so a divergence here does not produce a
## wrong pixel, it produces a garden that imports smaller than it was exported.
func _sweep_persistence() -> Dictionary:
	# Every numeric setting driven past both ends of its range, because a
	# corrupted duration makes the timer unusable from inside the app.
	var settings_inputs: Array = [
		{},
		{"focus_duration_minutes": 0.0, "short_break_minutes": 0.0, "long_break_minutes": 0.0},
		{"focus_duration_minutes": 99999.0, "short_break_minutes": 9999.0},
		{"focus_duration_minutes": -25.0, "minimum_credit_minutes": -5.0},
		{"sessions_before_long_break": 0}, {"sessions_before_long_break": 99},
		{"ui_scale": 0.1}, {"ui_scale": 12.0},
		{"animation_intensity": -1.0}, {"animation_intensity": 5.0},
		{"volume_master": -0.5, "volume_music": 2.0},
		{"window_mode": "nonsense"}, {"window_mode": "borderless"},
		{"theme_mode": "chartreuse"}, {"theme_mode": "dark"},
		{"daily_goal_minutes": 0.0}, {"daily_goal_minutes": 100000.0},
		{"streak_threshold_minutes": 0.0},
		{"notify_focus_complete": false, "check_for_updates": false},
		{"focus_duration_minutes": "not a number", "reduced_motion": "yes"},
	]
	var settings: Array = []
	for data: Dictionary in settings_inputs:
		settings.append({
			"in": data.duplicate(true), "out": GameSettings.from_dict(data).to_dict()
		})

	var catalogue_inputs: Array = [
		{},
		{"species_id": "aloe_vera", "discovered": true, "times_grown": -4},
		{"species_id": "monstera", "total_focus_minutes": -100.0},
		{"species_id": "fern", "fastest_growth_minutes": -1.0},
		{"species_id": "fern", "fastest_growth_minutes": 88.5, "favorite": true},
	]
	var catalogue: Array = []
	for data: Dictionary in catalogue_inputs:
		catalogue.append({
			"in": data.duplicate(true), "out": CatalogueEntry.from_dict(data).to_dict()
		})

	var achievement_inputs: Array = [
		{},
		{"achievement_id": "first_sprout", "unlocked": true, "progress_ratio": 0.4},
		{"achievement_id": "night_owl", "unlocked": false, "progress_ratio": 7.0},
		{"achievement_id": "night_owl", "unlocked": false, "progress_ratio": -3.0},
	]
	var achievements: Array = []
	for data: Dictionary in achievement_inputs:
		achievements.append({
			"in": data.duplicate(true), "out": AchievementState.from_dict(data).to_dict()
		})

	var journal_inputs: Array = [
		{},
		{"id": "j1", "kind": 99},
		{"id": "j2", "kind": -1},
		{"id": "j3", "kind": 7, "title": "Reached level 13", "body": "Grown from 12h."},
	]
	var journal: Array = []
	for data: Dictionary in journal_inputs:
		journal.append({"in": data.duplicate(true), "out": JournalEntry.from_dict(data).to_dict()})

	var project_inputs: Array = [
		{},
		{"id": "p1", "total_focus_minutes": -20.0},
		{"id": "p2", "display_name": "Network+", "color_token": "sky", "archived": true},
	]
	var projects: Array = []
	for data: Dictionary in project_inputs:
		projects.append({
			"in": data.duplicate(true), "out": ProjectCategory.from_dict(data).to_dict()
		})

	var shelf_inputs: Array = [
		{}, {"slot_count": 0}, {"slot_count": 9999},
		{"layout_id": "sh1", "display_name": "Window ledge", "style_id": "pale_ash"},
	]
	var shelves: Array = []
	for data: Dictionary in shelf_inputs:
		shelves.append({"in": data.duplicate(true), "out": ShelfLayout.from_dict(data).to_dict()})

	# Includes the format-1 bare-string decoration, which the model still reads
	# directly so a save that skipped the migration renders rather than crashes.
	var garden_inputs: Array = [
		{},
		{"grid_size_x": 0, "grid_size_y": 0},
		{"grid_size_x": 9999, "grid_size_y": 9999},
		{"decorations": {"1,1": "stone_bench"}},
		{"decorations": {"1,1": {"id": "stone_bench", "rotation": 2}}},
		{"decorations": {"1,1": {"id": "stone_bench", "rotation": -1}}},
		{"decorations": {"1,1": {"id": "", "rotation": 1}}},
		{"decorations": {"1,1": {"rotation": 1}}},
		{"decorations": {"1,1": ""}},
		{"unlocked_expansion_ids": ["a", "b", "a"]},
	]
	var gardens: Array = []
	for data: Dictionary in garden_inputs:
		gardens.append({"in": data.duplicate(true), "out": GardenLayout.from_dict(data).to_dict()})

	# Duplicate ids, id-less rows, and non-object entries: all the ways a
	# hand-edited or foreign save arrives damaged.
	var save_inputs: Array = [
		{},
		{"save_version": 2, "plants": [
			{"uid": "a"}, {"uid": "a"}, {"uid": ""}, "not a dict", {"uid": "b"}
		]},
		{"projects": [{"id": "p"}, {"id": "p"}, {"id": ""}]},
		{"catalogue": [{"species_id": "s"}, {"species_id": "s"}, {"species_id": ""}]},
		{"achievements": [{"achievement_id": "x"}, {"achievement_id": "x"}]},
		{"journal": [{"id": "j"}, {"id": "j"}, {"id": ""}]},
		{"save_version": 1},
		{"in_flight_session": {"wall_start": 123.0, "state": 1}},
	]
	var saves: Array = []
	for data: Dictionary in save_inputs:
		saves.append({"in": data.duplicate(true), "out": SaveData.from_dict(data).to_dict()})

	# The real chain, plus the two refusal cases the framework exists for.
	var migration_inputs: Array = [
		{"label": "v1 bare-string decoration upgrades", "target": 2, "data": {
			"save_version": 1,
			"garden": {"decorations": {"0,0": "stone_bench", "1,2": "pond"}},
			"settings": {},
		}},
		{"label": "v1 already-dict decoration left alone", "target": 2, "data": {
			"save_version": 1,
			"garden": {"decorations": {"0,0": {"id": "pond", "rotation": 3}}},
			"settings": {"theme_mode": "dark"},
		}},
		{"label": "v1 empty decoration dropped", "target": 2, "data": {
			"save_version": 1, "garden": {"decorations": {"0,0": ""}}, "settings": {},
		}},
		{"label": "already current is a no-op", "target": 2, "data": {"save_version": 2}},
		{"label": "future version refused", "target": 2, "data": {"save_version": 99}},
		{"label": "missing version reads as 1", "target": 2, "data": {}},
	]
	var migrations: Array = []
	for entry: Dictionary in migration_inputs:
		var result := SaveMigrations.migrate(entry["data"], entry["target"])
		migrations.append({
			"label": entry["label"],
			"in": (entry["data"] as Dictionary).duplicate(true),
			"target": entry["target"],
			"status": int(result.status),
			"from_version": result.from_version,
			"to_version": result.to_version,
			"applied_steps": result.applied_steps,
			"data": result.data,
		})

	# A gap in the chain must stop and report rather than half-migrate.
	var gap_chain: Array[Dictionary] = [
		{"from": 1, "to": 2, "apply": func(d: Dictionary) -> Dictionary: return d},
	]
	var gap := SaveMigrations.migrate({"save_version": 1}, 4, gap_chain)
	migrations.append({
		"label": "gap in the chain",
		"in": {"save_version": 1}, "target": 4,
		"status": int(gap.status), "from_version": gap.from_version,
		"to_version": gap.to_version, "applied_steps": gap.applied_steps, "data": gap.data,
	})

	return {
		"constants": {"SAVE_CURRENT_VERSION": SaveData.CURRENT_VERSION},
		"game_settings_from_dict": settings,
		"catalogue_entry_from_dict": catalogue,
		"achievement_state_from_dict": achievements,
		"journal_entry_from_dict": journal,
		"project_category_from_dict": projects,
		"shelf_layout_from_dict": shelves,
		"garden_layout_from_dict": gardens,
		"save_data_from_dict": saves,
		"migrate": migrations,
		"version_util": _sweep_version_util(),
		"save_bundle": _sweep_save_bundle(),
	}


func _sweep_version_util() -> Array:
	var versions: Array[String] = [
		"1.0.0", "0.9.0", "0.10.0", "1.2.3", "v1.2.3", "V1.2.3", "1.2.3-beta.1",
		"1.2.3+build9", "1.2", "1", "", "x.y.z", "1.-2.0", "1..2", "1.", "1.2.3.4",
		"01.02.03", "0.0.0", "10.0.0", "2.0.0-rc1",
	]
	var out: Array = []
	for v: String in versions:
		out.append({
			"version": v,
			"parse": VersionUtil.parse(v),
			"is_valid": VersionUtil.is_valid(v),
			"compare_to_1_0_0": VersionUtil.compare(v, "1.0.0"),
			"is_newer_than_1_0_0": VersionUtil.is_newer(v, "1.0.0"),
		})
	return out


func _sweep_save_bundle() -> Dictionary:
	var save := SaveData.create_new()
	save.profile.display_name = "Fixture"
	save.profile.total_xp = 4200
	save.profile.created_at_utc = 1780000000.0
	save.in_flight_session = {"wall_start": 999.0, "state": 1}
	var plant := PlantInstance.new()
	plant.uid = "pl_fixture"
	plant.species_id = &"aloe_vera"
	plant.accumulated_focus_minutes = 90.0
	save.plants.append(plant)

	var sessions: Array[FocusSession] = []
	for i in 4:
		var s := FocusSession.new()
		s.id = "s_%d" % i
		s.date_key = "2026-08-2%d" % (i + 1)
		s.actual_focus_minutes = 25.0
		s.kind = FocusSession.Kind.FOCUS if i < 3 else FocusSession.Kind.SHORT_BREAK
		sessions.append(s)

	var built := SaveBundle.build(save, sessions, "0.1.0", 1787000000.0)

	# The damaged bundle: a duplicate id, an id-less row, and a non-object entry.
	var damaged := built.duplicate(true)
	var rows: Array = (damaged[SaveBundle.SESSIONS_KEY] as Array).duplicate(true)
	rows.append(rows[0])
	rows.append({"date_key": "2026-08-29", "actual_focus_minutes": 10.0})
	rows.append("not a row")
	damaged[SaveBundle.SESSIONS_KEY] = rows

	var no_sessions := built.duplicate(true)
	no_sessions.erase(SaveBundle.SESSIONS_KEY)

	var cases: Array = []
	for entry: Array in [["clean", built], ["damaged", damaged], ["no_sessions_key", no_sessions]]:
		var imported := SaveBundle.read(entry[1])
		cases.append({
			"label": entry[0],
			"summary": {
				"plant_count": imported.summary.plant_count,
				"session_count": imported.summary.session_count,
				"break_count": imported.summary.break_count,
				"focus_minutes": imported.summary.focus_minutes,
				"days_focused": imported.summary.days_focused,
				"first_date_key": imported.summary.first_date_key,
				"last_date_key": imported.summary.last_date_key,
				"app_version": imported.summary.app_version,
				"has_sessions": imported.summary.has_sessions,
				"skipped_count": imported.summary.skipped_count,
				"duplicate_count": imported.summary.duplicate_count,
			},
			"describe_range": imported.summary.describe_range(),
			"session_ids": _session_ids(imported.sessions),
		})

	return {"built": built, "read": cases}


func _session_ids(sessions: Array[FocusSession]) -> Array:
	var out: Array = []
	for s: FocusSession in sessions:
		out.append(s.id)
	return out


# --- Builders -----------------------------------------------------------------

## A species that exists only for fixtures, so retuning shipped content cannot
## move these numbers.
func _synthetic_species(maturity_minutes: float) -> PlantSpecies:
	var species := PlantSpecies.new()
	species.id = &"fixture_species"
	species.display_name = "Fixture Species"
	species.growth_requirement = Requirement.make(
		Requirement.Type.TOTAL_FOCUS_MINUTES,
		{"amount": maturity_minutes},
		Requirement.Scope.ACTIVE_PLANT
	)
	return species


## A context with every field set to a distinct, memorable value, so a TypeScript
## reader that wires two fields the wrong way round produces a visibly wrong
## ratio rather than an accidentally correct one.
func _synthetic_context() -> RequirementContext:
	var c := RequirementContext.new()
	c.total_focus_minutes = 250.0
	c.completed_focus_sessions = 11
	c.completed_break_sessions = 6
	c.unique_focus_days = PackedStringArray([
		"2026-08-24", "2026-08-25", "2026-08-26", "2026-08-28",
	])
	c.current_streak = 1
	c.longest_streak = 3
	for hour in [6, 6, 7, 13, 21, 22, 23, 0, 1]:
		c.sessions_by_start_hour[hour] += 1
	c.focus_session_lengths = PackedFloat32Array([15.0, 25.0, 25.0, 50.0, 90.0, 120.0])
	c.player_level = 13
	c.plants_matured = 4
	c.species_discovered = 5
	c.species_total = 16
	c.unlocked_achievement_ids = PackedStringArray(["first_sprout", "night_owl"])
	c.completed_expedition_ids = PackedStringArray(["north_ridge"])

	c.plant_focus_minutes = 95.0
	c.plant_session_count = 4
	c.plant_unique_days = PackedStringArray(["2026-08-25", "2026-08-26"])
	for hour in [7, 13, 21]:
		c.plant_sessions_by_start_hour[hour] += 1
	c.plant_session_lengths = PackedFloat32Array([20.0, 25.0, 50.0])
	return c


# --- Output -------------------------------------------------------------------

func _write(name: String, payload: Dictionary) -> void:
	var count := 0
	for key: String in payload:
		if payload[key] is Array:
			count += (payload[key] as Array).size()

	var path := OUTPUT_DIR.path_join("%s.json" % name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("Could not write %s: %s" % [path, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(payload, "  ", false) + "\n")
	file.close()

	_files_written += 1
	_cases_written += count
	print("  %-18s %5d cases" % [name, count])
