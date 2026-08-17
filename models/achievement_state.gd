class_name AchievementState
extends RefCounted
## One player's progress against one AchievementDef (§26). Player data — JSON.
##
## Split from the definition for the same reason PlantInstance is split from
## PlantSpecies: the definition ships with the game, the state belongs to the
## player. A definition removed in a future update leaves an orphan state, which
## SaveManager preserves rather than deletes (§54).

var achievement_id: StringName = &""
var unlocked: bool = false
var unlocked_at_utc: float = 0.0
## Cached 0..1 progress so the achievements screen does not re-evaluate every
## requirement on every open (§44).
var progress_ratio: float = 0.0


static func create(id: StringName) -> AchievementState:
	var state := AchievementState.new()
	state.achievement_id = id
	return state


## Marks unlocked, returning true only on the transition so the reveal animation
## and journal entry fire exactly once (§63).
func unlock() -> bool:
	if unlocked:
		return false
	unlocked = true
	unlocked_at_utc = Time.get_unix_time_from_system()
	progress_ratio = 1.0
	return true


func to_dict() -> Dictionary:
	return {
		"achievement_id": String(achievement_id),
		"unlocked": unlocked,
		"unlocked_at_utc": unlocked_at_utc,
		"progress_ratio": progress_ratio,
	}


static func from_dict(data: Dictionary) -> AchievementState:
	var state := AchievementState.new()
	state.achievement_id = StringName(DictUtil.get_string(data, "achievement_id"))
	state.unlocked = DictUtil.get_bool(data, "unlocked")
	state.unlocked_at_utc = DictUtil.get_float(data, "unlocked_at_utc")
	state.progress_ratio = DictUtil.get_clamped_float(data, "progress_ratio", 0.0, 1.0)
	if state.unlocked:
		state.progress_ratio = 1.0
	return state
