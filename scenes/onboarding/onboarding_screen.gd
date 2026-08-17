class_name OnboardingScreen
extends Control
## First launch (§45).
##
## §45 asks five questions and explicitly warns against a long tutorial, so this
## is one screen with five answers and no "next" button between them — the whole
## thing is visible at once and can be finished in about fifteen seconds.
##
## Every answer has a working default already selected. A player who reads none
## of it and clicks the button straight through gets a perfectly good setup, and
## nothing here can be answered "wrong".

signal completed()

const PLANT_CHOICES: Array[StringName] = [
	&"pothos", &"aloe_vera", &"snake_plant", &"spider_plant", &"jade_plant",
]
const PROJECT_SUGGESTIONS: Array[String] = [
	"Studying", "Work", "Reading", "Programming", "Personal",
]

var _name_field: LineEdit
var _project_field: LineEdit
var _duration: float = 25.0
var _goal: float = 50.0
var _species: StringName = &"pothos"
var _plant_row: HBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = DesignTokens.BG_BASE
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, DesignTokens.SPACE_XXL)
	add_child(margin)

	var centre := CenterContainer.new()
	margin.add_child(centre)

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(760, 0)
	scroll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	centre.add_child(scroll)

	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 760
	column.add_theme_constant_override("separation", DesignTokens.SPACE_LG)
	scroll.add_child(column)

	_build_welcome(column)
	_build_name(column)
	_build_duration(column)
	_build_goal(column)
	_build_project(column)
	_build_plant(column)

	var start := Button.new()
	start.text = "Plant it and begin"
	start.theme_type_variation = &"PrimaryButton"
	start.custom_minimum_size = Vector2(0, 58)
	start.pressed.connect(_finish)
	column.add_child(start)


func _build_welcome(parent: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "Focus Garden"
	title.theme_type_variation = &"Display"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(title)

	var subtitle := Label.new()
	subtitle.text = (
		"Every plant you grow here is time you actually spent focusing. "
		+ "Five quick questions and you can start."
	)
	subtitle.theme_type_variation = &"Muted"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(subtitle)


func _build_name(parent: VBoxContainer) -> void:
	var column := _card(parent, "What should I call you?")
	_name_field = LineEdit.new()
	_name_field.placeholder_text = "Gardener"
	_name_field.max_length = 30
	column.add_child(_name_field)


func _build_duration(parent: VBoxContainer) -> void:
	var column := _card(parent, "How long do you like to focus for?")
	var row := ChoiceRow.new()
	for minutes: int in [15, 25, 45, 50, 90]:
		row.add_choice("%d min" % minutes, float(minutes))
	row.selected.connect(func(value: Variant) -> void: _duration = float(value))
	row.select_value(_duration)
	column.add_child(row)


func _build_goal(parent: VBoxContainer) -> void:
	var column := _card(parent, "How much would you like to do most days?")
	var row := ChoiceRow.new()
	for minutes: int in [25, 50, 120, 240]:
		row.add_choice(TimeUtil.format_duration(float(minutes)), float(minutes))
	row.selected.connect(func(value: Variant) -> void: _goal = float(value))
	row.select_value(_goal)
	column.add_child(row)

	var note := Label.new()
	note.text = "A target, not a rule. Missing it costs you nothing."
	note.theme_type_variation = &"Caption"
	column.add_child(note)


func _build_project(parent: VBoxContainer) -> void:
	var column := _card(parent, "What are you working on first?")
	_project_field = LineEdit.new()
	_project_field.placeholder_text = "Studying"
	_project_field.max_length = 40
	column.add_child(_project_field)

	var suggestions := HBoxContainer.new()
	suggestions.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	column.add_child(suggestions)
	for suggestion: String in PROJECT_SUGGESTIONS:
		var chip := Button.new()
		chip.text = suggestion
		chip.theme_type_variation = &"Chip"
		chip.pressed.connect(func() -> void: _project_field.text = suggestion)
		suggestions.add_child(chip)


func _build_plant(parent: VBoxContainer) -> void:
	var column := _card(parent, "Pick your first plant")
	_plant_row = HBoxContainer.new()
	_plant_row.add_theme_constant_override("separation", DesignTokens.SPACE_MD)
	column.add_child(_plant_row)
	_rebuild_plant_choices()


func _rebuild_plant_choices() -> void:
	for child in _plant_row.get_children():
		child.queue_free()

	for species_id: StringName in PLANT_CHOICES:
		var species := ContentDB.get_species(species_id)
		if species == null:
			continue
		var card := PlantCard.for_species(
			species, true, RequirementEvaluator.describe(species.growth_requirement)
		)
		# The chosen one stays fully lit; the others recede, so the selection is
		# visible without a tick that would need explaining.
		card.modulate = Color(1, 1, 1, 1.0 if species_id == _species else 0.6)
		var chosen := species_id
		card.pressed.connect(func() -> void:
			_species = chosen
			_rebuild_plant_choices())
		_plant_row.add_child(card)


func _card(parent: VBoxContainer, heading_text: String) -> VBoxContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = &"Card"
	parent.add_child(card)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", DesignTokens.SPACE_SM)
	card.add_child(column)

	var heading := Label.new()
	heading.text = heading_text
	heading.theme_type_variation = &"Heading"
	column.add_child(heading)
	return column


func _finish() -> void:
	var profile := AppState.data.profile
	var chosen_name := _name_field.text.strip_edges()
	profile.display_name = chosen_name if not chosen_name.is_empty() else "Gardener"
	profile.onboarding_completed = true

	var settings := AppState.get_settings()
	settings.focus_duration_minutes = _duration
	settings.daily_goal_minutes = _goal
	# The streak threshold should never exceed the daily goal, or the player
	# could hit their goal and still not keep their streak.
	settings.streak_threshold_minutes = minf(settings.streak_threshold_minutes, _goal)

	# The player's own first project goes at the head of the list, ahead of the
	# seeded suggestions, so it is the one already selected.
	var project_name := _project_field.text.strip_edges()
	if not project_name.is_empty():
		var project := ProjectCategory.create(project_name, "moss", "leaf")
		AppState.data.projects.insert(0, project)
		profile.active_project_id = project.id

	AppState.start_growing(_species)
	AppState.save_now()
	GameLog.info(GameLog.Category.APP, "Onboarding complete for '%s'." % profile.display_name)
	completed.emit()
	queue_free()
