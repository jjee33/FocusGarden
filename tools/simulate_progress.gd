extends SceneTree
## Fabricates a realistic play history in the local dev save.
##
##     ... --headless --path . --script res://tools/simulate_progress.gd
##
## DESTRUCTIVE: overwrites the save in user://. It is a development tool, never
## shipped, and the export preset excludes tools/.
##
## Why this exists: every screen after the timer — catalogue, shelf, statistics,
## heatmap, journal, garden — is meaningless on an empty save. Judging their
## layout, density and empty-versus-full behaviour needs months of plausible
## history, and waiting for that in real time is not an option. It also
## exercises growth, XP, streaks and achievements over hundreds of sessions,
## which is a genuine integration test of the whole progression stack.
##
## The history is deliberately irregular: missed days, varying lengths, varying
## hours, and a mix of projects. A tidy 25-minutes-every-day history would hide
## exactly the layout problems this is meant to expose.

const DAYS: int = 120
## Chance a given day has any focus at all. Leaves natural gaps, so streaks and
## the heatmap have something real to show.
const ACTIVE_DAY_CHANCE: float = 0.72
const SESSION_LENGTHS: Array[float] = [15.0, 25.0, 25.0, 25.0, 45.0, 50.0, 90.0]
## Hours sessions start at, weighted toward normal working patterns but with
## enough spread to trigger the early-bird and night-owl achievements.
const START_HOURS: Array[int] = [6, 7, 8, 9, 9, 10, 11, 13, 14, 15, 16, 19, 20, 21, 22, 23]

const GROW_ORDER: Array[String] = [
	"pothos", "aloe_vera", "snake_plant", "spider_plant", "jade_plant",
	"echeveria", "peace_lily", "monstera", "boston_fern", "rubber_plant",
	"lavender", "sunflower", "orchid", "moon_cactus",
	# Trailing entries the fabricated history cannot finish, so the save ends in
	# the normal mid-play state: something part-grown and selected.
	"calathea", "bonsai",
]

var _app_state: Node
var _content_db: Node
var _statistics: Node
var _progression: Node
var _achievements: Node


func _init() -> void:
	await process_frame
	_app_state = root.get_node("/root/AppState")
	_content_db = root.get_node("/root/ContentDB")
	_statistics = root.get_node("/root/StatisticsManager")
	_progression = root.get_node("/root/ProgressionManager")
	_achievements = root.get_node("/root/AchievementManager")

	seed(20260816)

	var sessions := _build_sessions()
	_app_state.sessions = sessions
	print("Fabricated %d sessions across %d days." % [sessions.size(), DAYS])

	_grow_plants(sessions)
	_award_experience(sessions)
	_settle_streak()

	_statistics.invalidate()
	var unlocked: PackedStringArray = _achievements.evaluate_all(_statistics.build_context())
	print("Achievements unlocked: %d" % unlocked.size())

	_report()
	_persist(sessions)
	quit(0)


func _build_sessions() -> Array[FocusSession]:
	var sessions: Array[FocusSession] = []
	var projects: Array = _app_state.get_active_projects()
	if projects.is_empty():
		printerr("No projects to attribute sessions to.")
		return sessions

	var now := Time.get_unix_time_from_system()

	for day_offset in range(DAYS, 0, -1):
		if randf() > ACTIVE_DAY_CHANCE:
			continue

		var day_start := now - float(day_offset) * float(TimeUtil.SECONDS_PER_DAY)
		var date_key := TimeUtil.local_date_key(day_start)
		var per_day := 1 + randi() % 4

		for i in per_day:
			var length: float = SESSION_LENGTHS[randi() % SESSION_LENGTHS.size()]
			var hour: int = START_HOURS[randi() % START_HOURS.size()]
			var project: ProjectCategory = projects[randi() % projects.size()]

			var session := FocusSession.new()
			session.id = Uid.generate("s")
			session.kind = FocusSession.Kind.FOCUS
			session.date_key = date_key
			session.start_hour = hour
			session.started_at_utc = day_start
			session.ended_at_utc = day_start + length * 60.0
			session.intended_duration_minutes = length
			# Most sessions run to completion; a few end early, as they do in life.
			if randf() < 0.14:
				session.completion = FocusSession.Completion.ENDED_EARLY
				session.actual_focus_minutes = length * randf_range(0.35, 0.9)
			else:
				session.completion = FocusSession.Completion.COMPLETED
				session.actual_focus_minutes = length
			session.project_id = project.id
			session.awards_applied = true
			sessions.append(session)

			# A break after roughly half of them, which the Taking Care
			# achievement counts.
			if randf() < 0.5:
				var rest := FocusSession.new()
				rest.id = Uid.generate("s")
				rest.kind = FocusSession.Kind.SHORT_BREAK
				rest.date_key = date_key
				rest.start_hour = hour
				rest.started_at_utc = session.ended_at_utc
				rest.ended_at_utc = rest.started_at_utc + 300.0
				rest.intended_duration_minutes = 5.0
				rest.actual_focus_minutes = 5.0
				rest.awards_applied = true
				rest.project_id = project.id
				sessions.append(rest)

	sessions.sort_custom(
		func(a: FocusSession, b: FocusSession) -> bool: return a.started_at_utc < b.started_at_utc
	)
	return sessions


