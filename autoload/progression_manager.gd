extends Node
## XP, levels, and unlock conditions (§40).
##
## Owns: awarding XP, detecting level changes, granting unlocks.
## Must never: evaluate achievements (AchievementManager) or do its own XP math
## (XpFormula is the single authoritative implementation, §38).
##
## Every award path is idempotent at the caller's level: SessionPipeline decides
## whether a session has already been processed, and this class simply refuses to
## re-grant an unlock the profile already has (§63).

## Unlocks are keyed by level. Data-driven content (§25 forbids hardcoding level
## thresholds across many files) — this stays the one table, and later milestones
## move it into data/ once there is real cosmetic content to reference.
const LEVEL_UNLOCKS: Dictionary = {
	2: "pot_ceramic_sage",
	3: "shelf_style_pale_birch",
	5: "ambient_rain",
	8: "pot_stoneware_cream",
	12: "shelf_background_studio",
	16: "ambient_fireplace",
	20: "garden_decor_lantern",
}


func get_level() -> int:
	return XpFormula.level_for_xp(AppState.data.profile.total_xp)


func get_level_progress_ratio() -> float:
	return XpFormula.level_progress_ratio(AppState.data.profile.total_xp)


## XP into the current level and the level's total span, as [earned, span].
func get_level_progress() -> Array[int]:
	return XpFormula.level_progress(AppState.data.profile.total_xp)


## Adds XP and emits the resulting events. Returns the number of levels gained.
##
## Callers must ensure they are not double-awarding — this class cannot tell a
## legitimate second award from a repeat. SessionPipeline's `awards_applied`
## guard is what enforces that for sessions (§63).
func award_xp(amount: int) -> int:
	if amount <= 0:
		return 0

	var profile := AppState.data.profile
	var previous_level := XpFormula.level_for_xp(profile.total_xp)
	profile.total_xp += amount
	var new_level := XpFormula.level_for_xp(profile.total_xp)

	EventBus.xp_changed.emit(profile.total_xp)
	GameLog.debug(GameLog.Category.PROGRESSION, "Awarded %d XP (total %d)." % [amount, profile.total_xp])

	if new_level <= previous_level:
		return 0

	# A single large award can cross several levels at once; each one must fire
	# its own event so no unlock is skipped.
	for level in range(previous_level + 1, new_level + 1):
		EventBus.level_up.emit(level)
		GameLog.info(GameLog.Category.PROGRESSION, "Reached level %d." % level)
		_grant_level_unlocks(level)

	return new_level - previous_level


## Grants an unlock if the player does not already have it.
## Returns true only on the first grant, so celebrations fire exactly once (§63).
func grant_unlock(unlock_id: String) -> bool:
	if not AppState.data.profile.grant_unlock(unlock_id):
		return false
	GameLog.info(GameLog.Category.PROGRESSION, "Unlocked '%s'." % unlock_id)
	EventBus.unlock_granted.emit(unlock_id)
	return true


func has_unlock(unlock_id: String) -> bool:
	return AppState.data.profile.has_unlock(unlock_id)


## Re-grants any level unlock the player has earned but does not have.
## Safe to call at any time: it is a convergence pass, so a level unlock added in
## a future update reaches existing players without duplicating anything.
func reconcile_level_unlocks() -> void:
	var level := get_level()
	for unlock_level: int in LEVEL_UNLOCKS:
		if level >= unlock_level:
			grant_unlock(LEVEL_UNLOCKS[unlock_level])


func _grant_level_unlocks(level: int) -> void:
	if LEVEL_UNLOCKS.has(level):
		grant_unlock(LEVEL_UNLOCKS[level])
