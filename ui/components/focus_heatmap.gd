class_name FocusHeatmap
extends Control
## A year of focus, one cell per day (§30).
##
## Drawn in a single `_draw` rather than as 365 child Controls. Three hundred and
## sixty-five nodes with their own styleboxes and hit areas is a real cost to
## build and lay out every time the screen opens, and §30 explicitly asks for
## this to stay performant. One canvas and a hit-test on click is far cheaper.
##
## §50 forbids conveying meaning by colour alone, so the tooltip states the exact
## figure for the day under the cursor, and intensity steps are coarse enough to
## be distinguishable without fine colour discrimination.

signal day_pressed(date_key: String)

const WEEKS: int = 53
const DAYS_PER_WEEK: int = 7
const CELL_GAP: float = 3.0
## Focus minutes at which a day reaches full intensity. Above this the colour
## stops changing, so one enormous day does not flatten every other day to grey.
const SATURATION_MINUTES: float = 180.0

var totals: Dictionary = {}:
	set(value):
		totals = value
		queue_redraw()

var _hovered_key: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size.y = 132


func _draw() -> void:
	var cell := _cell_size()
	if cell <= 0.0:
		return

	var today := TimeUtil.today_key()
	# The grid ends on today's column, so the most recent day is where the eye
	# naturally lands rather than buried mid-grid.
	var start_offset := (WEEKS * DAYS_PER_WEEK) - 1

	for index in WEEKS * DAYS_PER_WEEK:
		var date_key := TimeUtil.shift_date_key(today, index - start_offset)
		var week := index / DAYS_PER_WEEK
		var weekday := index % DAYS_PER_WEEK
		var rect := Rect2(
			Vector2(float(week) * (cell + CELL_GAP), float(weekday) * (cell + CELL_GAP)),
			Vector2(cell, cell)
		)

		var minutes := float(totals.get(date_key, 0.0))
		draw_rect(rect, _color_for(minutes), true)

		if date_key == _hovered_key:
			draw_rect(rect, DesignTokens.INK_PRIMARY, false, 1.5)


func _color_for(minutes: float) -> Color:
	if minutes <= 0.0:
		return DesignTokens.BG_SUNKEN
	# Four discrete steps rather than a continuous ramp: distinct bands are far
	# easier to compare at a glance than a smooth gradient.
	var intensity := clampf(minutes / SATURATION_MINUTES, 0.0, 1.0)
	var step := ceili(intensity * 4.0)
	return DesignTokens.MOSS_SOFT.lerp(DesignTokens.MOSS_DEEP, (float(step) - 1.0) / 3.0)


func _cell_size() -> float:
	var by_width := (size.x - float(WEEKS - 1) * CELL_GAP) / float(WEEKS)
	var by_height := (size.y - float(DAYS_PER_WEEK - 1) * CELL_GAP) / float(DAYS_PER_WEEK)
	return floorf(minf(by_width, by_height))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			var key := _key_at(button.position)
			if not key.is_empty():
				day_pressed.emit(key)
				accept_event()
	elif event is InputEventMouseMotion:
		var key := _key_at((event as InputEventMouseMotion).position)
		if key != _hovered_key:
			_hovered_key = key
			_update_tooltip(key)
			queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and not _hovered_key.is_empty():
		_hovered_key = ""
		queue_redraw()


func _update_tooltip(date_key: String) -> void:
	if date_key.is_empty():
		tooltip_text = ""
		return
	var minutes := float(totals.get(date_key, 0.0))
	tooltip_text = "%s — %s" % [
		date_key,
		TimeUtil.format_duration(minutes) if minutes > 0.0 else "no focus"
	]


func _key_at(point: Vector2) -> String:
	var cell := _cell_size()
	if cell <= 0.0:
		return ""
	var week := int(point.x / (cell + CELL_GAP))
	var weekday := int(point.y / (cell + CELL_GAP))
	if week < 0 or week >= WEEKS or weekday < 0 or weekday >= DAYS_PER_WEEK:
		return ""
	var index := week * DAYS_PER_WEEK + weekday
	return TimeUtil.shift_date_key(TimeUtil.today_key(), index - ((WEEKS * DAYS_PER_WEEK) - 1))
