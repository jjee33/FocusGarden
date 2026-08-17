class_name PlantCard
extends PanelContainer
## A species or an owned plant, presented as a card (§4's reusable item cards).
##
## Used by the catalogue grid, the plant picker, the shelf inventory and the
## home screen, so all four present a plant identically. §74 asks that every
## screen look like part of the same game; sharing this component is how that
## survives four screens built at different times.
##
## §50: rarity is shown as a NAMED badge, never as colour alone.

signal pressed()

const PREVIEW_HEIGHT: int = 132

var _button: Button
var _plant_view: PlantView


## A species as it appears in the catalogue. `discovered` false renders the
## silhouette treatment (§16).
static func for_species(
	species: PlantSpecies, discovered: bool = true, subtitle: String = ""
) -> PlantCard:
	var card := PlantCard.new()
	card._build(
		species,
		species.display_name if discovered else "???",
		subtitle if not subtitle.is_empty() else (
			species.scientific_name if discovered else "Not yet discovered"
		),
		1.0,
		not discovered,
		discovered
	)
	return card


## An owned plant, showing its own growth rather than a finished specimen.
static func for_plant(plant: PlantInstance, progress: float, subtitle: String = "") -> PlantCard:
	var species := ContentDB.get_species(plant.species_id)
	var card := PlantCard.new()
	if species == null:
		# §54: a species removed by an update must not erase the player's plant.
		card._build_missing(plant)
		return card
	card._build(
		species,
		plant.nickname if not plant.nickname.is_empty() else species.display_name,
		subtitle if not subtitle.is_empty() else "%d%% grown" % int(progress * 100.0),
		progress,
		false,
		true
	)
	card.pot_id = plant.pot_id
	return card


var pot_id: StringName = &"terracotta_basic":
	set(value):
		pot_id = value
		if _plant_view != null:
			_plant_view.pot = ContentDB.get_pot(value)


func _build(
	species: PlantSpecies,
	title: String,
	subtitle: String,
	growth: float,
	as_silhouette: bool,
	show_rarity: bool
) -> void:
	theme_type_variation = &"Card"
	# Cards share their row's width evenly. Without this they shrink to their
	# content and long names like "English Lavender" wrap mid-word.
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size.x = 180

	# A Button behind the content makes the whole card clickable and gives it
	# hover, pressed and keyboard focus states for free (§74).
	_button = Button.new()
	_button.flat = true
	_button.set_anchors_preset(Control.PRESET_FULL_RECT)
	_button.focus_mode = Control.FOCUS_ALL
	_button.pressed.connect(func() -> void: pressed.emit())
	add_child(_button)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)

	_plant_view = PlantView.new()
	_plant_view.species = species
	_plant_view.growth = growth
	_plant_view.silhouette = as_silhouette
	_plant_view.pot = ContentDB.get_pot(pot_id)
	_plant_view.custom_minimum_size.y = PREVIEW_HEIGHT
	_plant_view.plant_height = PREVIEW_HEIGHT
	_plant_view.animate = not AppState.get_settings().reduced_motion
	column.add_child(_plant_view)

	var name_label := Label.new()
	name_label.text = title
	name_label.theme_type_variation = &"CardTitle"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# WORD_SMART, not WORD: a species name that still does not fit should break
	# between words, never inside one.
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	column.add_child(name_label)

	var subtitle_label := Label.new()
	subtitle_label.text = subtitle
	subtitle_label.theme_type_variation = &"Caption"
	subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(subtitle_label)

	if show_rarity:
		var badge := _rarity_badge(species.rarity)
		badge.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		column.add_child(badge)

	tooltip_text = "%s — %s" % [title, subtitle]


func _build_missing(plant: PlantInstance) -> void:
	theme_type_variation = &"Card"
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", DesignTokens.SPACE_XS)
	add_child(column)

	var gap := Control.new()
	gap.custom_minimum_size.y = PREVIEW_HEIGHT
	column.add_child(gap)

	var name_label := Label.new()
	name_label.text = plant.nickname if not plant.nickname.is_empty() else "Unknown plant"
	name_label.theme_type_variation = &"Heading"
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(name_label)

	var note := Label.new()
	note.text = "This species is not in the current version. Its history is kept."
	note.theme_type_variation = &"Caption"
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(note)


## Rarity as a named pill. The colour supports the word; it never replaces it.
static func _rarity_badge(rarity: PlantSpecies.Rarity) -> Control:
	var badge := PanelContainer.new()
	badge.theme_type_variation = &"Badge"
	var style := StyleBoxFlat.new()
	style.bg_color = DesignTokens.rarity_color(rarity)
	style.set_corner_radius_all(DesignTokens.RADIUS_PILL)
	style.content_margin_left = DesignTokens.SPACE_XS
	style.content_margin_right = DesignTokens.SPACE_XS
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	badge.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = PlantSpecies.RARITY_NAMES[clampi(int(rarity), 0, 4)]
	label.add_theme_font_size_override("font_size", DesignTokens.FONT_CAPTION)
	label.add_theme_color_override("font_color", DesignTokens.INK_ON_ACCENT)
	badge.add_child(label)
	return badge
