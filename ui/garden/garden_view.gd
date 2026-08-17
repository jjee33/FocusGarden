class_name GardenView
extends Control
## The garden plot: grass, beds, plants and ornaments (§23, §24).
##
## Same approach as ShelfView — the ground is drawn, plants are child PlantViews
## positioned over it. Decorations are drawn rather than instanced, since they
## are static ornament with no behaviour of their own.
##
## Cell size is derived from the plot dimensions each layout, so an expansion
## from 4×3 to 10×7 reflows automatically instead of needing per-size artwork.

signal cell_pressed(cell: Vector2i)

const GRASS := Color("#7FA35C")
## Barely distinct from GRASS. A stronger alternation reads as a chessboard
## rather than as mown lawn, which is the opposite of the intended calm.
const GRASS_ALT := Color("#7C9F5A")
const BED_SOIL := Color("#6B5236")

var grid_size: Vector2i = Vector2i(4, 3):
	set(value):
		grid_size = Vector2i(maxi(1, value.x), maxi(1, value.y))
		_relayout()

## Cell key ("x,y") -> decoration id.
var decorations: Dictionary = {}:
	set(value):
		decorations = value
		queue_redraw()

var _plant_views: Dictionary = {}  ## cell key -> PlantView
var _hovered := Vector2i(-1, -1)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	resized.connect(_relayout)


func set_plants(plants: Array[PlantInstance]) -> void:
	for view: PlantView in _plant_views.values():
		view.queue_free()
	_plant_views.clear()

	for plant: PlantInstance in plants:
		var species := ContentDB.get_species(plant.species_id)
		if species == null:
			continue
		var view := PlantView.new()
		view.species = species
		view.growth = 1.0
		# Garden plants are in the ground, not in pots.
		view.show_pot = false
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(view)
		_plant_views[GardenLayout.cell_key(plant.garden_cell)] = view

	_relayout()
	queue_redraw()


func get_cell_rect(cell: Vector2i) -> Rect2:
	var cell_size := _cell_size()
	return Rect2(
		Vector2(float(cell.x) * cell_size.x, float(cell.y) * cell_size.y), cell_size
	)


func _cell_size() -> Vector2:
	return Vector2(size.x / float(grid_size.x), size.y / float(grid_size.y))


func _relayout() -> void:
	for key: String in _plant_views:
		var view: PlantView = _plant_views[key]
		var rect := get_cell_rect(GardenLayout.key_to_cell(key))
		# Plants stand on the lower edge of their cell, so a back row reads as
		# further away than a front row.
		view.position = rect.position + Vector2(rect.size.x * 0.1, rect.size.y * 0.05)
		view.size = Vector2(rect.size.x * 0.8, rect.size.y * 0.95)
		view.plant_height = view.size.y
	queue_redraw()


func _draw() -> void:
	var cell_size := _cell_size()

	for y in grid_size.y:
		for x in grid_size.x:
			var cell := Vector2i(x, y)
			var rect := get_cell_rect(cell)
			# Alternating tint gives the lawn a mown texture without a sprite.
			draw_rect(rect, GRASS if (x + y) % 2 == 0 else GRASS_ALT, true)

			var key := GardenLayout.cell_key(cell)
			if _plant_views.has(key):
				# A dug bed under each planted cell, so plants sit in soil.
				var bed := rect.grow(-rect.size.x * 0.28)
				bed.position.y = rect.position.y + rect.size.y * 0.72
				bed.size.y = rect.size.y * 0.2
				draw_rect(bed, BED_SOIL, true)

			if decorations.has(key):
				_draw_decoration(String(decorations[key]), rect)

			if cell == _hovered:
				draw_rect(rect.grow(-2.0), DesignTokens.AMBER_GLOW, false, 2.0)

	# Grid lines last, faint, so the plot reads as tended ground.
	for x in range(1, grid_size.x):
		var line_x := float(x) * cell_size.x
		draw_line(Vector2(line_x, 0.0), Vector2(line_x, size.y), Color(0, 0, 0, 0.06), 1.0)
	for y in range(1, grid_size.y):
		var line_y := float(y) * cell_size.y
		draw_line(Vector2(0.0, line_y), Vector2(size.x, line_y), Color(0, 0, 0, 0.06), 1.0)


