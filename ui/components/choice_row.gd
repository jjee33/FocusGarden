class_name ChoiceRow
extends HBoxContainer
## A row of mutually exclusive chips — durations, projects, colours (§9).
##
## Wraps a ButtonGroup so exactly one option can be selected and the selection is
## keyboard-navigable. Screens get a `selected` signal and a value, and never
## have to manage toggle state themselves; hand-rolled toggle rows are where
## "two things look selected at once" bugs come from.

signal selected(value: Variant)

var _group: ButtonGroup = ButtonGroup.new()
var _buttons: Array[Button] = []
var _values: Array = []


func _init() -> void:
	add_theme_constant_override("separation", DesignTokens.SPACE_XS)


## Adds an option. `value` is whatever the caller wants back from `selected`.
func add_choice(label: String, value: Variant, tooltip: String = "") -> Button:
	var button := Button.new()
	button.text = label
	button.theme_type_variation = &"Chip"
	button.toggle_mode = true
	button.button_group = _group
	button.focus_mode = Control.FOCUS_ALL
	if not tooltip.is_empty():
		button.tooltip_text = tooltip

	var index := _buttons.size()
	button.pressed.connect(func() -> void: selected.emit(_values[index]))
	add_child(button)
	_buttons.append(button)
	_values.append(value)
	return button


## Selects a choice by value without emitting, for restoring saved state.
func select_value(value: Variant) -> void:
	for i in _values.size():
		if _values[i] == value:
			_buttons[i].button_pressed = true
			return
	# Nothing matched: clear rather than leaving a stale highlight pointing at an
	# option the caller did not ask for.
	for button: Button in _buttons:
		button.button_pressed = false


func get_selected_value() -> Variant:
	for i in _buttons.size():
		if _buttons[i].button_pressed:
			return _values[i]
	return null


func clear_choices() -> void:
	for button: Button in _buttons:
		button.queue_free()
	_buttons.clear()
	_values.clear()
