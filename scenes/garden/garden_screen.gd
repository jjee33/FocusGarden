class_name GardenScreen
extends MilestoneScreen
## Expandable garden (§23). Real implementation: Milestone 7.


func _init() -> void:
	screen_glyph = "🌳"
	screen_title = "Garden"
	screen_subtitle = "The long view of everything you have grown."
	empty_headline = "The plot is still empty"
	screen_body = (
		"A garden that expands as your cumulative focus time grows, with room for "
		+ "paths, benches, ponds and lanterns earned along the way."
	)
	milestone_note = "Milestone 7. Expansions unlock from cumulative focus time and never expire."
