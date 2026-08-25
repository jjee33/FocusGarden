class_name GardenView
extends Control
## The garden plot: ground, beds, plants and ornaments (§23, §24).
##
## Same approach as ShelfView — the ground is drawn, plants are child PlantViews
## positioned over it. Ornaments are drawn rather than instanced, since they are
## static scenery with no behaviour of their own.
##
## Cell size is derived from the plot dimensions each layout, so an expansion
## from 4×3 to 10×7 reflows automatically instead of needing per-size artwork.
##
## HOW THINGS ARE MOVED. Press and drag: the object under the cursor lifts, a
## ghost follows the pointer, the cell under it highlights, and releasing drops
## it. Releasing outside the plot lifts the object out of the garden entirely.
##
## THERE IS A FULL KEYBOARD PATH, and §50 means it has to be a real one rather
## than a token. Tab reaches the plot, the arrow keys move a cursor square by
## square, Enter acts on it exactly as a click would, and R turns whatever is
## there. Everything a drag can do is reachable that way: placing goes through the
## side panel, and returning a plant to the collection is a button in the story
## dialog that Enter opens. The cursor is the same highlight the mouse uses, so
## there is only one idea of "the square being considered" to keep in sync.
##
## EVERY COLOUR COMES FROM Palette. This control is drawn entirely by hand, so it
## is exactly the kind of file where a hardcoded hex would survive a theme change
## and quietly break dark mode.

## A cell was clicked without a drag.
signal cell_pressed(cell: Vector2i)
## Something was dragged from `from` and dropped on `to`.
signal object_moved(from: Vector2i, to: Vector2i)
## Something was dragged off the plot entirely.
signal object_removed(cell: Vector2i)
## A rotate was asked for on a cell — right-click, or R while hovering.
signal rotate_requested(cell: Vector2i)
## The hovered cell changed, so the screen can update its hint. (-1,-1) = none.
signal hover_changed(cell: Vector2i)

## Pointer travel, in pixels, before a press becomes a drag rather than a click.
const DRAG_THRESHOLD: float = 6.0
## Breathing room between the plot and the edge of the card, in pixels.
const SURROUND_INSET: float = 18.0
## How far a cell may depart from square before the plot stops growing into the
## space it has been given. Outside this range a cell reads as a strip of ground
## rather than as a patch of it.
const CELL_ASPECT_MIN: float = 0.8
const CELL_ASPECT_MAX: float = 1.5
## Fraction of a cell taken up by the soil bed.
const BED_WIDTH_RATIO: float = 0.62
const BED_HEIGHT_RATIO: float = 0.20

var grid_size: Vector2i = Vector2i(4, 3):
	set(value):
		grid_size = Vector2i(maxi(1, value.x), maxi(1, value.y))
		_relayout()

## Cell key ("x,y") -> { "id": String, "rotation": int }, as GardenLayout stores it.
var decorations: Dictionary = {}:
	set(value):
		decorations = value
		queue_redraw()

## Holds the PlantViews and nothing else, sized to exactly the plot.
##
## Plants are children rather than drawings, so they cannot be clipped by this
## control's own `_draw`. A trailing species drawn at the front row hangs below
## its cell by design, and without a layer it hung out over the stone lip and on
## to the surround. Clipping the layer keeps foliage in the garden.
var _plot_layer: Control
var _plant_views: Dictionary = {}  ## cell key -> PlantView
## Every cell holding a plant, including one whose species this build cannot
## find. Kept apart from `_plant_views` because occupancy and drawability are
## different questions: a plant with no species is still standing there (§54).
var _occupied_cells: Dictionary = {}  ## cell key -> true
## The square under consideration, whether the mouse or the arrow keys put it
## there. One field, because two would drift apart the first time someone used
## both in the same second.
var _hovered := Vector2i(-1, -1)
## True while the cursor is being driven by the keyboard. Without it, the mouse
## leaving the control would clear a cursor the player had just arrowed to.
var _cursor_from_keyboard := false
var _press_cell := Vector2i(-1, -1)
var _press_position := Vector2.ZERO
var _dragging := false
var _drag_position := Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	focus_mode = Control.FOCUS_ALL
	clip_contents = true

	_plot_layer = Control.new()
	_plot_layer.clip_contents = true
	_plot_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_plot_layer)

	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	resized.connect(_relayout)


