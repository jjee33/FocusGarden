class_name ConfirmDialog
extends Control
## An in-scene modal confirmation (§35, §49).
##
## Built in-scene rather than using Godot's `ConfirmationDialog`, which is an OS
## window: it ignores the game theme, opens with system chrome, and looks like a
## different application. A cozy game cannot hand off its most tense moment —
## "discard this session?" — to a grey system box.
##
## §49 requires that destructive actions are never triggered by a single
## accidental input, so the cancel action is the default focus and Escape
## dismisses without confirming.

signal confirmed()
signal dismissed()

var _confirm_button: Button
var _cancel_button: Button


## Builds and shows a modal over `parent`. Frees itself once answered.
static func open(
	parent: Node,
	title: String,
	body: String,
	confirm_text: String,
	destructive: bool = false,
	cancel_text: String = "Cancel"
) -> ConfirmDialog:
	var dialog := ConfirmDialog.new()
	dialog._build(title, body, confirm_text, destructive, cancel_text)
	parent.add_child(dialog)
	dialog._focus_safe_default()
	return dialog


func _build(
	title: String, body: String, confirm_text: String, destructive: bool, cancel_text: String
) -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Blocks clicks to whatever is behind, which is what makes it modal.
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

	var title_label := Label.new()
	title_label.text = title
	title_label.theme_type_variation = &"Heading"
	column.add_child(title_label)

	var body_label := Label.new()
	body_label.text = body
	body_label.theme_type_variation = &"Muted"
	body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(body_label)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_END
	buttons.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	column.add_child(buttons)

	_cancel_button = Button.new()
	_cancel_button.text = cancel_text
	_cancel_button.theme_type_variation = &"SubtleButton"
	_cancel_button.pressed.connect(_on_cancel)
	buttons.add_child(_cancel_button)

	_confirm_button = Button.new()
	_confirm_button.text = confirm_text
	_confirm_button.theme_type_variation = &"DangerButton" if destructive else &"PrimaryButton"
	_confirm_button.pressed.connect(_on_confirm)
	buttons.add_child(_confirm_button)

	modulate.a = 0.0
	var duration := Motion.duration(DesignTokens.DURATION_FAST)
	if duration <= Motion.INSTANT_EPSILON:
		modulate.a = 1.0
	else:
		var tween := Motion.create_tween_for(self)
		tween.tween_property(self, "modulate:a", 1.0, duration)


## Focus lands on the SAFE option, so hammering Enter cannot confirm a
## destructive action the player has not read.
func _focus_safe_default() -> void:
	_cancel_button.grab_focus()


func _on_confirm() -> void:
	confirmed.emit()
	queue_free()


func _on_cancel() -> void:
	dismissed.emit()
	queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_back"):
		_on_cancel()
		get_viewport().set_input_as_handled()
