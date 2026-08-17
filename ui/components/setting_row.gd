class_name SettingRow
extends HBoxContainer
## One labelled control in a settings list (§35).
##
## Built as a component so every setting has the same shape: name and
## explanation on the left, control on the right, consistent spacing. §74 asks
## for consistent hierarchy and spacing, and a settings screen is where that
## slips first if each row is assembled by hand.
##
## Toggles are Chip-styled buttons rather than `CheckButton`, which draws icons
## from Godot's default theme and would be the one un-themed control in the app.

const CONTROL_WIDTH: int = 200


static func stepper(
	label: String,
	description: String,
	value: float,
	minimum: float,
	maximum: float,
	step: float,
	on_change: Callable,
	formatter: Callable = Callable()
) -> SettingRow:
	var row := SettingRow.new()
	row._build_label(label, description)

	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	controls.custom_minimum_size.x = CONTROL_WIDTH
	controls.alignment = BoxContainer.ALIGNMENT_END
	controls.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(controls)

	var display := Label.new()
	display.custom_minimum_size.x = 88
	display.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	display.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# Held in a single-element array so the lambdas below share one mutable value
	# rather than each capturing a copy.
	var current: Array[float] = [value]
	var render := func() -> void:
		display.text = (
			formatter.call(current[0]) if formatter.is_valid() else str(int(current[0]))
		)
	render.call()

	var minus := Button.new()
	minus.text = "−"
	minus.theme_type_variation = &"Chip"
	minus.tooltip_text = "Decrease %s" % label.to_lower()
	minus.pressed.connect(func() -> void:
		current[0] = clampf(current[0] - step, minimum, maximum)
		render.call()
		on_change.call(current[0]))
	controls.add_child(minus)
	controls.add_child(display)

	var plus := Button.new()
	plus.text = "+"
	plus.theme_type_variation = &"Chip"
	plus.tooltip_text = "Increase %s" % label.to_lower()
	plus.pressed.connect(func() -> void:
		current[0] = clampf(current[0] + step, minimum, maximum)
		render.call()
		on_change.call(current[0]))
	controls.add_child(plus)

	return row


static func toggle(
	label: String, description: String, value: bool, on_change: Callable
) -> SettingRow:
	var row := SettingRow.new()
	row._build_label(label, description)

	var button := Button.new()
	button.toggle_mode = true
	button.button_pressed = value
	button.theme_type_variation = &"Chip"
	button.custom_minimum_size.x = 88
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# The label states the current value in words, so the setting is readable
	# without interpreting a fill colour (§50).
	button.text = "On" if value else "Off"
	button.toggled.connect(func(pressed: bool) -> void:
		button.text = "On" if pressed else "Off"
		on_change.call(pressed))

	var holder := HBoxContainer.new()
	holder.custom_minimum_size.x = CONTROL_WIDTH
	holder.alignment = BoxContainer.ALIGNMENT_END
	holder.add_child(button)
	row.add_child(holder)

	return row


func _build_label(label: String, description: String) -> void:
	add_theme_constant_override("separation", DesignTokens.SPACE_MD)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", DesignTokens.SPACE_XXS)
	add_child(column)

	var name_label := Label.new()
	name_label.text = label
	column.add_child(name_label)

	if description.is_empty():
		return
	var description_label := Label.new()
	description_label.text = description
	description_label.theme_type_variation = &"Caption"
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(description_label)