## Replaces every plant on the plot. `plants` carries the instances; `growth`
## maps a cell key to a 0..1 ratio so a plant that is still growing is drawn at
## the size it has actually reached.
func set_plants(plants: Array[PlantInstance], growth: Dictionary = {}) -> void:
	for view: PlantView in _plant_views.values():
		view.queue_free()
	_plant_views.clear()
	_occupied_cells.clear()

	for plant: PlantInstance in plants:
		var key := GardenLayout.cell_key(plant.garden_cell)
		_occupied_cells[key] = true

		var species := ContentDB.get_species(plant.species_id)
		if species == null:
			# Nothing to draw, but the square is taken. The bed still gets dug, so
			# the player can see something is there and move it.
			continue
		if _plant_views.has(key):
			# The screen never puts two plants on one square, but a save written by
			# a tool or edited by hand can. Keeping the first and skipping the rest
			# beats the alternative, which was building a second view, losing the
			# reference to it, and leaving it parented and drawing forever.
			continue
		var view := PlantView.new()
		view.species = species
		view.growth = float(growth.get(key, 1.0))
		view.mature = plant.is_mature()
		view.facing = plant.garden_rotation
		# Garden plants are in the ground, not in pots.
		view.show_pot = false
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_plot_layer.add_child(view)
		_plant_views[key] = view

	_relayout()
	queue_redraw()


func has_object_at(cell: Vector2i) -> bool:
	var key := GardenLayout.cell_key(cell)
	return _occupied_cells.has(key) or decorations.has(key)


func get_cell_rect(cell: Vector2i) -> Rect2:
	var plot := plot_rect()
	var cell_size := _cell_size()
	return Rect2(
		plot.position + Vector2(float(cell.x) * cell_size.x, float(cell.y) * cell_size.y),
		cell_size
	)


## The plot itself, centred inside this control.
##
## THE PLOT IS NOT THE CONTROL, and it is not a strict aspect fit either. Filling
## the whole card stretched square cells into letterbox strips, which was most of
## why the garden looked wrong; fitting the grid's exact ratio then left a small
## plot marooned in a tall card. So the plot takes the room it is given and the
## CELLS are what is constrained — kept between CELL_ASPECT_MIN and MAX, which is
## the range where a cell still reads as a patch of ground rather than as a strip.
##
## Doing this here rather than wrapping the control in an AspectRatioContainer
## keeps the surround under this class's control, so the space left over can be
## painted as part of the scene instead of showing as a blank band of card.
func plot_rect() -> Rect2:
	var inset := size - Vector2(SURROUND_INSET, SURROUND_INSET) * 2.0
	if inset.x <= 0.0 or inset.y <= 0.0:
		return Rect2(Vector2.ZERO, size)

	var cell := Vector2(inset.x / float(grid_size.x), inset.y / float(grid_size.y))
	var cell_aspect := cell.x / maxf(1.0, cell.y)
	if cell_aspect > CELL_ASPECT_MAX:
		cell.x = cell.y * CELL_ASPECT_MAX
	elif cell_aspect < CELL_ASPECT_MIN:
		cell.y = cell.x / CELL_ASPECT_MIN

	var plot_size := Vector2(cell.x * float(grid_size.x), cell.y * float(grid_size.y))
	return Rect2(((size - plot_size) * 0.5).floor(), plot_size.floor())


func _cell_size() -> Vector2:
	var plot := plot_rect()
	return Vector2(plot.size.x / float(grid_size.x), plot.size.y / float(grid_size.y))


func _relayout() -> void:
	if _plot_layer == null:
		return
	var plot := plot_rect()
	_plot_layer.position = plot.position
	_plot_layer.size = plot.size

	for key: String in _plant_views:
		var view: PlantView = _plant_views[key]
		# Positions are relative to the plot layer, so the cell rect has the plot's
		# own offset taken back off.
		var rect := get_cell_rect(GardenLayout.key_to_cell(key))
		rect.position -= plot.position
		# Plants stand on the lower edge of their cell, so a back row reads as
		# further away than a front row.
		view.position = rect.position + Vector2(rect.size.x * 0.1, rect.size.y * 0.05)
		view.size = Vector2(rect.size.x * 0.8, rect.size.y * 0.95)
		view.plant_height = view.size.y
	queue_redraw()


