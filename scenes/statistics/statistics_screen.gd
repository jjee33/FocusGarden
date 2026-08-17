class_name StatisticsScreen
extends MilestoneScreen
## Focus statistics (§29, §30). Real implementation: Milestone 6.


func _init() -> void:
	screen_glyph = "📊"
	screen_title = "Statistics"
	screen_subtitle = "Where your hours actually went."
	empty_headline = "Nothing to chart yet"
	screen_body = (
		"Focus totals by day, week, month and year, a breakdown by project, and a "
		+ "calendar heatmap of every day you sat down to work."
	)
	milestone_note = (
		"Milestone 6. Every figure is derived from the stored session records rather "
		+ "than from running totals, so the numbers can always be recomputed and checked."
	)
