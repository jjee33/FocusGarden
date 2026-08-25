class_name ShelfView
extends Control
## The display shelf itself: timber tiers in a dark metal frame (§21).
##
## Drawn rather than assembled from sprites, for the same reasons as the plants:
## it scales to any window size, needs no art, and matches the reference's
## warm-oak-and-black-frame shelving unit exactly.
##
## Slots are laid out by this view and reported back by index. PlantInstance
## owns which slot it occupies, so this control never stores placement — it only
## knows where slot N is on screen.

signal slot_pressed(slot_index: int)

const TIERS: int = 3
const SLOTS_PER_TIER: int = 4
const SLOT_COUNT: int = TIERS * SLOTS_PER_TIER

## The range the whole unit's width-over-height may sit in. Not a single ratio:
## a strict fit left a small unit marooned in a tall card, and letting it fill the
## card outright gave four columns of very deep, very empty shelves. Between these
## it uses the room it has and still looks like furniture.
const UNIT_ASPECT_MIN: float = 1.0
const UNIT_ASPECT_MAX: float = 1.4
## Breathing room between the unit and the edge of the card, in pixels.
const WALL_INSET: float = 20.0

## Thickness of the timber, as a fraction of a tier's height.
const PLANK_RATIO: float = 0.075
const FRAME_WIDTH: float = 7.0

var _plant_views: Dictionary = {}  ## slot index -> PlantView
## The slot under consideration, whether the mouse or the arrow keys put it
## there. One field, because two would drift apart the first time someone used
## both in the same second.
var _hovered_slot: int = -1
## True while the cursor is being driven by the keyboard. Without it, the mouse
## leaving the control would clear a cursor the player had just arrowed to.
var _cursor_from_keyboard := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Tab reaches the shelf, the arrow keys walk the slots and Enter opens or
	# fills one, which is everything the mouse can do here (§50).
	focus_mode = Control.FOCUS_ALL
	focus_entered.connect(_on_focus_entered)
	focus_exited.connect(_on_focus_exited)
	# Wide plants — trailing vines especially — draw past their slot. Clipping to
	# the unit keeps foliage inside the furniture instead of spilling across the
	# page, while still letting neighbours overlap a little, as they do on a real
	# shelf.
	clip_contents = true
	resized.connect(_layout_plants)


## Replaces everything on the shelf. `plants_by_slot` maps slot index to
## PlantInstance and `growth_by_slot` maps the same keys to a 0..1 progress
## ratio; absent slots render empty.
##
## Growth is passed in rather than looked up here for the same reason PlantView
## takes it as a property: this control draws what it is told to draw, so it
## stays usable from tool scripts and tests that have no player state at all.
func set_plants(plants_by_slot: Dictionary, growth_by_slot: Dictionary = {}) -> void:
	for view: PlantView in _plant_views.values():
		view.queue_free()
	_plant_views.clear()

	for slot: int in plants_by_slot:
		var plant: PlantInstance = plants_by_slot[slot]
		var species := ContentDB.get_species(plant.species_id)
		if species == null:
			continue

		var view := PlantView.new()
		view.species = species
		# A plant may be shelved from its first stage onward, so the shelf shows
		# real growth. Defaulting to 1.0 kept a half-grown plant looking finished.
		view.growth = float(growth_by_slot.get(slot, 1.0))
		view.mature = plant.is_mature()
		view.pot = ContentDB.get_pot(plant.pot_id)
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(view)
		_plant_views[slot] = view

	_layout_plants()
	queue_redraw()


## The unit itself, centred in this control at its own proportions.
##
## Same reasoning as GardenView.plot_rect(): stretched to fill a tall card, four
## columns of plants became a set of very deep, very empty shelves. The space
## around it is painted as the wall behind, so a small unit in a large card reads
## as a room rather than as a layout mistake.
func unit_rect() -> Rect2:
	var inset := size - Vector2(WALL_INSET, WALL_INSET) * 2.0
	if inset.x <= 0.0 or inset.y <= 0.0:
		return Rect2(Vector2.ZERO, size)

	var unit := inset
	var aspect := unit.x / maxf(1.0, unit.y)
	if aspect > UNIT_ASPECT_MAX:
		unit.x = unit.y * UNIT_ASPECT_MAX
	elif aspect < UNIT_ASPECT_MIN:
		unit.y = unit.x / UNIT_ASPECT_MIN
	return Rect2(((size - unit) * 0.5).floor(), unit.floor())


## Screen rect of a slot: where a plant stands, measured from the plank it rests on.
func get_slot_rect(slot: int) -> Rect2:
	var unit := unit_rect()
	var tier := slot / SLOTS_PER_TIER
	var column := slot % SLOTS_PER_TIER
	var tier_height := unit.size.y / float(TIERS)
	var slot_width := unit.size.x / float(SLOTS_PER_TIER)
	var plank_thickness := tier_height * PLANK_RATIO

	# The plant stands ON the plank, so its box ends where the timber begins.
	return Rect2(
		unit.position + Vector2(slot_width * float(column), tier_height * float(tier)),
		Vector2(slot_width, tier_height - plank_thickness)
	)


func _layout_plants() -> void:
	for slot: int in _plant_views:
		var view: PlantView = _plant_views[slot]
		var rect := get_slot_rect(slot)
		# Inset so a wide plant does not touch its neighbour.
		view.position = rect.position + Vector2(rect.size.x * 0.1, rect.size.y * 0.12)
		view.size = Vector2(rect.size.x * 0.8, rect.size.y * 0.88)
		view.plant_height = view.size.y


