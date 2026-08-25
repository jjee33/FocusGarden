class_name StatTile
extends PanelContainer
## A single labelled figure — today's focus, streak, level (§7, §29).
##
## Built as one component so every number in the game gets the same treatment:
## label above, value below, consistent spacing. §74 requires consistent
## typography and spacing across screens, and the reliable way to get that is to
## make the shared case a component rather than a convention people re-implement.

var _value_label: Label
var _caption_label: Label


static func create(caption: String, value: String, accent: Color = Palette.ink_primary()) -> StatTile:
	var tile := StatTile.new()
	tile._configure(caption, value, accent)
	return tile


func _configure(caption: String, value: String, accent: Color) -> void:
	theme_type_variation = &"CardSunken"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", DesignTokens.SPACE_XXS)
	add_child(column)

	# Caption first in the tree so screen readers and tab order encounter the
	# label before the number it describes.
	_caption_label = Label.new()
	# Upper-cased and tracked: it reads as a field label rather than as a second,
	# competing sentence next to the number.
	_caption_label.text = caption.to_upper()
	_caption_label.theme_type_variation = &"Eyebrow"
	column.add_child(_caption_label)

	_value_label = Label.new()
	_value_label.text = value
	_value_label.theme_type_variation = &"Display"
	_value_label.add_theme_font_override(
		"font", DesignTokens.font(DesignTokens.WEIGHT_SEMIBOLD, true)
	)
	_value_label.add_theme_font_size_override("font_size", DesignTokens.FONT_TITLE)
	_value_label.add_theme_color_override("font_color", accent)
	column.add_child(_value_label)


## Updates the displayed figure. Screens call this instead of rebuilding the
## tile, so a value change never costs a node allocation (§44).
func set_value(value: String) -> void:
	_value_label.text = value


func set_caption(caption: String) -> void:
	_caption_label.text = caption.to_upper()
