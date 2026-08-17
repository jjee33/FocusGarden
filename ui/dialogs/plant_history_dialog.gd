class_name PlantHistoryDialog
extends Control
## One plant's permanent record (§22).
##
## §22 calls this a core product feature, and it is the clearest expression of
## the whole premise: this plant is not decoration, it is fourteen hours of your
## Network+ study made visible. So the copy here is deliberately specific —
## which project grew it, when it was planted, when it matured, how many
## sessions went into it.
##
## Also the place a plant is repotted, renamed, favourited, or taken off the
## shelf, because those are all things you do while looking at one plant.

signal changed()

const DIALOG_SIZE := Vector2(760, 640)
const ART_HEIGHT: int = 220

var _plant: PlantInstance
var _art: PlantView


static func open(parent: Node, plant: PlantInstance) -> PlantHistoryDialog:
	var dialog := PlantHistoryDialog.new()
	dialog._plant = plant
	dialog._build()
	parent.add_child(dialog)
	return dialog


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

	var scrim := ColorRect.new()
	scrim.color = DesignTokens.BG_OVERLAY
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
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
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
	body.add_theme_constant_override("separation", DesignTokens.SPACE_MD)
	scroll.add_child(body)

	var species := ContentDB.get_species(_plant.species_id)
	if species == null:
		# §54: the species was removed by an update. The plant and its history
		# survive; only the artwork is unavailable.
		body.add_child(PlantDetailDialog._section_label("This species is not in the current version"))
		body.add_child(PlantDetailDialog._fact_row(
			"Focus invested", TimeUtil.format_duration(_plant.accumulated_focus_minutes)
		))
		return

	_build_summary(body, species)
	_build_facts(body, species)
	_build_actions(body)


func _build_summary(parent: VBoxContainer, species: PlantSpecies) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DesignTokens.SPACE_XL)
	parent.add_child(row)

	_art = PlantView.new()
	_art.species = species
	_art.growth = AppState.get_plant_progress(_plant)
	_art.pot = ContentDB.get_pot(_plant.pot_id)
	_art.custom_minimum_size = Vector2(200, ART_HEIGHT)
	_art.plant_height = ART_HEIGHT
	_art.animate = not AppState.get_settings().reduced_motion
	row.add_child(_art)

	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	row.add_child(copy)

	var title := Label.new()
	title.text = _plant.nickname if not _plant.nickname.is_empty() else species.display_name
	title.theme_type_variation = &"Title"
	copy.add_child(title)

	# The headline claim of the whole product, stated plainly.
	var headline := Label.new()
	headline.text = "%s of focus, grown while working on %s." % [
		TimeUtil.format_duration(_plant.accumulated_focus_minutes),
		AppState.get_project_name(_plant.primary_project_id),
	]
	headline.theme_type_variation = &"Muted"
	headline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(headline)

	if not _plant.is_mature():
		var progress := AppState.get_plant_progress(_plant)
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.value = progress
		bar.show_percentage = false
		bar.custom_minimum_size.y = 10
		copy.add_child(bar)

		var requirement := Label.new()
		requirement.text = "%s · %d%% grown" % [
			RequirementEvaluator.describe(species.growth_requirement), int(progress * 100.0)
		]
		requirement.theme_type_variation = &"Caption"
		requirement.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		copy.add_child(requirement)


func _build_facts(parent: VBoxContainer, species: PlantSpecies) -> void:
	parent.add_child(PlantDetailDialog._section_label("Record"))
	parent.add_child(PlantDetailDialog._fact_row("Species", species.display_name))
	parent.add_child(PlantDetailDialog._fact_row("Planted", PlantDetailDialog._format_date(_plant.planted_at_utc)))
	parent.add_child(PlantDetailDialog._fact_row(
		"Matured",
		PlantDetailDialog._format_date(_plant.matured_at_utc)
		if _plant.is_mature() else "Still growing"
	))
	parent.add_child(PlantDetailDialog._fact_row(
		"Focus time", TimeUtil.format_duration(_plant.accumulated_focus_minutes)
	))
	parent.add_child(PlantDetailDialog._fact_row(
		"Sessions", "%d" % _plant.contributing_session_ids.size()
	))
	parent.add_child(PlantDetailDialog._fact_row(
		"Grown while", AppState.get_project_name(_plant.primary_project_id)
	))
	parent.add_child(PlantDetailDialog._fact_row("Pot", _pot_name()))
	parent.add_child(PlantDetailDialog._fact_row("Location", _location_name()))


func _build_actions(parent: VBoxContainer) -> void:
	parent.add_child(PlantDetailDialog._section_label("Pot"))

	# Repotting is cosmetic and instant. Locked pots are shown disabled with the
	# reason, rather than hidden, so the player can see what is coming (§74).
	var pots := HBoxContainer.new()
	pots.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	parent.add_child(pots)

	var context := StatisticsManager.build_context()
	for pot: PotStyle in ContentDB.get_all_pots():
		var button := Button.new()
		button.text = pot.display_name
		button.theme_type_variation = &"Chip"
		button.toggle_mode = true
		button.button_pressed = pot.id == _plant.pot_id

		var locked := (
			pot.unlock_requirement != null
			and not RequirementEvaluator.is_met(pot.unlock_requirement, context)
		)
		if locked:
			button.disabled = true
			button.tooltip_text = RequirementEvaluator.describe(pot.unlock_requirement)
		else:
			var pot_id := pot.id
			button.pressed.connect(func() -> void: _repot(pot_id))
		pots.add_child(button)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	parent.add_child(buttons)

	var favourite := Button.new()
	favourite.text = "★  Favourite" if _plant.favorite else "☆  Favourite"
	favourite.theme_type_variation = &"SubtleButton"
	favourite.pressed.connect(func() -> void:
		_plant.favorite = not _plant.favorite
		favourite.text = "★  Favourite" if _plant.favorite else "☆  Favourite"
		AppState.save_now()
		changed.emit())
	buttons.add_child(favourite)

	if _plant.location != PlantInstance.Location.INVENTORY:
		var remove := Button.new()
		remove.text = "Return to inventory"
		remove.theme_type_variation = &"SubtleButton"
		remove.pressed.connect(func() -> void:
			_plant.move_to_inventory()
			AppState.save_now()
			changed.emit()
			queue_free())
		buttons.add_child(remove)


func _repot(pot_id: StringName) -> void:
	_plant.pot_id = pot_id
	AppState.save_now()
	if _art != null:
		_art.pot = ContentDB.get_pot(pot_id)
	changed.emit()


func _pot_name() -> String:
	var pot := ContentDB.get_pot(_plant.pot_id)
	return pot.display_name if pot != null else "—"


func _location_name() -> String:
	match _plant.location:
		PlantInstance.Location.SHELF:
			return "On the shelf"
		PlantInstance.Location.GARDEN:
			return "In the garden"
		_:
			return "In your collection"


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_back"):
		queue_free()
		get_viewport().set_input_as_handled()
