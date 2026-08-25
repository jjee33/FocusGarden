class_name Palette
extends RefCounted
## Every colour in Focus Garden, in both light and dark (§4, §50).
##
## WHY THIS IS NOT PART OF DesignTokens: a colour now depends on the active
## appearance mode, so it cannot be a `const`. DesignTokens keeps everything that
## is mode-independent — spacing, radii, type scale, motion, layout — and this
## file owns everything that changes between light and dark.
##
## THE RULE: no `_draw` implementation, stylebox or screen may write a literal
## `Color("#...")`. Every colour comes from a getter here. That is what makes a
## second palette possible at all — the light theme was originally spread across
## twenty files as hex literals, and every one of them would have had to be found
## by eye.
##
## Accessors are typed static functions rather than a string-keyed dictionary so
## that a token renamed here breaks the build at every call site instead of
## silently resolving to a fallback colour at runtime.
##
## PALETTE INTENT (§4): the interior of a small plant shop at golden hour.
## The navigation rail is the deep sage wall, the content area is warm light wood
## and paper, accents are terracotta pots and amber lantern glow. Dark mode is
## the same shop after closing: the light goes, the warmth does not, so the dark
## surfaces are warm charcoal-green rather than neutral black.

enum Mode { LIGHT, DARK }

const MODE_LIGHT: String = "light"
const MODE_DARK: String = "dark"


## One complete set of colours. Fields, not a dictionary, so a missing token is a
## compile error rather than a silent fallback.
class Colors extends RefCounted:
	# --- Surfaces ---
	var bg_base: Color             ## App background.
	var bg_sunken: Color           ## Recessed wells, track backgrounds.
	var bg_raised: Color           ## Cards and panels that sit above the page.
	var surface_high: Color        ## Dialogs and popovers, above cards.
	var bg_overlay: Color          ## Dialog scrim.
	var overlay_hover: Color       ## Translucent hover wash, valid on any surface.

	# --- Navigation rail ---
	var bg_nav: Color
	var bg_nav_deep: Color         ## Rail footer and dividers.
	var bg_nav_active: Color       ## Hovered navigation item.

	# --- Ink ---
	var ink_primary: Color
	var ink_secondary: Color
	var ink_muted: Color
	var ink_on_accent: Color       ## Text on a filled accent surface.
	var ink_on_nav: Color
	var ink_on_nav_muted: Color
	var ink_on_disabled: Color

	# --- Accents ---
	var moss: Color                ## Primary action, growth, success.
	var moss_deep: Color           ## Pressed primary.
	var moss_soft: Color           ## Tinted fills.
	var accent_subtle: Color       ## The quietest accent wash.
	var terracotta: Color
	var amber: Color               ## Streaks, lantern glow, celebration.
	var amber_glow: Color
	var sky: Color                 ## Breaks, calm states.
	var clay: Color                ## Destructive actions.
	var oak: Color                 ## Shelf timber.
	var oak_deep: Color            ## Shelf shadow, frame joinery.

	# --- Lines, focus and elevation ---
	var border_soft: Color
	var border_strong: Color
	var border_hairline: Color     ## Alpha-only, so it reads on any surface.
	var track: Color               ## Empty portion of a progress bar or slider.
	var focus_ring: Color          ## Keyboard focus (§50).
	var shadow_ambient: Color      ## Wide, soft, always-on shadow layer.
	var shadow_key: Color          ## Tighter, offset shadow layer.

	# --- Garden and shelf scenery ---
	var grass: Color
	var grass_alt: Color
	var grass_deep: Color          ## Mown band in shade.
	var garden_edge: Color         ## Stone lip around the plot.
	var bed_soil: Color
	var bed_soil_dark: Color
	var shelf_wall: Color          ## Back panel behind the shelving unit.
	var shelf_frame: Color         ## Metal uprights.

	## Multiplied over authored plant, pot and ornament colours. Content colours
	## are the same in both modes — a monstera is green at night too — but they
	## have to sit down into a dark scene rather than glowing out of it.
	var foliage_ambient: Color

	# --- Rarity (§15) ---
	## §50 forbids status by colour alone, so every rarity also has a NAME.
	## PlantSpecies.RARITY_NAMES supplies the text; these are only the tint.
	var rarity: Array[Color] = []

	## Colours a project category may be tagged with, by token name. Categories
	## store a TOKEN NAME, never a hex value, so the palette can be retuned
	## without rewriting save files.
	var project: Dictionary = {}


## Ordered for the category colour picker, so the choices always appear the same
## way round rather than in Dictionary iteration order.
const PROJECT_COLOR_ORDER: Array[String] = ["moss", "terracotta", "amber", "sky", "clay", "ink"]

static var _mode: Mode = Mode.LIGHT
static var _active: Colors = light()


## Switches the active palette. Callers are responsible for repainting — see
## `scenes/main/main.gd`, which swaps the baked Theme and refreshes every screen.
static func set_mode(mode: Mode) -> void:
	_mode = mode
	_active = dark() if mode == Mode.DARK else light()