# --- Drawing ------------------------------------------------------------------

func _draw() -> void:
	_draw_ground()

	for y in grid_size.y:
		for x in grid_size.x:
			var cell := Vector2i(x, y)
			var rect := get_cell_rect(cell)
			var key := GardenLayout.cell_key(cell)

			if _occupied_cells.has(key):
				_draw_bed(rect)
			if decorations.has(key):
				_draw_decoration(cell, rect)

	_draw_cell_highlights()
	_draw_drag_ghost()


## The lawn. Mown bands across the plot rather than a per-cell chequerboard: the
## bands are wider than a cell, so the ground reads as one piece of grass that the
## grid happens to sit on instead of as a tiled surface.
func _draw_ground() -> void:
	var plot := plot_rect()

	# The surround: what the plot sits on. Painted rather than left blank, so the
	# space around a small plot in a large card reads as a table top rather than
	# as a layout mistake.
	draw_rect(Rect2(Vector2.ZERO, size), Palette.bg_sunken(), true)
	# A shadow under the near edge only, softened over three passes. A rectangle
	# around all four sides reads as a picture frame, which is not what a plot
	# lying on a surface looks like.
	var shadow := Palette.shadow_ambient()
	for i in 3:
		shadow.a = Palette.shadow_ambient().a * (1.0 - float(i) / 3.0)
		draw_rect(
			Rect2(
				Vector2(plot.position.x - float(i) * 2.0, plot.position.y + 2.0),
				Vector2(plot.size.x + float(i) * 4.0, plot.size.y + float(i) * 3.0)
			),
			shadow, true
		)
	draw_rect(plot, Palette.grass(), true)

	# Bands are a fixed share of the plot's height rather than a fixed pixel size,
	# so a 4x3 plot and a 10x7 one are mown at the same visual scale. Drawn as a
	# translucent wash rather than a second green: at a full second colour the
	# lawn read as a set of stripes, and the point is a mown texture you notice
	# only if you look for it.
	var band_height := plot.size.y / 16.0
	var bands := int(ceil(plot.size.y / band_height))
	var band_tint := Palette.grass_alt()
	band_tint.a = 0.5
	for i in bands:
		if i % 2 == 1:
			continue
		var band_y := plot.position.y + float(i) * band_height
		var height := minf(band_height, plot.end.y - band_y)
		draw_rect(
			Rect2(Vector2(plot.position.x, band_y), Vector2(plot.size.x, height)),
			band_tint, true
		)

	# A soft darkening toward the back edge, so the plot has a far side. Four
	# stacked translucent strips is enough of a gradient at this scale, and costs
	# four draw calls rather than a shader.
	var shade := Palette.grass_deep()
	for i in 4:
		shade.a = 0.10 - float(i) * 0.02
		draw_rect(
			Rect2(plot.position, Vector2(plot.size.x, plot.size.y * (0.10 + 0.05 * float(i)))),
			shade, true
		)

	_draw_border(plot)


## The stone lip around the plot. What makes the garden look like somewhere that
## was made, rather than like a rectangle of green.
func _draw_border(plot: Rect2) -> void:
	var thickness := maxf(5.0, minf(plot.size.x, plot.size.y) * 0.02)
	var edge := Palette.garden_edge()
	draw_rect(Rect2(plot.position, Vector2(plot.size.x, thickness)), edge, true)
	draw_rect(
		Rect2(Vector2(plot.position.x, plot.end.y - thickness), Vector2(plot.size.x, thickness)),
		edge, true
	)
	draw_rect(Rect2(plot.position, Vector2(thickness, plot.size.y)), edge, true)
	draw_rect(
		Rect2(Vector2(plot.end.x - thickness, plot.position.y), Vector2(thickness, plot.size.y)),
		edge, true
	)

	# A lit top face on the near lip, so the stone has a thickness rather than
	# being a painted line.
	draw_rect(
		Rect2(
			Vector2(plot.position.x, plot.end.y - thickness),
			Vector2(plot.size.x, thickness * 0.35)
		),
		edge.lightened(0.16), true
	)


