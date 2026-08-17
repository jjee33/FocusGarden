class_name AchievementsScreen
extends MilestoneScreen
## Achievements (§26). Real implementation: Milestone 5.


func _init() -> void:
	screen_glyph = "🏅"
	screen_title = "Achievements"
	screen_subtitle = "Quiet milestones, not a scoreboard."
	empty_headline = "No achievements earned yet"
	screen_body = (
		"Achievements for depth, consistency and collection — each with its own "
		+ "progress, so you can see how close you are rather than only whether you won."
	)
	milestone_note = (
		"Milestone 5. The evaluation engine is already built: achievements share one "
		+ "requirement system with plant unlocks and garden expansions."
	)
