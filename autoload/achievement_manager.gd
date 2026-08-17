extends Node
## Achievement evaluation (§40).
##
## Owns: checking achievement requirements and recording unlocks.
## Must never: do XP math, apply plant growth, or write save files.
##
## Achievements have no bespoke condition code. Each one carries a Requirement
## and is measured by RequirementEvaluator, the same engine that drives plant
## unlocks and expeditions (§48).


## Evaluates every achievement against a context, unlocking any newly satisfied.
## Returns the ids unlocked by THIS call, so the caller can queue reveals.
##
## §54 requires multiple simultaneous unlocks to be handled: the full list is
## returned rather than a single id, and the UI queues them instead of stacking
## overlapping popups.
func evaluate_all(context: RequirementContext) -> PackedStringArray:
	var newly_unlocked := PackedStringArray()

	for definition: AchievementDef in ContentDB.get_all_achievements():
		var state := AppState.ensure_achievement_state(definition.id)
		if state.unlocked:
			continue

		var ratio := RequirementEvaluator.evaluate(definition.requirement, context)
		if not is_equal_approx(ratio, state.progress_ratio):
			state.progress_ratio = ratio
			EventBus.achievement_progress_changed.emit(String(definition.id), ratio)

		if ratio >= 1.0 and state.unlock():
			newly_unlocked.append(String(definition.id))
			GameLog.info(GameLog.Category.ACHIEVEMENT, "Unlocked '%s'." % definition.id)
			EventBus.achievement_unlocked.emit(String(definition.id))

	return newly_unlocked


## 0..1 progress for one achievement, from cached state. Reads the cache rather
## than re-evaluating so opening the achievements screen is cheap (§44).
func get_progress(achievement_id: StringName) -> float:
	var state := AppState.get_achievement_state(achievement_id)
	return state.progress_ratio if state != null else 0.0


func is_unlocked(achievement_id: StringName) -> bool:
	var state := AppState.get_achievement_state(achievement_id)
	return state != null and state.unlocked


func get_unlocked_count() -> int:
	var count := 0
	for state: AchievementState in AppState.data.achievements:
		if state.unlocked:
			count += 1
	return count


## Whether an achievement should be shown as "???" (§26 hidden achievements).
## A hidden achievement stays concealed until it is actually earned.
func should_conceal(definition: AchievementDef) -> bool:
	return definition.hidden and not is_unlocked(definition.id)
