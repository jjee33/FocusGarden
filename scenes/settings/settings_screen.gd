class_name SettingsScreen
extends AppScreen
## Settings (§35).
##
## MILESTONE STATUS: the Timer, Notifications, Gameplay and Projects sections are
## complete and persist. Appearance, Audio and Data are Milestone 8 and are shown
## as a clearly-labelled placeholder rather than as dead controls — §72 forbids
## presenting a switch that does nothing as a finished feature.
##
## Every change writes through immediately. A settings screen with a Save button
## is a screen that loses your changes when you navigate away.

func build_content() -> void:
	content.add_child(
		SectionHeader.create("Settings", "Changes are saved as you make them.")
	)
	_build_timer_section()
	_build_projects_section()
	_build_notifications_section()
	_build_gameplay_section()
	_build_pending_section()


func _build_timer_section() -> void:
	var settings := AppState.get_settings()
	var column := _section("Timer")

	column.add_child(SettingRow.stepper(
		"Focus length", "Default length of a focus session.",
		settings.focus_duration_minutes, 1.0, 480.0, 5.0,
		func(value: float) -> void: _apply(func() -> void:
			AppState.get_settings().focus_duration_minutes = value),
		func(value: float) -> String: return TimeUtil.format_duration(value)
	))

	column.add_child(SettingRow.stepper(
		"Short break", "Between focus sessions.",
		settings.short_break_minutes, 1.0, 120.0, 1.0,
		func(value: float) -> void: _apply(func() -> void:
			AppState.get_settings().short_break_minutes = value),
		func(value: float) -> String: return TimeUtil.format_duration(value)
	))

	column.add_child(SettingRow.stepper(
		"Long break", "After a full cycle of focus sessions.",
		settings.long_break_minutes, 1.0, 120.0, 5.0,
		func(value: float) -> void: _apply(func() -> void:
			AppState.get_settings().long_break_minutes = value),
		func(value: float) -> String: return TimeUtil.format_duration(value)
	))

	column.add_child(SettingRow.stepper(
		"Sessions per cycle", "Focus sessions before a long break is offered.",
		float(settings.sessions_before_long_break), 1.0, 12.0, 1.0,
		func(value: float) -> void: _apply(func() -> void:
			AppState.get_settings().sessions_before_long_break = int(value))
	))

	column.add_child(SettingRow.toggle(
		"Start breaks automatically", "Begin a break shortly after focus ends.",
		settings.auto_start_breaks,
		func(value: bool) -> void: _apply(func() -> void:
			AppState.get_settings().auto_start_breaks = value)
	))

	column.add_child(SettingRow.toggle(
		"Start focus automatically", "Begin the next session shortly after a break ends.",
		settings.auto_start_focus,
		func(value: bool) -> void: _apply(func() -> void:
			AppState.get_settings().auto_start_focus = value)
	))

	column.add_child(SettingRow.stepper(
		"Minimum for credit", "Sessions shorter than this grow nothing. Time is still recorded.",
		settings.minimum_credit_minutes, 0.0, 60.0, 1.0,
		func(value: float) -> void: _apply(func() -> void:
			AppState.get_settings().minimum_credit_minutes = value),
		func(value: float) -> String:
			return "Off" if value <= 0.0 else TimeUtil.format_duration(value)
	))


func _build_projects_section() -> void:
	var column := _section("Projects")

	var projects := AppState.get_active_projects()
	if projects.is_empty():
		var empty := Label.new()
		empty.text = "No projects yet."
		empty.theme_type_variation = &"Muted"
		column.add_child(empty)

	for project: ProjectCategory in projects:
		column.add_child(_build_project_row(project))

	var add := Button.new()
	add.text = "+  New project"
	add.theme_type_variation = &"SubtleButton"
	add.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add.pressed.connect(func() -> void:
		var dialog := NewProjectDialog.open(get_tree().root)
		dialog.created.connect(func(name: String, color: String) -> void:
			AppState.add_project(name, color)
			_rebuild()))
	column.add_child(add)