## Distributes the fabricated focus time across a series of plants, maturing them
## in order, exactly as playing through would have.
func _grow_plants(sessions: Array[FocusSession]) -> void:
	var focus_sessions: Array[FocusSession] = []
	for session: FocusSession in sessions:
		if session.is_focus() and session.counts_toward_progress():
			focus_sessions.append(session)

	var index := 0
	for species_id: String in GROW_ORDER:
		if index >= focus_sessions.size():
			break
		var species: PlantSpecies = _content_db.get_species(StringName(species_id))
		if species == null:
			continue

		var plant: PlantInstance = _app_state.start_growing(StringName(species_id))
		if plant == null:
			continue

		# Sessions belonging to this plant, accumulated as we go. Asking AppState
		# to rescan the whole history for them on every iteration turned this
		# loop quadratic and made the tool unusable.
		var plant_sessions: Array[FocusSession] = []

		# Feed sessions in until the requirement is satisfied, then move on.
		while index < focus_sessions.size():
			var session: FocusSession = focus_sessions[index]
			session.plant_uid = plant.uid
			plant.accumulated_focus_minutes += session.actual_focus_minutes
			plant.contributing_session_ids.append(session.id)
			plant.primary_project_id = session.project_id
			plant_sessions.append(session)
			index += 1

			var context: RequirementContext = _statistics.build_plant_context(
				plant.uid, plant_sessions
			)
			var result: PlantGrowthService.GrowthResult = PlantGrowthService.apply_growth(
				plant, species, context
			)
			if result.just_matured:
				var entry: CatalogueEntry = _app_state.ensure_catalogue_entry(plant.species_id)
				entry.discover()
				entry.record_maturity(plant.accumulated_focus_minutes)
				entry.total_focus_minutes += plant.accumulated_focus_minutes
				plant.matured_at_utc = session.ended_at_utc
				_app_state.add_journal_entry(
					JournalEntry.create(
						JournalEntry.Kind.PLANT_MATURED,
						"%s reached maturity" % species.display_name,
						"Grown over %s of focus." % TimeUtil.format_duration(
							plant.accumulated_focus_minutes
						),
						plant.uid
					)
				)
				break

	# The save should end in the ordinary mid-play state: something on the go.
	# If the fabricated history happened to finish everything, plant one more so
	# the screens are exercised with an active target rather than an empty slot.
	var growing: Array = _app_state.get_growing_plants()
	if growing.is_empty():
		var fresh: PlantInstance = _app_state.start_growing(&"monstera")
		if fresh != null:
			growing = [fresh]
	_app_state.data.profile.active_plant_uid = growing[0].uid if not growing.is_empty() else ""


func _award_experience(sessions: Array[FocusSession]) -> void:
	var total := 0
	for session: FocusSession in sessions:
		var xp := XpFormula.xp_for_session(session)
		session.xp_earned = xp
		total += xp
	_app_state.data.profile.total_xp = total
	_progression.reconcile_level_unlocks()


func _settle_streak() -> void:
	var streak: StreakCalculator.Result = StreakCalculator.calculate(
		_app_state.sessions, _app_state.get_settings().streak_threshold_minutes
	)
	var profile: PlayerProfile = _app_state.data.profile
	profile.current_streak = streak.current
	profile.longest_streak = streak.longest
	profile.last_focus_date_key = streak.last_qualifying_day


func _report() -> void:
	# Deliberately untyped. Annotating this as StatisticsManager.Summary makes the
	# autoload's script a COMPILE-TIME dependency of this tool, and autoloads are
	# not registered yet when a --script tool is compiled. The result is not an
	# error but something worse: a stale copy of the autoload gets compiled, and
	# calls silently hit an older version of the class.
	var summary: Variant = _statistics.get_summary()
	print("  lifetime focus : %s" % TimeUtil.format_duration(summary.focus_lifetime))
	print("  sessions       : %d focus, %d breaks" % [summary.session_count, summary.break_count])
	print("  days focused   : %d" % summary.days_focused)
	print("  streak         : %d current, %d longest" % [summary.current_streak, summary.longest_streak])
	print("  plants matured : %d" % summary.plants_matured)
	print("  species found  : %d" % summary.species_discovered)
	print("  level          : %d (%d XP)" % [_progression.get_level(), summary.total_xp])


func _persist(sessions: Array[FocusSession]) -> void:
	var save_dir: String = root.get_node("/root/SaveManager").get_save_dir()
	# Written in one pass rather than session by session: three hundred atomic
	# writes would take minutes and prove nothing the single write does not.
	var error := SessionStore.save_all(save_dir, sessions)
	if error != OK:
		printerr("Failed to write sessions (error %d)" % error)
	if not _app_state.save_now():
		printerr("Failed to write the profile.")
	print("Saved to %s" % ProjectSettings.globalize_path(save_dir))
