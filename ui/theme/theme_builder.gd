class_name ThemeBuilder
extends RefCounted
## Builds the game's Theme resource from DesignTokens.
##
## The theme is GENERATED rather than hand-authored as a .tres. A Theme file with
## every stylebox spelled out is thousands of unreviewable lines, and it drifts
## from the tokens the moment someone edits it in the inspector. Generating it
## keeps DesignTokens as the only place a colour is decided (§4).
##
## `tools/bake_theme.gd` runs this and writes ui/theme/focus_garden.tres, which is
## committed and referenced by project.godot so the EDITOR previews correctly too.
## Re-run the bake after changing any token:
##     tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless --path . \
##         --script res://tools/bake_theme.gd
##
## §74 requires every button to have hover, pressed, focus and disabled states.
## They are defined here once, so no screen can ship a button that silently lacks
## feedback.


static func build() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = DesignTokens.FONT_BODY

	_build_button(theme)
	_build_panels(theme)
	_build_labels(theme)
	_build_inputs(theme)
	_build_progress(theme)
	_build_scrollbars(theme)
	_build_tooltip(theme)
	_build_variations(theme)
	return theme


# --- Buttons -----------------------------------------------------------------

static func _build_button(theme: Theme) -> void:
	theme.set_stylebox("normal", "Button", _button_box(DesignTokens.BG_RAISED, DesignTokens.BORDER_SOFT))
	theme.set_stylebox("hover", "Button", _button_box(Color("#FFFCF4"), DesignTokens.BORDER_STRONG))
	theme.set_stylebox("pressed", "Button", _button_box(DesignTokens.BG_SUNKEN, DesignTokens.BORDER_STRONG))
	theme.set_stylebox("disabled", "Button", _button_box(Color("#EDE6D6"), Color("#E0D6C0")))
	theme.set_stylebox("focus", "Button", _focus_box())

	theme.set_color("font_color", "Button", DesignTokens.INK_PRIMARY)
	theme.set_color("font_hover_color", "Button", DesignTokens.INK_PRIMARY)
	theme.set_color("font_pressed_color", "Button", DesignTokens.MOSS_DEEP)
	theme.set_color("font_focus_color", "Button", DesignTokens.INK_PRIMARY)
	# Disabled text stays well above the "is this even there?" line — a disabled
	# control must still be readable so the player knows what it would do (§74).
	theme.set_color("font_disabled_color", "Button", DesignTokens.INK_MUTED)
	theme.set_font_size("font_size", "Button", DesignTokens.FONT_BODY)
	theme.set_constant("h_separation", "Button", DesignTokens.SPACE_XS)


# --- Panels ------------------------------------------------------------------

static func _build_panels(theme: Theme) -> void:
	var panel := _flat(DesignTokens.BG_RAISED, DesignTokens.RADIUS_LG)
	panel.border_color = DesignTokens.BORDER_SOFT
	_set_borders(panel, 1)
	_set_margins(panel, DesignTokens.SPACE_LG)
	_set_shadow(panel)
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel.duplicate())

	var scroll := StyleBoxEmpty.new()
	theme.set_stylebox("panel", "ScrollContainer", scroll)


# --- Labels ------------------------------------------------------------------

static func _build_labels(theme: Theme) -> void:
	theme.set_color("font_color", "Label", DesignTokens.INK_PRIMARY)
	theme.set_font_size("font_size", "Label", DesignTokens.FONT_BODY)
	theme.set_color("font_color", "RichTextLabel", DesignTokens.INK_PRIMARY)
	theme.set_font_size("normal_font_size", "RichTextLabel", DesignTokens.FONT_BODY)


# --- Inputs ------------------------------------------------------------------

static func _build_inputs(theme: Theme) -> void:
	var normal := _flat(Color("#FFFCF4"), DesignTokens.RADIUS_MD)
	normal.border_color = DesignTokens.BORDER_SOFT
	_set_borders(normal, 1)
	_set_margins(normal, DesignTokens.SPACE_SM)

	var focused := normal.duplicate() as StyleBoxFlat
	focused.border_color = DesignTokens.MOSS
	_set_borders(focused, 2)

	theme.set_stylebox("normal", "LineEdit", normal)
	theme.set_stylebox("focus", "LineEdit", focused)
	theme.set_color("font_color", "LineEdit", DesignTokens.INK_PRIMARY)
	theme.set_color("font_placeholder_color", "LineEdit", DesignTokens.INK_MUTED)
	theme.set_color("caret_color", "LineEdit", DesignTokens.MOSS_DEEP)
	theme.set_color("selection_color", "LineEdit", DesignTokens.MOSS_SOFT)
	theme.set_font_size("font_size", "LineEdit", DesignTokens.FONT_BODY)

	var slider_track := _flat(DesignTokens.TRACK, DesignTokens.RADIUS_PILL)
	var slider_fill := _flat(DesignTokens.MOSS, DesignTokens.RADIUS_PILL)
	theme.set_stylebox("slider", "HSlider", slider_track)
	theme.set_stylebox("grabber_area", "HSlider", slider_fill)
	theme.set_stylebox("grabber_area_highlight", "HSlider", slider_fill.duplicate())


