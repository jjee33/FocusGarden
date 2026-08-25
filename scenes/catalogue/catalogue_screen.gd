class_name CatalogueScreen
extends AppScreen
## The species collection (§16).
##
## Filtering, sorting and search all operate on a VIEW of the content, never on
## the content itself — §61's acceptance criterion is that filters do not alter
## stored data, and the surest way to guarantee that is for this screen to have
## no way to write. It reads ContentDB and the player's catalogue entries and
## renders them; the only mutation reachable from here is the favourite toggle in
## the detail dialog.

const COLUMNS: int = 5

enum Sort { DEFAULT, NAME, RARITY, MOST_GROWN }

var _search: LineEdit
var _grid: GridContainer
var _completion_label: Label
var _empty_holder: Control

var _rarity_filter: int = -1      ## -1 = any
var _biome_filter: StringName = &""
var _sort: Sort = Sort.DEFAULT
var _favourites_only: bool = false
var _query: String = ""


func build_content() -> void:
	content.add_child(
		SectionHeader.create(
			"Catalogue", "Every species you have grown, and the ones still to find."
		)
	)
	_build_toolbar()

	_completion_label = Label.new()
	_completion_label.theme_type_variation = &"Muted"
	content.add_child(_completion_label)

	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", DesignTokens.SPACE_MD)
	_grid.add_theme_constant_override("v_separation", DesignTokens.SPACE_MD)
	content.add_child(_grid)

	_empty_holder = VBoxContainer.new()
	content.add_child(_empty_holder)

	EventBus.catalogue_entry_discovered.connect(_on_discovered)
	EventBus.save_loaded.connect(_refresh)
	_refresh()


func on_shown() -> void:
	_refresh()


func _build_toolbar() -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardSunken"
	content.add_child(card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", DesignTokens.SPACE_SM)
	card.add_child(column)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", DesignTokens.SPACE_SM)
	column.add_child(top)

	_search = LineEdit.new()
	_search.placeholder_text = "Search by name, family or tag…"
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(text: String) -> void:
		_query = text.strip_edges().to_lower()
		_refresh())
	top.add_child(_search)

	var favourites := Button.new()
	favourites.text = "★  Favourites"
	favourites.theme_type_variation = &"Chip"
	favourites.toggle_mode = true
	favourites.toggled.connect(func(on: bool) -> void:
		_favourites_only = on
		_refresh())
	top.add_child(favourites)

	column.add_child(_filter_row("Rarity", _build_rarity_choices()))
	column.add_child(_filter_row("Biome", _build_biome_choices()))
	column.add_child(_filter_row("Sort", _build_sort_choices()))


func _filter_row(label: String, row: ChoiceRow) -> HBoxContainer:
	var holder := HBoxContainer.new()
	holder.add_theme_constant_override("separation", DesignTokens.SPACE_SM)

	var caption := Label.new()
	caption.text = label
	caption.theme_type_variation = &"Caption"
	caption.custom_minimum_size.x = 56
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	holder.add_child(caption)
	holder.add_child(row)
	return holder


func _build_rarity_choices() -> ChoiceRow:
	var row := ChoiceRow.new()
	row.add_choice("Any", -1)
	for i in PlantSpecies.RARITY_NAMES.size():
		row.add_choice(PlantSpecies.RARITY_NAMES[i], i)
	row.selected.connect(func(value: Variant) -> void:
		_rarity_filter = int(value)
		_refresh())
	row.select_value(-1)
	return row


func _build_biome_choices() -> ChoiceRow:
	var row := ChoiceRow.new()
	row.add_choice("Any", "")
	# Built from the content actually present, so a new biome needs no code change.
	var seen := {}
	for species: PlantSpecies in ContentDB.get_all_species():
		var biome := String(species.biome_id)
		if seen.has(biome):
			continue
		seen[biome] = true
		row.add_choice(biome.capitalize(), biome)
	row.selected.connect(func(value: Variant) -> void:
		_biome_filter = StringName(String(value))
		_refresh())
	row.select_value("")
	return row


func _build_sort_choices() -> ChoiceRow:
	var row := ChoiceRow.new()
	row.add_choice("Catalogue", Sort.DEFAULT)
	row.add_choice("Name", Sort.NAME)
	row.add_choice("Rarity", Sort.RARITY)
	row.add_choice("Most grown", Sort.MOST_GROWN)
	row.selected.connect(func(value: Variant) -> void:
		_sort = value as Sort
		_refresh())
	row.select_value(Sort.DEFAULT)
	return row


