extends SceneTree
## Fabricates a realistic play history in the local dev save.
##
##     ... --headless --path . --script res://tools/simulate_progress.gd
##
## DESTRUCTIVE: overwrites the save in user://. It is a development tool, never
## shipped, and the export preset excludes tools/.
##
## IT WILL REFUSE to overwrite a save it did not itself write. Every save this
## tool produces is stamped with SIMULATED_MARKER as the player name; anything
## else is treated as somebody's real garden and the run stops. Pass `-- --force`
## to override:
##
##     ... --script res://tools/simulate_progress.gd -- --force
##
## That guard exists because the docstring above did not save the one real save
## this tool has destroyed. The line had been read days before it mattered, and
## at the moment it mattered the tool said nothing at all.
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

	if not _may_overwrite_save():
		quit(1)
		return

	seed(20260816)
	_clear_previous_run()

	var sessions := _build_sessions()
	_app_state.sessions = sessions
	print("Fabricated %d sessions across %d days." % [sessions.size(), DAYS])

	_grow_plants(sessions)
	_award_experience(sessions)
	_settle_streak()

	_arrange_shelf()

	_statistics.invalidate()
	var unlocked: PackedStringArray = _achievements.evaluate_all(_statistics.build_context())
	print("Achievements unlocked: %d" % unlocked.size())

	_report()
	_persist(sessions)
	quit(0)


## Name stamped on every save this tool writes, and the thing the guard looks for.
const SIMULATED_MARKER: String = "Simulated Gardener"


## Refuses to run over a save this tool did not write.
##
## A fresh save is fine, and so is one of ours. Anything else belongs to a person
## and gets a message naming what is in it rather than a silent overwrite.
func _may_overwrite_save() -> bool:
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--force":
			print("--force given; overwriting whatever is there.")
			return true

	var save_manager: Node = root.get_node("/root/SaveManager")
	if not save_manager.has_existing_save():
		return true

	var profile: PlayerProfile = _app_state.data.profile
	if profile.display_name == SIMULATED_MARKER:
		return true

	printerr(
		"REFUSING: the save in %s was not written by this tool." % save_manager.get_save_dir()
	)
	printerr(
		"  It holds %d plants, %d sessions and %d projects."
		% [
			_app_state.data.plants.size(),
			_app_state.sessions.size(),
			_app_state.data.projects.size(),
		]
	)
	printerr("  Back it up, or pass `-- --force` if you are certain it is disposable.")
	return false


## Wipes what a previous run left behind.
##
## The header has always said DESTRUCTIVE, and it was only half true: sessions
## were replaced wholesale but plants, catalogue entries and journal rows were
## APPENDED. Two runs left two of every plant, stacked on the same garden squares,
## and a "plants matured: 32" line for a sixteen-species game. Anyone comparing
## screenshots between runs was comparing against a save that had quietly doubled.
##
## Projects and settings are deliberately kept: the starter projects are what the
## fabricated sessions are attributed to, and re-seeding them would change the
## history from run to run and defeat the fixed random seed above.
func _clear_previous_run() -> void:
	var data: SaveData = _app_state.data
	data.plants.clear()
	data.catalogue.clear()
	data.journal.clear()
	data.achievements.clear()
	data.shelf = ShelfLayout.create()
	data.garden = GardenLayout.create()
	data.profile.display_name = SIMULATED_MARKER
	data.profile.active_plant_uid = ""
	data.profile.total_xp = 0
	data.profile.current_streak = 0
	data.profile.longest_streak = 0
	data.profile.unlocked_ids = PackedStringArray()
	_app_state.sessions = []


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


## Puts some of the collection on display and gives them varied pots, so the
## shelf is exercised part-full rather than empty or completely packed. Both
## extremes hide layout problems.
func _arrange_shelf() -> void:
	var pot_ids: Array[StringName] = []
	for pot: PotStyle in _content_db.get_all_pots():
		pot_ids.append(pot.id)

	var slot := 0
	for plant: PlantInstance in _app_state.get_mature_plants():
		if slot >= 7:
			break
		plant.move_to_shelf(slot)
		plant.pot_id = pot_ids[slot % pot_ids.size()]
		slot += 1

	# One unfinished plant on the shelf as well. Displaying a plant from its first
	# stage is the whole point of the staged-maturity change, and a shelf of
	# nothing but finished specimens would never exercise it.
	for plant: PlantInstance in _app_state.get_growing_plants():
		if plant.can_be_displayed() and plant.location == PlantInstance.Location.INVENTORY:
			plant.move_to_shelf(slot)
			plant.pot_id = pot_ids[slot % pot_ids.size()]
			break

	_plant_the_garden()


## Plants out part of the collection and sets some ornaments, so the garden is
## exercised with a real arrangement rather than bare ground.
func _plant_the_garden() -> void:
	var layout: GardenLayout = _app_state.data.garden
	var context: RequirementContext = _statistics.build_context()
	GardenService.reconcile(layout, context, _content_db.get_all_expansions())

	var remaining: Array[PlantInstance] = []
	for plant: PlantInstance in _app_state.get_mature_plants():
		if plant.location == PlantInstance.Location.INVENTORY:
			remaining.append(plant)

	var index := 0
	for plant: PlantInstance in remaining:
		if index >= 6:
			break
		# Spread across the plot rather than filling row one, so overlap and
		# depth ordering are actually exercised.
		# Varied facings as well as varied cells: a row of one species all facing
		# the same way is exactly the thing facings exist to break up, and a
		# capture that never turns one would not show whether they work.
		plant.move_to_garden(
			Vector2i(index % layout.grid_size.x, (index * 2) % layout.grid_size.y),
			index % PlantInstance.GARDEN_ROTATIONS
		)
		index += 1

	# Cell -> [ornament id, quarter turns]. Turned ornaments are included on
	# purpose, so a capture shows whether rotation actually draws.
	var ornaments := {
		Vector2i(0, layout.grid_size.y - 1): ["stone_path", 0],
		Vector2i(1, layout.grid_size.y - 1): ["stone_path", 1],
		Vector2i(2, layout.grid_size.y - 1): ["garden_bench", 0],
		Vector2i(layout.grid_size.x - 1, 1): ["lantern", 2],
	}
	for cell: Vector2i in ornaments:
		if not layout.is_cell_in_bounds(cell):
			continue
		# Never bury a plant that was just placed.
		var occupied := false
		for plant: PlantInstance in _app_state.data.plants:
			if plant.location == PlantInstance.Location.GARDEN and plant.garden_cell == cell:
				occupied = true
				break
		if not occupied:
			var entry: Array = ornaments[cell]
			layout.set_decoration(cell, String(entry[0]), int(entry[1]))


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