func _draw() -> void:
	var unit := unit_rect()
	var tier_height := unit.size.y / float(TIERS)
	var plank_thickness := tier_height * PLANK_RATIO
	var slot_width := unit.size.x / float(SLOTS_PER_TIER)

	# Back panel: the sage wall behind the unit, which is what makes foliage read
	# against something rather than floating on the page background. It fills the
	# whole control, so the unit hangs on a wall rather than on a card edge.
	draw_rect(Rect2(Vector2.ZERO, size), Palette.shelf_wall())
	draw_rect(unit.grow(4.0), Palette.shadow_ambient(), true)

	# Empty-slot hints, drawn under the timber so they never overlap it.
	for slot in SLOT_COUNT:
		if _plant_views.has(slot):
			continue
		var rect := get_slot_rect(slot)
		var is_hovered := slot == _hovered_slot
		var tint := Palette.bg_nav_active() if is_hovered else Palette.bg_nav()
		var inset := rect.grow(-rect.size.x * 0.16)
		inset.size.y = rect.size.y * 0.34
		inset.position.y = rect.position.y + rect.size.y * 0.6
		draw_rect(inset, tint.lightened(0.10 if is_hovered else 0.02), true)

	for tier in TIERS:
		var plank_y := unit.position.y + tier_height * float(tier + 1) - plank_thickness

		# The plank, with a darker front edge so it reads as timber with depth.
		draw_rect(
			Rect2(Vector2(unit.position.x, plank_y), Vector2(unit.size.x, plank_thickness)),
			Palette.oak()
		)
		draw_rect(
			Rect2(
				Vector2(unit.position.x, plank_y + plank_thickness * 0.62),
				Vector2(unit.size.x, plank_thickness * 0.38)
			),
			Palette.oak_deep()
		)

		# A soft shadow cast onto the plank by whatever stands on it.
		for slot in range(tier * SLOTS_PER_TIER, (tier + 1) * SLOTS_PER_TIER):
			if not _plant_views.has(slot):
				continue
			var rect := get_slot_rect(slot)
			draw_rect(
				Rect2(
					Vector2(rect.position.x + rect.size.x * 0.22, plank_y - 3.0),
					Vector2(rect.size.x * 0.56, 3.0)
				),
				Palette.shadow_ambient()
			)

	# A focus ring around the unit, so a player who tabbed here can see that the
	# arrow keys now belong to the shelf (§50).
	if has_focus():
		draw_rect(unit.grow(3.0), Palette.focus_ring(), false, 2.0)

	# Metal uprights, drawn last so they sit in front of the planks.
	for column in SLOTS_PER_TIER + 1:
		var x := clampf(
			unit.position.x + slot_width * float(column),
			unit.position.x + FRAME_WIDTH * 0.5,
			unit.end.x - FRAME_WIDTH * 0.5
		)
		draw_line(
			Vector2(x, unit.position.y), Vector2(x, unit.end.y),
			Palette.shelf_frame(), FRAME_WIDTH
		)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			grab_focus()
			var slot := _slot_at(button.position)
			if slot >= 0:
				_set_cursor(slot, false)
				slot_pressed.emit(slot)
				accept_event()
	elif event is InputEventMouseMotion:
		var slot := _slot_at((event as InputEventMouseMotion).position)
		if slot != _hovered_slot:
			_set_cursor(slot, false)
	elif event is InputEventKey and (event as InputEventKey).pressed:
		_handle_key(event as InputEventKey)


func _handle_key(event: InputEventKey) -> void:
	if event.is_action_pressed("ui_accept"):
		if _hovered_slot >= 0:
			slot_pressed.emit(_hovered_slot)
			accept_event()
		return

	# Slots are a grid, so left and right walk a tier and up and down change tier.
	# Treating them as one flat list would make the arrow keys jump the cursor
	# across the shelf in a way that matches nothing the player can see.
	# Echo allowed, so holding an arrow key walks the shelf rather than moving one
	# slot and stopping. Enter deliberately does not repeat.
	var step := 0
	if event.is_action_pressed("ui_left", true):
		step = -1
	elif event.is_action_pressed("ui_right", true):
		step = 1
	elif event.is_action_pressed("ui_up", true):
		step = -SLOTS_PER_TIER
	elif event.is_action_pressed("ui_down", true):
		step = SLOTS_PER_TIER
	if step == 0:
		return

	# Stops at the ends rather than wrapping, so the arrow key that would move
	# focus off the shelf is not swallowed by a cursor looping round.
	var moved := clampi(
		(_hovered_slot if _hovered_slot >= 0 else 0) + step, 0, SLOT_COUNT - 1
	)
	if moved == _hovered_slot:
		return
	_set_cursor(moved, true)
	accept_event()


func _set_cursor(slot: int, from_keyboard: bool) -> void:
	_cursor_from_keyboard = from_keyboard
	if slot == _hovered_slot:
		return
	_hovered_slot = slot
	queue_redraw()


func _on_focus_entered() -> void:
	if _hovered_slot < 0:
		_set_cursor(0, true)


func _on_focus_exited() -> void:
	if _cursor_from_keyboard:
		_set_cursor(-1, false)


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hovered_slot != -1 and not _cursor_from_keyboard:
		_set_cursor(-1, false)


func _slot_at(point: Vector2) -> int:
	var unit := unit_rect()
	var tier_height := unit.size.y / float(TIERS)
	var slot_width := unit.size.x / float(SLOTS_PER_TIER)
	if tier_height <= 0.0 or slot_width <= 0.0 or not unit.has_point(point):
		return -1
	var local := point - unit.position
	var tier := int(local.y / tier_height)
	var column := int(local.x / slot_width)
	if tier < 0 or tier >= TIERS or column < 0 or column >= SLOTS_PER_TIER:
		return -1
	return tier * SLOTS_PER_TIER + column
