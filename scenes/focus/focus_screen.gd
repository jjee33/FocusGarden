class_name FocusScreen
extends AppScreen
## Session preparation, the running timer, and the completion summary (§9-§12).
##
## Three modes in one screen rather than three screens, because the player's
## attention should not be moved around a session they are trying to concentrate
## on. Starting a session changes what is in front of them without changing where
## they are.
##
## §10 is the constraint that shapes the running mode: "do not expose distracting
## navigation unless necessary". So running mode drops to a countdown, the
## project name, and three controls — and offers Focus Mode, which hides the
## navigation rail entirely.
##
## The screen owns no timing. Every figure comes from TimerManager, which derives
## it from timestamps; this only renders.

enum Mode { SETUP, RUNNING, COMPLETE }

## Offered focus lengths. The player's own configured default is merged in, so a
## custom 37-minute preference is always one click away rather than being buried
## behind the custom stepper every time.
const DURATION_PRESETS: Array[int] = [15, 25, 45, 50, 90]
const CUSTOM_STEP_MINUTES: float = 5.0
const RING_SIZE: int = 320

var _mode: Mode = Mode.SETUP
var _selected_project_id: String = ""
var _selected_duration: float = 25.0
var _last_outcome: SessionPipeline.Outcome = null
var _last_session_was_break: bool = false

# Running-mode nodes, refreshed on tick rather than rebuilt.
var _ring: ProgressRing
var _countdown_label: Label
var _state_label: Label
var _pause_button: Button
var _auto_start_label: Label


func build_content() -> void:
	var settings := AppState.get_settings()
	_selected_duration = settings.focus_duration_minutes
	_selected_project_id = AppState.data.profile.active_project_id

	EventBus.session_tick.connect(_on_tick)
	EventBus.session_started.connect(_on_session_started)
	EventBus.session_paused.connect(_on_session_state_changed)
	EventBus.session_resumed.connect(_on_session_state_changed)
	EventBus.auto_start_scheduled.connect(_on_auto_start_scheduled)
	EventBus.auto_start_cancelled.connect(_on_auto_start_cancelled)

	# A session may already be running — the player can start one and navigate
	# away, and coming back must show the timer, not the setup form.
	_mode = Mode.RUNNING if TimerManager.is_active() else Mode.SETUP
	_rebuild()


func on_shown() -> void:
	if TimerManager.is_active() and _mode != Mode.RUNNING:
		_set_mode(Mode.RUNNING)
	elif not TimerManager.is_active() and _mode == Mode.RUNNING:
		_set_mode(Mode.SETUP)


func _set_mode(mode: Mode) -> void:
	if _mode == mode:
		return
	_mode = mode
	_rebuild()


func _rebuild() -> void:
	for child in content.get_children():
		child.queue_free()
	# Freed nodes linger until the end of the frame; clearing the references
	# stops a tick landing on a node that is on its way out.
	_ring = null
	_countdown_label = null
	_state_label = null
	_pause_button = null
	_auto_start_label = null

	match _mode:
		Mode.SETUP:
			_build_setup()
		Mode.RUNNING:
			_build_running()
		Mode.COMPLETE:
			_build_complete()


# --- Setup (§9) ---------------------------------------------------------------

func _build_setup() -> void:
	content.add_child(
		SectionHeader.create("Focus", "Pick what you are working on, then choose a length.")
	)

	_build_project_picker()
	_build_duration_picker()
	_build_plant_notice()

	var start := Button.new()
	start.text = "Start Focus"
	start.theme_type_variation = &"PrimaryButton"
	start.custom_minimum_size = Vector2(0, 60)
	start.pressed.connect(_on_start_pressed)
	content.add_child(start)

	# Nothing to focus *on* is the one state that genuinely blocks starting.
	if AppState.get_active_projects().is_empty():
		start.disabled = true
		start.tooltip_text = "Add a project first."