## A dug bed under a planted cell: rounded soil with a darker hollow and a contact
## shadow, so the plant sits IN the ground instead of on top of it.
func _draw_bed(rect: Rect2) -> void:
	var centre := Vector2(
		rect.position.x + rect.size.x * 0.5,
		rect.position.y + rect.size.y * 0.82
	)
	var radius_x := rect.size.x * BED_WIDTH_RATIO * 0.5
	var radius_y := rect.size.y * BED_HEIGHT_RATIO * 0.5

	_draw_ellipse(
		centre + Vector2(0.0, radius_y * 0.25), radius_x * 1.06, radius_y * 1.05,
		Palette.shadow_key()
	)
	_draw_ellipse(centre, radius_x, radius_y, Palette.bed_soil())
	_draw_ellipse(
		centre - Vector2(0.0, radius_y * 0.28), radius_x * 0.78, radius_y * 0.55,
		Palette.bed_soil_dark()
	)


func _draw_cell_highlights() -> void:
	if _dragging:
		_draw_grid_lines()

	# A focus ring around the whole plot, so a player who tabbed here can see that
	# the arrow keys now belong to the garden (§50).
	if has_focus():
		draw_rect(plot_rect().grow(3.0), Palette.focus_ring(), false, 2.0)

	if _hovered.x < 0:
		return
	var rect := get_cell_rect(_hovered).grow(-3.0)
	var tint := Palette.amber_glow()
	tint.a = 0.30 if _dragging else 0.16
	draw_rect(rect, tint, true)
	# The keyboard cursor is drawn heavier than a hover. A hover follows a pointer
	# and needs no emphasis; a cursor IS the player's position and has to be
	# findable without one.
	draw_rect(rect, Palette.amber_glow(), false, 3.0 if _cursor_from_keyboard else 2.0)


## Grid lines exist only while something is being moved. At rest they made the
## garden look like a spreadsheet; during a drag they are the only way to see
## where a thing will land.
func _draw_grid_lines() -> void:
	var plot := plot_rect()
	var cell_size := _cell_size()
	var line := Palette.ink_primary()
	line.a = 0.10
	for x in range(1, grid_size.x):
		var line_x := plot.position.x + float(x) * cell_size.x
		draw_line(Vector2(line_x, plot.position.y), Vector2(line_x, plot.end.y), line, 1.0)
	for y in range(1, grid_size.y):
		var line_y := plot.position.y + float(y) * cell_size.y
		draw_line(Vector2(plot.position.x, line_y), Vector2(plot.end.x, line_y), line, 1.0)


## The thing being dragged, under the cursor. A plant is shown as its bed outline
## rather than as a second copy of the plant: the real PlantView is still in its
## old cell until the drop lands, and two of them at once reads as a bug.
func _draw_drag_ghost() -> void:
	if not _dragging or _press_cell.x < 0:
		return
	var cell_size := _cell_size()
	var ghost := Rect2(_drag_position - cell_size * 0.5, cell_size)
	var key := GardenLayout.cell_key(_press_cell)

	if decorations.has(key):
		var entry: Variant = decorations[key]
		_draw_decoration_shape(_entry_id(entry), ghost, _entry_rotation(entry), 0.6)
		return

	var tint := Palette.moss()
	tint.a = 0.35
	_draw_ellipse(
		ghost.get_center() + Vector2(0.0, ghost.size.y * 0.3),
		ghost.size.x * BED_WIDTH_RATIO * 0.5, ghost.size.y * BED_HEIGHT_RATIO * 0.5, tint
	)


# --- Ornaments ----------------------------------------------------------------

func _draw_decoration(cell: Vector2i, rect: Rect2) -> void:
	var entry: Variant = decorations[GardenLayout.cell_key(cell)]
	_draw_decoration_shape(_entry_id(entry), rect, _entry_rotation(entry), 1.0)


