class_name JournalScreen
extends AppScreen
## The chronological record (§31).
##
## Entries are shown newest first and grouped by day, because the question this
## screen answers is "what has been happening lately", not "what happened in
## order from the beginning".
##
## Nothing here writes. §31's entries are append-only and are never rewritten,
## and each stores the wording composed when the event happened — so a later
## change to how we phrase things cannot retroactively alter the player's own
## history.

const PAGE_SIZE: int = 60

var _list: VBoxContainer
var _kind_filter: int = -1
var _shown: int = PAGE_SIZE


func build_content() -> void:
	content.add_child(
		SectionHeader.create("Journal", "A dated record of everything your garden has been through.")
	)

	_build_toolbar()

	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", DesignTokens.SPACE_SM)
	content.add_child(_list)

	EventBus.journal_entry_added.connect(_on_entry_added)
	EventBus.save_loaded.connect(_refresh)
	_refresh()


func on_shown() -> void:
	_refresh()


func _build_toolbar() -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardSunken"
	content.add_child(card)

	var row := ChoiceRow.new()
	row.add_choice("Everything", -1)
	row.add_choice("Planted", JournalEntry.Kind.SEED_PLANTED)
	row.add_choice("Matured", JournalEntry.Kind.PLANT_MATURED)
	row.add_choice("Achievements", JournalEntry.Kind.ACHIEVEMENT_UNLOCKED)
	row.add_choice("Milestones", JournalEntry.Kind.MILESTONE_REACHED)
	row.selected.connect(func(value: Variant) -> void:
		_kind_filter = int(value)
		_shown = PAGE_SIZE
		_refresh())
	row.select_value(-1)
	card.add_child(row)


func _refresh() -> void:
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()

	var entries := _filtered_entries()
	if entries.is_empty():
		_list.add_child(
			EmptyState.create(
				"📔", "Nothing written yet",
				"Plant something and finish a session — the first entry writes itself.", ""
			)
		)
		return

	# Grouped under day headings, so a busy day reads as one event rather than
	# five disconnected rows.
	var current_day := ""
	var rendered := 0
	for entry: JournalEntry in entries:
		if rendered >= _shown:
			break
		if entry.date_key != current_day:
			current_day = entry.date_key
			_list.add_child(_day_heading(current_day))
		_list.add_child(_entry_card(entry))
		rendered += 1

	# Paged rather than capped: a long history stays responsive without the
	# player losing access to any of it (§64).
	if entries.size() > _shown:
		var more := Button.new()
		more.text = "Show earlier entries (%d remaining)" % (entries.size() - _shown)
		more.theme_type_variation = &"SubtleButton"
		more.pressed.connect(func() -> void:
			_shown += PAGE_SIZE
			_refresh())
		_list.add_child(more)


func _filtered_entries() -> Array[JournalEntry]:
	var out: Array[JournalEntry] = []
	for entry: JournalEntry in AppState.data.journal:
		if _kind_filter >= 0 and int(entry.kind) != _kind_filter:
			continue
		out.append(entry)
	out.reverse()  # Newest first.
	return out


func _day_heading(date_key: String) -> Label:
	var label := Label.new()
	var today := TimeUtil.today_key()
	var gap := TimeUtil.days_between(date_key, today)
	# Relative wording for the recent past, absolute beyond that. "Yesterday"
	# is more meaningful than a date; "43 days ago" is not.
	if gap == 0:
		label.text = "Today"
	elif gap == 1:
		label.text = "Yesterday"
	else:
		label.text = date_key
	label.theme_type_variation = &"Heading"
	return label


func _entry_card(entry: JournalEntry) -> PanelContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = &"Card"

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DesignTokens.SPACE_MD)
	card.add_child(row)

	var glyph := Label.new()
	glyph.text = _glyph_for(entry.kind)
	glyph.add_theme_font_size_override("font_size", 26)
	glyph.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(glyph)

	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", DesignTokens.SPACE_XXS)
	row.add_child(column)

	var title := Label.new()
	title.text = entry.title
	title.theme_type_variation = &"Heading"
	column.add_child(title)

	if not entry.body.is_empty():
		var body := Label.new()
		body.text = entry.body
		body.theme_type_variation = &"Muted"
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(body)

	# Entries about a specific plant open that plant's record.
	var plant := AppState.get_plant(entry.subject_id) if not entry.subject_id.is_empty() else null
	if plant != null:
		var open := Button.new()
		open.text = "Open its record"
		open.theme_type_variation = &"SubtleButton"
		open.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		open.pressed.connect(func() -> void: PlantHistoryDialog.open(get_tree().root, plant))
		row.add_child(open)

	return card


static func _glyph_for(kind: JournalEntry.Kind) -> String:
	match kind:
		JournalEntry.Kind.SEED_PLANTED:
			return "🌱"
		JournalEntry.Kind.STAGE_REACHED:
			return "🌿"
		JournalEntry.Kind.PLANT_MATURED:
			return "🪴"
		JournalEntry.Kind.MUTATION_DISCOVERED:
			return "✨"
		JournalEntry.Kind.ACHIEVEMENT_UNLOCKED:
			return "🏅"
		JournalEntry.Kind.GARDEN_EXPANSION:
			return "🌳"
		JournalEntry.Kind.LEVEL_UP:
			return "⭐"
		JournalEntry.Kind.EXPEDITION_COMPLETED:
			return "🧭"
		_:
			return "📔"


func _on_entry_added(_entry_id: String) -> void:
	_refresh()
