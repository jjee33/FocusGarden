class_name SettingsScreen
extends MilestoneScreen
## Settings (§35). Real implementation: Milestone 8.


func _init() -> void:
	screen_glyph = "⚙"
	screen_title = "Settings"
	screen_subtitle = "Timer lengths, sound, motion, goals, and your save data."
	empty_headline = "Settings are not wired up yet"
	screen_body = (
		"Session durations and auto-start, independent volume sliders, reduced motion "
		+ "and UI scale, daily goal and streak threshold, plus export and import of your save."
	)
	milestone_note = (
		"Milestone 8. Every setting already exists in the data model and persists — "
		+ "this screen is the controls for them."
	)
