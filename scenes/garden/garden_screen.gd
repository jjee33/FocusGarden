class_name GardenScreen
extends AppScreen
## The expandable garden (§23, §24).
##
## Placement follows the shelf: select something, then click a cell. §24 asks
## that overlapping be prevented where inappropriate, which falls out of the
## model — a cell holds one plant, and placing onto an occupied cell swaps rather
## than stacking.
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


func build_content() -> void:
	content.add_child(
		SectionHeader.create("Garden", "The long view of everything you have grown.")
	)

	_hint = Label.new()
	_hint.theme_type_variation = &"Muted"
	content.add_child(_hint)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DesignTokens.SPACE_LG)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(row)

	var frame := PanelContainer.new()
	frame.theme_type_variation = &"Card"
	frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(frame)

	_garden_view = GardenView.new()
	_garden_view.custom_minimum_size = Vector2(700, 500)
	_garden_view.cell_pressed.connect(_on_cell_pressed)
	frame.add_child(_garden_view)

	row.add_child(_build_side_panel())

	EventBus.save_loaded.connect(_refresh)
	EventBus.plant_matured.connect(_on_plant_matured)
	_refresh()


func on_shown() -> void:
	_refresh()


func _build_side_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"CardSunken"
	panel.custom_minimum_size.x = 400

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
	_progress_bar.custom_minimum_size.y = 10
	column.add_child(_progress_bar)

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
	_side_panel.add_theme_constant_override("separation", DesignTokens.SPACE_SM)
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
	for plant: PlantInstance in AppState.data.plants:
		if plant.location == PlantInstance.Location.GARDEN:
			planted.append(plant)
	_garden_view.set_plants(planted)

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
	var available: Array[PlantInstance] = []
	for plant: PlantInstance in AppState.data.plants:
		if plant.location == PlantInstance.Location.INVENTORY and plant.is_mature():
			available.append(plant)

	if available.is_empty():
		_side_panel.add_child(
			EmptyState.create(
				"🌳", "Nothing to plant out",
				"Mature plants that are not on the shelf can be planted here.", ""
			)
		)
		return

	for plant: PlantInstance in available:
		var species := ContentDB.get_species(plant.species_id)
		if species == null:
			continue
		var button := Button.new()
		button.text = "%s · %s" % [
			species.display_name, TimeUtil.format_duration(plant.accumulated_focus_minutes)
		]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.theme_type_variation = (
			&"PrimaryButton" if _pending_plant != null and _pending_plant.uid == plant.uid
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
		button.theme_type_variation = (
			&"PrimaryButton" if _pending_decoration == decoration.id else &"SubtleButton"
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

	var clear := Button.new()
	clear.text = "Clear a square"
	clear.theme_type_variation = (
		&"PrimaryButton" if _pending_decoration == &"__clear" else &"SubtleButton"
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
	_hint.text = "%d plants in a %d×%d plot. Click a planted square to open its story." % [
		planted_count, layout.grid_size.x, layout.grid_size.y
	]


func _on_cell_pressed(cell: Vector2i) -> void:
	var layout := AppState.data.garden
	var occupant := _plant_at(cell)
	var key := GardenLayout.cell_key(cell)

	if _pending_decoration == &"__clear":
		layout.decorations.erase(key)
		AppState.save_now()
		_refresh()
		return

	if _pending_decoration != &"":
		# Ornaments and plants share the ground: a square holds one or the other,
		# so placing an ornament returns any resident plant to the collection.
		if occupant != null:
			occupant.move_to_inventory()
		layout.decorations[key] = String(_pending_decoration)
		_pending_decoration = &""
		AppState.save_now()
		_refresh()
		return

	if _pending_plant != null:
		if occupant != null:
			occupant.move_to_inventory()
		layout.decorations.erase(key)
		_pending_plant.move_to_garden(cell)
		_pending_plant = null
		AppState.save_now()
		_refresh()
		return

	if occupant != null:
		var dialog := PlantHistoryDialog.open(get_tree().root, occupant)
		dialog.changed.connect(_refresh)


func _plant_at(cell: Vector2i) -> PlantInstance:
	for plant: PlantInstance in AppState.data.plants:
		if plant.location == PlantInstance.Location.GARDEN and plant.garden_cell == cell:
			return plant
	return null


func _on_plant_matured(_plant_uid: String) -> void:
	_refresh()
