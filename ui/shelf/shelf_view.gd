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

## Thickness of the timber, as a fraction of a tier's height.
const PLANK_RATIO: float = 0.075
const FRAME_WIDTH: float = 7.0
const FRAME_COLOR := Color("#3B3630")

var _plant_views: Dictionary = {}  ## slot index -> PlantView
var _hovered_slot: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Wide plants — trailing vines especially — draw past their slot. Clipping to
	# the unit keeps foliage inside the furniture instead of spilling across the
	# page, while still letting neighbours overlap a little, as they do on a real
	# shelf.
	clip_contents = true
	resized.connect(_layout_plants)


## Replaces everything on the shelf. `plants_by_slot` maps slot index to
## PlantInstance; absent slots render empty.
func set_plants(plants_by_slot: Dictionary) -> void:
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
		view.growth = 1.0
		view.pot = ContentDB.get_pot(plant.pot_id)
		view.animate = not AppState.get_settings().reduced_motion
		view.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(view)
		_plant_views[slot] = view

	_layout_plants()
	queue_redraw()


## Screen rect of a slot: where a plant stands, measured from the plank it rests on.
func get_slot_rect(slot: int) -> Rect2:
	var tier := slot / SLOTS_PER_TIER
	var column := slot % SLOTS_PER_TIER
	var tier_height := size.y / float(TIERS)
	var slot_width := size.x / float(SLOTS_PER_TIER)
	var plank_thickness := tier_height * PLANK_RATIO

	# The plant stands ON the plank, so its box ends where the timber begins.
	return Rect2(
		Vector2(slot_width * float(column), tier_height * float(tier)),
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
	var tier_height := size.y / float(TIERS)
	var plank_thickness := tier_height * PLANK_RATIO
	var slot_width := size.x / float(SLOTS_PER_TIER)

	# Back panel: the sage wall behind the unit, which is what makes foliage read
	# against something rather than floating on the page background.
	draw_rect(Rect2(Vector2.ZERO, size), DesignTokens.BG_NAV.lightened(0.06))

	# Empty-slot hints, drawn under the timber so they never overlap it.
	for slot in SLOT_COUNT:
		if _plant_views.has(slot):
			continue
		var rect := get_slot_rect(slot)
		var is_hovered := slot == _hovered_slot
		var tint := DesignTokens.BG_NAV_ACTIVE if is_hovered else DesignTokens.BG_NAV
		var inset := rect.grow(-rect.size.x * 0.16)
		inset.size.y = rect.size.y * 0.34
		inset.position.y = rect.position.y + rect.size.y * 0.6
		draw_rect(inset, tint.lightened(0.10 if is_hovered else 0.02), true)

	for tier in TIERS:
		var plank_y := tier_height * float(tier + 1) - plank_thickness

		# The plank, with a darker front edge so it reads as timber with depth.
		draw_rect(Rect2(Vector2(0.0, plank_y), Vector2(size.x, plank_thickness)), DesignTokens.OAK)
		draw_rect(
			Rect2(
				Vector2(0.0, plank_y + plank_thickness * 0.62),
				Vector2(size.x, plank_thickness * 0.38)
			),
			DesignTokens.OAK_DEEP
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
				DesignTokens.SHADOW
			)

	# Metal uprights, drawn last so they sit in front of the planks.
	for column in SLOTS_PER_TIER + 1:
		var x := clampf(slot_width * float(column), FRAME_WIDTH * 0.5, size.x - FRAME_WIDTH * 0.5)
		draw_line(Vector2(x, 0.0), Vector2(x, size.y), FRAME_COLOR, FRAME_WIDTH)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if button.pressed and button.button_index == MOUSE_BUTTON_LEFT:
			var slot := _slot_at(button.position)
			if slot >= 0:
				slot_pressed.emit(slot)
				accept_event()
	elif event is InputEventMouseMotion:
		var slot := _slot_at((event as InputEventMouseMotion).position)
		if slot != _hovered_slot:
			_hovered_slot = slot
			queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_EXIT and _hovered_slot != -1:
		_hovered_slot = -1
		queue_redraw()


func _slot_at(point: Vector2) -> int:
	var tier_height := size.y / float(TIERS)
	var slot_width := size.x / float(SLOTS_PER_TIER)
	if tier_height <= 0.0 or slot_width <= 0.0:
		return -1
	var tier := int(point.y / tier_height)
	var column := int(point.x / slot_width)
	if tier < 0 or tier >= TIERS or column < 0 or column >= SLOTS_PER_TIER:
		return -1
	return tier * SLOTS_PER_TIER + column