func _build_project_row(project: ProjectCategory) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", DesignTokens.SPACE_SM)

	# A small colour swatch beside the name — decoration, since the name is
	# already the identifier (§50).
	var swatch := ColorRect.new()
	swatch.color = DesignTokens.project_color(project.color_token)
	swatch.custom_minimum_size = Vector2(12, 12)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(swatch)

	var name_label := Label.new()
	name_label.text = project.display_name
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var total := Label.new()
	total.text = TimeUtil.format_duration(_project_minutes(project.id))
	total.theme_type_variation = &"Caption"
	total.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(total)

	var archive := Button.new()
	archive.text = "Archive"
	archive.theme_type_variation = &"SubtleButton"
	# Archive, never delete: every session ever recorded references this id, and
	# removing it would orphan that history.
	archive.tooltip_text = "Hide from the picker. Past sessions keep their history."
	archive.pressed.connect(func() -> void:
		var dialog := ConfirmDialog.open(
			get_tree().root,
			"Archive %s?" % project.display_name,
			"It will no longer appear when starting a session. Sessions already recorded against it are kept.",
			"Archive",
			false,
			"Cancel"
		)
		dialog.confirmed.connect(func() -> void:
			AppState.archive_project(project.id)
			_rebuild()))
	row.add_child(archive)

	return row


func _build_notifications_section() -> void:
	var settings := AppState.get_settings()
	var column := _section("Notifications")

	column.add_child(SettingRow.toggle(
		"Focus session complete", "Show a message when a session finishes.",
		settings.notify_focus_complete,
		func(value: bool) -> void: _apply(func() -> void:
			AppState.get_settings().notify_focus_complete = value)
	))

	column.add_child(SettingRow.toggle(
		"Break complete", "Show a message when a break finishes.",
		settings.notify_break_complete,
		func(value: bool) -> void: _apply(func() -> void:
			AppState.get_settings().notify_break_complete = value)
	))

	var note := Label.new()
	note.text = (
		"Messages appear inside Focus Garden and flash the taskbar icon. Godot has no "
		+ "cross-platform desktop notification support, so system notifications are not available yet."
	)
	note.theme_type_variation = &"Caption"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)


func _build_gameplay_section() -> void:
	var settings := AppState.get_settings()
	var column := _section("Gameplay")

	column.add_child(SettingRow.stepper(
		"Daily goal", "How much focus you are aiming for each day.",
		settings.daily_goal_minutes, 5.0, 960.0, 5.0,
		func(value: float) -> void: _apply(func() -> void:
			AppState.get_settings().daily_goal_minutes = value),
		func(value: float) -> String: return TimeUtil.format_duration(value)
	))

	column.add_child(SettingRow.stepper(
		"Streak threshold", "Focus needed for a day to count toward your streak.",
		settings.streak_threshold_minutes, 1.0, 480.0, 5.0,
		func(value: float) -> void: _apply(func() -> void:
			AppState.get_settings().streak_threshold_minutes = value),
		func(value: float) -> String: return TimeUtil.format_duration(value)
	))

	column.add_child(SettingRow.toggle(
		"Confirm before discarding", "Ask before throwing away a session in progress.",
		settings.confirm_before_cancel_session,
		func(value: bool) -> void: _apply(func() -> void:
			AppState.get_settings().confirm_before_cancel_session = value)
	))


func _build_pending_section() -> void:
	_build_appearance_section()
	_build_audio_section()
	_build_data_section()


