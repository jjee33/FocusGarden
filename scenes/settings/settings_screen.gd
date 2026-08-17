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
	var column := _section("Appearance, audio and data")
	var label := Label.new()
	label.text = (
		"Window mode, UI scale, reduced motion, volume sliders, and save export and import "
		+ "arrive in Milestone 8. They are absent rather than shown as switches that do nothing."
	)
	label.theme_type_variation = &"Muted"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(label)


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
