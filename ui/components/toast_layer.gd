class_name ToastLayer
extends Control
## In-app notifications (§34).
##
## WHY NOT OS NOTIFICATIONS: Godot 4 has no cross-platform desktop notification
## API. The available workarounds are a GDExtension or shelling out to
## PowerShell, which flashes a console window and depends on a module that is not
## installed by default. Neither is acceptable for a calm, offline app, so the
## honest implementation is an in-app toast plus a taskbar flash via
## `DisplayServer.window_request_attention()` — which IS a real engine API and
## does get the player's attention when the window is in the background.
##
## This is a documented limitation, not a claim that §34 is fully met.
## See README "Known limitations".
##
## §3 forbids excessive notifications, so this only ever speaks when a session
## ends, and one toast is visible at a time.

const VISIBLE_SECONDS: float = 4.5
const TOAST_WIDTH: int = 340

var _current: PanelContainer = null
var _dismiss_timer: Timer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Purely an overlay: it must never intercept clicks meant for the screen
	# underneath, or the whole app would become unclickable while a toast shows.
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_dismiss_timer = Timer.new()
	_dismiss_timer.one_shot = true
	_dismiss_timer.timeout.connect(_dismiss)
	add_child(_dismiss_timer)

	EventBus.toast_requested.connect(_on_toast_requested)


func _on_toast_requested(title: String, body: String, icon_id: String) -> void:
	# Replace rather than stack. Stacked toasts are how a cozy app starts feeling
	# like a notification centre.
	if _current != null:
		_current.queue_free()
		_current = null

	var card := PanelContainer.new()
	card.theme_type_variation = &"Card"
	card.custom_minimum_size.x = TOAST_WIDTH
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Anchored bottom-right, offset in from the edge.
	card.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	card.grow_vertical = Control.GROW_DIRECTION_BEGIN
	card.position = Vector2(-DesignTokens.SPACE_XL, -DesignTokens.SPACE_XL)
	add_child(card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DesignTokens.SPACE_SM)
	card.add_child(row)

	if not icon_id.is_empty():
		var glyph := Label.new()
		glyph.text = icon_id
		glyph.add_theme_font_size_override("font_size", 28)
		glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(glyph)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", DesignTokens.SPACE_XXS)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(column)

	var title_label := Label.new()
	title_label.text = title
	title_label.theme_type_variation = &"Heading"
	column.add_child(title_label)

	if not body.is_empty():
		var body_label := Label.new()
		body_label.text = body
		body_label.theme_type_variation = &"Muted"
		body_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(body_label)

	_current = card
	_animate_in(card)
	_dismiss_timer.start(VISIBLE_SECONDS)

	# The taskbar flash is the part that reaches a player who has alt-tabbed away.
	# Only when unfocused: requesting attention on the window you are already
	# looking at is noise.
	if not get_window().has_focus():
		DisplayServer.window_request_attention()


func _animate_in(card: PanelContainer) -> void:
	var duration := Motion.duration(DesignTokens.DURATION_NORMAL)
	if duration <= Motion.INSTANT_EPSILON:
		card.modulate.a = 1.0
		return
	card.modulate.a = 0.0
	var start_y := card.position.y
	card.position.y = start_y + 16.0
	var tween := Motion.create_tween_for(card)
	tween.set_parallel(true)
	tween.tween_property(card, "modulate:a", 1.0, duration)
	tween.tween_property(card, "position:y", start_y, duration)


func _dismiss() -> void:
	if _current == null:
		return
	var card := _current
	_current = null

	var duration := Motion.duration(DesignTokens.DURATION_FAST)
	if duration <= Motion.INSTANT_EPSILON:
		card.queue_free()
		return
	var tween := Motion.create_tween_for(card)
	tween.tween_property(card, "modulate:a", 0.0, duration)
	tween.tween_callback(card.queue_free)
