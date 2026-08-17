class_name PlantDetailDialog
extends Control
## A species entry in full (§16's detail view, §17's botanical information).
##
## Shows the artwork, both names, rarity, biome, description, real botanical
## facts, the growth requirement, and the player's own history with the species:
## how many they have grown, when they first found it, their fastest growth, and
## the total focus time invested in it.
##
## §16 requires undiscovered data to stay hidden. An undiscovered species shows
## its silhouette and nothing else — not even its family — because the point of a
## collection is that finding something reveals it.

const DIALOG_SIZE := Vector2(860, 660)
const ART_HEIGHT: int = 260


static func open(parent: Node, species: PlantSpecies) -> PlantDetailDialog:
	var dialog := PlantDetailDialog.new()
	dialog._build(species)
	parent.add_child(dialog)
	return dialog


func _build(species: PlantSpecies) -> void:
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

	var entry := AppState.get_catalogue_entry(species.id)
	var discovered := entry != null and entry.discovered

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

	var body := HBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", DesignTokens.SPACE_XL)
	scroll.add_child(body)

	var art := PlantView.new()
	art.species = species
	art.growth = 1.0
	art.silhouette = not discovered
	art.pot = ContentDB.get_pot(&"terracotta_basic")
	art.custom_minimum_size = Vector2(260, ART_HEIGHT)
	art.plant_height = ART_HEIGHT
	body.add_child(art)

	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", DesignTokens.SPACE_SM)
	body.add_child(details)

	if not discovered:
		_build_undiscovered(details, species)
		return
	_build_discovered(details, species, entry)


## §16: an undiscovered entry withholds everything except how to find it.
func _build_undiscovered(parent: VBoxContainer, species: PlantSpecies) -> void:
	var title := Label.new()
	title.text = "Undiscovered"
	title.theme_type_variation = &"Title"
	parent.add_child(title)

	var hint := Label.new()
	hint.text = "Grow this plant to add it to your catalogue."
	hint.theme_type_variation = &"Muted"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(hint)

	# Rarity is not a spoiler and helps the player judge whether to chase it.
	parent.add_child(_fact_row("Rarity", species.get_rarity_name()))
	parent.add_child(
		_fact_row("To grow", RequirementEvaluator.describe(species.growth_requirement))
	)


func _build_discovered(
	parent: VBoxContainer, species: PlantSpecies, entry: CatalogueEntry
) -> void:
	var title := Label.new()
	title.text = species.display_name
	title.theme_type_variation = &"Title"
	parent.add_child(title)

	var latin := Label.new()
	latin.text = species.scientific_name
	latin.theme_type_variation = &"Muted"
	parent.add_child(latin)

	var tags := HBoxContainer.new()
	tags.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	tags.add_child(PlantCard._rarity_badge(species.rarity))
	var biome := Label.new()
	biome.text = String(species.biome_id).capitalize()
	biome.theme_type_variation = &"Caption"
	biome.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	tags.add_child(biome)
	parent.add_child(tags)

	var description := Label.new()
	description.text = species.description
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(description)

	parent.add_child(_divider())
	parent.add_child(_section_label("To grow"))
	parent.add_child(
		_fact_row("Requirement", RequirementEvaluator.describe(species.growth_requirement))
	)

	# §17's botanical block. Presentation only — nothing here affects gameplay.
	if species.botanical != null and species.botanical.is_populated():
		parent.add_child(_divider())
		parent.add_child(_section_label("Botanical notes"))
		parent.add_child(_fact_row("Family", species.botanical.family))
		parent.add_child(_fact_row("Native to", species.botanical.native_region))
		parent.add_child(_fact_row("Light", species.botanical.light_preference))
		parent.add_child(_fact_row("Water", species.botanical.watering_preference))
		parent.add_child(_fact_row("Care", species.botanical.care_difficulty))

		var fact := Label.new()
		fact.text = species.botanical.interesting_fact
		fact.theme_type_variation = &"Caption"
		fact.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		parent.add_child(fact)

	parent.add_child(_divider())
	parent.add_child(_section_label("Your history"))
	parent.add_child(_fact_row("Grown", "%d time%s" % [
		entry.times_grown, "" if entry.times_grown == 1 else "s"
	]))
	parent.add_child(_fact_row("First discovered", _format_date(entry.first_discovered_at_utc)))
	parent.add_child(_fact_row(
		"Fastest growth",
		TimeUtil.format_duration(entry.fastest_growth_minutes)
		if entry.fastest_growth_minutes >= 0.0 else "Not yet matured"
	))
	parent.add_child(
		_fact_row("Total focus", TimeUtil.format_duration(entry.total_focus_minutes))
	)

	var favourite := Button.new()
	favourite.text = "★  Favourited" if entry.favorite else "☆  Add to favourites"
	favourite.theme_type_variation = &"SubtleButton"
	favourite.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	favourite.pressed.connect(func() -> void:
		entry.favorite = not entry.favorite
		favourite.text = "★  Favourited" if entry.favorite else "☆  Add to favourites"
		AppState.save_now())
	parent.add_child(favourite)


static func _fact_row(label: String, value: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DesignTokens.SPACE_SM)

	var name_label := Label.new()
	name_label.text = label
	name_label.theme_type_variation = &"Caption"
	name_label.custom_minimum_size.x = 130
	row.add_child(name_label)

	var value_label := Label.new()
	value_label.text = value if not value.is_empty() else "—"
	value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(value_label)
	return row


static func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"Heading"
	return label


static func _divider() -> Control:
	var line := ColorRect.new()
	line.color = DesignTokens.BORDER_SOFT
	line.custom_minimum_size.y = 1
	return line


static func _format_date(unix_time: float) -> String:
	if unix_time <= 0.0:
		return "—"
	var parts := Time.get_datetime_dict_from_unix_time(
		int(unix_time) + TimeUtil.local_offset_seconds()
	)
	const MONTHS := [
		"January", "February", "March", "April", "May", "June",
		"July", "August", "September", "October", "November", "December",
	]
	return "%d %s %d" % [
		DictUtil.get_int(parts, "day"),
		MONTHS[clampi(DictUtil.get_int(parts, "month", 1) - 1, 0, 11)],
		DictUtil.get_int(parts, "year"),
	]


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_back"):
		queue_free()
		get_viewport().set_input_as_handled()
