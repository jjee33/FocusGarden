class_name FocusScreen
extends MilestoneScreen
## Focus session screen (§10). Real implementation: Milestone 1.


func _init() -> void:
	screen_glyph = "⏳"
	screen_title = "Focus"
	screen_subtitle = "Choose a project, a plant, and a length — then begin."
	empty_headline = "Nothing running right now"
	screen_body = (
		"The timer will live here: a large, calm countdown with your plant beside it "
		+ "and almost nothing else competing for attention."
	)
	milestone_note = (
		"Milestone 1. The underlying timing is already built and tested — elapsed time "
		+ "is derived from system timestamps, so it stays accurate when the window is "
		+ "minimized or the machine is busy."
	)
