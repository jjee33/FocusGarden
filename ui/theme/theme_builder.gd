class_name ThemeBuilder
extends RefCounted
## Builds the game's Theme resources from DesignTokens and Palette.
##
## The theme is GENERATED rather than hand-authored as a .tres. A Theme file with
## every stylebox spelled out is thousands of unreviewable lines, and it drifts
## from the tokens the moment someone edits it in the inspector. Generating it
## keeps DesignTokens and Palette as the only places a value is decided (§4).
##
## TWO THEMES, ONE BUILDER. Light and dark are the same structure with a different
## palette bound, so a variation can never exist in one mode and not the other.
## `tools/bake_theme.gd` runs this twice and writes ui/theme/focus_garden_light.tres
## and focus_garden_dark.tres. Both are committed; project.godot references the
## light one so the EDITOR previews correctly too. Re-run the bake after changing
## any token:
##     tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless --path . \
##         --script res://tools/bake_theme.gd
##
## §74 requires every button to have hover, pressed, focus and disabled states.
## They are defined here once, so no screen can ship a button that silently lacks
## feedback.


## Builds the theme for one appearance mode. The palette is bound for the duration
## and restored afterwards, so baking dark never leaves a tool or a running game
## looking at the wrong colours.
static func build(mode: Palette.Mode = Palette.Mode.LIGHT) -> Theme:
	var previous := Palette.get_mode()
	Palette.set_mode(mode)

	var theme := Theme.new()
	theme.default_font = DesignTokens.font()
	theme.default_font_size = DesignTokens.FONT_BODY

	_build_button(theme)
	_build_panels(theme)
	_build_labels(theme)
	_build_inputs(theme)
	_build_progress(theme)
	_build_scrollbars(theme)
	_build_separators(theme)
	_build_tooltip(theme)
	_build_variations(theme)

	Palette.set_mode(previous)
	return theme


# --- Buttons -----------------------------------------------------------------

static func _build_button(theme: Theme) -> void:
	theme.set_stylebox("normal", "Button", _button_box(Palette.bg_raised(), Palette.border_soft()))
	theme.set_stylebox("hover", "Button", _button_box(_lift(Palette.bg_raised()), Palette.border_strong()))
	theme.set_stylebox("pressed", "Button", _button_box(Palette.bg_sunken(), Palette.border_strong()))
	theme.set_stylebox("disabled", "Button", _button_box(_muted_fill(), Palette.border_soft()))
	theme.set_stylebox("focus", "Button", _focus_box())

	theme.set_font("font", "Button", DesignTokens.font(DesignTokens.WEIGHT_MEDIUM))
	theme.set_color("font_color", "Button", Palette.ink_primary())
	theme.set_color("font_hover_color", "Button", Palette.ink_primary())
	theme.set_color("font_pressed_color", "Button", Palette.moss_deep())
	theme.set_color("font_focus_color", "Button", Palette.ink_primary())
	# Disabled text stays well above the "is this even there?" line — a disabled
	# control must still be readable so the player knows what it would do (§74).
	theme.set_color("font_disabled_color", "Button", Palette.ink_muted())
	theme.set_font_size("font_size", "Button", DesignTokens.FONT_BODY)
	theme.set_constant("h_separation", "Button", DesignTokens.SPACE_XS)


# --- Panels ------------------------------------------------------------------

static func _build_panels(theme: Theme) -> void:
	var panel := _surface_box(Palette.bg_raised(), DesignTokens.RADIUS_LG, 1)
	_set_margins(panel, DesignTokens.SPACE_LG)
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel.duplicate())

	theme.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())

	# Dialogs sit above cards, so they get the highest surface and a real lift.
	var window := _surface_box(Palette.surface_high(), DesignTokens.RADIUS_LG, 2)
	_set_margins(window, DesignTokens.SPACE_LG)
	theme.set_stylebox("panel", "PopupPanel", window)


# --- Labels ------------------------------------------------------------------

static func _build_labels(theme: Theme) -> void:
	theme.set_color("font_color", "Label", Palette.ink_primary())
	theme.set_font_size("font_size", "Label", DesignTokens.FONT_BODY)
	theme.set_constant("line_spacing", "Label", DesignTokens.LINE_SPACING)
	theme.set_color("font_color", "RichTextLabel", Palette.ink_primary())
	theme.set_font_size("normal_font_size", "RichTextLabel", DesignTokens.FONT_BODY)
	theme.set_constant("line_separation", "RichTextLabel", DesignTokens.LINE_SPACING)


