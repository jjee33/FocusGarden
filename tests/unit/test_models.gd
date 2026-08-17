extends TestCase
## Player-data serialization (§53, §36 "validation on load").
##
## Every model must survive a to_dict/from_dict round trip, and must survive
## HOSTILE input: missing keys, wrong types, out-of-range enums, and duplicate
## ids. A save file is just JSON on the player's disk — it can be truncated,
## hand-edited, or written by a different version, and none of those may crash
## the game or corrupt a total.


func test_focus_session_round_trip() -> void:
	var session := FocusSession.create(FocusSession.Kind.FOCUS, 25.0, "proj_1", "plant_1")
	session.actual_focus_minutes = 24.5
	session.paused_minutes = 2.0
	session.xp_earned = 49
	session.awards_applied = true
	session.anomaly = FocusSession.Anomaly.SUSPEND

	var restored := FocusSession.from_dict(session.to_dict())
	assert_eq(restored.id, session.id, "id survived")
	assert_almost_eq(restored.actual_focus_minutes, 24.5, "credited minutes survived")
	assert_eq(restored.xp_earned, 49, "xp survived")
	assert_true(restored.awards_applied, "the idempotency guard survived")
	assert_eq(restored.anomaly, FocusSession.Anomaly.SUSPEND, "anomaly flag survived")
	assert_eq(restored.date_key, session.date_key, "date key survived")


func test_session_from_empty_dict_is_safe() -> void:
	var session := FocusSession.from_dict({})
	assert_eq(session.actual_focus_minutes, 0.0, "missing minutes default to zero")
	assert_eq(session.completion, FocusSession.Completion.COMPLETED, "completion has a default")


func test_session_rejects_negative_durations() -> void:
	# §55: impossible data must not corrupt statistics that sum these fields.
	var session := FocusSession.from_dict({
		"actual_focus_minutes": -500.0, "paused_minutes": -10.0, "xp_earned": -99,
	})
	assert_eq(session.actual_focus_minutes, 0.0, "negative focus time is clamped")
	assert_eq(session.paused_minutes, 0.0, "negative pause time is clamped")
	assert_eq(session.xp_earned, 0, "negative XP is clamped")


func test_session_rejects_out_of_range_enums() -> void:
	var session := FocusSession.from_dict({"kind": 99, "completion": -3, "anomaly": 42})
	assert_eq(session.kind, FocusSession.Kind.FOCUS, "bad kind falls back")
	assert_eq(session.completion, FocusSession.Completion.COMPLETED, "bad completion falls back")
	assert_eq(session.anomaly, FocusSession.Anomaly.NONE, "bad anomaly falls back")


func test_session_rebuilds_a_missing_date_key() -> void:
	# Without a date key a session cannot appear on the calendar or in a streak.
	var session := FocusSession.from_dict({
		"id": "s_1", "started_at_utc": 1_760_000_000.0, "date_key": "",
	})
	assert_true(
		TimeUtil.is_valid_date_key(session.date_key),
		"a date key was rebuilt from the timestamp"
	)


func test_plant_instance_round_trip() -> void:
	var plant := PlantInstance.create(&"monstera", "proj_1")
	plant.accumulated_focus_minutes = 125.5
	plant.growth_stage = 3
	plant.mutation_ids = [&"variegated"]
	plant.favorite = true
	plant.move_to_shelf(4)

	var restored := PlantInstance.from_dict(plant.to_dict())
	assert_eq(restored.species_id, &"monstera", "species survived")
	assert_almost_eq(restored.accumulated_focus_minutes, 125.5, "growth survived")
	assert_eq(restored.growth_stage, 3, "stage survived")
	assert_eq(restored.shelf_slot, 4, "placement survived")
	assert_eq(restored.mutation_ids.size(), 1, "mutations survived")
	assert_true(restored.favorite, "favorite survived")


func test_plant_placement_is_exclusive() -> void:
	# §62 requires duplicate placement bugs to be prevented. Moving a plant must
	# clear wherever it was before.
	var plant := PlantInstance.create(&"pothos")
	plant.move_to_shelf(2)
	plant.move_to_garden(Vector2i(1, 1))
	assert_eq(plant.shelf_slot, -1, "the shelf slot was released")
	assert_eq(plant.location, PlantInstance.Location.GARDEN, "the plant is in the garden")

	plant.move_to_inventory()
	assert_eq(plant.garden_cell, Vector2i(-1, -1), "the garden cell was released")


func test_corrupt_placement_is_repaired_on_load() -> void:
	# A save written by a buggy build could claim both placements at once.
	var plant := PlantInstance.from_dict({
		"uid": "pl_1", "species_id": "aloe",
		"location": int(PlantInstance.Location.SHELF),
		"shelf_slot": 3, "garden_cell_x": 5, "garden_cell_y": 5,
	})
	assert_eq(plant.garden_cell, Vector2i(-1, -1), "location wins; the garden cell is cleared")
	assert_eq(plant.shelf_slot, 3, "the declared placement is kept")


func test_mystery_seed_hides_its_species() -> void:
	# §19: the species must not be visible before the seed reveals itself.
	var plant := PlantInstance.create(&"secret")
	plant.is_mystery = true
	assert_true(plant.is_species_hidden(), "an unrevealed mystery seed is hidden")
	plant.mystery_revealed = true
	assert_false(plant.is_species_hidden(), "a revealed seed shows its species")


