class_name GardenScreen
extends AppScreen
## The expandable garden (§23, §24).
##
## TWO WAYS TO ARRANGE, ON PURPOSE. Dragging is the fast one: pick a plant or an
## ornament up and put it down, drag it off the plot to lift it out. Clicking is
## the reachable one: choose something in the side panel, then click a square.
## §50 requires the second to exist, and §24 asks that overlapping be prevented
## where inappropriate — which falls out of the model, since a cell holds one
## thing and dropping onto an occupied cell swaps rather than stacking.
##
## Expansions are reconciled on every open rather than only on session
## completion, so a player who earns a milestone and then opens this screen sees
## it applied, and so a content update adding a step reaches existing saves.

enum Mode { PLANT, DECORATE }

var _garden_view: GardenView
var _side_panel: VBoxContainer
var _hint: Label
var _progress_label: Label
var _progress_bar: ProgressBar

var _mode: Mode = Mode.PLANT
var _pending_plant: PlantInstance = null
var _pending_decoration: StringName = &""
var _hovered_cell := Vector2i(-1, -1)


func build_content() -> void:
	content.add_child(
		SectionHeader.create(
			"Garden", "The long view of everything you have grown.", "Your plot"
		)
	)

	_hint = Label.new()
	_hint.theme_type_variation = &"Muted"
	content.add_child(_hint)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DesignTokens.SPACE_LG)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)

	# CardFlush, not Card: the plot is a full-bleed drawing and should meet the
	# card's rounded edge rather than float inside a band of page colour.
	var frame := PanelContainer.new()
	frame.theme_type_variation = &"CardFlush"
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frame.clip_contents = true
	row.add_child(frame)

	_garden_view = GardenView.new()
	# Wide enough to be worth looking at, short enough to survive a 200% interface
	# scale, and set to expand so the plot uses whatever room the window has. The
	# old fixed 700x500 is what a scaled-down logical viewport could not supply.
	_garden_view.custom_minimum_size = Vector2(320, 300)
	_garden_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_garden_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_garden_view.cell_pressed.connect(_on_cell_pressed)
	_garden_view.object_moved.connect(_on_object_moved)
	_garden_view.object_removed.connect(_on_object_removed)
	_garden_view.rotate_requested.connect(_on_rotate_requested)
	_garden_view.hover_changed.connect(_on_hover_changed)
	frame.add_child(_garden_view)

	row.add_child(_build_side_panel())

	EventBus.save_loaded.connect(_refresh)
	EventBus.plant_matured.connect(_on_plant_matured)
	# A planted specimen goes on growing in the ground, so the plot has to repaint
	# when it advances a stage and not only when it finishes.
	EventBus.plant_stage_changed.connect(_on_plant_stage_changed)
	_refresh()


func on_shown() -> void:
	_refresh()


func _build_side_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"CardSunken"
	panel.custom_minimum_size.x = 280

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", DesignTokens.SPACE_SM)
	panel.add_child(column)

	var heading := Label.new()
	heading.text = "The next patch"
	heading.theme_type_variation = &"Heading"
	column.add_child(heading)

	_progress_label = Label.new()
	_progress_label.theme_type_variation = &"Caption"
	_progress_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_progress_label)

	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 1.0
	_progress_bar.show_percentage = false
	_progress_bar.custom_minimum_size.y = 8
	column.add_child(_progress_bar)

	column.add_child(HSeparator.new())

	var modes := ChoiceRow.new()
	modes.add_choice("Plants", Mode.PLANT)
	modes.add_choice("Ornaments", Mode.DECORATE)
	modes.selected.connect(func(value: Variant) -> void:
		_mode = value as Mode
		_pending_plant = null
		_pending_decoration = &""
		_refresh())
	modes.select_value(Mode.PLANT)
	column.add_child(modes)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_side_panel = VBoxContainer.new()
	_side_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_side_panel.add_theme_constant_override("separation", DesignTokens.SPACE_XXS)
	scroll.add_child(_side_panel)

	return panel


func _refresh() -> void:
	if _garden_view == null:
		return

	var layout := AppState.data.garden
	var context := StatisticsManager.build_context()
	var result := GardenService.reconcile(layout, context, ContentDB.get_all_expansions())

	if not result.newly_unlocked.is_empty():
		for expansion: GardenExpansion in result.newly_unlocked:
			AppState.add_journal_entry(
				JournalEntry.create(
					JournalEntry.Kind.GARDEN_EXPANSION,
					expansion.display_name, expansion.description, String(expansion.id)
				)
			)
			EventBus.garden_expansion_unlocked.emit(String(expansion.id))
		AppState.save_now()

	_garden_view.grid_size = layout.grid_size
	_garden_view.decorations = layout.decorations

	var planted: Array[PlantInstance] = []
	var growth := {}
	for plant: PlantInstance in AppState.data.plants:
		if plant.location == PlantInstance.Location.GARDEN:
			planted.append(plant)
			growth[GardenLayout.cell_key(plant.garden_cell)] = AppState.get_plant_progress(plant)
	_garden_view.set_plants(planted, growth)

	_refresh_progress(layout, context)
	_refresh_side_panel()
	_refresh_hint(planted.size(), layout)