## Draws one ornament into `rect`, turned by `rotation` quarter turns.
##
## Every shape is built around the cell centre in a unit-square space, so a
## rotation is one transform rather than eight sets of special-cased coordinates.
## That is the whole reason the ornaments were redrawn: the old ones were
## axis-aligned rectangles that could not be turned at all.
func _draw_decoration_shape(
	decoration_id: String, rect: Rect2, rotation: int, alpha: float
) -> void:
	var decoration := ContentDB.get_decoration(StringName(decoration_id))
	if decoration == null:
		return

	var centre := rect.get_center()
	var unit := minf(rect.size.x, rect.size.y)
	var primary := Palette.content(decoration.primary_color)
	var accent := Palette.content(decoration.accent_color)
	primary.a *= alpha
	accent.a *= alpha

	# Ground shadow first, and unrotated: the light comes from the room, not from
	# the ornament, so the shadow must not spin with it.
	var shadow := Palette.shadow_key()
	shadow.a *= alpha
	_draw_ellipse(centre + Vector2(0.0, unit * 0.20), unit * 0.30, unit * 0.09, shadow)

	draw_set_transform(centre, float(posmod(rotation, 4)) * PI * 0.5, Vector2.ONE)
	match decoration.shape:
		DecorationDef.Shape.PATH:
			_shape_path(unit, primary, accent)
		DecorationDef.Shape.POND:
			_shape_pond(unit, primary, accent)
		DecorationDef.Shape.BENCH:
			_shape_bench(unit, primary, accent)
		DecorationDef.Shape.LANTERN:
			_shape_lantern(unit, primary, accent)
		DecorationDef.Shape.FENCE:
			_shape_fence(unit, primary, accent)
		DecorationDef.Shape.BIRDBATH:
			_shape_birdbath(unit, primary, accent)
		DecorationDef.Shape.PLANTER:
			_shape_planter(unit, primary, accent)
		DecorationDef.Shape.STONE:
			_shape_stone(unit, primary, accent)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Flagstones with grass showing between them, rather than one flat strip.
func _shape_path(unit: float, primary: Color, accent: Color) -> void:
	for i in 3:
		var x := (float(i) - 1.0) * unit * 0.30
		var slab := Rect2(Vector2(x - unit * 0.13, -unit * 0.15), Vector2(unit * 0.26, unit * 0.30))
		draw_rect(slab, primary, true)
		draw_rect(Rect2(slab.position, Vector2(slab.size.x, slab.size.y * 0.28)), accent, true)


func _shape_pond(unit: float, primary: Color, accent: Color) -> void:
	_draw_ellipse(Vector2.ZERO, unit * 0.40, unit * 0.27, primary.darkened(0.25))
	_draw_ellipse(Vector2.ZERO, unit * 0.35, unit * 0.22, primary)
	# Two catchlights, offset, so the surface reads as water rather than as paint.
	_draw_ellipse(Vector2(-unit * 0.10, -unit * 0.07), unit * 0.11, unit * 0.04, accent)
	_draw_ellipse(Vector2(unit * 0.12, unit * 0.04), unit * 0.06, unit * 0.02, accent)


func _shape_bench(unit: float, primary: Color, accent: Color) -> void:
	for side: float in [-0.26, 0.26]:
		draw_rect(
			Rect2(Vector2(unit * side - unit * 0.03, unit * 0.04), Vector2(unit * 0.06, unit * 0.20)),
			accent, true
		)
	# Back rail, then seat, then the seat's lit front edge.
	draw_rect(
		Rect2(Vector2(-unit * 0.32, -unit * 0.24), Vector2(unit * 0.64, unit * 0.07)),
		primary.darkened(0.12), true
	)
	draw_rect(Rect2(Vector2(-unit * 0.34, -unit * 0.02), Vector2(unit * 0.68, unit * 0.09)), primary, true)
	draw_rect(
		Rect2(Vector2(-unit * 0.34, unit * 0.05), Vector2(unit * 0.68, unit * 0.02)),
		primary.lightened(0.22), true
	)


func _shape_lantern(unit: float, primary: Color, accent: Color) -> void:
	draw_rect(Rect2(Vector2(-unit * 0.04, -unit * 0.04), Vector2(unit * 0.08, unit * 0.30)), primary, true)
	# The glow around the pane, which is where the reference art's warmth is.
	var glow := accent
	glow.a *= 0.30
	_draw_ellipse(Vector2(0.0, -unit * 0.16), unit * 0.22, unit * 0.24, glow)
	_draw_ellipse(Vector2(0.0, -unit * 0.16), unit * 0.12, unit * 0.14, accent)
	draw_rect(Rect2(Vector2(-unit * 0.13, -unit * 0.34), Vector2(unit * 0.26, unit * 0.05)), primary, true)


