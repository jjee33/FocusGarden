class_name NewProjectDialog
extends Control
## Creates a project category (§9: "users must be able to create custom categories").
##
## Same in-scene modal approach as ConfirmDialog, for the same reason: a system
## dialog would ignore the theme and look like a different application.

signal created(project_name: String, color_token: String)

const MAX_NAME_LENGTH: int = 40

var _name_field: LineEdit
var _create_button: Button
var _color_token: String = "moss"


static func open(parent: Node) -> NewProjectDialog:
	var dialog := NewProjectDialog.new()
	dialog._build()
	parent.add_child(dialog)
	dialog._name_field.grab_focus()
	return dialog


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var scrim := ColorRect.new()
	scrim.color = DesignTokens.BG_OVERLAY
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var card := PanelContainer.new()
	card.theme_type_variation = &"Card"
	card.custom_minimum_size = Vector2(460, 0)
	centre.add_child(card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", DesignTokens.SPACE_MD)
	card.add_child(column)

	var title := Label.new()
	title.text = "New project"
	title.theme_type_variation = &"Heading"
	column.add_child(title)

	_name_field = LineEdit.new()
	_name_field.placeholder_text = "Network+, Thesis, Guitar practice…"
	_name_field.max_length = MAX_NAME_LENGTH
	_name_field.text_changed.connect(_on_name_changed)
	_name_field.text_submitted.connect(func(_text: String) -> void: _try_create())
	column.add_child(_name_field)

	var colour_label := Label.new()
	colour_label.text = "Colour"
	colour_label.theme_type_variation = &"Caption"
	column.add_child(colour_label)

	var colours := ChoiceRow.new()
	column.add_child(colours)
	for token: String in DesignTokens.PROJECT_COLOR_ORDER:
		# The swatch is labelled with its name, not shown as a bare colour square:
		# §50 forbids relying on colour alone to distinguish options.
		var chip := colours.add_choice(token.capitalize(), token)
		chip.add_theme_color_override("font_color", DesignTokens.project_color(token))
	colours.selected.connect(func(value: Variant) -> void: _color_token = String(value))
	colours.select_value(_color_token)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	column.add_child(buttons)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.theme_type_variation = &"SubtleButton"
	cancel.pressed.connect(queue_free)
	buttons.add_child(cancel)

	_create_button = Button.new()
	_create_button.text = "Create"
	_create_button.theme_type_variation = &"PrimaryButton"
	# Disabled until there is a name, rather than allowing a blank category that
	# would render as an empty chip forever after.
	_create_button.disabled = true
	_create_button.pressed.connect(_try_create)
	buttons.add_child(_create_button)


func _on_name_changed(text: String) -> void:
	_create_button.disabled = text.strip_edges().is_empty()


func _try_create() -> void:
	var name := _name_field.text.strip_edges()
	if name.is_empty():
		return
	created.emit(name, _color_token)
	queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_back"):
		queue_free()
		get_viewport().set_input_as_handled()