static func get_mode() -> Mode:
	return _mode


static func is_dark() -> bool:
	return _mode == Mode.DARK


## Resolves the saved setting string. An unknown value falls back to light rather
## than erroring, so a hand-edited save cannot brick the app's appearance.
static func mode_from_setting(value: String) -> Mode:
	return Mode.DARK if value == MODE_DARK else Mode.LIGHT


static func setting_from_mode(mode: Mode) -> String:
	return MODE_DARK if mode == Mode.DARK else MODE_LIGHT


static func colors() -> Colors:
	return _active


# --- Light --------------------------------------------------------------------

static func light() -> Colors:
	var c := Colors.new()

	c.bg_base = Color("#E9DFC9")
	c.bg_sunken = Color("#DCD0B4")
	# A near-white card against a warm page. The old palette put card and page
	# within a few percent of each other, which is why nothing read as raised.
	c.bg_raised = Color("#FFFCF5")
	c.surface_high = Color("#FFFFFF")
	c.bg_overlay = Color("#1F1B15CC")
	c.overlay_hover = Color("#2B251914")

	c.bg_nav = Color("#365A4D")
	c.bg_nav_deep = Color("#2A4A3F")
	c.bg_nav_active = Color("#46705F")

	c.ink_primary = Color("#2B2519")
	c.ink_secondary = Color("#5C5240")
	c.ink_muted = Color("#8B7C64")
	c.ink_on_accent = Color("#FFFDF7")
	c.ink_on_nav = Color("#F2E9D6")
	c.ink_on_nav_muted = Color("#A8C2B3")
	# Dark rather than light: a pale label on a pale disabled fill is unreadable,
	# and §74 requires disabled states to stay clear.
	c.ink_on_disabled = Color("#6B6355")

	c.moss = Color("#4F8340")
	c.moss_deep = Color("#38602D")
	c.moss_soft = Color("#DDE9CE")
	c.accent_subtle = Color("#E7F0DC")
	c.terracotta = Color("#BF6440")
	c.amber = Color("#DC9A32")
	c.amber_glow = Color("#F6CC80")
	c.sky = Color("#5F9391")
	c.clay = Color("#A94B33")
	c.oak = Color("#C69A63")
	c.oak_deep = Color("#9C6E3B")

	c.border_soft = Color("#D8C6A2")
	c.border_strong = Color("#B79F73")
	c.border_hairline = Color("#2B251914")
	# Deliberately darker than bg_sunken: an earlier version reused it and the XP
	# bar vanished whenever it sat on a sunken card.
	c.track = Color("#CDB88F")
	c.focus_ring = Color("#BF6440")
	c.shadow_ambient = Color("#2B251912")
	c.shadow_key = Color("#2B25191F")

	c.grass = Color("#82A85D")
	c.grass_alt = Color("#7BA157")
	c.grass_deep = Color("#628544")
	c.garden_edge = Color("#BCA97D")
	c.bed_soil = Color("#6B5236")
	c.bed_soil_dark = Color("#513E29")
	c.shelf_wall = Color("#48705F")
	c.shelf_frame = Color("#3B3630")

	c.foliage_ambient = Color(1.0, 1.0, 1.0)

	c.rarity = [
		Color("#8C8171"),  # Common
		Color("#5C8A54"),  # Uncommon
		Color("#4A7FA5"),  # Rare
		Color("#8A5FA8"),  # Epic
		Color("#C98A2E"),  # Legendary
	]
	c.project = {
		"moss": c.moss,
		"terracotta": c.terracotta,
		"amber": c.amber,
		"sky": c.sky,
		"clay": c.clay,
		"ink": c.ink_secondary,
	}
	return c


# --- Dark ---------------------------------------------------------------------