func _shape_fence(unit: float, primary: Color, accent: Color) -> void:
	for i in 4:
		var x := (float(i) - 1.5) * unit * 0.24
		draw_rect(
			Rect2(Vector2(x - unit * 0.035, -unit * 0.22), Vector2(unit * 0.07, unit * 0.44)),
			primary, true
		)
		# A lit cap, drawn as a small lighter block rather than a triangle so it
		# stays legible when the cell is small.
		draw_rect(
			Rect2(Vector2(x - unit * 0.035, -unit * 0.22), Vector2(unit * 0.07, unit * 0.05)),
			primary.lightened(0.2), true
		)
	draw_rect(Rect2(Vector2(-unit * 0.42, -unit * 0.09), Vector2(unit * 0.84, unit * 0.05)), accent, true)
	draw_rect(Rect2(Vector2(-unit * 0.42, unit * 0.08), Vector2(unit * 0.84, unit * 0.05)), accent, true)


func _shape_birdbath(unit: float, primary: Color, accent: Color) -> void:
	draw_rect(Rect2(Vector2(-unit * 0.05, 0.0), Vector2(unit * 0.10, unit * 0.24)), primary, true)
	_draw_ellipse(Vector2(0.0, unit * 0.24), unit * 0.14, unit * 0.05, primary.darkened(0.15))
	_draw_ellipse(Vector2(0.0, -unit * 0.02), unit * 0.23, unit * 0.11, primary)
	_draw_ellipse(Vector2(0.0, -unit * 0.04), unit * 0.16, unit * 0.07, accent)


func _shape_planter(unit: float, primary: Color, accent: Color) -> void:
	# A tapered trough: narrower at the base than at the rim.
	draw_colored_polygon(PackedVector2Array([
		Vector2(-unit * 0.28, -unit * 0.02),
		Vector2(unit * 0.28, -unit * 0.02),
		Vector2(unit * 0.22, unit * 0.22),
		Vector2(-unit * 0.22, unit * 0.22),
	]), primary)
	draw_rect(Rect2(Vector2(-unit * 0.31, -unit * 0.09), Vector2(unit * 0.62, unit * 0.08)), accent, true)
	draw_rect(
		Rect2(Vector2(-unit * 0.31, -unit * 0.09), Vector2(unit * 0.62, unit * 0.02)),
		accent.lightened(0.2), true
	)


func _shape_stone(unit: float, primary: Color, accent: Color) -> void:
	_draw_ellipse(Vector2(0.0, unit * 0.02), unit * 0.24, unit * 0.16, primary.darkened(0.18))
	_draw_ellipse(Vector2.ZERO, unit * 0.22, unit * 0.14, primary)
	_draw_ellipse(Vector2(-unit * 0.05, -unit * 0.04), unit * 0.11, unit * 0.06, accent)