func _refresh() -> void:
	if _grid == null:
		return
	for child in _grid.get_children():
		child.queue_free()
	for child in _empty_holder.get_children():
		child.queue_free()

	var all_species := ContentDB.get_all_species()
	var discovered_count := 0
	for species: PlantSpecies in all_species:
		var entry := AppState.get_catalogue_entry(species.id)
		if entry != null and entry.discovered:
			discovered_count += 1

	_completion_label.text = "%d of %d discovered · %d%% complete" % [
		discovered_count, all_species.size(),
		int(round(float(discovered_count) / maxf(1.0, float(all_species.size())) * 100.0)),
	]

	var shown := _apply_filters(all_species)
	if shown.is_empty():
		_empty_holder.add_child(
			EmptyState.create(
				"🔍", "Nothing matches",
				"No species fit those filters. Try widening the search.", ""
			)
		)
		return

	for species: PlantSpecies in shown:
		var entry := AppState.get_catalogue_entry(species.id)
		var discovered := entry != null and entry.discovered
		# The cost is shown for every species, discovered or not. It is derived
		# from rarity, which the silhouette card already states, so it gives
		# nothing away about a plant that has not been grown yet — and knowing
		# what a legendary asks of you is most of the reason to want one.
		var subtitle := "%s to grow" % TimeUtil.format_duration(species.get_maturity_minutes())
		if discovered and entry.times_grown > 0:
			subtitle += " · grown %d×" % entry.times_grown
		var card := PlantCard.for_species(species, discovered, subtitle)
		var chosen := species
		card.pressed.connect(func() -> void: PlantDetailDialog.open(get_tree().root, chosen))
		_grid.add_child(card)


## Produces the filtered, sorted view. Returns a new array; ContentDB's own
## ordering and the player's entries are never modified.
func _apply_filters(source: Array[PlantSpecies]) -> Array[PlantSpecies]:
	var out: Array[PlantSpecies] = []

	for species: PlantSpecies in source:
		var entry := AppState.get_catalogue_entry(species.id)
		var discovered := entry != null and entry.discovered

		if _rarity_filter >= 0 and int(species.rarity) != _rarity_filter:
			continue
		if _biome_filter != &"" and species.biome_id != _biome_filter:
			continue
		if _favourites_only and (entry == null or not entry.favorite):
			continue
		if not _query.is_empty() and not _matches_query(species, discovered):
			continue
		out.append(species)

	match _sort:
		Sort.NAME:
			out.sort_custom(
				func(a: PlantSpecies, b: PlantSpecies) -> bool:
					return a.display_name.naturalcasecmp_to(b.display_name) < 0
			)
		Sort.RARITY:
			out.sort_custom(
				func(a: PlantSpecies, b: PlantSpecies) -> bool: return int(a.rarity) > int(b.rarity)
			)
		Sort.MOST_GROWN:
			out.sort_custom(
				func(a: PlantSpecies, b: PlantSpecies) -> bool:
					return _times_grown(a) > _times_grown(b)
			)
		_:
			pass
	return out


## Searching an undiscovered species matches only on rarity and biome. Its name
## and family are exactly what the player has not earned yet (§16), and letting
## the search field surface them would quietly undo the silhouette.
func _matches_query(species: PlantSpecies, discovered: bool) -> bool:
	if not discovered:
		return (
			species.get_rarity_name().to_lower().contains(_query)
			or String(species.biome_id).to_lower().contains(_query)
		)

	if species.display_name.to_lower().contains(_query):
		return true
	if species.scientific_name.to_lower().contains(_query):
		return true
	if String(species.biome_id).to_lower().contains(_query):
		return true
	if species.botanical != null and species.botanical.family.to_lower().contains(_query):
		return true
	for tag: StringName in species.tags:
		if String(tag).to_lower().contains(_query):
			return true
	return false


func _times_grown(species: PlantSpecies) -> int:
	var entry := AppState.get_catalogue_entry(species.id)
	return entry.times_grown if entry != null else 0


func _on_discovered(_species_id: String) -> void:
	_refresh()
