class_name PlayerProfile
extends RefCounted
## Identity and progression state (§13, §25, §27). Player data — JSON.
##
## Level is NOT stored. It is derived from `total_xp` by XpFormula, which is the
## single authoritative level calculation (§38). Storing a level alongside the XP
## that determines it would let the two disagree after any formula change.
##
## Streak fields ARE stored, as a cache: recomputing a streak means walking every
## session record, which §44 asks us not to do on every frame or screen open.
## StatisticsManager owns keeping them correct and can rebuild them from sessions.

var display_name: String = "Gardener"
var created_at_utc: float = 0.0
var total_xp: int = 0

## What the player is currently growing and working on (§9).
var active_plant_uid: String = ""
var active_project_id: String = ""

## Unlock ids already granted, so an unlock event can only fire once (§63).
var unlocked_ids: PackedStringArray = PackedStringArray()

# --- Streak cache (§27). Rebuildable from sessions. ---
var current_streak: int = 0
var longest_streak: int = 0
var last_focus_date_key: String = ""

## Focus sessions completed since the last long break (§8's session cycle).
## Persisted so closing the app mid-cycle does not reset the player's place in it.
var focus_sessions_in_cycle: int = 0

var onboarding_completed: bool = false


static func create(name: String) -> PlayerProfile:
	var profile := PlayerProfile.new()
	profile.display_name = name
	profile.created_at_utc = Time.get_unix_time_from_system()
	return profile


func has_unlock(unlock_id: String) -> bool:
	return unlocked_ids.has(unlock_id)


## Returns true only the first time an unlock is granted, so callers can fire the
## celebration exactly once (§63: "unlock events only trigger once").
func grant_unlock(unlock_id: String) -> bool:
	if unlock_id.is_empty() or unlocked_ids.has(unlock_id):
		return false
	unlocked_ids.append(unlock_id)
	return true


func to_dict() -> Dictionary:
	return {
		"display_name": display_name,
		"created_at_utc": created_at_utc,
		"total_xp": total_xp,
		"active_plant_uid": active_plant_uid,
		"active_project_id": active_project_id,
		"unlocked_ids": unlocked_ids,
		"current_streak": current_streak,
		"longest_streak": longest_streak,
		"last_focus_date_key": last_focus_date_key,
		"focus_sessions_in_cycle": focus_sessions_in_cycle,
		"onboarding_completed": onboarding_completed,
	}


static func from_dict(data: Dictionary) -> PlayerProfile:
	var profile := PlayerProfile.new()
	profile.display_name = DictUtil.get_string(data, "display_name", "Gardener")
	profile.created_at_utc = DictUtil.get_float(data, "created_at_utc")
	profile.total_xp = maxi(0, DictUtil.get_int(data, "total_xp"))
	profile.active_plant_uid = DictUtil.get_string(data, "active_plant_uid")
	profile.active_project_id = DictUtil.get_string(data, "active_project_id")
	profile.unlocked_ids = DictUtil.get_string_array(data, "unlocked_ids")
	profile.current_streak = maxi(0, DictUtil.get_int(data, "current_streak"))
	profile.longest_streak = maxi(0, DictUtil.get_int(data, "longest_streak"))
	profile.last_focus_date_key = DictUtil.get_string(data, "last_focus_date_key")
	profile.focus_sessions_in_cycle = maxi(0, DictUtil.get_int(data, "focus_sessions_in_cycle"))
	profile.onboarding_completed = DictUtil.get_bool(data, "onboarding_completed")

	# longest can never be below current; a save written mid-update could disagree.
	profile.longest_streak = maxi(profile.longest_streak, profile.current_streak)
	return profile
