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

## Rebuilt on every _rebuild(), so the update section keeps references rather
## than looking its controls up again: the state it displays changes while the
## screen is open, driven by signals rather than by anything the player did.
var _update_status: Label = null
var _update_action: Button = null
var _update_notes: Button = null


func build_content() -> void:
	content.add_child(
		SectionHeader.create("Settings", "Changes are saved as you make them.")
	)
	_build_timer_section()
	_build_projects_section()
	_build_notifications_section()
	_build_gameplay_section()
	_build_pending_section()
	_build_updates_section()


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
	swatch.color = Palette.project_color(project.color_token)
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

	var theme_label := VBoxContainer.new()
	theme_label.add_theme_constant_override("separation", 2)
	var theme_title := Label.new()
	theme_title.text = "Appearance"
	theme_label.add_child(theme_title)
	var theme_hint := Label.new()
	theme_hint.text = "Dark keeps the same garden, after closing time."
	theme_hint.theme_type_variation = &"Caption"
	theme_label.add_child(theme_hint)
	column.add_child(theme_label)

	var theme_choices := ChoiceRow.new()
	theme_choices.add_choice("Light", "light")
	theme_choices.add_choice("Dark", "dark")
	theme_choices.selected.connect(func(value: Variant) -> void:
		_apply(func() -> void: AppState.get_settings().theme_mode = String(value))
		EventBus.theme_mode_changed.emit(String(value)))
	theme_choices.select_value(settings.theme_mode)
	column.add_child(theme_choices)

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
	reset.add_theme_color_override("font_color", Palette.clay())
	reset.pressed.connect(_on_reset_pressed)
	buttons.add_child(reset)

	var warning := Label.new()
	warning.text = (
		"Resetting deletes every plant, session and achievement. A backup is written "
		+ "first, so it can be undone below — but export a copy too if there is any doubt."
	)
	warning.theme_type_variation = &"Caption"
	warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(warning)

	column.add_child(HSeparator.new())
	_build_backup_section(column)


## Automatic backups (§36). Kept visible rather than silent: a backup nobody
## knows about is one nobody reaches for when they need it.
func _build_backup_section(column: VBoxContainer) -> void:
	var heading := Label.new()
	heading.text = "Backups"
	heading.theme_type_variation = &"Heading"
	column.add_child(heading)

	var snapshots := SaveManager.list_snapshots()
	var location := Label.new()
	location.text = "Kept in %s" % SaveManager.get_snapshot_dir()
	location.theme_type_variation = &"Caption"
	location.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(location)

	var summary := Label.new()
	summary.theme_type_variation = &"Caption"
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if snapshots.is_empty():
		summary.text = (
			"A dated copy of your whole garden is written when the app starts, "
			+ "hourly while you play, and when you close it. None yet."
		)
	else:
		summary.text = "%d kept, newest %s. Written on launch, hourly, and on close." % [
			snapshots.size(), snapshots[0].describe()
		]
	column.add_child(summary)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	column.add_child(buttons)

	var back_up := Button.new()
	back_up.text = "Back up now"
	back_up.theme_type_variation = &"SecondaryButton"
	back_up.pressed.connect(_on_back_up_now_pressed)
	buttons.add_child(back_up)

	var open := Button.new()
	open.text = "Open folder"
	open.theme_type_variation = &"SubtleButton"
	open.pressed.connect(func() -> void: OS.shell_open(SaveManager.get_snapshot_dir()))
	buttons.add_child(open)

	var restore := Button.new()
	restore.text = "Restore a backup"
	restore.theme_type_variation = &"SubtleButton"
	restore.disabled = snapshots.is_empty()
	if restore.disabled:
		restore.tooltip_text = "There is nothing to restore from yet."
	else:
		restore.pressed.connect(_on_restore_pressed)
	buttons.add_child(restore)


func _on_back_up_now_pressed() -> void:
	# Forced: pressing the button and getting nothing because a snapshot happened
	# four minutes ago would read as a broken button.
	if SaveManager.snapshot_now(true):
		EventBus.toast_requested.emit("Backed up", SaveManager.get_snapshot_dir(), "💾")
		_rebuild()
	else:
		_show_error(
			"Could not back up",
			"Focus Garden could not write to %s." % SaveManager.get_snapshot_dir()
		)


