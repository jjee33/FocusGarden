class_name CatalogueScreen
extends MilestoneScreen
## Plant catalogue (§16). Real implementation: Milestone 3.


func _init() -> void:
	screen_glyph = "📖"
	screen_title = "Catalogue"
	screen_subtitle = "Every species you have discovered, and the silhouettes of those you have not."
	empty_headline = "No species discovered yet"
	screen_body = (
		"A browsable encyclopedia of plants with filters, search, rarity, and the "
		+ "botanical details of each species you bring to maturity."
	)
	milestone_note = "Milestone 3. Species definitions are data-driven and load from data/plants."
