class_name AchievementsScreen
extends AppScreen
## Achievements (§26).
##
## Progress is read from the cached ratio on each AchievementState rather than
## re-evaluated on open (§44): thirty requirements against a full session history
## is real work, and it has already been done at the moment it could have changed.
##
## §26 requires hidden achievements. A concealed entry shows as "???" with its
## category still visible, so the player knows a category holds more without
## being told what.

const COLUMNS: int = 3

var _grid: GridContainer
var _summary: Label
var _category_filter: int = -1
var _hide_unlocked: bool = false


func build_content() -> void:
	content.add_child(
		SectionHeader.create("Achievements", "Milestones worth marking, earned by focusing.")
	)

	_summary = Label.new()
	_summary.theme_type_variation = &"Muted"
	content.add_child(_summary)

	_build_toolbar()

	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", DesignTokens.SPACE_MD)
	_grid.add_theme_constant_override("v_separation", DesignTokens.SPACE_MD)
	content.add_child(_grid)

	EventBus.achievement_unlocked.connect(_on_unlocked)
	EventBus.save_loaded.connect(_refresh)
	_refresh()


func on_shown() -> void:
	_refresh()


func _build_toolbar() -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardSunken"
	content.add_child(card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DesignTokens.SPACE_SM)
	card.add_child(row)

	var categories := ChoiceRow.new()
	categories.add_choice("All", -1)
	for i in AchievementDef.CATEGORY_NAMES.size():
		categories.add_choice(AchievementDef.CATEGORY_NAMES[i], i)
	categories.selected.connect(func(value: Variant) -> void:
		_category_filter = int(value)
		_refresh())
	categories.select_value(-1)
	row.add_child(categories)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var hide := Button.new()
	hide.text = "Hide earned"
	hide.theme_type_variation = &"Chip"
	hide.toggle_mode = true
	hide.toggled.connect(func(on: bool) -> void:
		_hide_unlocked = on
		_refresh())
	row.add_child(hide)


func _refresh() -> void:
	if _grid == null:
		return
	for child in _grid.get_children():
		child.queue_free()

	var all := ContentDB.get_all_achievements()
	var unlocked := AchievementManager.get_unlocked_count()
	_summary.text = "%d of %d earned · %d%% complete" % [
		unlocked, all.size(),
		int(round(float(unlocked) / maxf(1.0, float(all.size())) * 100.0)),
	]

	for definition: AchievementDef in all:
		if _category_filter >= 0 and int(definition.category) != _category_filter:
			continue
		var is_unlocked := AchievementManager.is_unlocked(definition.id)
		if _hide_unlocked and is_unlocked:
			continue
		_grid.add_child(_build_card(definition, is_unlocked))


func _build_card(definition: AchievementDef, is_unlocked: bool) -> PanelContainer:
	var concealed := AchievementManager.should_conceal(definition)

	var card := PanelContainer.new()
	card.theme_type_variation = &"Card"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DesignTokens.SPACE_MD)
	card.add_child(row)

	# The medal states earned, locked or hidden on its own, before any colour is
	# interpreted (§50).
	var glyph := Label.new()
	glyph.text = "🏅" if is_unlocked else ("❓" if concealed else "🔒")
	glyph.add_theme_font_size_override("font_size", 34)
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(glyph)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", DesignTokens.SPACE_XXS)
	row.add_child(column)

	var title := Label.new()
	title.text = "???" if concealed else definition.title
	title.theme_type_variation = &"Heading"
	column.add_child(title)

	var description := Label.new()
	description.text = (
		"A hidden achievement. You will know it when you earn it."
		if concealed else definition.description
	)
	description.theme_type_variation = &"Caption"
	description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(description)

	if is_unlocked:
		var state := AppState.get_achievement_state(definition.id)
		var earned := Label.new()
		earned.text = "Earned %s" % PlantDetailDialog._format_date(
			state.unlocked_at_utc if state != null else 0.0
		)
		earned.theme_type_variation = &"Caption"
		earned.add_theme_color_override("font_color", Palette.moss())
		column.add_child(earned)
	elif definition.track_progress and not concealed:
		# §26 asks for progress tracking. Showing how close you are is the
		# difference between a locked door and something visibly within reach.
		var ratio := AchievementManager.get_progress(definition.id)
		var bar := ProgressBar.new()
		bar.min_value = 0.0
		bar.max_value = 1.0
		bar.value = ratio
		bar.show_percentage = false
		bar.custom_minimum_size.y = 8
		column.add_child(bar)

		var progress_label := Label.new()
		progress_label.text = "%d%% there" % int(ratio * 100.0)
		progress_label.theme_type_variation = &"Caption"
		column.add_child(progress_label)

	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	meta.add_child(PlantCard._rarity_badge(definition.rarity))
	var category := Label.new()
	category.text = definition.get_category_name()
	category.theme_type_variation = &"Caption"
	category.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	meta.add_child(category)
	column.add_child(meta)

	# Unearned cards recede rather than disappear, so the screen reads as a
	# collection with room left in it (§74).
	if not is_unlocked:
		card.modulate = Color(1.0, 1.0, 1.0, 0.72)
	return card


func _on_unlocked(_achievement_id: String) -> void:
	_refresh()