# --- Inputs ------------------------------------------------------------------

static func _build_inputs(theme: Theme) -> void:
	var normal := _flat(_lift(Palette.bg_raised()), DesignTokens.RADIUS_SM)
	normal.border_color = Palette.border_soft()
	_set_borders(normal, DesignTokens.BORDER_HAIRLINE)
	_set_margins(normal, DesignTokens.SPACE_SM)

	var focused := normal.duplicate() as StyleBoxFlat
	focused.border_color = Palette.moss()
	_set_borders(focused, DesignTokens.BORDER_EMPHASIS)

	theme.set_stylebox("normal", "LineEdit", normal)
	theme.set_stylebox("focus", "LineEdit", focused)
	theme.set_color("font_color", "LineEdit", Palette.ink_primary())
	theme.set_color("font_placeholder_color", "LineEdit", Palette.ink_muted())
	theme.set_color("caret_color", "LineEdit", Palette.moss_deep())
	theme.set_color("selection_color", "LineEdit", Palette.moss_soft())
	theme.set_font_size("font_size", "LineEdit", DesignTokens.FONT_BODY)

	var slider_track := _flat(Palette.track(), DesignTokens.RADIUS_PILL)
	var slider_fill := _flat(Palette.moss(), DesignTokens.RADIUS_PILL)
	theme.set_stylebox("slider", "HSlider", slider_track)
	theme.set_stylebox("grabber_area", "HSlider", slider_fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", slider_fill.duplicate())


# --- Progress ----------------------------------------------------------------

static func _build_progress(theme: Theme) -> void:
	theme.set_stylebox("background", "ProgressBar", _flat(Palette.track(), DesignTokens.RADIUS_PILL))
	theme.set_stylebox("fill", "ProgressBar", _flat(Palette.moss(), DesignTokens.RADIUS_PILL))
	theme.set_color("font_color", "ProgressBar", Palette.ink_secondary())
	theme.set_font_size("font_size", "ProgressBar", DesignTokens.FONT_CAPTION)


# --- Scrollbars --------------------------------------------------------------

static func _build_scrollbars(theme: Theme) -> void:
	for type: String in ["VScrollBar", "HScrollBar"]:
		var track := _flat(Color(0, 0, 0, 0), DesignTokens.RADIUS_PILL)
		var grabber := _flat(Palette.border_strong(), DesignTokens.RADIUS_PILL)
		var grabber_hover := _flat(Palette.ink_muted(), DesignTokens.RADIUS_PILL)
		theme.set_stylebox("scroll", type, track)
		theme.set_stylebox("grabber", type, grabber)
		theme.set_stylebox("grabber_highlight", type, grabber_hover)
		theme.set_stylebox("grabber_pressed", type, grabber_hover.duplicate())


# --- Separators --------------------------------------------------------------

static func _build_separators(theme: Theme) -> void:
	for type: String in ["HSeparator", "VSeparator"]:
		var line := StyleBoxLine.new()
		line.color = Palette.border_hairline()
		line.thickness = DesignTokens.BORDER_HAIRLINE
		line.vertical = type == "VSeparator"
		theme.set_stylebox("separator", type, line)
		theme.set_constant("separation", type, DesignTokens.SPACE_MD)


# --- Tooltips (§50: tooltips must not rely on icons alone) -------------------

static func _build_tooltip(theme: Theme) -> void:
	# The tooltip is always the inverse of the page, in both modes: a dark card in
	# light mode, a light card in dark mode, so it never disappears into the
	# surface it floats over.
	var fill := Palette.ink_primary()
	fill.a = 0.95
	var box := _flat(fill, DesignTokens.RADIUS_SM)
	_set_margins(box, DesignTokens.SPACE_SM)
	theme.set_stylebox("panel", "TooltipPanel", box)
	theme.set_color("font_color", "TooltipLabel", Palette.bg_raised())
	theme.set_font_size("font_size", "TooltipLabel", DesignTokens.FONT_SMALL)


# --- Type variations ---------------------------------------------------------
# Named variants so screens set `theme_type_variation` instead of overriding
# colours locally. Adding a variant here is how new styling enters the app.

static func _build_variations(theme: Theme) -> void:
	_build_primary_button(theme)
	_build_secondary_button(theme)
	_build_subtle_button(theme)
	_build_danger_button(theme)
	_build_nav_button(theme)
	_build_chip(theme)
	_build_surfaces(theme)
	_build_text_roles(theme)


## Primary action — the Start Focus button the home screen is built around (§7).
static func _build_primary_button(theme: Theme) -> void:
	theme.set_type_variation("PrimaryButton", "Button")
	theme.set_stylebox("normal", "PrimaryButton", _button_box(Palette.moss(), Palette.moss()))
	theme.set_stylebox("hover", "PrimaryButton", _button_box(_lift(Palette.moss()), _lift(Palette.moss())))
	theme.set_stylebox("pressed", "PrimaryButton", _button_box(Palette.moss_deep(), Palette.moss_deep()))
	theme.set_stylebox("disabled", "PrimaryButton", _button_box(_muted_fill(), _muted_fill()))
	theme.set_stylebox("focus", "PrimaryButton", _focus_box())
	theme.set_font("font", "PrimaryButton", DesignTokens.font(DesignTokens.WEIGHT_SEMIBOLD))
	for state: String in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		theme.set_color(state, "PrimaryButton", Palette.ink_on_accent())
	theme.set_color("font_disabled_color", "PrimaryButton", Palette.ink_on_disabled())
	theme.set_font_size("font_size", "PrimaryButton", DesignTokens.FONT_HEADING)


## Tonal secondary — the missing middle between a filled primary and a ghost
## button. Screens were reaching for PrimaryButton to make a second action
## visible, which put two competing primaries on the same card.
static func _build_secondary_button(theme: Theme) -> void:
	theme.set_type_variation("SecondaryButton", "Button")
	theme.set_stylebox("normal", "SecondaryButton", _button_box(Palette.accent_subtle(), Color(0, 0, 0, 0)))
	theme.set_stylebox("hover", "SecondaryButton", _button_box(Palette.moss_soft(), Palette.moss()))
	theme.set_stylebox("pressed", "SecondaryButton", _button_box(Palette.moss_soft(), Palette.moss_deep()))
	theme.set_stylebox("disabled", "SecondaryButton", _button_box(_muted_fill(), Color(0, 0, 0, 0)))
	theme.set_stylebox("focus", "SecondaryButton", _focus_box())
	theme.set_font("font", "SecondaryButton", DesignTokens.font(DesignTokens.WEIGHT_MEDIUM))
	theme.set_color("font_color", "SecondaryButton", Palette.moss_deep())
	theme.set_color("font_hover_color", "SecondaryButton", Palette.moss_deep())
	theme.set_color("font_pressed_color", "SecondaryButton", Palette.moss_deep())
	theme.set_color("font_disabled_color", "SecondaryButton", Palette.ink_muted())


## Quiet button — flat until hovered, for tertiary actions.
static func _build_subtle_button(theme: Theme) -> void:
	theme.set_type_variation("SubtleButton", "Button")
	var clear := Color(0, 0, 0, 0)
	theme.set_stylebox("normal", "SubtleButton", _button_box(clear, clear))
	theme.set_stylebox("hover", "SubtleButton", _button_box(Palette.overlay_hover(), clear))
	theme.set_stylebox("pressed", "SubtleButton", _button_box(Palette.bg_sunken(), clear))
	theme.set_stylebox("disabled", "SubtleButton", _button_box(clear, clear))
	theme.set_stylebox("focus", "SubtleButton", _focus_box())
	theme.set_color("font_color", "SubtleButton", Palette.ink_secondary())
	theme.set_color("font_hover_color", "SubtleButton", Palette.ink_primary())
	theme.set_color("font_disabled_color", "SubtleButton", Palette.ink_muted())


## Destructive — reset progress, delete a layout (§35 strong confirmation).
static func _build_danger_button(theme: Theme) -> void:
	theme.set_type_variation("DangerButton", "Button")
	var wash := Palette.clay()
	wash.a = 0.14
	theme.set_stylebox("normal", "DangerButton", _button_box(wash, Palette.clay()))
	theme.set_stylebox("hover", "DangerButton", _button_box(Palette.clay(), Palette.clay()))
	theme.set_stylebox("pressed", "DangerButton", _button_box(_deepen(Palette.clay()), _deepen(Palette.clay())))
	theme.set_stylebox("disabled", "DangerButton", _button_box(_muted_fill(), Palette.border_soft()))
	theme.set_stylebox("focus", "DangerButton", _focus_box())
	theme.set_font("font", "DangerButton", DesignTokens.font(DesignTokens.WEIGHT_MEDIUM))
	theme.set_color("font_color", "DangerButton", Palette.clay())
	theme.set_color("font_hover_color", "DangerButton", Palette.ink_on_accent())
	theme.set_color("font_pressed_color", "DangerButton", Palette.ink_on_accent())
	theme.set_color("font_disabled_color", "DangerButton", Palette.ink_muted())


## Navigation rail entries. The selected one is a filled pill with an accent bar
## down its leading edge, so the current section is legible by shape as well as
## by colour (§50).
static func _build_nav_button(theme: Theme) -> void:
	theme.set_type_variation("NavButton", "Button")
	var clear := Color(0, 0, 0, 0)

	var normal := _nav_box(clear, clear)
	var hover := _nav_box(Palette.bg_nav_active(), clear)
	var active := _nav_box(Palette.bg_nav_active(), Palette.moss())
	active.border_width_left = 3

	theme.set_stylebox("normal", "NavButton", normal)
	theme.set_stylebox("hover", "NavButton", hover)
	theme.set_stylebox("pressed", "NavButton", active)
	theme.set_stylebox("hover_pressed", "NavButton", active.duplicate())
	theme.set_stylebox("focus", "NavButton", _focus_box())

	theme.set_color("font_color", "NavButton", Palette.ink_on_nav_muted())
	theme.set_color("font_hover_color", "NavButton", Palette.ink_on_nav())
	theme.set_color("font_pressed_color", "NavButton", Palette.ink_on_nav())
	theme.set_color("font_hover_pressed_color", "NavButton", Palette.ink_on_nav())
	theme.set_font("font", "NavButton", DesignTokens.font(DesignTokens.WEIGHT_MEDIUM))
	theme.set_font_size("font_size", "NavButton", DesignTokens.FONT_BODY)


## Chips — mutually exclusive choices (durations, projects, colours). Pill-shaped
## and quiet until selected, so a row of them reads as options rather than as a
## row of competing buttons.
static func _build_chip(theme: Theme) -> void:
	theme.set_type_variation("Chip", "Button")
	theme.set_stylebox("normal", "Chip", _chip_box(Color(0, 0, 0, 0), Palette.border_strong()))
	theme.set_stylebox("hover", "Chip", _chip_box(Palette.overlay_hover(), Palette.border_strong()))
	theme.set_stylebox("pressed", "Chip", _chip_box(Palette.moss(), Palette.moss()))
	theme.set_stylebox("hover_pressed", "Chip", _chip_box(_lift(Palette.moss()), Palette.moss()))
	theme.set_stylebox("disabled", "Chip", _chip_box(Color(0, 0, 0, 0), Palette.border_soft()))
	theme.set_stylebox("focus", "Chip", _focus_box())
	theme.set_color("font_color", "Chip", Palette.ink_secondary())
	theme.set_color("font_hover_color", "Chip", Palette.ink_primary())
	# A selected chip is filled with moss, so its label must flip.
	theme.set_color("font_pressed_color", "Chip", Palette.ink_on_accent())
	theme.set_color("font_hover_pressed_color", "Chip", Palette.ink_on_accent())
	theme.set_color("font_disabled_color", "Chip", Palette.ink_muted())
	theme.set_font("font", "Chip", DesignTokens.font(DesignTokens.WEIGHT_MEDIUM))
	theme.set_font_size("font_size", "Chip", DesignTokens.FONT_SMALL)


## Card and panel surfaces (§4).
static func _build_surfaces(theme: Theme) -> void:
	theme.set_type_variation("Card", "PanelContainer")
	var card := _surface_box(Palette.bg_raised(), DesignTokens.RADIUS_LG, 1)
	_set_margins(card, DesignTokens.SPACE_LG)
	theme.set_stylebox("panel", "Card", card)

	# A card with no padding of its own, for one that hosts a full-bleed drawing
	# such as the shelf or the garden plot.
	theme.set_type_variation("CardFlush", "PanelContainer")
	var flush := _surface_box(Palette.bg_raised(), DesignTokens.RADIUS_LG, 1)
	_set_margins(flush, 0)
	theme.set_stylebox("panel", "CardFlush", flush)

	theme.set_type_variation("CardSunken", "PanelContainer")
	var sunken := _flat(Palette.bg_sunken(), DesignTokens.RADIUS_MD)
	sunken.border_color = Palette.border_hairline()
	_set_borders(sunken, DesignTokens.BORDER_HAIRLINE)
	_set_margins(sunken, DesignTokens.SPACE_MD)
	theme.set_stylebox("panel", "CardSunken", sunken)

	theme.set_type_variation("NavPanel", "PanelContainer")
	var nav_panel := _flat(Palette.bg_nav(), 0)
	_set_margins(nav_panel, DesignTokens.SPACE_MD)
	theme.set_stylebox("panel", "NavPanel", nav_panel)

	# Rarity and status pills. The fill colour is set per instance; this supplies
	# only the shape and padding, so every badge in the app is the same pill.
	theme.set_type_variation("Badge", "PanelContainer")
	var badge := _flat(Palette.bg_sunken(), DesignTokens.RADIUS_PILL)
	badge.content_margin_left = DesignTokens.SPACE_XS
	badge.content_margin_right = DesignTokens.SPACE_XS
	badge.content_margin_top = 2
	badge.content_margin_bottom = 2
	theme.set_stylebox("panel", "Badge", badge)


static func _build_text_roles(theme: Theme) -> void:
	_label_variation(theme, "Display", DesignTokens.FONT_DISPLAY, Palette.ink_primary(), DesignTokens.WEIGHT_SEMIBOLD)
	_label_variation(theme, "Title", DesignTokens.FONT_TITLE, Palette.ink_primary(), DesignTokens.WEIGHT_SEMIBOLD)
	_label_variation(theme, "Heading", DesignTokens.FONT_HEADING, Palette.ink_primary(), DesignTokens.WEIGHT_SEMIBOLD)
	_label_variation(theme, "Caption", DesignTokens.FONT_CAPTION, Palette.ink_muted())
	_label_variation(theme, "Muted", DesignTokens.FONT_BODY, Palette.ink_secondary())
	# Card titles sit between body and heading: large enough to lead the card,
	# small enough that a two-word species name fits a grid column.
	_label_variation(theme, "CardTitle", DesignTokens.FONT_BODY, Palette.ink_primary(), DesignTokens.WEIGHT_SEMIBOLD)
	# Eyebrow: the small spaced label above a section heading. Call sites supply
	# uppercase text; the tracking is what stops it reading as shouting.
	_label_variation(theme, "Eyebrow", DesignTokens.FONT_LABEL, Palette.ink_muted(), DesignTokens.WEIGHT_SEMIBOLD)

	# The focus countdown — the largest type in the game (§10 "large readable
	# countdown"), in tabular figures so the digits do not shuffle as it counts.
	theme.set_type_variation("Countdown", "Label")
	theme.set_font("font", "Countdown", DesignTokens.font(DesignTokens.WEIGHT_MEDIUM, true))
	theme.set_font_size("font_size", "Countdown", DesignTokens.FONT_COUNTDOWN)
	theme.set_color("font_color", "Countdown", Palette.ink_primary())

	# Text roles for the sage rail. The ordinary roles are dark ink and would be
	# unreadable there, so the rail gets its own pair rather than every call site
	# overriding a colour by hand.
	_label_variation(theme, "NavBrand", DesignTokens.FONT_HEADING, Palette.ink_on_nav(), DesignTokens.WEIGHT_SEMIBOLD)
	_label_variation(theme, "NavCaption", DesignTokens.FONT_CAPTION, Palette.ink_on_nav_muted())


static func _label_variation(
	theme: Theme, name: String, size: int, color: Color, weight: int = DesignTokens.WEIGHT_REGULAR
) -> void:
	theme.set_type_variation(name, "Label")
	theme.set_font("font", name, DesignTokens.font(weight))
	theme.set_font_size("font_size", name, size)
	theme.set_color("font_color", name, color)


# --- Stylebox helpers --------------------------------------------------------

static func _flat(color: Color, radius: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.corner_radius_top_left = radius
	box.corner_radius_top_right = radius
	box.corner_radius_bottom_left = radius
	box.corner_radius_bottom_right = radius
	# Godot's stylebox anti-aliasing keeps rounded corners from looking ragged at
	# fractional DPI scales, which §5 requires us to support.
	box.anti_aliasing = true
	return box


## A raised surface: fill, hairline border and the ambient shadow layer for its
## elevation level. StyleBoxFlat supports one shadow, so the ambient layer is the
## one it gets — that is the layer doing the work of separating a card from the
## page, and the key layer sharpens an edge a stylebox cannot draw anyway.
static func _surface_box(fill: Color, radius: int, elevation: int) -> StyleBoxFlat:
	var box := _flat(fill, radius)
	box.border_color = Palette.border_hairline()
	_set_borders(box, DesignTokens.BORDER_HAIRLINE)
	var level := clampi(elevation, 0, DesignTokens.ELEVATION_AMBIENT_SIZE.size() - 1)
	box.shadow_color = Palette.shadow_ambient()
	box.shadow_size = DesignTokens.ELEVATION_AMBIENT_SIZE[level]
	box.shadow_offset = Vector2(0, DesignTokens.ELEVATION_KEY_OFFSET[level])
	return box


static func _chip_box(fill: Color, border: Color) -> StyleBoxFlat:
	var box := _flat(fill, DesignTokens.RADIUS_PILL)
	box.border_color = border
	_set_borders(box, DesignTokens.BORDER_HAIRLINE)
	box.content_margin_left = DesignTokens.SPACE_MD
	box.content_margin_right = DesignTokens.SPACE_MD
	box.content_margin_top = DesignTokens.SPACE_XS
	box.content_margin_bottom = DesignTokens.SPACE_XS
	return box


static func _button_box(fill: Color, border: Color) -> StyleBoxFlat:
	var box := _flat(fill, DesignTokens.RADIUS_SM)
	box.border_color = border
	_set_borders(box, DesignTokens.BORDER_HAIRLINE)
	box.content_margin_left = DesignTokens.SPACE_MD
	box.content_margin_right = DesignTokens.SPACE_MD
	box.content_margin_top = DesignTokens.SPACE_SM
	box.content_margin_bottom = DesignTokens.SPACE_SM
	return box


## A rail entry. The accent colour becomes a bar down the leading edge only, so
## the selected item is marked without boxing it in.
static func _nav_box(fill: Color, accent: Color) -> StyleBoxFlat:
	var box := _flat(fill, DesignTokens.RADIUS_SM)
	box.border_color = accent
	_set_borders(box, 0)
	_set_margins(box, DesignTokens.SPACE_SM)
	box.content_margin_left = DesignTokens.SPACE_MD
	return box


## Keyboard focus indicator (§50). Drawn as an outset ring so it reads clearly
## against both filled and transparent buttons.
static func _focus_box() -> StyleBoxFlat:
	var box := _flat(Color(0, 0, 0, 0), DesignTokens.RADIUS_SM)
	box.border_color = Palette.focus_ring()
	_set_borders(box, DesignTokens.BORDER_EMPHASIS)
	box.expand_margin_left = 2
	box.expand_margin_right = 2
	box.expand_margin_top = 2
	box.expand_margin_bottom = 2
	return box


static func _set_borders(box: StyleBoxFlat, width: int) -> void:
	box.border_width_left = width
	box.border_width_right = width
	box.border_width_top = width
	box.border_width_bottom = width


static func _set_margins(box: StyleBoxFlat, margin: int) -> void:
	box.content_margin_left = margin
	box.content_margin_right = margin
	box.content_margin_top = margin
	box.content_margin_bottom = margin


## Hover state for a filled surface. Both modes move the surface toward the light,
## which is what a hover should feel like; the amounts differ because a dark
## surface needs more of a change to register at all.
static func _lift(color: Color) -> Color:
	return color.lightened(0.12 if Palette.is_dark() else 0.045)


static func _deepen(color: Color) -> Color:
	return color.darkened(0.18)


## Fill for a disabled control: the sunken surface nudged toward the ink, so it
## reads as inert without disappearing into the card it sits on.
static func _muted_fill() -> Color:
	return Palette.bg_sunken().lerp(Palette.ink_muted(), 0.12)
