class_name ShelfScreen
extends MilestoneScreen
## Plant shelf (§21). Real implementation: Milestone 4.


func _init() -> void:
	screen_glyph = "🪴"
	screen_title = "Shelf"
	screen_subtitle = "Your curated display of favourite plants."
	empty_headline = "Your shelf is bare"
	screen_body = (
		"Arrange grown plants on a shelf, choose their pots, and set the lighting. "
		+ "Clicking any plant opens the history of the focus that grew it."
	)
	milestone_note = "Milestone 4. Placement is already modelled so a plant can only ever be in one place."
