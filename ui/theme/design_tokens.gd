class_name DesignTokens
extends RefCounted
## The single source of truth for everything visual that does NOT change between
## light and dark (§4): spacing, radii, type, motion, elevation and layout.
##
## §4 requires a central reusable theme rather than per-screen styling. This file
## and `Palette` are that centre, split along the one axis that matters: colours
## depend on the appearance mode and live in `Palette`; sizes and timings do not
## and live here. ThemeBuilder turns both into the Theme resources Godot applies.
##
## Nothing in the codebase may hardcode a spacing value or a duration. If a screen
## needs a gap that is not here, the right move is to add a token, not a literal —
## that is what keeps §74's "spacing is consistent, typography is consistent" true
## as screens are added by different hands over time.

# --- Typography ---------------------------------------------------------------
## Font families, most preferred first. No typeface is bundled (§73 keeps the
## repo free of licensed assets), so the theme asks the OS for a modern UI face
## and falls back through a chain that ends at something every system has.
## Resolved at runtime by SystemFont, which costs nothing and needs no import.
const FONT_FAMILIES: Array[String] = [
	"Segoe UI Variable Text",
	"Segoe UI",
	"Inter",
	"Noto Sans",
	"Open Sans",
	"DejaVu Sans",
]

## Weights, on the OpenType 100–900 scale.
const WEIGHT_REGULAR: int = 400
const WEIGHT_MEDIUM: int = 500
const WEIGHT_SEMIBOLD: int = 600

# --- Type scale ---------------------------------------------------------------
## A restrained scale. Fewer, more distinct steps read as more designed than many
## near-identical ones, which is what made the old six-size ramp feel flat.
const FONT_COUNTDOWN: int = 88 ## The focus countdown — deliberately the largest thing on screen.
const FONT_DISPLAY: int = 42
const FONT_TITLE: int = 26
const FONT_HEADING: int = 18
const FONT_BODY: int = 15
const FONT_SMALL: int = 13
const FONT_CAPTION: int = 12
## Eyebrow labels above a section: small, spaced, uppercase at the call site.
const FONT_LABEL: int = 11

## Extra pixels between lines, added to the font's own line height. Godot's
## default is tight enough that paragraphs read as a block.
const LINE_SPACING: int = 4
## Tracking for eyebrow labels, in pixels.
const LETTER_SPACING_LABEL: int = 1

# --- Motion (§43, §50) --------------------------------------------------------
## Base durations in seconds. These are raw constants — they do NOT account for
## the player's reduced-motion or animation-intensity settings. Always run them
## through `Motion.duration()`, which owns that policy. Keeping tokens free of
## any dependency on player state is what lets this file stay a pure constants
## table that anything (including tools and tests) can read.
const DURATION_INSTANT: float = 0.08
const DURATION_FAST: float = 0.15
const DURATION_NORMAL: float = 0.25
const DURATION_SLOW: float = 0.4

# --- Spacing scale ------------------------------------------------------------
## A 4px base grid. Screens compose from these rather than inventing gaps.
const SPACE_XXS: int = 4
const SPACE_XS: int = 8
const SPACE_SM: int = 12
const SPACE_MD: int = 16
const SPACE_LG: int = 24
const SPACE_XL: int = 32
const SPACE_XXL: int = 48

# --- Corner radii -------------------------------------------------------------
const RADIUS_SM: int = 8
const RADIUS_MD: int = 12
const RADIUS_LG: int = 18
const RADIUS_PILL: int = 999

# --- Elevation ----------------------------------------------------------------
## Two-layer shadows, indexed by level. A single flat shadow reads as a sticker;
## a wide ambient layer plus a tight offset key layer reads as something lifted
## off the page. Level 0 is flush, 1 is a card, 2 is a dialog or a dragged item.
##
## Godot's StyleBoxFlat supports only one shadow, so ThemeBuilder renders the
## ambient layer and custom `_draw` code uses both — see `Elevation` helpers there.
const ELEVATION_AMBIENT_SIZE: Array[int] = [0, 10, 22]
const ELEVATION_KEY_SIZE: Array[int] = [0, 3, 8]
const ELEVATION_KEY_OFFSET: Array[int] = [0, 2, 6]

# --- Layout -------------------------------------------------------------------
const NAV_RAIL_WIDTH: int = 232
const CONTENT_MAX_WIDTH: int = 1180
const MIN_WINDOW_SIZE := Vector2i(1280, 720)
## Hairline and emphasis border widths, so no stylebox invents its own.
const BORDER_HAIRLINE: int = 1
const BORDER_EMPHASIS: int = 2


## The interface font at a given weight. Built fresh per call site rather than
## cached, because Godot shares the underlying face internally and a FontVariation
## is a thin wrapper.
static func font(weight: int = WEIGHT_REGULAR, tabular_figures: bool = false) -> FontVariation:
	var system := SystemFont.new()
	system.font_names = PackedStringArray(FONT_FAMILIES)
	system.subpixel_positioning = TextServer.SUBPIXEL_POSITIONING_AUTO

	var variation := FontVariation.new()
	variation.base_font = system
	variation.variation_embolden = _embolden_for(weight)
	if tabular_figures:
		# Fixed-width digits, so a counting-down timer does not jitter as digits
		# change. This is why the countdown no longer needs a fixed-width box.
		variation.opentype_features = {"tnum": 1}
	return variation


## Synthetic weight, as a fraction of the em. Real variable-font axes are only
## available when the resolved family actually has them; emboldening works with
## every fallback in the chain, so the heading weight is never silently lost.
static func _embolden_for(weight: int) -> float:
	if weight >= WEIGHT_SEMIBOLD:
		return 0.4
	if weight >= WEIGHT_MEDIUM:
		return 0.2
	return 0.0
