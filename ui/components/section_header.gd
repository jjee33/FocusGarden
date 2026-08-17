class_name SectionHeader
extends VBoxContainer
## The title block at the top of every screen (§74: "hierarchy is obvious").
##
## Every screen opens with one of these, so the player always knows where they
## are and every screen's first element sits at the same height with the same
## type treatment. Screens that invent their own heading are what makes an app
## feel like nine different apps.

static func create(title: String, subtitle: String = "") -> SectionHeader:
	var header := SectionHeader.new()
	header.add_theme_constant_override("separation", DesignTokens.SPACE_XXS)

	var title_label := Label.new()
	title_label.text = title
	title_label.theme_type_variation = &"Title"
	header.add_child(title_label)

	if not subtitle.is_empty():
		var subtitle_label := Label.new()
		subtitle_label.text = subtitle
		subtitle_label.theme_type_variation = &"Muted"
		subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		header.add_child(subtitle_label)

	return header