func _refresh_progress(layout: GardenLayout, context: RequirementContext) -> void:
	var next := GardenService.next_expansion(layout, context, ContentDB.get_all_expansions())
	if next == null:
		_progress_label.text = "Every patch of ground is yours. Nothing left to clear."
		_progress_bar.value = 1.0
		return
	var progress := GardenService.next_expansion_progress(layout, context, ContentDB.get_all_expansions())
	_progress_label.text = "%s — %s (%d%%)" % [
		next.display_name,
		RequirementEvaluator.describe(next.requirement),
		int(progress * 100.0),
	]
	_progress_bar.value = progress


func _refresh_side_panel() -> void:
	for child in _side_panel.get_children():
		child.queue_free()

	if _mode == Mode.PLANT:
		_build_plant_list()
	else:
		_build_decoration_list()


func _build_plant_list() -> void:
	# Displayable, not mature: a plant can be planted out from its first stage and
	# finish growing in the ground, which is where it looks best doing it.
	var available: Array[PlantInstance] = []
	for plant: PlantInstance in AppState.data.plants:
		if plant.location == PlantInstance.Location.INVENTORY and plant.can_be_displayed():
			available.append(plant)

	if available.is_empty():
		_side_panel.add_child(
			EmptyState.create(
				"🌳", "Nothing to plant out",
				"A plant can go in the ground once it reaches its first stage, about a "
				+ "third of the way. Anything not on the shelf will appear here.", ""
			)
		)
		return

	for plant: PlantInstance in available:
		var species := ContentDB.get_species(plant.species_id)
		if species == null:
			continue
		var button := Button.new()
		button.text = "%s · %s" % [species.display_name, PlantStageText.describe(plant)]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = "%s — grown over %s" % [
			species.display_name, TimeUtil.format_duration(plant.accumulated_focus_minutes)
		]
		button.theme_type_variation = (
			&"SecondaryButton" if _pending_plant != null and _pending_plant.uid == plant.uid
			else &"SubtleButton"
		)
		var chosen := plant
		button.pressed.connect(func() -> void:
			_pending_plant = null if _pending_plant != null and _pending_plant.uid == chosen.uid else chosen
			_pending_decoration = &""
			_refresh())
		_side_panel.add_child(button)


func _build_decoration_list() -> void:
	var layout := AppState.data.garden
	var available := GardenService.available_decorations(layout, ContentDB.get_all_decorations())

	for decoration: DecorationDef in ContentDB.get_all_decorations():
		var unlocked := available.any(
			func(d: DecorationDef) -> bool: return d.id == decoration.id
		)
		var button := Button.new()
		button.text = decoration.display_name
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.theme_type_variation = (
			&"SecondaryButton" if _pending_decoration == decoration.id else &"SubtleButton"
		)
		if not unlocked:
			# Shown but disabled, with the reason — §74 wants disabled states to
			# be clear, and seeing what is coming is part of the reward.
			button.disabled = true
			button.tooltip_text = "Unlocked by an expansion you have not reached yet."
		else:
			var chosen := decoration.id
			button.pressed.connect(func() -> void:
				_pending_decoration = &"" if _pending_decoration == chosen else chosen
				_pending_plant = null
				_refresh())
		_side_panel.add_child(button)

	_side_panel.add_child(HSeparator.new())

	var clear := Button.new()
	clear.text = "Clear a square"
	clear.theme_type_variation = (
		&"SecondaryButton" if _pending_decoration == &"__clear" else &"SubtleButton"
	)
	clear.pressed.connect(func() -> void:
		_pending_decoration = &"" if _pending_decoration == &"__clear" else &"__clear"
		_pending_plant = null
		_refresh())
	_side_panel.add_child(clear)