func _draw_decoration(decoration_id: String, rect: Rect2) -> void:
	var decoration := ContentDB.get_decoration(StringName(decoration_id))
	if decoration == null:
		return
	var centre := rect.get_center()
	var unit := minf(rect.size.x, rect.size.y)

	match decoration.shape:
		DecorationDef.Shape.PATH:
			draw_rect(
				Rect2(
					Vector2(rect.position.x, centre.y - unit * 0.16),
					Vector2(rect.size.x, unit * 0.32)
				),
				decoration.primary_color, true
			)
			for i in 3:
				draw_rect(
					Rect2(
						Vector2(rect.position.x + rect.size.x * (0.14 + 0.3 * float(i)), centre.y - unit * 0.1),
						Vector2(unit * 0.18, unit * 0.2)
					),
					decoration.accent_color, true
				)
		DecorationDef.Shape.POND:
			_draw_ellipse(centre, unit * 0.38, unit * 0.26, decoration.primary_color)
			_draw_ellipse(centre, unit * 0.28, unit * 0.18, decoration.accent_color)
		DecorationDef.Shape.BENCH:
			var seat := Rect2(
				Vector2(centre.x - unit * 0.32, centre.y), Vector2(unit * 0.64, unit * 0.10)
			)
			draw_rect(seat, decoration.primary_color, true)
			draw_rect(
				Rect2(Vector2(centre.x - unit * 0.32, centre.y - unit * 0.24), Vector2(unit * 0.64, unit * 0.08)),
				decoration.primary_color, true
			)
			for side: float in [-0.28, 0.28]:
				draw_rect(
					Rect2(
						Vector2(centre.x + unit * side, centre.y + unit * 0.10),
						Vector2(unit * 0.06, unit * 0.18)
					),
					decoration.accent_color, true
				)
		DecorationDef.Shape.LANTERN:
			draw_rect(
				Rect2(Vector2(centre.x - unit * 0.04, centre.y - unit * 0.05), Vector2(unit * 0.08, unit * 0.34)),
				decoration.primary_color, true
			)
			# The lit pane, which is where the reference art's warmth comes from.
			_draw_ellipse(
				Vector2(centre.x, centre.y - unit * 0.16), unit * 0.13, unit * 0.15,
				decoration.accent_color
			)
		DecorationDef.Shape.FENCE:
			for i in 4:
				draw_rect(
					Rect2(
						Vector2(rect.position.x + rect.size.x * (0.12 + 0.24 * float(i)), centre.y - unit * 0.22),
						Vector2(unit * 0.08, unit * 0.44)
					),
					decoration.primary_color, true
				)
			draw_rect(
				Rect2(Vector2(rect.position.x, centre.y - unit * 0.08), Vector2(rect.size.x, unit * 0.06)),
				decoration.accent_color, true
			)
		DecorationDef.Shape.BIRDBATH:
			draw_rect(
				Rect2(Vector2(centre.x - unit * 0.05, centre.y), Vector2(unit * 0.10, unit * 0.26)),
				decoration.primary_color, true
			)
			_draw_ellipse(Vector2(centre.x, centre.y - unit * 0.04), unit * 0.22, unit * 0.10, decoration.primary_color)
			_draw_ellipse(Vector2(centre.x, centre.y - unit * 0.05), unit * 0.15, unit * 0.06, decoration.accent_color)
		DecorationDef.Shape.PLANTER:
			draw_rect(
				Rect2(Vector2(centre.x - unit * 0.28, centre.y - unit * 0.02), Vector2(unit * 0.56, unit * 0.24)),
				decoration.primary_color, true
			)
			draw_rect(
				Rect2(Vector2(centre.x - unit * 0.30, centre.y - unit * 0.08), Vector2(unit * 0.60, unit * 0.07)),
				decoration.accent_color, true
			)
		DecorationDef.Shape.STONE:
			_draw_ellipse(centre, unit * 0.22, unit * 0.15, decoration.primary_color)
			_draw_ellipse(
				Vector2(centre.x - unit * 0.04, centre.y - unit * 0.03),
				unit * 0.12, unit * 0.07, decoration.accent_color
			)


func _draw_ellipse(centre: Vector2, radius_x: float, radius_y: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 22:
		var angle := TAU * float(i) / 22.0
		points.append(centre + Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	draw_colored_polygon(points, color)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			var cell := _cell_at(button.position)
			if cell.x >= 0:
				cell_pressed.emit(cell)
				accept_event()
	elif event is InputEventMouseMotion:
		var cell := _cell_at((event as InputEventMouseMotion).position)
		if cell != _hovered:
			_hovered = cell
			queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hovered.x >= 0:
		_hovered = Vector2i(-1, -1)
		queue_redraw()


func _cell_at(point: Vector2) -> Vector2i:
	var cell_size := _cell_size()
	if cell_size.x <= 0.0 or cell_size.y <= 0.0:
		return Vector2i(-1, -1)
	var cell := Vector2i(int(point.x / cell_size.x), int(point.y / cell_size.y))
	if cell.x < 0 or cell.y < 0 or cell.x >= grid_size.x or cell.y >= grid_size.y:
		return Vector2i(-1, -1)
	return cell