## Restoring replaces the live save, so it asks first and says exactly which copy
## it would bring back. The current garden is snapshotted before the swap, so
## even choosing the wrong date is recoverable.
func _on_restore_pressed() -> void:
	var snapshots := SaveManager.list_snapshots()
	if snapshots.is_empty():
		return
	var newest := snapshots[0]

	var dialog := ConfirmDialog.open(
		get_tree().root,
		"Restore the backup from %s?" % newest.describe(),
		(
			"Everything currently in Focus Garden is replaced by that copy. Your "
			+ "garden as it stands right now is backed up first, so this can be undone."
		),
		"Restore",
		true,
		"Cancel"
	)
	dialog.confirmed.connect(func() -> void:
		if SaveManager.restore_snapshot(newest.path) == null:
			_show_error("Could not restore", SaveManager.last_error_detail)
			return
		# The files on disk ARE the restored save now, so the live state is
		# re-read from them rather than assigned — that way sessions, projects and
		# the migration path all come back through the one loading route.
		AppState.load_game()
		_rebuild()
		EventBus.toast_requested.emit("Restored", newest.describe(), "💾"))


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
		# The garden being replaced is backed up first, for the same reason reset
		# does it: an import that turns out to be the wrong file must not be how
		# someone loses the one they had.
		SaveManager.snapshot_now(true)
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
			"This deletes %s of recorded focus, %d plants and %d achievements. A backup "
			+ "is written first, so it can be restored — but export a copy too if you "
			+ "are not certain."
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
			(
				"Delete everything and start a new garden? A dated backup is written "
				+ "first, so this can be undone from Restore a backup."
			),
			"Delete everything",
			true,
			"Cancel"
		)
		second.confirmed.connect(_perform_reset))


func _perform_reset() -> void:
	# Forced, and before anything is touched. A player who resets by accident has
	# minutes to realise it and hundreds of hours riding on the answer, so the
	# backup has to happen even if one was written four minutes ago.
	if not SaveManager.snapshot_now(true):
		GameLog.warn(
			GameLog.Category.SAVE,
			"Reset could not write a backup first; continuing at the player's request."
		)
	AppState.reset_to_new_game()
	_rebuild()
	EventBus.navigation_requested.emit("home")


## Updates (docs/UPDATES.md). Deliberately the last section on the screen: it is
## the one part of Focus Garden that touches the network, and a player who wants
## to know that should find it stated rather than have to infer it.
func _build_updates_section() -> void:
	var column := _section("Updates")

	var current := Label.new()
	current.text = "You are running version %s." % VersionUtil.current()
	current.theme_type_variation = &"Caption"
	column.add_child(current)

	column.add_child(SettingRow.toggle(
		"Check for updates",
		(
			"Asks GitHub once, a few seconds after launch, whether a newer version "
			+ "exists. It is the only time Focus Garden uses the network, and it sends "
			+ "nothing about you."
		),
		AppState.get_settings().check_for_updates,
		func(value: bool) -> void:
			_apply(func() -> void: AppState.get_settings().check_for_updates = value)
			_refresh_update_controls()
	))

	_update_status = Label.new()
	_update_status.theme_type_variation = &"Muted"
	_update_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_update_status)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	column.add_child(buttons)

	_update_action = Button.new()
	_update_action.theme_type_variation = &"SecondaryButton"
	_update_action.pressed.connect(_on_update_action_pressed)
	buttons.add_child(_update_action)

	_update_notes = Button.new()
	_update_notes.text = "What's new"
	_update_notes.theme_type_variation = &"SubtleButton"
	_update_notes.pressed.connect(func() -> void: UpdateManager.open_release_page())
	buttons.add_child(_update_notes)

	_connect_update_signals()
	_refresh_update_controls()


## Connected once per screen instance. build_content() runs again on every
## _rebuild(), and a second connection would show every message twice.
func _connect_update_signals() -> void:
	if EventBus.update_available.is_connected(_on_update_available):
		return
	EventBus.update_available.connect(_on_update_available)
	EventBus.update_check_completed.connect(_on_update_check_completed)
	EventBus.update_download_progress.connect(_on_update_download_progress)
	EventBus.update_ready_to_install.connect(_on_update_ready)
	EventBus.update_failed.connect(_on_update_failed)


