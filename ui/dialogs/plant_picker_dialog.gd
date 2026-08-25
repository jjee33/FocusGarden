class_name PlantPickerDialog
extends Control
## Chooses which plant receives a session's growth (§9, §18).
##
## Offers two things in one place, because from the player's point of view they
## are the same decision: carry on with something already growing, or start
## something new. Splitting them across two screens would make "what am I growing
## today" a navigation problem.
##
## §18 requires the requirement and current progress to be visible at the point
## of choosing, and forbids promising a completion date — so each entry shows the
## real requirement text and a progress figure, never an estimated finish day.

signal chosen(plant_uid: String)

const COLUMNS: int = 4
const DIALOG_SIZE := Vector2(980, 700)


static func open(parent: Node) -> PlantPickerDialog:
	var dialog := PlantPickerDialog.new()
	dialog._build()
	parent.add_child(dialog)
	return dialog


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var scrim := ColorRect.new()
	scrim.color = Palette.bg_overlay()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var card := PanelContainer.new()
	card.theme_type_variation = &"Card"
	card.custom_minimum_size = DIALOG_SIZE
	centre.add_child(card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", DesignTokens.SPACE_MD)
	card.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)

	var title := Label.new()
	title.text = "Choose a plant"
	title.theme_type_variation = &"Title"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close := Button.new()
	close.text = "Close"
	close.theme_type_variation = &"SubtleButton"
	close.pressed.connect(queue_free)
	header.add_child(close)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", DesignTokens.SPACE_LG)
	scroll.add_child(body)

	_build_growing_section(body)
	_build_new_section(body)


func _build_growing_section(parent: VBoxContainer) -> void:
	var growing := AppState.get_growing_plants()
	if growing.is_empty():
		return

	parent.add_child(_section_label("Continue growing"))

	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", DesignTokens.SPACE_MD)
	grid.add_theme_constant_override("v_separation", DesignTokens.SPACE_MD)
	parent.add_child(grid)

	for plant: PlantInstance in growing:
		var species := ContentDB.get_species(plant.species_id)
		var progress := AppState.get_plant_progress(plant)
		var subtitle := PlantStageText.describe(plant)
		# A plant already on display can still be the growth target, and saying
		# where it stands stops the shelf and the picker reading as two separate
		# collections.
		match plant.location:
			PlantInstance.Location.SHELF:
				subtitle += " · on the shelf"
			PlantInstance.Location.GARDEN:
				subtitle += " · in the garden"
			_:
				pass
		if species != null and species.growth_requirement != null:
			subtitle += "\n%s" % RequirementEvaluator.describe(species.growth_requirement)
		var card := PlantCard.for_plant(plant, progress, subtitle)
		var uid := plant.uid
		card.pressed.connect(func() -> void: _choose_existing(uid))
		grid.add_child(card)


func _build_new_section(parent: VBoxContainer) -> void:
	parent.add_child(_section_label("Start something new"))

	var grid := GridContainer.new()
	grid.columns = COLUMNS
	grid.add_theme_constant_override("h_separation", DesignTokens.SPACE_MD)
	grid.add_theme_constant_override("v_separation", DesignTokens.SPACE_MD)
	parent.add_child(grid)

	for species: PlantSpecies in AppState.get_available_species():
		# The requirement in its own words — §18 forbids implying a finish date,
		# and "focus on 5 separate days" cannot honestly be turned into one.
		var subtitle := RequirementEvaluator.describe(species.growth_requirement)
		var card := PlantCard.for_species(species, true, subtitle)
		var id := species.id
		card.pressed.connect(func() -> void: _choose_new(id))
		grid.add_child(card)


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"Heading"
	return label


func _choose_existing(plant_uid: String) -> void:
	AppState.set_active_plant(plant_uid)
	chosen.emit(plant_uid)
	queue_free()


func _choose_new(species_id: StringName) -> void:
	var plant := AppState.start_growing(species_id)
	if plant == null:
		return
	chosen.emit(plant.uid)
	queue_free()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_back"):
		queue_free()
		get_viewport().set_input_as_handled()