static func dark() -> Colors:
	var c := Colors.new()

	c.bg_base = Color("#191D1A")
	c.bg_sunken = Color("#141813")
	c.bg_raised = Color("#232A25")
	c.surface_high = Color("#2B332C")
	c.bg_overlay = Color("#0B0D0BE6")
	c.overlay_hover = Color("#FFFFFF12")

	c.bg_nav = Color("#131A16")
	c.bg_nav_deep = Color("#0E1411")
	c.bg_nav_active = Color("#22302A")

	c.ink_primary = Color("#EDE7D8")
	c.ink_secondary = Color("#BCB5A4")
	c.ink_muted = Color("#8B8878")
	# Accent fills are bright in dark mode, so their label goes dark.
	c.ink_on_accent = Color("#0F1410")
	c.ink_on_nav = Color("#EDE7D8")
	c.ink_on_nav_muted = Color("#93A89A")
	c.ink_on_disabled = Color("#9AA394")

	c.moss = Color("#7CBB63")
	c.moss_deep = Color("#5C9648")
	c.moss_soft = Color("#2B3A28")
	c.accent_subtle = Color("#253022")
	c.terracotta = Color("#E08A5F")
	c.amber = Color("#EBB55A")
	c.amber_glow = Color("#F7D9A0")
	c.sky = Color("#7FB6B3")
	c.clay = Color("#DB7358")
	c.oak = Color("#B98D5C")
	c.oak_deep = Color("#7E5C33")

	c.border_soft = Color("#333D35")
	c.border_strong = Color("#4A574C")
	c.border_hairline = Color("#FFFFFF14")
	c.track = Color("#2E3830")
	c.focus_ring = Color("#E08A5F")
	# Shadows have to work much harder on dark surfaces to read at all.
	c.shadow_ambient = Color("#00000040")
	c.shadow_key = Color("#00000059")

	c.grass = Color("#3E5C36")
	c.grass_alt = Color("#3A5733")
	c.grass_deep = Color("#2C4527")
	c.garden_edge = Color("#4C4838")
	c.bed_soil = Color("#3B2E20")
	c.bed_soil_dark = Color("#2A2017")
	c.shelf_wall = Color("#26302A")
	c.shelf_frame = Color("#0F1310")

	c.foliage_ambient = Color(0.78, 0.84, 0.80)

	c.rarity = [
		Color("#A79A87"),  # Common
		Color("#84BC79"),  # Uncommon
		Color("#71ACD4"),  # Rare
		Color("#B48CD0"),  # Epic
		Color("#E7B65C"),  # Legendary
	]
	c.project = {
		"moss": c.moss,
		"terracotta": c.terracotta,
		"amber": c.amber,
		"sky": c.sky,
		"clay": c.clay,
		"ink": c.ink_secondary,
	}
	return c


# --- Accessors ----------------------------------------------------------------
# One per token. Verbose on purpose: `Palette.ink_primary()` reads at a call site
# exactly as the old constant did, and renaming one breaks the build loudly.

static func bg_base() -> Color: return _active.bg_base
static func bg_sunken() -> Color: return _active.bg_sunken
static func bg_raised() -> Color: return _active.bg_raised
static func surface_high() -> Color: return _active.surface_high
static func bg_overlay() -> Color: return _active.bg_overlay
static func overlay_hover() -> Color: return _active.overlay_hover

static func bg_nav() -> Color: return _active.bg_nav
static func bg_nav_deep() -> Color: return _active.bg_nav_deep
static func bg_nav_active() -> Color: return _active.bg_nav_active

static func ink_primary() -> Color: return _active.ink_primary
static func ink_secondary() -> Color: return _active.ink_secondary
static func ink_muted() -> Color: return _active.ink_muted
static func ink_on_accent() -> Color: return _active.ink_on_accent
static func ink_on_nav() -> Color: return _active.ink_on_nav
static func ink_on_nav_muted() -> Color: return _active.ink_on_nav_muted
static func ink_on_disabled() -> Color: return _active.ink_on_disabled

static func moss() -> Color: return _active.moss
static func moss_deep() -> Color: return _active.moss_deep
static func moss_soft() -> Color: return _active.moss_soft
static func accent_subtle() -> Color: return _active.accent_subtle
static func terracotta() -> Color: return _active.terracotta
static func amber() -> Color: return _active.amber
static func amber_glow() -> Color: return _active.amber_glow
static func sky() -> Color: return _active.sky
static func clay() -> Color: return _active.clay
static func oak() -> Color: return _active.oak
static func oak_deep() -> Color: return _active.oak_deep

static func border_soft() -> Color: return _active.border_soft
static func border_strong() -> Color: return _active.border_strong
static func border_hairline() -> Color: return _active.border_hairline
static func track() -> Color: return _active.track
static func focus_ring() -> Color: return _active.focus_ring
static func shadow_ambient() -> Color: return _active.shadow_ambient
static func shadow_key() -> Color: return _active.shadow_key

static func grass() -> Color: return _active.grass
static func grass_alt() -> Color: return _active.grass_alt
static func grass_deep() -> Color: return _active.grass_deep
static func garden_edge() -> Color: return _active.garden_edge
static func bed_soil() -> Color: return _active.bed_soil
static func bed_soil_dark() -> Color: return _active.bed_soil_dark
static func shelf_wall() -> Color: return _active.shelf_wall
static func shelf_frame() -> Color: return _active.shelf_frame

static func foliage_ambient() -> Color: return _active.foliage_ambient


## Tints an authored content colour for the active mode. Plants, pots and
## ornaments keep the colours the designer chose; this only seats them in the
## scene's light.
static func content(color: Color) -> Color:
	return color * _active.foliage_ambient


static func rarity_color(rarity: PlantSpecies.Rarity) -> Color:
	return _active.rarity[clampi(int(rarity), 0, _active.rarity.size() - 1)]


## Resolves a stored token name to a colour, falling back to moss for a name this
## build no longer recognises.
static func project_color(token: String) -> Color:
	return _active.project.get(token, _active.moss)