func test_settings_clamp_hostile_values() -> void:
	var settings := GameSettings.from_dict({
		"focus_duration_minutes": 0.0,
		"volume_master": 50.0,
		"ui_scale": -3.0,
		"window_mode": "hologram",
	})
	assert_gt(settings.focus_duration_minutes, 0.0, "a zero-minute timer is unusable and is clamped")
	assert_true(settings.volume_master <= 1.0, "volume is clamped to 0..1")
	assert_true(settings.ui_scale >= 0.75, "ui scale is clamped to a legible range")
	assert_eq(settings.window_mode, "windowed", "an unknown window mode falls back")


func test_settings_round_trip() -> void:
	var settings := GameSettings.new()
	settings.focus_duration_minutes = 50.0
	settings.reduced_motion = true
	settings.daily_goal_minutes = 120.0

	var restored := GameSettings.from_dict(settings.to_dict())
	assert_almost_eq(restored.focus_duration_minutes, 50.0, "duration survived")
	assert_true(restored.reduced_motion, "reduced motion survived")
	assert_almost_eq(restored.daily_goal_minutes, 120.0, "daily goal survived")


func test_profile_unlocks_are_granted_once() -> void:
	# §63: unlock events must only trigger once.
	var profile := PlayerProfile.create("Tester")
	assert_true(profile.grant_unlock("pot_a"), "first grant returns true")
	assert_false(profile.grant_unlock("pot_a"), "second grant returns false")
	assert_eq(profile.unlocked_ids.size(), 1, "no duplicate was stored")


func test_profile_repairs_impossible_streaks() -> void:
	var profile := PlayerProfile.from_dict({"current_streak": 10, "longest_streak": 2})
	assert_true(profile.longest_streak >= profile.current_streak, "longest cannot be below current")


func test_achievement_unlocks_once() -> void:
	var state := AchievementState.create(&"first_sprout")
	assert_true(state.unlock(), "first unlock returns true")
	assert_false(state.unlock(), "a second unlock is refused")
	assert_almost_eq(state.progress_ratio, 1.0, "an unlocked achievement reads as complete")


func test_catalogue_discovery_happens_once() -> void:
	var entry := CatalogueEntry.create(&"pothos")
	assert_true(entry.discover(), "first discovery returns true")
	assert_false(entry.discover(), "rediscovery returns false")


func test_catalogue_tracks_fastest_growth() -> void:
	var entry := CatalogueEntry.create(&"pothos")
	entry.record_maturity(300.0)
	entry.record_maturity(120.0)
	entry.record_maturity(400.0)
	assert_almost_eq(entry.fastest_growth_minutes, 120.0, "the fastest run is kept")
	assert_eq(entry.times_grown, 3, "every maturity is counted")


func test_save_data_round_trip() -> void:
	var save := SaveData.create_new()
	save.profile.display_name = "Fern"
	save.profile.total_xp = 1234
	save.plants.append(PlantInstance.create(&"pothos"))
	save.projects.append(ProjectCategory.create("Network+"))
	save.journal.append(JournalEntry.create(JournalEntry.Kind.SEED_PLANTED, "Planted", "A pothos."))

	var restored := SaveData.from_dict(save.to_dict())
	assert_eq(restored.profile.display_name, "Fern", "profile survived")
	assert_eq(restored.profile.total_xp, 1234, "xp survived")
	assert_eq(restored.plants.size(), 1, "plants survived")
	assert_eq(restored.projects.size(), 1, "projects survived")
	assert_eq(restored.journal.size(), 1, "journal survived")
	assert_eq(restored.save_version, SaveData.CURRENT_VERSION, "version stamped")


func test_save_data_drops_duplicate_ids() -> void:
	# §54 lists duplicated IDs as a case that must not be left undefined —
	# a dupe would make every lookup nondeterministic.
	var restored := SaveData.from_dict({
		"save_version": 1,
		"plants": [
			{"uid": "pl_1", "species_id": "pothos"},
			{"uid": "pl_1", "species_id": "aloe"},
			{"uid": "pl_2", "species_id": "jade"},
		],
	})
	assert_eq(restored.plants.size(), 2, "the duplicate was dropped")
	assert_eq(restored.plants[0].species_id, &"pothos", "the first occurrence won")


func test_save_data_skips_malformed_entries() -> void:
	# Losing one bad plant is recoverable; losing the save is not.
	var restored := SaveData.from_dict({
		"save_version": 1,
		"plants": [{"uid": "", "species_id": "x"}, {"uid": "pl_ok", "species_id": "pothos"}],
	})
	assert_eq(restored.plants.size(), 1, "the entry with no id was skipped, the good one kept")


func test_garden_expansion_grants_once() -> void:
	var garden := GardenLayout.create()
	assert_true(garden.grant_expansion("plot_2"), "first grant")
	assert_false(garden.grant_expansion("plot_2"), "second grant refused")


func test_garden_cell_key_round_trip() -> void:
	var cell := Vector2i(3, 7)
	assert_eq(GardenLayout.key_to_cell(GardenLayout.cell_key(cell)), cell, "cell key round trips")
	assert_eq(GardenLayout.key_to_cell("garbage"), Vector2i(-1, -1), "a bad key is rejected")