func _build_appearance_section() -> void:
	var settings := AppState.get_settings()
	var column := _section("Appearance")

	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", DesignTokens.SPACE_MD)
	column.add_child(modes)

	var mode_label := VBoxContainer.new()
	mode_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var mode_name := Label.new()
	mode_name.text = "Window"
	mode_label.add_child(mode_name)
	var mode_hint := Label.new()
	mode_hint.text = "Borderless fills the screen without changing resolution."
	mode_hint.theme_type_variation = &"Caption"
	mode_label.add_child(mode_hint)
	modes.add_child(mode_label)

	var mode_choices := ChoiceRow.new()
	mode_choices.add_choice("Windowed", "windowed")
	mode_choices.add_choice("Fullscreen", "fullscreen")
	mode_choices.add_choice("Borderless", "borderless")
	mode_choices.selected.connect(func(value: Variant) -> void:
		_apply(func() -> void: AppState.get_settings().window_mode = String(value))
		WindowMode.apply(String(value)))
	mode_choices.select_value(settings.window_mode)
	modes.add_child(mode_choices)

	column.add_child(SettingRow.stepper(
		"Interface scale", "Makes everything larger or smaller.",
		settings.ui_scale, 0.75, 2.0, 0.05,
		func(value: float) -> void:
			_apply(func() -> void: AppState.get_settings().ui_scale = value)
			UiScale.apply(value),
		func(value: float) -> String: return "%d%%" % int(round(value * 100.0))
	))

	column.add_child(SettingRow.toggle(
		"Reduced motion", "Stops plants swaying and screens fading.",
		settings.reduced_motion,
		func(value: bool) -> void:
			_apply(func() -> void: AppState.get_settings().reduced_motion = value)
			EventBus.reduced_motion_changed.emit(value)
	))


func _build_audio_section() -> void:
	var settings := AppState.get_settings()
	var column := _section("Audio")

	if not AudioManager.is_audio_available():
		# §54 lists an unavailable audio device as a case to handle. Saying so
		# beats sliders that appear to work and change nothing.
		var note := Label.new()
		note.text = "No audio device is available, so these have no effect right now."
		note.theme_type_variation = &"Muted"
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(note)

	var volumes: Array[Array] = [
		["Master", "volume_master", AudioManager.BUS_MASTER],
		["Music", "volume_music", AudioManager.BUS_MUSIC],
		["Ambient", "volume_ambient", AudioManager.BUS_AMBIENT],
		["Interface", "volume_ui", AudioManager.BUS_UI],
		["Timer", "volume_timer", AudioManager.BUS_TIMER],
	]
	for entry: Array in volumes:
		var label: String = entry[0]
		var key: String = entry[1]
		var bus: StringName = entry[2]
		column.add_child(SettingRow.stepper(
			label, "", settings.get(key), 0.0, 1.0, 0.05,
			func(value: float) -> void:
				_apply(func() -> void: AppState.get_settings().set(key, value))
				AudioManager.set_bus_volume(bus, value)
				# Play the click on change so the level is audible as it is set,
				# which is the only way to judge a volume slider.
				AudioManager.play(&"ui_click"),
			func(value: float) -> String: return "%d%%" % int(round(value * 100.0))
		))


func _build_data_section() -> void:
	var column := _section("Your data")

	var location := Label.new()
	location.text = "Saved in %s" % ProjectSettings.globalize_path(SaveManager.get_save_dir())
	location.theme_type_variation = &"Caption"
	location.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(location)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	column.add_child(buttons)

	var export_button := Button.new()
	export_button.text = "Export a copy"
	export_button.theme_type_variation = &"SubtleButton"
	export_button.pressed.connect(_on_export_pressed)
	buttons.add_child(export_button)

	var import_button := Button.new()
	import_button.text = "Import a save"
	import_button.theme_type_variation = &"SubtleButton"
	import_button.pressed.connect(_on_import_pressed)
	buttons.add_child(import_button)

	var reset := Button.new()
	reset.text = "Reset everything"
	reset.theme_type_variation = &"SubtleButton"
	reset.add_theme_color_override("font_color", DesignTokens.CLAY)
	reset.pressed.connect(_on_reset_pressed)
	buttons.add_child(reset)

	var warning := Label.new()
	warning.text = (
		"Resetting deletes every plant, session and achievement. There is no undo, "
		+ "so export a copy first if there is any doubt."
	)
	warning.theme_type_variation = &"Caption"
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(warning)


