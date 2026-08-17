class_name HomeScreen
extends AppScreen
## Home: the player's current state at a glance (§7).
##
## §7 requires this screen to visually prioritize Start Focus above everything
## else, and warns against information overload. So the hierarchy here is
## deliberate: greeting, then the primary action, then four figures, then the
## active plant. Anything else belongs on a dedicated screen.
##
## Every value shown is read from real state. On a new save they are genuinely
## zero rather than mocked, which is why this screen doubles as its own empty
## state (§54's "no plants currently selected" case).

var _today_tile: StatTile
var _streak_tile: StatTile
var _level_tile: StatTile
var _goal_tile: StatTile
var _xp_bar: ProgressBar
var _plant_slot: VBoxContainer


func build_content() -> void:
	_build_greeting()
	_build_primary_action()
	_build_stat_row()
	_build_level_strip()
	_build_active_plant()
	refresh()

	# Event-driven rather than polled: §44 asks us not to recompute analytics
	# every frame, and these are the only events that change what is displayed.
	EventBus.xp_changed.connect(_on_progress_changed)
	EventBus.streak_changed.connect(_on_streak_changed)
	EventBus.focus_time_recorded.connect(_on_focus_recorded)
	EventBus.save_loaded.connect(refresh)


func on_shown() -> void:
	refresh()


func refresh() -> void:
	var summary := StatisticsManager.get_summary()
	var settings := AppState.get_settings()

	_today_tile.set_value(TimeUtil.format_duration(summary.focus_today))
	_streak_tile.set_value(_format_streak(summary.current_streak))
	_level_tile.set_value("Level %d" % ProgressionManager.get_level())

	var goal := settings.daily_goal_minutes
	var goal_ratio := 0.0 if goal <= 0.0 else clampf(summary.focus_today / goal, 0.0, 1.0)
	_goal_tile.set_value("%d%%" % int(round(goal_ratio * 100.0)))
	_goal_tile.set_caption("Daily goal — %s" % TimeUtil.format_duration(goal))

	var progress := ProgressionManager.get_level_progress()
	_xp_bar.max_value = maxi(1, progress[1])
	_xp_bar.value = progress[0]
	# At max level the span is 0; show a full bar rather than an empty one.
	if progress[1] <= 0:
		_xp_bar.max_value = 1
		_xp_bar.value = 1

	_rebuild_plant_slot()


func _build_greeting() -> void:
	var hour := TimeUtil.local_hour(Time.get_unix_time_from_system())
	var greeting := "Good evening"
	if hour < 12:
		greeting = "Good morning"
	elif hour < 18:
		greeting = "Good afternoon"

	content.add_child(
		SectionHeader.create(
			"%s, %s" % [greeting, AppState.data.profile.display_name],
			"Every plant here grew out of time you spent focusing."
		)
	)


func _build_primary_action() -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = &"Card"
	content.add_child(card)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DesignTokens.SPACE_LG)
	card.add_child(row)

	var copy := VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", DesignTokens.SPACE_XXS)
	row.add_child(copy)

	var heading := Label.new()
	heading.text = "Ready to focus?"
	heading.theme_type_variation = &"Heading"
	copy.add_child(heading)

	var detail := Label.new()
	detail.text = "Pick what you are working on, choose a plant, and begin."
	detail.theme_type_variation = &"Muted"
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	copy.add_child(detail)

	var start_button := Button.new()
	start_button.text = "Start Focus"
	start_button.theme_type_variation = &"PrimaryButton"
	start_button.custom_minimum_size = Vector2(200, 56)
	start_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Disabled with an explanation rather than hidden: §74 requires disabled
	# states to be clear, and hiding the app's primary action would make Home
	# look broken rather than unfinished.
	start_button.disabled = true
	start_button.tooltip_text = "The focus timer arrives in Milestone 1."
	start_button.pressed.connect(func() -> void: EventBus.navigation_requested.emit("focus"))
	row.add_child(start_button)


func _build_stat_row() -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DesignTokens.SPACE_MD)
	content.add_child(row)

	_today_tile = StatTile.create("Focused today", "0m", DesignTokens.MOSS)
	_streak_tile = StatTile.create("Current streak", "No streak yet", DesignTokens.AMBER)
	_level_tile = StatTile.create("Gardener level", "Level 1", DesignTokens.TERRACOTTA)
	_goal_tile = StatTile.create("Daily goal", "0%", DesignTokens.SKY)
	row.add_child(_today_tile)
	row.add_child(_streak_tile)
	row.add_child(_level_tile)
	row.add_child(_goal_tile)


func _build_level_strip() -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardSunken"
	content.add_child(card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	card.add_child(column)

	var label := Label.new()
	label.text = "Experience"
	label.theme_type_variation = &"Caption"
	column.add_child(label)

	_xp_bar = ProgressBar.new()
	_xp_bar.custom_minimum_size.y = 14
	_xp_bar.show_percentage = false
	column.add_child(_xp_bar)


func _build_active_plant() -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = &"Card"
	content.add_child(card)

	_plant_slot = VBoxContainer.new()
	_plant_slot.add_theme_constant_override("separation", DesignTokens.SPACE_SM)
	card.add_child(_plant_slot)


func _rebuild_plant_slot() -> void:
	for child in _plant_slot.get_children():
		child.queue_free()

	var plant := AppState.get_active_plant()
	if plant == null:
		# §54 lists "no plants currently selected" as a case that must be defined.
		_plant_slot.add_child(
			EmptyState.create(
				"🌱",
				"No plant chosen yet",
				"When you pick a plant, its progress will live here and grow with every session you finish.",
				"Choosing and growing plants arrives in Milestones 2 and 3."
			)
		)
		return

	var species := ContentDB.get_species(plant.species_id)
	var title := Label.new()
	# A species can be missing if content was removed in an update (§54). The
	# plant is still the player's, so it is shown with an honest label rather
	# than vanishing from their garden.
	title.text = species.display_name if species != null else "Unknown plant"
	title.theme_type_variation = &"Heading"
	_plant_slot.add_child(title)

	var detail := Label.new()
	detail.text = "%s of focus grown in" % TimeUtil.format_duration(plant.accumulated_focus_minutes)
	detail.theme_type_variation = &"Muted"
	_plant_slot.add_child(detail)


static func _format_streak(days: int) -> String:
	if days <= 0:
		return "No streak yet"
	return "%d day%s" % [days, "" if days == 1 else "s"]


func _on_progress_changed(_total_xp: int) -> void:
	refresh()


func _on_streak_changed(_streak: int) -> void:
	refresh()


func _on_focus_recorded(_session_id: String, _minutes: float) -> void:
	refresh()