func _build_project_picker() -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = &"Card"
	content.add_child(card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", DesignTokens.SPACE_SM)
	card.add_child(column)

	var heading := Label.new()
	heading.text = "What are you working on?"
	heading.theme_type_variation = &"Heading"
	column.add_child(heading)

	var projects := AppState.get_active_projects()
	if projects.is_empty():
		var empty := Label.new()
		empty.text = "No projects yet — add one to get started."
		empty.theme_type_variation = &"Muted"
		column.add_child(empty)
	else:
		var row := ChoiceRow.new()
		column.add_child(row)
		for project: ProjectCategory in projects:
			var chip := row.add_choice(project.display_name, project.id)
			# The category colour is decoration; the name carries the meaning
			# (§50 forbids colour-only encoding).
			chip.add_theme_color_override(
				"font_hover_color", DesignTokens.project_color(project.color_token)
			)
		row.selected.connect(_on_project_selected)
		if not projects.any(func(p: ProjectCategory) -> bool: return p.id == _selected_project_id):
			_selected_project_id = projects[0].id
		row.select_value(_selected_project_id)

	var add_button := Button.new()
	add_button.text = "+  New project"
	add_button.theme_type_variation = &"SubtleButton"
	add_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_button.pressed.connect(_on_new_project_pressed)
	column.add_child(add_button)


func _build_duration_picker() -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = &"Card"
	content.add_child(card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", DesignTokens.SPACE_SM)
	card.add_child(column)

	var heading := Label.new()
	heading.text = "How long?"
	heading.theme_type_variation = &"Heading"
	column.add_child(heading)

	var row := ChoiceRow.new()
	column.add_child(row)

	var offered := DURATION_PRESETS.duplicate()
	var configured := int(round(AppState.get_settings().focus_duration_minutes))
	if not offered.has(configured):
		offered.append(configured)
	offered.sort()
	for minutes: int in offered:
		row.add_choice("%d min" % minutes, float(minutes))
	row.selected.connect(_on_duration_selected)
	row.select_value(_selected_duration)

	# Custom stepper. Coarse 5-minute steps rather than a spin box: a focus
	# length is a rough intention, and precise entry invites fiddling on a screen
	# whose whole job is to get out of the way.
	var stepper := HBoxContainer.new()
	stepper.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	column.add_child(stepper)

	var custom_label := Label.new()
	custom_label.text = "Custom"
	custom_label.theme_type_variation = &"Muted"
	custom_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stepper.add_child(custom_label)

	var minus := Button.new()
	minus.text = "−"
	minus.theme_type_variation = &"Chip"
	minus.tooltip_text = "5 minutes shorter"
	minus.pressed.connect(func() -> void: _nudge_duration(-CUSTOM_STEP_MINUTES, row))
	stepper.add_child(minus)

	var value := Label.new()
	value.name = "CustomValue"
	value.text = TimeUtil.format_duration(_selected_duration)
	value.custom_minimum_size.x = 84
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stepper.add_child(value)

	var plus := Button.new()
	plus.text = "+"
	plus.theme_type_variation = &"Chip"
	plus.tooltip_text = "5 minutes longer"
	plus.pressed.connect(func() -> void: _nudge_duration(CUSTOM_STEP_MINUTES, row))
	stepper.add_child(plus)


## §9 asks the player to choose a plant. Plants do not exist until Milestone 2,
## and saying so plainly beats an empty picker that looks broken.
func _build_plant_notice() -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = &"CardSunken"
	content.add_child(card)

	var label := Label.new()
	label.text = (
		"Plant selection arrives in Milestone 2. Sessions you complete now are still "
		+ "recorded in full, so the time will count toward whatever you grow later."
	)
	label.theme_type_variation = &"Caption"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	card.add_child(label)


func _nudge_duration(delta: float, row: ChoiceRow) -> void:
	_selected_duration = clampf(_selected_duration + delta, 1.0, 480.0)
	var value := content.find_child("CustomValue", true, false) as Label
	if value != null:
		value.text = TimeUtil.format_duration(_selected_duration)
	# A stepped value is no longer one of the presets, so drop the chip highlight
	# rather than leaving a chip looking selected while the real value differs.
	row.select_value(_selected_duration)
	_persist_duration()


func _on_duration_selected(value: Variant) -> void:
	_selected_duration = float(value)
	var label := content.find_child("CustomValue", true, false) as Label
	if label != null:
		label.text = TimeUtil.format_duration(_selected_duration)
	_persist_duration()


## The chosen length becomes the new default, so the setting the player actually
## uses is the one that persists (§59's "settings persist").
func _persist_duration() -> void:
	AppState.get_settings().focus_duration_minutes = _selected_duration
	AppState.save_now()


func _on_project_selected(value: Variant) -> void:
	_selected_project_id = String(value)
	AppState.data.profile.active_project_id = _selected_project_id
	AppState.save_now()


func _on_new_project_pressed() -> void:
	var dialog := NewProjectDialog.open(get_tree().root)
	dialog.created.connect(
		func(name: String, color: String) -> void:
			var project := AppState.add_project(name, color)
			_selected_project_id = project.id
			AppState.data.profile.active_project_id = project.id
			AppState.save_now()
			_rebuild()
	)


func _on_start_pressed() -> void:
	if AppState.get_active_projects().is_empty():
		return
	TimerManager.start_focus(_selected_project_id, "", _selected_duration)


# --- Running (§10) ------------------------------------------------------------

func _build_running() -> void:
	var session := TimerManager.current_session
	if session == null:
		_build_setup()
		return

	var is_break := session.is_break()
	var accent := DesignTokens.SKY if is_break else DesignTokens.MOSS

	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", DesignTokens.SPACE_SM)
	content.add_child(heading)

	_state_label = Label.new()
	_state_label.text = _session_kind_name(session.kind)
	_state_label.theme_type_variation = &"Heading"
	_state_label.add_theme_color_override("font_color", accent)
	_state_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(_state_label)

	var focus_mode := Button.new()
	focus_mode.text = "Focus Mode"
	focus_mode.theme_type_variation = &"SubtleButton"
	focus_mode.toggle_mode = true
	focus_mode.tooltip_text = "Hide the navigation rail while you work"
	focus_mode.toggled.connect(func(on: bool) -> void: EventBus.focus_mode_changed.emit(on))
	heading.add_child(focus_mode)

	var ring_holder := CenterContainer.new()
	ring_holder.custom_minimum_size.y = RING_SIZE + DesignTokens.SPACE_LG
	content.add_child(ring_holder)

	_ring = ProgressRing.new()
	_ring.custom_minimum_size = Vector2(RING_SIZE, RING_SIZE)
	_ring.arc_color = accent
	ring_holder.add_child(_ring)

	# The countdown sits inside the ring rather than under it, so the eye has one
	# place to rest.
	var centre_column := VBoxContainer.new()
	centre_column.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre_column.alignment = BoxContainer.ALIGNMENT_CENTER
	centre_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ring.add_child(centre_column)

	_countdown_label = Label.new()
	_countdown_label.theme_type_variation = &"Countdown"
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	centre_column.add_child(_countdown_label)

	var project_label := Label.new()
	project_label.text = (
		AppState.get_project_name(session.project_id) if not is_break else "Rest your eyes"
	)
	project_label.theme_type_variation = &"Muted"
	project_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	centre_column.add_child(project_label)

	if not is_break:
		var cycle := Label.new()
		cycle.text = "Session %d of %d in this cycle" % [
			TimerManager.get_cycle_position(),
			AppState.get_settings().sessions_before_long_break,
		]
		cycle.theme_type_variation = &"Caption"
		cycle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(cycle)

	var controls := HBoxContainer.new()
	controls.alignment = BoxContainer.ALIGNMENT_CENTER
	controls.add_theme_constant_override("separation", DesignTokens.SPACE_SM)
	content.add_child(controls)

	_pause_button = Button.new()
	_pause_button.custom_minimum_size = Vector2(160, 48)
	_pause_button.pressed.connect(_on_pause_pressed)
	controls.add_child(_pause_button)

	var finish := Button.new()
	finish.text = "Finish early"
	finish.theme_type_variation = &"SubtleButton"
	finish.tooltip_text = "End now and keep the time you have focused"
	finish.pressed.connect(_on_finish_pressed)
	controls.add_child(finish)

	var discard := Button.new()
	discard.text = "Discard"
	discard.theme_type_variation = &"SubtleButton"
	# Tinted so the destructive control is distinguishable from the two benign
	# ones beside it. The tint is a hint, not the message — the label already
	# says "Discard" and the confirmation spells out the consequence (§50).
	discard.add_theme_color_override("font_color", DesignTokens.CLAY)
	discard.tooltip_text = "End without keeping this session's time"
	discard.pressed.connect(_on_discard_pressed)
	controls.add_child(discard)

	_refresh_running()


func _refresh_running() -> void:
	if _ring == null or TimerManager.current_session == null:
		return
	_countdown_label.text = TimeUtil.format_countdown(TimerManager.get_remaining_seconds())
	_ring.progress = TimerManager.get_progress_ratio()

	var paused := TimerManager.state == TimerManager.State.PAUSED
	_pause_button.text = "Resume" if paused else "Pause"
	# Pause is the one control the player reaches for mid-session, so it carries
	# a visible edge rather than sitting flat like the two secondary actions.
	# Resuming is the urgent one, so it becomes the primary button while paused.
	_pause_button.theme_type_variation = &"PrimaryButton" if paused else &"Button"
	_state_label.text = (
		"Paused" if paused else _session_kind_name(TimerManager.current_session.kind)
	)


func _on_pause_pressed() -> void:
	if TimerManager.state == TimerManager.State.PAUSED:
		TimerManager.resume()
	else:
		TimerManager.pause()


func _on_finish_pressed() -> void:
	_last_session_was_break = TimerManager.current_session.is_break()
	_last_outcome = TimerManager.finish_early()
	_set_mode(Mode.COMPLETE)


func _on_discard_pressed() -> void:
	if not AppState.get_settings().confirm_before_cancel_session:
		_discard_now()
		return

	# §49: a destructive action never happens on one accidental click.
	var dialog := ConfirmDialog.open(
		get_tree().root,
		"Discard this session?",
		(
			"The time you have focused so far will not be counted. "
			+ "If you want to keep it, choose Finish early instead."
		),
		"Discard",
		true,
		"Keep going"
	)
	dialog.confirmed.connect(_discard_now)


func _discard_now() -> void:
	EventBus.focus_mode_changed.emit(false)
	TimerManager.cancel("Discarded by the player.")
	_set_mode(Mode.SETUP)


# --- Completion (§11) ---------------------------------------------------------

func _build_complete() -> void:
	var outcome := _last_outcome
	var was_break := _last_session_was_break

	content.add_child(
		SectionHeader.create(
			"Nice work" if not was_break else "Break over",
			"Here is what that session added." if not was_break else "Ready when you are."
		)
	)

	var card := PanelContainer.new()
	card.theme_type_variation = &"Card"
	content.add_child(card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", DesignTokens.SPACE_MD)
	card.add_child(column)

	var tiles := HBoxContainer.new()
	tiles.add_theme_constant_override("separation", DesignTokens.SPACE_MD)
	column.add_child(tiles)

	var credited := outcome.credited_minutes if outcome != null else 0.0
	tiles.add_child(
		StatTile.create("Focused", TimeUtil.format_duration(credited), DesignTokens.MOSS)
	)
	tiles.add_child(
		StatTile.create(
			"Experience", "+%d XP" % (outcome.xp_awarded if outcome != null else 0),
			DesignTokens.AMBER
		)
	)
	var summary := StatisticsManager.get_summary()
	tiles.add_child(
		StatTile.create(
			"Today", TimeUtil.format_duration(summary.focus_today), DesignTokens.TERRACOTTA
		)
	)

	if outcome != null and outcome.levels_gained > 0:
		var level_up := Label.new()
		level_up.text = "Level %d reached." % ProgressionManager.get_level()
		level_up.theme_type_variation = &"Heading"
		level_up.add_theme_color_override("font_color", DesignTokens.AMBER)
		column.add_child(level_up)

	# An anomalous session is reported plainly rather than hidden. §55 requires we
	# preserve and flag rather than punish, and the player deserves to know why a
	# figure looks lower than the wall clock suggested.
	if outcome != null and not outcome.skipped_reason.is_empty():
		var note := Label.new()
		note.text = outcome.skipped_reason
		note.theme_type_variation = &"Caption"
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		column.add_child(note)

	_auto_start_label = Label.new()
	_auto_start_label.theme_type_variation = &"Caption"
	_auto_start_label.visible = TimerManager.is_auto_start_pending()
	column.add_child(_auto_start_label)

	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	content.add_child(actions)

	var next := Button.new()
	next.theme_type_variation = &"PrimaryButton"
	next.custom_minimum_size = Vector2(0, 52)
	next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if was_break:
		next.text = "Start focusing"
		next.pressed.connect(
			func() -> void: TimerManager.start_focus(_selected_project_id, "", _selected_duration)
		)
	else:
		var break_kind := TimerManager.get_next_break_kind()
		next.text = "Take a %s" % _session_kind_name(break_kind).to_lower()
		next.pressed.connect(func() -> void: TimerManager.start_break())
	actions.add_child(next)

	var done := Button.new()
	done.text = "Done for now"
	done.theme_type_variation = &"SubtleButton"
	done.custom_minimum_size = Vector2(0, 52)
	done.pressed.connect(
		func() -> void:
			TimerManager.cancel_auto_start()
			_set_mode(Mode.SETUP)
	)
	actions.add_child(done)


# --- Events -------------------------------------------------------------------

func _on_tick(_remaining_seconds: float) -> void:
	if _mode == Mode.RUNNING:
		_refresh_running()
	elif _mode == Mode.COMPLETE and _auto_start_label != null:
		_refresh_auto_start_label()


func _on_session_started(_session_id: String) -> void:
	EventBus.focus_mode_changed.emit(false)
	_set_mode(Mode.RUNNING)


func _on_session_state_changed(_session_id: String) -> void:
	if _mode == Mode.RUNNING:
		_refresh_running()


func _on_auto_start_scheduled(_delay: float) -> void:
	if _auto_start_label != null:
		_auto_start_label.visible = true
		_refresh_auto_start_label()


func _on_auto_start_cancelled() -> void:
	if _auto_start_label != null:
		_auto_start_label.visible = false


func _refresh_auto_start_label() -> void:
	if not TimerManager.is_auto_start_pending():
		_auto_start_label.visible = false
		return
	_auto_start_label.visible = true
	_auto_start_label.text = "%s starts in %ds — choose anything above to stop it." % [
		_session_kind_name(TimerManager.get_pending_kind()),
		int(ceil(TimerManager.get_auto_start_remaining())),
	]


static func _session_kind_name(kind: FocusSession.Kind) -> String:
	match kind:
		FocusSession.Kind.SHORT_BREAK:
			return "Short break"
		FocusSession.Kind.LONG_BREAK:
			return "Long break"
		_:
			return "Focusing"