# --- Progress ----------------------------------------------------------------

static func _build_progress(theme: Theme) -> void:
	var background := _flat(DesignTokens.TRACK, DesignTokens.RADIUS_PILL)
	var fill := _flat(DesignTokens.MOSS, DesignTokens.RADIUS_PILL)
	theme.set_stylebox("background", "ProgressBar", background)
	theme.set_stylebox("fill", "ProgressBar", fill)
	theme.set_color("font_color", "ProgressBar", DesignTokens.INK_SECONDARY)
	theme.set_font_size("font_size", "ProgressBar", DesignTokens.FONT_CAPTION)


# --- Scrollbars --------------------------------------------------------------

static func _build_scrollbars(theme: Theme) -> void:
	for type: String in ["VScrollBar", "HScrollBar"]:
		var track := _flat(Color("#00000000"), DesignTokens.RADIUS_PILL)
		var grabber := _flat(DesignTokens.BORDER_STRONG, DesignTokens.RADIUS_PILL)
		var grabber_hover := _flat(DesignTokens.INK_MUTED, DesignTokens.RADIUS_PILL)
		theme.set_stylebox("scroll", type, track)
		theme.set_stylebox("grabber", type, grabber)
		theme.set_stylebox("grabber_highlight", type, grabber_hover)
		theme.set_stylebox("grabber_pressed", type, grabber_hover.duplicate())


# --- Tooltips (§50: tooltips must not rely on icons alone) -------------------

static func _build_tooltip(theme: Theme) -> void:
	var box := _flat(Color("#3B342AF2"), DesignTokens.RADIUS_MD)
	_set_margins(box, DesignTokens.SPACE_SM)
	theme.set_stylebox("panel", "TooltipPanel", box)
	theme.set_color("font_color", "TooltipLabel", Color("#FBF6EA"))
	theme.set_font_size("font_size", "TooltipLabel", DesignTokens.FONT_SMALL)


# --- Type variations ---------------------------------------------------------
# Named variants so screens set `theme_type_variation` instead of overriding
# colours locally. Adding a variant here is how new styling enters the app.

