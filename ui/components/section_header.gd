class_name SectionHeader
extends VBoxContainer
## The title block at the top of every screen (§74: "hierarchy is obvious").
##
## Every screen opens with one of these, so the player always knows where they
## are and every screen's first element sits at the same height with the same
## type treatment. Screens that invent their own heading are what makes an app
## feel like nine different apps.
##
## The short accent rule above the title is the one piece of pure decoration in
## the component, and it earns its place: it gives every screen the same visual
## starting point and stops a page of left-aligned text from opening on nothing.

## Length of the accent rule, in pixels.
const RULE_WIDTH: int = 34
const RULE_HEIGHT: int = 3


static func create(title: String, subtitle: String = "", eyebrow: String = "") -> SectionHeader:
	var header := SectionHeader.new()
	header.add_theme_constant_override("separation", DesignTokens.SPACE_XXS)

	header.add_child(_accent_rule())

	if not eyebrow.is_empty():
		var eyebrow_label := Label.new()
		# Upper-cased here rather than at the call site, so no screen can ship an
		# eyebrow in the wrong case.
		eyebrow_label.text = eyebrow.to_upper()
		eyebrow_label.theme_type_variation = &"Eyebrow"
		header.add_child(eyebrow_label)

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


static func _accent_rule() -> Control:
	var holder := MarginContainer.new()
	holder.add_theme_constant_override("margin_bottom", DesignTokens.SPACE_XS)

	var rule := PanelContainer.new()
	rule.custom_minimum_size = Vector2(RULE_WIDTH, RULE_HEIGHT)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	rule.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var style := StyleBoxFlat.new()
	style.bg_color = Palette.moss()
	style.corner_radius_top_left = RULE_HEIGHT
	style.corner_radius_top_right = RULE_HEIGHT
	style.corner_radius_bottom_left = RULE_HEIGHT
	style.corner_radius_bottom_right = RULE_HEIGHT
	style.anti_aliasing = true
	rule.add_theme_stylebox_override("panel", style)

	holder.add_child(rule)
	return holder
