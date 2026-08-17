class_name MilestoneScreen
extends AppScreen
## Base for sections whose real implementation belongs to a later milestone.
##
## §72 forbids treating a screen that merely exists as a finished feature, and
## §74 requires empty states to look intentional. This class threads that needle:
## each unbuilt section gets a properly designed page that states plainly which
## milestone will fill it, so the shell is navigable and honest at the same time.
##
## Subclasses set the four fields below and nothing else. When a section is
## actually built, its subclass stops extending this and overrides
## `build_content()` directly — the screen's file and route never change.

var screen_glyph: String = "🌿"
var screen_title: String = ""
var screen_subtitle: String = ""
## Headline inside the empty state. Deliberately NOT the same as `screen_title`:
## repeating the page title two inches below itself reads as a rendering bug
## rather than a design (§74 "hierarchy is obvious").
var empty_headline: String = "Nothing here yet"
var screen_body: String = ""
var milestone_note: String = ""


func build_content() -> void:
	content.add_child(SectionHeader.create(screen_title, screen_subtitle))

	var card := PanelContainer.new()
	card.theme_type_variation = &"Card"
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.y = 380
	content.add_child(card)

	card.add_child(EmptyState.create(screen_glyph, empty_headline, screen_body, milestone_note))
