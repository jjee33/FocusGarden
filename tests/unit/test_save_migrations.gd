extends TestCase
## SaveMigrations (§53, §36).
##
## The real chain is empty at save version 1 — there is nothing older than the
## first release. These tests supply their own chains, so the framework is fully
## exercised BEFORE the first real migration exists rather than after players
## already have files that depend on it.


func test_current_version_needs_no_migration() -> void:
	var result := SaveMigrations.migrate({"save_version": 1}, 1, _chain([]))
	assert_true(result.is_ok(), "an already-current save is fine")
	assert_eq(result.applied_steps.size(), 0, "nothing was applied")


func test_single_step_upgrade() -> void:
	var chain := _chain([
		{"from": 1, "to": 2, "apply": func(data: Dictionary) -> Dictionary:
			data["added"] = "yes"
			return data},
	])
	var result := SaveMigrations.migrate({"save_version": 1}, 2, chain)
	assert_true(result.is_ok(), "upgrade succeeded")
	assert_eq(result.data["added"], "yes", "the step ran")
	assert_eq(result.data["save_version"], 2, "version was stamped")


func test_multi_step_upgrade_runs_in_order() -> void:
	# Order matters: a step that depends on the previous one's output must never
	# run first, whatever order the chain happens to be declared in.
	var chain := _chain([
		{"from": 2, "to": 3, "apply": func(data: Dictionary) -> Dictionary:
			data["trail"] = str(data.get("trail", "")) + "B"
			return data},
		{"from": 1, "to": 2, "apply": func(data: Dictionary) -> Dictionary:
			data["trail"] = str(data.get("trail", "")) + "A"
			return data},
	])
	var result := SaveMigrations.migrate({"save_version": 1}, 3, chain)
	assert_true(result.is_ok(), "both steps ran")
	assert_eq(result.data["trail"], "AB", "steps applied in version order, not declaration order")
	assert_eq(result.to_version, 3, "landed on the target version")


func test_future_version_is_refused() -> void:
	# §36: never silently erase an incompatible save. A save from a NEWER build
	# must be refused and left alone, because we cannot know what its fields mean.
	var result := SaveMigrations.migrate({"save_version": 99, "precious": true}, 1, _chain([]))
	assert_eq(result.status, SaveMigrations.Status.FUTURE_VERSION, "refused")
	assert_false(result.is_ok(), "not treated as a success")
	assert_eq(result.data["precious"], true, "the original data is preserved untouched")


func test_missing_step_reports_no_path() -> void:
	# A gap must be reported, not silently half-applied.
	var chain := _chain([
		{"from": 1, "to": 2, "apply": func(data: Dictionary) -> Dictionary: return data},
	])
	var result := SaveMigrations.migrate({"save_version": 1}, 5, chain)
	assert_eq(result.status, SaveMigrations.Status.NO_PATH, "gap detected")
	assert_eq(result.to_version, 2, "stopped where the chain ran out")


func test_migration_does_not_mutate_the_input() -> void:
	# The caller still holds the raw data read from disk; corrupting it would
	# destroy the fallback if the migration is later rejected.
	var original := {"save_version": 1, "keep": "me"}
	var chain := _chain([
		{"from": 1, "to": 2, "apply": func(data: Dictionary) -> Dictionary:
			data["keep"] = "changed"
			return data},
	])
	SaveMigrations.migrate(original, 2, chain)
	assert_eq(original["keep"], "me", "the input dictionary was not modified")
	assert_eq(original["save_version"], 1, "the input version was not modified")


func test_missing_version_defaults_to_one() -> void:
	var result := SaveMigrations.migrate({}, 1, _chain([]))
	assert_eq(result.from_version, 1, "an absent save_version is treated as the first version")


func test_real_chain_is_self_consistent() -> void:
	# Guards the actual shipped chain: every step must be well-formed and reach
	# the current version without a gap.
	var chain := SaveMigrations.get_chain()
	var result := SaveMigrations.migrate({"save_version": 1}, SaveData.CURRENT_VERSION, chain)
	assert_true(
		result.is_ok(),
		"the shipped chain upgrades a version-1 save to %d" % SaveData.CURRENT_VERSION
	)


# --- The real chain -----------------------------------------------------------
# The tests above exercise the framework with synthetic chains. These exercise
# the chain the game actually ships, against the shape a version-1 save has on
# disk — which is the only version of it that will ever exist, so getting this
# wrong once is permanent.

func test_version_one_decorations_gain_a_rotation() -> void:
	var save := {
		"save_version": 1,
		"garden": {"decorations": {"1,1": "stone_bench", "2,0": "garden_lantern"}},
	}
	var result := SaveMigrations.migrate(save)
	assert_true(result.is_ok(), "a version-1 save upgrades")

	var decorations: Dictionary = result.data["garden"]["decorations"]
	assert_eq(decorations["1,1"]["id"], "stone_bench", "the ornament is preserved")
	assert_eq(decorations["1,1"]["rotation"], 0, "an unturned ornament keeps facing the same way")
	assert_eq(decorations["2,0"]["id"], "garden_lantern", "every cell is converted")


func test_version_one_gains_an_appearance_setting() -> void:
	var result := SaveMigrations.migrate({"save_version": 1, "settings": {"ui_scale": 1.5}})
	assert_eq(result.data["settings"]["theme_mode"], "light", "existing saves stay light")
	assert_eq(result.data["settings"]["ui_scale"], 1.5, "other settings are untouched")


func test_a_version_one_save_with_no_garden_survives() -> void:
	# A save written before the player ever opened the garden has no garden key at
	# all. A migration that assumed one would take out the whole file.
	var result := SaveMigrations.migrate({"save_version": 1})
	assert_true(result.is_ok(), "a sparse save still upgrades")
	assert_eq(result.data["save_version"], 2, "version was stamped")
	assert_true(result.data.has("garden"), "an empty garden was written in")


func test_already_migrated_decorations_are_left_alone() -> void:
	var save := {
		"save_version": 1,
		"garden": {"decorations": {"0,0": {"id": "stone_bench", "rotation": 3}}},
	}
	var result := SaveMigrations.migrate(save)
	assert_eq(
		result.data["garden"]["decorations"]["0,0"]["rotation"], 3,
		"a facing already in the new shape is not reset"
	)

func _chain(steps: Array) -> Array[Dictionary]:
	var typed: Array[Dictionary] = []
	for step: Dictionary in steps:
		typed.append(step)
	return typed
