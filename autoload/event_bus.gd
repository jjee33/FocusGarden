extends Node
## Cross-system signal hub (§41).
##
## Owns: signal DECLARATIONS ONLY. Zero state, zero logic, zero methods.
## Must never: do work. This file is a wire, not a system. If you are tempted to
## add a variable or a function here, it belongs in a service instead.
##
## Why a bus at all: it lets ProgressionManager react to a completed session
## without AchievementManager and TimerManager holding references to each other,
## which is what produces circular dependencies (§70).

# --- Session lifecycle (owned by TimerManager) ---
signal session_started(session_id: String)
signal session_paused(session_id: String)
signal session_resumed(session_id: String)
signal session_cancelled(session_id: String)
signal session_completed(session_id: String)
signal session_tick(remaining_seconds: float)

# --- Focus accounting (owned by SessionPipeline) ---
signal focus_time_recorded(session_id: String, credited_minutes: float)
signal session_anomaly_detected(session_id: String, anomaly: String)

# --- Plants (owned by PlantGrowthService) ---
signal plant_growth_changed(plant_uid: String, accumulated_minutes: float)
signal plant_stage_changed(plant_uid: String, new_stage: int)
signal plant_matured(plant_uid: String)
signal active_plant_changed(plant_uid: String)
signal catalogue_entry_discovered(species_id: String)

# --- Progression (owned by ProgressionManager) ---
signal xp_changed(total_xp: int)
signal level_up(new_level: int)
signal unlock_granted(unlock_id: String)

# --- Achievements (owned by AchievementManager) ---
signal achievement_unlocked(achievement_id: String)
signal achievement_progress_changed(achievement_id: String, ratio: float)

# --- Garden / shelf ---
signal garden_expansion_unlocked(expansion_id: String)
signal shelf_layout_changed()

# --- Streaks & goals (owned by StatisticsManager) ---
signal streak_changed(current_streak: int)
signal daily_goal_reached(date_key: String)

# --- Persistence (owned by SaveManager) ---
signal save_completed()
signal save_failed(reason: String)
signal save_loaded()
signal save_recovered_from_backup(backup_name: String)

# --- Journal ---
signal journal_entry_added(entry_id: String)

# --- Navigation & app shell (consumed by the main scene, not an autoload) ---
signal navigation_requested(screen_id: String)
signal settings_changed(key: String)
signal reduced_motion_changed(enabled: bool)
signal toast_requested(title: String, body: String, icon_id: String)