static func _build_variations(theme: Theme) -> void:
	# Primary action — the Start Focus button the home screen is built around (§7).
	theme.set_type_variation("PrimaryButton", "Button")
	theme.set_stylebox("normal", "PrimaryButton", _button_box(DesignTokens.MOSS, DesignTokens.MOSS_DEEP))
	theme.set_stylebox("hover", "PrimaryButton", _button_box(Color("#6A9B61"), DesignTokens.MOSS_DEEP))
	theme.set_stylebox("pressed", "PrimaryButton", _button_box(DesignTokens.MOSS_DEEP, DesignTokens.MOSS_DEEP))
	theme.set_stylebox("disabled", "PrimaryButton", _button_box(Color("#B3C6AE"), Color("#A6BCA1")))
	theme.set_stylebox("focus", "PrimaryButton", _focus_box())
	theme.set_color("font_color", "PrimaryButton", DesignTokens.INK_ON_ACCENT)
	theme.set_color("font_hover_color", "PrimaryButton", DesignTokens.INK_ON_ACCENT)
	theme.set_color("font_pressed_color", "PrimaryButton", DesignTokens.INK_ON_ACCENT)
	theme.set_color("font_focus_color", "PrimaryButton", DesignTokens.INK_ON_ACCENT)
	theme.set_color("font_disabled_color", "PrimaryButton", DesignTokens.INK_ON_DISABLED)
	theme.set_font_size("font_size", "PrimaryButton", DesignTokens.FONT_HEADING)

	# Quiet button — flat until hovered, for secondary actions.
	theme.set_type_variation("SubtleButton", "Button")
	theme.set_stylebox("normal", "SubtleButton", _button_box(Color("#00000000"), Color("#00000000")))
	theme.set_stylebox("hover", "SubtleButton", _button_box(Color("#E6DCC7A0"), Color("#00000000")))
	theme.set_stylebox("pressed", "SubtleButton", _button_box(DesignTokens.BG_SUNKEN, Color("#00000000")))
	theme.set_stylebox("disabled", "SubtleButton", _button_box(Color("#00000000"), Color("#00000000")))
	theme.set_stylebox("focus", "SubtleButton", _focus_box())
	theme.set_color("font_color", "SubtleButton", DesignTokens.INK_SECONDARY)
	theme.set_color("font_hover_color", "SubtleButton", DesignTokens.INK_PRIMARY)
	theme.set_color("font_disabled_color", "SubtleButton", DesignTokens.INK_MUTED)

	# Destructive — reset progress, delete a layout (§35 strong confirmation).
	theme.set_type_variation("DangerButton", "Button")
	theme.set_stylebox("normal", "DangerButton", _button_box(Color("#F3E2DC"), DesignTokens.CLAY))
	theme.set_stylebox("hover", "DangerButton", _button_box(DesignTokens.CLAY, DesignTokens.CLAY))
	theme.set_stylebox("pressed", "DangerButton", _button_box(Color("#96412D"), Color("#96412D")))
	theme.set_stylebox("disabled", "DangerButton", _button_box(Color("#EDE6D6"), Color("#E0D6C0")))
	theme.set_stylebox("focus", "DangerButton", _focus_box())
	theme.set_color("font_color", "DangerButton", DesignTokens.CLAY)
	theme.set_color("font_hover_color", "DangerButton", DesignTokens.INK_ON_ACCENT)
	theme.set_color("font_pressed_color", "DangerButton", DesignTokens.INK_ON_ACCENT)
	theme.set_color("font_disabled_color", "DangerButton", DesignTokens.INK_MUTED)

	# Navigation rail entries.
	theme.set_type_variation("NavButton", "Button")
	var nav_normal := _button_box(Color("#00000000"), Color("#00000000"))
	_set_margins(nav_normal, DesignTokens.SPACE_SM)
	nav_normal.content_margin_left = DesignTokens.SPACE_MD
	var nav_hover := _button_box(DesignTokens.BG_NAV_ACTIVE, Color("#00000000"))
	_set_margins(nav_hover, DesignTokens.SPACE_SM)
	nav_hover.content_margin_left = DesignTokens.SPACE_MD
	# The selected entry is a lit panel against the sage wall, echoing how the
	# content area reads as lamplit next to the rail.
	var nav_active := _button_box(DesignTokens.BG_RAISED, Color("#00000000"))
	_set_margins(nav_active, DesignTokens.SPACE_SM)
	nav_active.content_margin_left = DesignTokens.SPACE_MD
	theme.set_stylebox("normal", "NavButton", nav_normal)
	theme.set_stylebox("hover", "NavButton", nav_hover)
	theme.set_stylebox("pressed", "NavButton", nav_active)
	theme.set_stylebox("focus", "NavButton", _focus_box())
	# Cream on sage at rest; the selected entry flips to dark ink because its
	# background became the light card colour.
	theme.set_color("font_color", "NavButton", DesignTokens.INK_ON_NAV)
	theme.set_color("font_hover_color", "NavButton", DesignTokens.INK_ON_ACCENT)
	theme.set_color("font_pressed_color", "NavButton", DesignTokens.MOSS_DEEP)
	theme.set_color("font_hover_pressed_color", "NavButton", DesignTokens.MOSS_DEEP)
	theme.set_font_size("font_size", "NavButton", DesignTokens.FONT_BODY)

	# Chips — mutually exclusive choices (durations, projects, colours).
	# Pill-shaped and quiet until selected, so a row of them reads as options
	# rather than as a row of competing buttons.
	theme.set_type_variation("Chip", "Button")
	var chip_normal := _chip_box(Color("#00000000"), DesignTokens.BORDER_STRONG)
	var chip_hover := _chip_box(Color("#FFFCF4"), DesignTokens.BORDER_STRONG)
	var chip_on := _chip_box(DesignTokens.MOSS, DesignTokens.MOSS_DEEP)
	theme.set_stylebox("normal", "Chip", chip_normal)
	theme.set_stylebox("hover", "Chip", chip_hover)
	theme.set_stylebox("pressed", "Chip", chip_on)
	theme.set_stylebox("disabled", "Chip", _chip_box(Color("#00000000"), Color("#E0D6C0")))
	theme.set_stylebox("focus", "Chip", _focus_box())
	theme.set_color("font_color", "Chip", DesignTokens.INK_SECONDARY)
	theme.set_color("font_hover_color", "Chip", DesignTokens.INK_PRIMARY)
	# A selected chip is filled with moss, so its label must flip to light.
	theme.set_color("font_pressed_color", "Chip", DesignTokens.INK_ON_ACCENT)
	theme.set_color("font_hover_pressed_color", "Chip", DesignTokens.INK_ON_ACCENT)
	theme.set_color("font_disabled_color", "Chip", DesignTokens.INK_MUTED)
	theme.set_font_size("font_size", "Chip", DesignTokens.FONT_SMALL)

	# The focus countdown — the largest type in the game (§10 "large readable
	# countdown"). Tabular figures are not available without a custom font, so
	# the label is centred in a fixed-width container instead of relying on
	# digit widths matching.
	theme.set_type_variation("Countdown", "Label")
	theme.set_font_size("font_size", "Countdown", DesignTokens.FONT_COUNTDOWN)
	theme.set_color("font_color", "Countdown", DesignTokens.INK_PRIMARY)

	# Cards (§4).
	theme.set_type_variation("Card", "PanelContainer")
	var card := _flat(DesignTokens.BG_RAISED, DesignTokens.RADIUS_LG)
	card.border_color = DesignTokens.BORDER_SOFT
	_set_borders(card, 1)
	_set_margins(card, DesignTokens.SPACE_LG)
	_set_shadow(card)
	theme.set_stylebox("panel", "Card", card)

	theme.set_type_variation("CardSunken", "PanelContainer")
	var sunken := _flat(DesignTokens.BG_SUNKEN, DesignTokens.RADIUS_MD)
	_set_margins(sunken, DesignTokens.SPACE_MD)
	theme.set_stylebox("panel", "CardSunken", sunken)

	theme.set_type_variation("NavPanel", "PanelContainer")
	var nav_panel := _flat(DesignTokens.BG_NAV, 0)
	_set_margins(nav_panel, DesignTokens.SPACE_MD)
	theme.set_stylebox("panel", "NavPanel", nav_panel)

	# Text roles.
	_label_variation(theme, "Display", DesignTokens.FONT_DISPLAY, DesignTokens.INK_PRIMARY)
	_label_variation(theme, "Title", DesignTokens.FONT_TITLE, DesignTokens.INK_PRIMARY)
	_label_variation(theme, "Heading", DesignTokens.FONT_HEADING, DesignTokens.INK_PRIMARY)
	_label_variation(theme, "Caption", DesignTokens.FONT_CAPTION, DesignTokens.INK_MUTED)
	_label_variation(theme, "Muted", DesignTokens.FONT_BODY, DesignTokens.INK_SECONDARY)
	# Card titles sit between body and heading: large enough to lead the card,
	# small enough that a two-word species name fits a grid column.
	_label_variation(theme, "CardTitle", DesignTokens.FONT_BODY, DesignTokens.INK_PRIMARY)

	# Text roles for the sage rail. The ordinary roles are dark ink and would be
	# unreadable there, so the rail gets its own pair rather than every call site
	# overriding a colour by hand.
	_label_variation(theme, "NavBrand", DesignTokens.FONT_HEADING, DesignTokens.INK_ON_NAV)
	_label_variation(theme, "NavCaption", DesignTokens.FONT_CAPTION, DesignTokens.INK_ON_NAV_MUTED)


