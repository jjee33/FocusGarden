class_name JournalScreen
extends MilestoneScreen
## Plant journal (§31). Real implementation: Milestone 6.


func _init() -> void:
	screen_glyph = "📔"
	screen_title = "Journal"
	screen_subtitle = "A dated record of everything your garden has been through."
	empty_headline = "The first page is blank"
	screen_body = (
		"Seeds planted, stages reached, plants matured, achievements earned — kept in "
		+ "order, so the whole history of your focus reads back as a story."
	)
	milestone_note = "Milestone 6. Journal entries are append-only and are never rewritten."