func _on_update_available(_version: String, _notes: String) -> void:
	_refresh_update_controls()


func _on_update_check_completed(up_to_date: bool) -> void:
	_refresh_update_controls()
	if up_to_date and is_instance_valid(_update_status):
		_update_status.text = "Focus Garden is up to date."


func _on_update_download_progress(received: int, total: int) -> void:
	if not is_instance_valid(_update_status):
		return
	if total <= 0:
		_update_status.text = "Downloading… %s so far." % _format_bytes(received)
		return
	_update_status.text = "Downloading… %s of %s." % [
		_format_bytes(received), _format_bytes(total)
	]


func _on_update_ready(version: String, _path: String) -> void:
	_refresh_update_controls()
	if is_instance_valid(_update_status):
		_update_status.text = "Version %s is ready to install." % version


func _on_update_failed(reason: String) -> void:
	_refresh_update_controls()
	if is_instance_valid(_update_status):
		_update_status.text = reason


## One place decides what the button says and whether it can be pressed, so the
## six states this section can be in cannot drift apart.
func _refresh_update_controls() -> void:
	if not is_instance_valid(_update_status) or not is_instance_valid(_update_action):
		return

	var has_update := not UpdateManager.available_version.is_empty()
	_update_notes.visible = has_update
	_update_action.disabled = false
	_update_action.tooltip_text = ""

	if not UpdateManager.is_available():
		# A development build has no installer to replace, and checking from one
		# would be the only network call the editor ever made.
		_update_status.text = "Update checking is part of a released build, not this one."
		_update_action.text = "Check now"
		_update_action.disabled = true
		_update_notes.visible = false
		return

	match UpdateManager.state:
		UpdateManager.State.CHECKING:
			_update_status.text = "Checking…"
			_update_action.text = "Check now"
			_update_action.disabled = true
		UpdateManager.State.DOWNLOADING:
			_update_action.text = "Downloading…"
			_update_action.disabled = true
		UpdateManager.State.READY:
			_update_status.text = "Version %s is ready to install." % UpdateManager.available_version
			_update_action.text = "Install and restart"
		UpdateManager.State.INSTALLING:
			_update_status.text = "Installing…"
			_update_action.text = "Installing…"
			_update_action.disabled = true
		UpdateManager.State.AVAILABLE:
			_update_status.text = "Version %s is available." % UpdateManager.available_version
			if UpdateManager.can_self_install() and UpdateManager.has_asset():
				_update_action.text = "Download and install"
			else:
				# A build we cannot replace — an extracted AppDir, a distribution
				# package, a platform with no asset in this release. Offering an
				# install we cannot perform would be worse than saying so.
				_update_status.text += " This build updates from the release page."
				_update_action.text = "Open the release page"
		_:
			if not AppState.get_settings().check_for_updates:
				_update_status.text = "Automatic checking is off. You can still check by hand."
			elif _update_status.text.is_empty():
				_update_status.text = "No newer version found yet."
			_update_action.text = "Check now"


func _on_update_action_pressed() -> void:
	match UpdateManager.state:
		UpdateManager.State.READY:
			_confirm_install()
		UpdateManager.State.AVAILABLE:
			if UpdateManager.can_self_install() and UpdateManager.has_asset():
				UpdateManager.download()
			else:
				UpdateManager.open_release_page()
		_:
			_update_status.text = "Checking…"
			UpdateManager.check_now(true)
	_refresh_update_controls()


## The install closes the app, so it asks first and says so plainly. A player
## mid-thought should not have the window vanish because they pressed a button
## whose consequence was not stated.
func _confirm_install() -> void:
	var dialog := ConfirmDialog.open(
		get_tree().root,
		"Install version %s?" % UpdateManager.available_version,
		(
			"Focus Garden will close, update, and open again. Your garden, sessions "
			+ "and settings are stored separately and are not touched."
		),
		"Install",
		false,
		"Not now"
	)
	dialog.confirmed.connect(func() -> void:
		if not UpdateManager.install():
			_refresh_update_controls())


func _format_bytes(bytes: int) -> String:
	if bytes < 1024 * 1024:
		return "%d KB" % int(round(float(bytes) / 1024.0))
	return "%.1f MB" % (float(bytes) / 1048576.0)


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
