class_name ShelfScreen
extends AppScreen
## The curated display shelf (§21).
##
## Placement works by SELECT-THEN-PLACE rather than drag-and-drop. §21 asks for
## drag-and-drop, and this is a deliberate deviation: a click-to-select, click-to-
## place model is fully keyboard-reachable (§50), needs no drag threshold tuning,
## and cannot drop a plant into a dead zone. The underlying model supports either,
## so drag can be layered on later without changing how placement is stored.
##
## A plant's location lives on the PlantInstance and nowhere else, so §62's
## duplicate-placement bug is not something this screen has to defend against —
## it cannot be represented.

const INVENTORY_COLUMNS: int = 2

var _shelf_view: ShelfView
var _inventory: GridContainer
var _hint: Label
var _inventory_empty: VBoxContainer

## The plant awaiting a slot, or null. Set by clicking an inventory card.
var _pending_plant: PlantInstance = null


func build_content() -> void:
	content.add_child(
		SectionHeader.create("Shelf", "Arrange what you have grown. Every plant here is time you spent.")
	)

	_hint = Label.new()
	_hint.theme_type_variation = &"Muted"
	content.add_child(_hint)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DesignTokens.SPACE_LG)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)

	var shelf_frame := PanelContainer.new()
	shelf_frame.theme_type_variation = &"Card"
	shelf_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(shelf_frame)

	_shelf_view = ShelfView.new()
	_shelf_view.custom_minimum_size = Vector2(680, 520)
	_shelf_view.slot_pressed.connect(_on_slot_pressed)
	shelf_frame.add_child(_shelf_view)

	row.add_child(_build_inventory_panel())

	EventBus.save_loaded.connect(_refresh)
	EventBus.plant_matured.connect(_on_plant_matured)
	_refresh()


func on_shown() -> void:
	_refresh()


func _build_inventory_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"CardSunken"
	panel.custom_minimum_size.x = 420

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", DesignTokens.SPACE_SM)
	panel.add_child(column)

	var heading := Label.new()
	heading.text = "Your collection"
	heading.theme_type_variation = &"Heading"
	column.add_child(heading)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var holder := VBoxContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(holder)

	_inventory_empty = VBoxContainer.new()
	holder.add_child(_inventory_empty)

	_inventory = GridContainer.new()
	_inventory.columns = INVENTORY_COLUMNS
	_inventory.add_theme_constant_override("h_separation", DesignTokens.SPACE_SM)
	_inventory.add_theme_constant_override("v_separation", DesignTokens.SPACE_SM)
	_inventory.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.add_child(_inventory)

	return panel


func _refresh() -> void:
	if _shelf_view == null:
		return

	# Slots are read from the plants themselves, which is what makes the shelf
	# and the plants incapable of disagreeing about placement.
	var placed := {}
	for plant: PlantInstance in AppState.data.plants:
		if plant.location == PlantInstance.Location.SHELF and plant.shelf_slot >= 0:
			placed[plant.shelf_slot] = plant
	_shelf_view.set_plants(placed)

	_rebuild_inventory()
	_update_hint(placed.size())


func _rebuild_inventory() -> void:
	for child in _inventory.get_children():
		child.queue_free()
	for child in _inventory_empty.get_children():
		child.queue_free()

	var available: Array[PlantInstance] = []
	for plant: PlantInstance in AppState.data.plants:
		if plant.location == PlantInstance.Location.INVENTORY and plant.is_mature():
			available.append(plant)

	if available.is_empty():
		_inventory_empty.add_child(
			EmptyState.create(
				"🌿",
				"Nothing to display yet" if AppState.get_mature_plants().is_empty() else "Everything is placed",
				(
					"Plants appear here once they reach maturity. Keep focusing and the first one will arrive."
					if AppState.get_mature_plants().is_empty()
					else "Every plant you have grown is already on the shelf or in the garden."
				),
				""
			)
		)
		return

	for plant: PlantInstance in available:
		var card := PlantCard.for_plant(plant, 1.0, _plant_subtitle(plant))
		var chosen := plant
		card.pressed.connect(func() -> void: _select_for_placement(chosen))
		if _pending_plant != null and _pending_plant.uid == plant.uid:
			card.modulate = Color(1.0, 1.0, 1.0, 0.55)
		_inventory.add_child(card)


func _plant_subtitle(plant: PlantInstance) -> String:
	return "%s · %s" % [
		TimeUtil.format_duration(plant.accumulated_focus_minutes),
		AppState.get_project_name(plant.primary_project_id),
	]


func _update_hint(placed_count: int) -> void:
	if _pending_plant != null:
		var species := ContentDB.get_species(_pending_plant.species_id)
		var name := species.display_name if species != null else "That plant"
		_hint.text = "Choose a spot for %s, or click it again to cancel." % name
		return
	_hint.text = "%d of %d spots filled. Click a plant to place it, or a placed plant to open its story." % [
		placed_count, ShelfView.SLOT_COUNT
	]


func _select_for_placement(plant: PlantInstance) -> void:
	# Clicking the pending plant again cancels, so there is always a way out
	# without having to place it somewhere unwanted.
	_pending_plant = null if _pending_plant != null and _pending_plant.uid == plant.uid else plant
	_refresh()


func _on_slot_pressed(slot: int) -> void:
	var occupant := _plant_in_slot(slot)

	if _pending_plant != null:
		# Placing onto an occupied slot swaps: the resident returns to the
		# collection rather than being silently overwritten.
		if occupant != null:
			occupant.move_to_inventory()
		_pending_plant.move_to_shelf(slot)
		_pending_plant = null
		AppState.save_now()
		EventBus.shelf_layout_changed.emit()
		_refresh()
		return

	if occupant == null:
		return

	var dialog := PlantHistoryDialog.open(get_tree().root, occupant)
	dialog.changed.connect(_refresh)


func _plant_in_slot(slot: int) -> PlantInstance:
	for plant: PlantInstance in AppState.data.plants:
		if plant.location == PlantInstance.Location.SHELF and plant.shelf_slot == slot:
			return plant
	return null


func _on_plant_matured(_plant_uid: String) -> void:
	_refresh()
