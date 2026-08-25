class_name StatisticsScreen
extends AppScreen
## Focus statistics (§29) and the yearly heatmap (§30).
##
## Every figure is derived from the stored session records rather than from a
## running total, which is what makes §64's "totals match underlying session
## records" checkable rather than assumed — the totals ARE the records, summed.
##
## §29 asks for charts used sparingly and clearly. There is one bar breakdown and
## one heatmap; the rest is plain numbers, because a number is the clearest chart
## of a single value.

var _tiles: HBoxContainer
var _period_tiles: HBoxContainer
var _project_rows: VBoxContainer
var _heatmap: FocusHeatmap
var _day_detail: VBoxContainer


func build_content() -> void:
	content.add_child(
		SectionHeader.create("Statistics", "Where your hours actually went.")
	)

	if AppState.sessions.is_empty():
		content.add_child(
			EmptyState.create(
				"📊", "Nothing to chart yet",
				"Finish a focus session and your first figures will appear here.", ""
			)
		)
		return

	_build_period_row()
	_build_headline_row()
	_build_projects()
	_build_heatmap()

	EventBus.focus_time_recorded.connect(_on_changed)
	EventBus.save_loaded.connect(_refresh)
	_refresh()


func on_shown() -> void:
	_refresh()


func _build_period_row() -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = &"Card"
	content.add_child(card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", DesignTokens.SPACE_SM)
	card.add_child(column)

	var heading := Label.new()
	heading.text = "Focus time"
	heading.theme_type_variation = &"Heading"
	column.add_child(heading)

	_period_tiles = HBoxContainer.new()
	_period_tiles.add_theme_constant_override("separation", DesignTokens.SPACE_MD)
	column.add_child(_period_tiles)


func _build_headline_row() -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = &"Card"
	content.add_child(card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", DesignTokens.SPACE_SM)
	card.add_child(column)

	var heading := Label.new()
	heading.text = "Sessions and streaks"
	heading.theme_type_variation = &"Heading"
	column.add_child(heading)

	_tiles = HBoxContainer.new()
	_tiles.add_theme_constant_override("separation", DesignTokens.SPACE_MD)
	column.add_child(_tiles)


func _build_projects() -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = &"Card"
	content.add_child(card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", DesignTokens.SPACE_SM)
	card.add_child(column)

	var heading := Label.new()
	heading.text = "By project"
	heading.theme_type_variation = &"Heading"
	column.add_child(heading)

	_project_rows = VBoxContainer.new()
	_project_rows.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	column.add_child(_project_rows)


func _build_heatmap() -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = &"Card"
	content.add_child(card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", DesignTokens.SPACE_SM)
	card.add_child(column)

	var heading := Label.new()
	heading.text = "The past year"
	heading.theme_type_variation = &"Heading"
	column.add_child(heading)

	var hint := Label.new()
	hint.text = "Each square is a day. Click one to see what you did."
	hint.theme_type_variation = &"Caption"
	column.add_child(hint)

	_heatmap = FocusHeatmap.new()
	_heatmap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_heatmap.day_pressed.connect(_on_day_pressed)
	column.add_child(_heatmap)

	_day_detail = VBoxContainer.new()
	_day_detail.add_theme_constant_override("separation", DesignTokens.SPACE_XXS)
	column.add_child(_day_detail)


func _refresh() -> void:
	if _tiles == null:
		return
	var summary := StatisticsManager.get_summary()

	_fill(_period_tiles, [
		StatTile.create("Today", TimeUtil.format_duration(summary.focus_today), Palette.moss()),
		StatTile.create("This week", TimeUtil.format_duration(summary.focus_week), Palette.moss()),
		StatTile.create("This month", TimeUtil.format_duration(summary.focus_month), Palette.sky()),
		StatTile.create("This year", TimeUtil.format_duration(summary.focus_year), Palette.sky()),
		StatTile.create("Lifetime", TimeUtil.format_duration(summary.focus_lifetime), Palette.terracotta()),
	])

	_fill(_tiles, [
		StatTile.create("Sessions", str(summary.session_count), Palette.moss()),
		StatTile.create("Average", TimeUtil.format_duration(summary.average_session_minutes), Palette.moss()),
		StatTile.create("Longest", TimeUtil.format_duration(summary.longest_session_minutes), Palette.amber()),
		StatTile.create("Days focused", str(summary.days_focused), Palette.sky()),
		StatTile.create("Current streak", "%d day%s" % [
			summary.current_streak, "" if summary.current_streak == 1 else "s"
		], Palette.amber()),
		StatTile.create("Longest streak", "%d days" % summary.longest_streak, Palette.terracotta()),
	])

	_refresh_projects()
	_heatmap.totals = StatisticsManager.get_daily_totals()


func _fill(row: HBoxContainer, tiles: Array) -> void:
	for child in row.get_children():
		child.queue_free()
	for tile: Control in tiles:
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(tile)


## A horizontal bar per project, sized against the largest. §29 asks for charts
## used sparingly — this is the one place a comparison genuinely needs shape
## rather than digits.
func _refresh_projects() -> void:
	for child in _project_rows.get_children():
		child.queue_free()

	var totals := StatisticsManager.get_totals_by_project()
	if totals.is_empty():
		var empty := Label.new()
		empty.text = "No project time recorded yet."
		empty.theme_type_variation = &"Muted"
		_project_rows.add_child(empty)
		return

	var ordered: Array = totals.keys()
	ordered.sort_custom(
		func(a: String, b: String) -> bool: return float(totals[a]) > float(totals[b])
	)
	var largest := float(totals[ordered[0]])

	for project_id: String in ordered:
		var minutes := float(totals[project_id])
		var project := AppState.get_project(project_id)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", DesignTokens.SPACE_SM)
		_project_rows.add_child(row)

		var name_label := Label.new()
		name_label.text = AppState.get_project_name(project_id)
		name_label.custom_minimum_size.x = 150
		row.add_child(name_label)

		var track := PanelContainer.new()
		track.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		track.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var track_style := StyleBoxFlat.new()
		track_style.bg_color = Palette.track()
		track_style.set_corner_radius_all(DesignTokens.RADIUS_PILL)
		track.add_theme_stylebox_override("panel", track_style)
		track.custom_minimum_size.y = 16
		row.add_child(track)

		var fill := PanelContainer.new()
		var fill_style := StyleBoxFlat.new()
		fill_style.bg_color = (
			Palette.project_color(project.color_token) if project != null
			else Palette.ink_muted()
		)
		fill_style.set_corner_radius_all(DesignTokens.RADIUS_PILL)
		fill.add_theme_stylebox_override("panel", fill_style)
		# Ratio expressed as a size flag so the bar reflows with the window
		# instead of being pinned to a pixel width computed once.
		fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fill.size_flags_stretch_ratio = maxf(0.001, minutes / maxf(1.0, largest))
		track.add_child(fill)

		var gap := Control.new()
		gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		gap.size_flags_stretch_ratio = maxf(
			0.001, 1.0 - minutes / maxf(1.0, largest)
		)
		track.add_child(gap)

		var value := Label.new()
		value.text = TimeUtil.format_duration(minutes)
		value.theme_type_variation = &"Caption"
		value.custom_minimum_size.x = 90
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(value)


## §30: clicking a date shows total focus, sessions, categories and plants.
func _on_day_pressed(date_key: String) -> void:
	for child in _day_detail.get_children():
		child.queue_free()

	var day_sessions: Array[FocusSession] = []
	for session: FocusSession in AppState.sessions:
		if session.date_key == date_key and session.counts_toward_progress():
			day_sessions.append(session)

	var heading := Label.new()
	heading.theme_type_variation = &"Heading"
	heading.text = date_key
	_day_detail.add_child(heading)

	if day_sessions.is_empty():
		var none := Label.new()
		none.text = "No focus recorded on this day. That is allowed."
		none.theme_type_variation = &"Muted"
		_day_detail.add_child(none)
		return

	var total := 0.0
	var focus_count := 0
	var by_project := {}
	var plants := {}
	for session: FocusSession in day_sessions:
		if session.is_break():
			continue
		total += session.actual_focus_minutes
		focus_count += 1
		var project_name := AppState.get_project_name(session.project_id)
		by_project[project_name] = float(by_project.get(project_name, 0.0)) + session.actual_focus_minutes
		if not session.plant_uid.is_empty():
			var plant := AppState.get_plant(session.plant_uid)
			if plant != null:
				var species := ContentDB.get_species(plant.species_id)
				if species != null:
					plants[species.display_name] = true

	var summary := Label.new()
	summary.text = "%s across %d session%s" % [
		TimeUtil.format_duration(total), focus_count, "" if focus_count == 1 else "s"
	]
	_day_detail.add_child(summary)

	for project_name: String in by_project:
		var line := Label.new()
		line.text = "· %s — %s" % [
			project_name, TimeUtil.format_duration(float(by_project[project_name]))
		]
		line.theme_type_variation = &"Caption"
		_day_detail.add_child(line)

	if not plants.is_empty():
		var grown := Label.new()
		grown.text = "Growing: %s" % ", ".join(PackedStringArray(plants.keys()))
		grown.theme_type_variation = &"Caption"
		_day_detail.add_child(grown)


func _on_changed(_session_id: String, _minutes: float) -> void:
	_refresh()
