class_name GameSettings
extends RefCounted
## All user-configurable preferences (§35). Player data — JSON.
##
## Defaults are deliberately conservative: audio starts quiet so first launch is
## never loud (§33), notifications are on but minimal (§34), and no aggressive
## nudging is enabled by default (§3).

# --- Timer (§35) ---
var focus_duration_minutes: float = 25.0
var short_break_minutes: float = 5.0
var long_break_minutes: float = 15.0
var sessions_before_long_break: int = 4
var auto_start_breaks: bool = false
var auto_start_focus: bool = false
## Sessions shorter than this award no plant growth (§12). Set to 0 to disable.
var minimum_credit_minutes: float = 1.0

# --- Appearance (§35, §50) ---
var window_mode: String = "windowed"  ## windowed | fullscreen | borderless
## Appearance mode. Stored as a plain string rather than a Palette enum so this
## model stays free of any dependency on the UI layer (§40) and so the value in
## the save file is readable rather than an integer nobody can interpret.
var theme_mode: String = "light"  ## light | dark
var ui_scale: float = 1.0
var reduced_motion: bool = false
var animation_intensity: float = 1.0

# --- Audio (§33). Conservative defaults; nothing blares on first run. ---
var volume_master: float = 0.7
var volume_music: float = 0.4
var volume_ambient: float = 0.5
var volume_ui: float = 0.6
var volume_timer: float = 0.8
var ambient_track_id: String = "none"

# --- Notifications (§34) ---
var notify_focus_complete: bool = true
var notify_break_complete: bool = true

# --- Gameplay (§28, §27) ---
var daily_goal_minutes: float = 50.0
## Minutes of focus that count a day toward the streak (§27).
var streak_threshold_minutes: float = 25.0
var confirm_before_cancel_session: bool = true

# --- Updates ---
## Check GitHub for a newer release on launch. This is the only network request
## the app ever makes — see docs/UPDATES.md. On by default, because a tool people
## rely on daily should not quietly rot on an old version, but one toggle turns it
## off for good and nothing else re-enables it.
var check_for_updates: bool = true

# --- Data (§35) ---
## Empty means the default user:// location.
var custom_save_directory: String = ""

const WINDOW_MODES: Array[String] = ["windowed", "fullscreen", "borderless"]
const THEME_MODES: Array[String] = ["light", "dark"]


func to_dict() -> Dictionary:
	return {
		"focus_duration_minutes": focus_duration_minutes,
		"short_break_minutes": short_break_minutes,
		"long_break_minutes": long_break_minutes,
		"sessions_before_long_break": sessions_before_long_break,
		"auto_start_breaks": auto_start_breaks,
		"auto_start_focus": auto_start_focus,
		"minimum_credit_minutes": minimum_credit_minutes,
		"window_mode": window_mode,
		"theme_mode": theme_mode,
		"ui_scale": ui_scale,
		"reduced_motion": reduced_motion,
		"animation_intensity": animation_intensity,
		"volume_master": volume_master,
		"volume_music": volume_music,
		"volume_ambient": volume_ambient,
		"volume_ui": volume_ui,
		"volume_timer": volume_timer,
		"ambient_track_id": ambient_track_id,
		"notify_focus_complete": notify_focus_complete,
		"notify_break_complete": notify_break_complete,
		"daily_goal_minutes": daily_goal_minutes,
		"streak_threshold_minutes": streak_threshold_minutes,
		"confirm_before_cancel_session": confirm_before_cancel_session,
		"check_for_updates": check_for_updates,
		"custom_save_directory": custom_save_directory,
	}


static func from_dict(data: Dictionary) -> GameSettings:
	var settings := GameSettings.new()
	# Durations are clamped to sane bounds: a corrupted 0-minute or 10,000-minute
	# focus duration would make the timer unusable with no way to fix it in-app.
	settings.focus_duration_minutes = DictUtil.get_clamped_float(
		data, "focus_duration_minutes", 1.0, 480.0, 25.0
	)
	settings.short_break_minutes = DictUtil.get_clamped_float(
		data, "short_break_minutes", 1.0, 120.0, 5.0
	)
	settings.long_break_minutes = DictUtil.get_clamped_float(
		data, "long_break_minutes", 1.0, 120.0, 15.0
	)
	settings.sessions_before_long_break = clampi(
		DictUtil.get_int(data, "sessions_before_long_break", 4), 1, 12
	)
	settings.auto_start_breaks = DictUtil.get_bool(data, "auto_start_breaks")
	settings.auto_start_focus = DictUtil.get_bool(data, "auto_start_focus")
	settings.minimum_credit_minutes = DictUtil.get_clamped_float(
		data, "minimum_credit_minutes", 0.0, 60.0, 1.0
	)

	settings.window_mode = DictUtil.get_string(data, "window_mode", "windowed")
	if not WINDOW_MODES.has(settings.window_mode):
		settings.window_mode = "windowed"
	settings.theme_mode = DictUtil.get_string(data, "theme_mode", "light")
	if not THEME_MODES.has(settings.theme_mode):
		settings.theme_mode = "light"
	settings.ui_scale = DictUtil.get_clamped_float(data, "ui_scale", 0.75, 2.0, 1.0)
	settings.reduced_motion = DictUtil.get_bool(data, "reduced_motion")
	settings.animation_intensity = DictUtil.get_clamped_float(
		data, "animation_intensity", 0.0, 1.0, 1.0
	)

	settings.volume_master = DictUtil.get_clamped_float(data, "volume_master", 0.0, 1.0, 0.7)
	settings.volume_music = DictUtil.get_clamped_float(data, "volume_music", 0.0, 1.0, 0.4)
	settings.volume_ambient = DictUtil.get_clamped_float(data, "volume_ambient", 0.0, 1.0, 0.5)
	settings.volume_ui = DictUtil.get_clamped_float(data, "volume_ui", 0.0, 1.0, 0.6)
	settings.volume_timer = DictUtil.get_clamped_float(data, "volume_timer", 0.0, 1.0, 0.8)
	settings.ambient_track_id = DictUtil.get_string(data, "ambient_track_id", "none")

	settings.notify_focus_complete = DictUtil.get_bool(data, "notify_focus_complete", true)
	settings.notify_break_complete = DictUtil.get_bool(data, "notify_break_complete", true)

	settings.daily_goal_minutes = DictUtil.get_clamped_float(
		data, "daily_goal_minutes", 5.0, 960.0, 50.0
	)
	settings.streak_threshold_minutes = DictUtil.get_clamped_float(
		data, "streak_threshold_minutes", 1.0, 480.0, 25.0
	)
	settings.confirm_before_cancel_session = DictUtil.get_bool(
		data, "confirm_before_cancel_session", true
	)
	settings.check_for_updates = DictUtil.get_bool(data, "check_for_updates", true)

	settings.custom_save_directory = DictUtil.get_string(data, "custom_save_directory")
	return settings