func _on_export_pressed() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.add_filter("*.json", "Focus Garden save")
	dialog.current_file = "focus-garden-%s.json" % TimeUtil.today_key()
	dialog.title = "Export your garden"
	dialog.file_selected.connect(func(path: String) -> void:
		if SaveManager.export_save(path, AppState.data):
			EventBus.toast_requested.emit("Exported", path.get_file(), "💾")
		else:
			_show_error("Export failed", SaveManager.last_error_detail))
	get_tree().root.add_child(dialog)
	dialog.popup_centered_ratio(0.6)


func _on_import_pressed() -> void:
	var dialog := FileDialog.new()
	dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.add_filter("*.json", "Focus Garden save")
	dialog.title = "Import a garden"
	dialog.file_selected.connect(_on_import_selected)
	get_tree().root.add_child(dialog)
	dialog.popup_centered_ratio(0.6)


func _on_import_selected(path: String) -> void:
	# Validated BEFORE anything is replaced, so a bad file cannot destroy the
	# live save (§36). The confirmation states what is about to be lost.
	var imported := SaveManager.import_save(path)
	if imported == null:
		_show_error("Could not import that file", SaveManager.last_error_detail)
		return

	var dialog := ConfirmDialog.open(
		get_tree().root,
		"Replace your garden?",
		(
			"That file holds %d plants and %s of focus. Importing it replaces everything "
			+ "currently in Focus Garden."
		) % [imported.plants.size(), TimeUtil.format_duration(_imported_focus(imported))],
		"Replace",
		true,
		"Keep mine"
	)
	dialog.confirmed.connect(func() -> void:
		AppState.data = imported
		AppState.save_now()
		AppState.load_game()
		_rebuild()
		EventBus.toast_requested.emit("Imported", "Your garden has been replaced.", "💾"))


func _imported_focus(save: SaveData) -> float:
	var total := 0.0
	for plant: PlantInstance in save.plants:
		total += plant.accumulated_focus_minutes
	return total


## §35 requires strong confirmation before deleting progress. Two steps, and the
## second states the exact figures about to be destroyed.
func _on_reset_pressed() -> void:
	var summary := StatisticsManager.get_summary()
	var dialog := ConfirmDialog.open(
		get_tree().root,
		"Reset everything?",
		(
			"This deletes %s of recorded focus, %d plants and %d achievements, permanently. "
			+ "Export a copy first if you are not certain."
		) % [
			TimeUtil.format_duration(summary.focus_lifetime),
			AppState.data.plants.size(),
			AchievementManager.get_unlocked_count(),
		],
		"Continue",
		true,
		"Cancel"
	)
	dialog.confirmed.connect(func() -> void:
		var second := ConfirmDialog.open(
			get_tree().root,
			"Last check",
			"There is no undo. Delete everything and start a new garden?",
			"Delete everything",
			true,
			"Cancel"
		)
		second.confirmed.connect(_perform_reset))


func _perform_reset() -> void:
	AppState.reset_to_new_game()
	_rebuild()
	EventBus.navigation_requested.emit("home")


func _show_error(title: String, detail: String) -> void:
	ConfirmDialog.open(
		get_tree().root, title,
		detail if not detail.is_empty() else "No further detail is available.",
		"OK", false, "Close"
	)


func _section(title: String) -> VBoxContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = &"Card"
	content.add_child(card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", DesignTokens.SPACE_MD)
	card.add_child(column)

	var heading := Label.new()
	heading.text = title
	heading.theme_type_variation = &"Heading"
	column.add_child(heading)

	return column


## Applies a mutation and persists immediately. Every setting change goes through
## here so none can be forgotten on the way to disk.
func _apply(mutation: Callable) -> void:
	mutation.call()
	AppState.save_now()
	AudioManager.apply_settings(AppState.get_settings())


func _rebuild() -> void:
	for child in content.get_children():
		child.queue_free()
	build_content()


## Credited focus minutes recorded against a project, for the projects list.
func _project_minutes(project_id: String) -> float:
	return float(StatisticsManager.get_totals_by_project().get(project_id, 0.0))