static func _label_variation(theme: Theme, name: String, size: int, color: Color) -> void:
	theme.set_type_variation(name, "Label")
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


static func _chip_box(fill: Color, border: Color) -> StyleBoxFlat:
	var box := _flat(fill, DesignTokens.RADIUS_PILL)
	box.border_color = border
	_set_borders(box, 1)
	box.content_margin_left = DesignTokens.SPACE_MD
	box.content_margin_right = DesignTokens.SPACE_MD
	box.content_margin_top = DesignTokens.SPACE_XS
	box.content_margin_bottom = DesignTokens.SPACE_XS
	return box


static func _button_box(fill: Color, border: Color) -> StyleBoxFlat:
	var box := _flat(fill, DesignTokens.RADIUS_MD)
	box.border_color = border
	_set_borders(box, 1)
	box.content_margin_left = DesignTokens.SPACE_MD
	box.content_margin_right = DesignTokens.SPACE_MD
	box.content_margin_top = DesignTokens.SPACE_SM
	box.content_margin_bottom = DesignTokens.SPACE_SM
	return box


## Keyboard focus indicator (§50). Drawn as an outset ring so it reads clearly
## against both filled and transparent buttons.
static func _focus_box() -> StyleBoxFlat:
	var box := _flat(Color("#00000000"), DesignTokens.RADIUS_MD)
	box.border_color = DesignTokens.FOCUS_RING
	_set_borders(box, 2)
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


static func _set_shadow(box: StyleBoxFlat) -> void:
	box.shadow_color = DesignTokens.SHADOW
	box.shadow_size = 6
	box.shadow_offset = Vector2(0, 2)