func _refresh_hint(planted_count: int, layout: GardenLayout) -> void:
	if _pending_plant != null:
		_hint.text = "Click a square to plant it, or click the plant again to cancel."
		return
	if _pending_decoration == &"__clear":
		_hint.text = "Click a square to clear whatever is on it."
		return
	if _pending_decoration != &"":
		_hint.text = "Click a square to place it, or click the ornament again to cancel."
		return
	if _hovered_cell.x >= 0 and _garden_view.has_object_at(_hovered_cell):
		_hint.text = "Drag to move it, R or right-click to turn it, drag it off the plot to lift it out."
		return
	_hint.text = (
		"%d plants in a %d×%d plot. Drag things around, or click one to open its "
		+ "story. Arrow keys and Enter work too."
	) % [planted_count, layout.grid_size.x, layout.grid_size.y]


# --- Interaction --------------------------------------------------------------

func _on_hover_changed(cell: Vector2i) -> void:
	_hovered_cell = cell
	_refresh_hint(_planted_count(), AppState.data.garden)


func _on_cell_pressed(cell: Vector2i) -> void:
	var layout := AppState.data.garden
	var occupant := _plant_at(cell)

	if _pending_decoration == &"__clear":
		layout.clear_decoration(cell)
		AppState.save_now()
		_refresh()
		return

	if _pending_decoration != &"":
		# Ornaments and plants share the ground: a square holds one or the other,
		# so placing an ornament returns any resident plant to the collection.
		if occupant != null:
			occupant.move_to_inventory()
		layout.set_decoration(cell, String(_pending_decoration))
		_pending_decoration = &""
		AppState.save_now()
		_refresh()
		return

	if _pending_plant != null:
		if occupant != null:
			occupant.move_to_inventory()
		layout.clear_decoration(cell)
		_pending_plant.move_to_garden(cell)
		_pending_plant = null
		AppState.save_now()
		_refresh()
		return

	if occupant != null:
		var dialog := PlantHistoryDialog.open(get_tree().root, occupant)
		dialog.changed.connect(_refresh)


## A drag landed on another square. Whatever was already there swaps back into the
## square the dragged object came from, so a drop never destroys anything.
func _on_object_moved(from: Vector2i, to: Vector2i) -> void:
	var layout := AppState.data.garden

	var moving_plant := _plant_at(from)
	var moving_decoration := layout.get_decoration_id(from)
	var moving_rotation := layout.get_decoration_rotation(from)

	var resident_plant := _plant_at(to)
	var resident_decoration := layout.get_decoration_id(to)
	var resident_rotation := layout.get_decoration_rotation(to)

	layout.clear_decoration(from)
	layout.clear_decoration(to)

	if moving_plant != null:
		moving_plant.move_to_garden(to)
	elif not moving_decoration.is_empty():
		layout.set_decoration(to, moving_decoration, moving_rotation)

	if resident_plant != null:
		resident_plant.move_to_garden(from)
	elif not resident_decoration.is_empty():
		layout.set_decoration(from, resident_decoration, resident_rotation)

	AppState.save_now()
	_refresh()


## A drag ended off the plot. A plant goes back to the collection with everything
## it has grown intact; an ornament is simply removed, and can be placed again
## from the panel at no cost.
func _on_object_removed(cell: Vector2i) -> void:
	var layout := AppState.data.garden
	var plant := _plant_at(cell)

	if plant != null:
		var species := ContentDB.get_species(plant.species_id)
		plant.move_to_inventory()
		EventBus.toast_requested.emit(
			"Back in your collection",
			species.display_name if species != null else "That plant",
			"🌿"
		)
	elif layout.has_decoration(cell):
		var decoration := ContentDB.get_decoration(StringName(layout.get_decoration_id(cell)))
		layout.clear_decoration(cell)
		# Ornaments cost nothing to place again, so this is information rather
		# than a warning — but saying nothing at all would read as a misfire.
		EventBus.toast_requested.emit(
			"Taken away",
			"%s is back in the list." % (decoration.display_name if decoration != null else "That ornament"),
			"🪴"
		)

	AppState.save_now()
	_refresh()


func _on_rotate_requested(cell: Vector2i) -> void:
	var layout := AppState.data.garden
	if layout.rotate_decoration(cell):
		AppState.save_now()
		_refresh()
		return

	var plant := _plant_at(cell)
	if plant == null:
		return
	plant.rotate_in_garden()
	AppState.save_now()
	_refresh()


func _plant_at(cell: Vector2i) -> PlantInstance:
	for plant: PlantInstance in AppState.data.plants:
		if plant.location == PlantInstance.Location.GARDEN and plant.garden_cell == cell:
			return plant
	return null


func _planted_count() -> int:
	var count := 0
	for plant: PlantInstance in AppState.data.plants:
		if plant.location == PlantInstance.Location.GARDEN:
			count += 1
	return count


func _on_plant_matured(_plant_uid: String) -> void:
	_refresh()


func _on_plant_stage_changed(_plant_uid: String, _stage: int) -> void:
	_refresh()