func _draw_ellipse(centre: Vector2, radius_x: float, radius_y: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 24:
		var angle := TAU * float(i) / 24.0
		points.append(centre + Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	draw_colored_polygon(points, color)


## Both accessors accept the format-1 bare string as well as the format-2
## dictionary, so this control can be handed a layout straight off disk.
static func _entry_id(entry: Variant) -> String:
	if entry is String:
		return entry
	if entry is Dictionary:
		return DictUtil.get_string(entry, "id")
	return ""


static func _entry_rotation(entry: Variant) -> int:
	if entry is Dictionary:
		return DictUtil.get_int(entry, "rotation")
	return 0


# --- Input --------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_handle_button(event as InputEventMouseButton)
	elif event is InputEventMouseMotion:
		_handle_motion(event as InputEventMouseMotion)
	elif event is InputEventKey and (event as InputEventKey).pressed:
		_handle_key(event as InputEventKey)


func _handle_button(event: InputEventMouseButton) -> void:
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		var cell := _cell_at(event.position)
		if cell.x >= 0 and has_object_at(cell):
			rotate_requested.emit(cell)
			accept_event()
		return

	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	if event.pressed:
		grab_focus()
		_cursor_from_keyboard = false
		_press_cell = _cell_at(event.position)
		_press_position = event.position
		_drag_position = event.position
		_dragging = false
		accept_event()
		return

	_finish_press(event.position)
	accept_event()


func _handle_motion(event: InputEventMouseMotion) -> void:
	_drag_position = event.position

	# A press only becomes a drag once the pointer has actually travelled. Without
	# the threshold every click on a plant would start a drag, and a one-pixel
	# wobble during a click would move it a cell.
	if (
		not _dragging
		and _press_cell.x >= 0
		and has_object_at(_press_cell)
		and event.position.distance_to(_press_position) > DRAG_THRESHOLD
	):
		_dragging = true

	var cell := _cell_at(event.position)
	if cell != _hovered:
		_set_cursor(cell, false)
	elif _dragging:
		queue_redraw()


func _handle_key(event: InputEventKey) -> void:
	# R turns whatever is under the cursor. Handled here rather than on the screen
	# so it works during a drag as well as at rest (§49).
	if event.keycode == KEY_R:
		if _hovered.x >= 0 and has_object_at(_hovered):
			rotate_requested.emit(_hovered)
			accept_event()
		return

	if event.is_action_pressed("ui_accept"):
		if _hovered.x >= 0:
			cell_pressed.emit(_hovered)
			accept_event()
		return

	# Echo allowed, so holding an arrow key walks the plot instead of moving one
	# square and stopping. Enter deliberately does not repeat — holding it would
	# reopen a dialog as fast as the key repeats.
	var step := Vector2i.ZERO
	if event.is_action_pressed("ui_left", true):
		step = Vector2i(-1, 0)
	elif event.is_action_pressed("ui_right", true):
		step = Vector2i(1, 0)
	elif event.is_action_pressed("ui_up", true):
		step = Vector2i(0, -1)
	elif event.is_action_pressed("ui_down", true):
		step = Vector2i(0, 1)
	if step == Vector2i.ZERO:
		return

	# The cursor stops at the edges rather than wrapping. Wrapping from the last
	# column round to the first is disorienting on a grid you are looking at, and
	# it also swallows the arrow key that would move focus out of the plot.
	var moved := _hovered + step if _hovered.x >= 0 else Vector2i.ZERO
	moved = Vector2i(
		clampi(moved.x, 0, grid_size.x - 1), clampi(moved.y, 0, grid_size.y - 1)
	)
	if moved == _hovered:
		return
	_set_cursor(moved, true)
	accept_event()


## Moves the cursor and tells the screen, so its hint follows the keyboard as it
## already follows the mouse.
func _set_cursor(cell: Vector2i, from_keyboard: bool) -> void:
	_cursor_from_keyboard = from_keyboard
	if cell == _hovered:
		queue_redraw()
		return
	_hovered = cell
	hover_changed.emit(cell)
	queue_redraw()


func _on_focus_entered() -> void:
	# Tabbing in with no cursor lands on the first square rather than on nothing,
	# so the first arrow key moves a visible thing instead of summoning one.
	if _hovered.x < 0:
		_set_cursor(Vector2i.ZERO, true)


func _on_focus_exited() -> void:
	if _cursor_from_keyboard:
		_set_cursor(Vector2i(-1, -1), false)


func _finish_press(position: Vector2) -> void:
	var from := _press_cell
	var was_dragging := _dragging
	_press_cell = Vector2i(-1, -1)
	_dragging = false
	queue_redraw()

	if from.x < 0:
		return

	if not was_dragging:
		cell_pressed.emit(from)
		return

	var to := _cell_at(position)
	if to.x < 0:
		# Dropped off the plot. Lifting something out this way is the quickest way
		# to clear a square, and the screen hands it back rather than deleting it.
		object_removed.emit(from)
		return
	if to != from:
		object_moved.emit(from, to)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hovered.x >= 0 and not _cursor_from_keyboard:
		_set_cursor(Vector2i(-1, -1), false)


func _cell_at(point: Vector2) -> Vector2i:
	var plot := plot_rect()
	var cell_size := _cell_size()
	if cell_size.x <= 0.0 or cell_size.y <= 0.0 or not plot.has_point(point):
		return Vector2i(-1, -1)
	var local := point - plot.position
	var cell := Vector2i(int(local.x / cell_size.x), int(local.y / cell_size.y))
	if cell.x < 0 or cell.y < 0 or cell.x >= grid_size.x or cell.y >= grid_size.y:
		return Vector2i(-1, -1)
	return cell
