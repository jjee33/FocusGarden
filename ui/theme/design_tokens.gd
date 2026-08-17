class_name DesignTokens
extends RefCounted
## The single source of truth for the game's visual language (§4).
##
## §4 requires a central reusable theme rather than per-screen styling. This file
## is that centre: every colour, size, radius and duration in Focus Garden comes
## from here, and ThemeBuilder turns it into the Theme resource Godot applies.
##
## Nothing in the codebase may hardcode a colour or a pixel spacing value. If a
## screen needs a shade that is not here, the right move is to add a token, not a
## literal — that is what keeps §74's "spacing is consistent, typography is
## consistent" true as screens are added by different hands over time.
##
## PALETTE INTENT (§4): warm parchment grounds, deep moss greens, terracotta and
## amber accents. Restrained and warm — a lamplit potting bench, not a dashboard.
## The design deliberately commits to a single warm light look rather than
## offering a dark mode, so contrast and mood can be tuned properly once.

# --- Surfaces -----------------------------------------------------------------
const BG_BASE := Color("#F2EADA")        ## App background, warm parchment.
const BG_SUNKEN := Color("#E6DCC7")      ## Recessed wells, track backgrounds.
const BG_RAISED := Color("#FBF6EA")      ## Cards and panels that sit above.
const BG_NAV := Color("#E9DFC9")         ## Persistent navigation rail.
const BG_OVERLAY := Color("#2B2620E0")   ## Dialog scrim.

# --- Ink ----------------------------------------------------------------------
const INK_PRIMARY := Color("#3B342A")    ## Headings and body text.
const INK_SECONDARY := Color("#6B6153")  ## Supporting text.
const INK_MUTED := Color("#9C917D")      ## Metadata, disabled text.
const INK_ON_ACCENT := Color("#FDFAF3")  ## Text on a filled accent surface.

# --- Accents ------------------------------------------------------------------
const MOSS := Color("#5C8A54")           ## Primary action, growth, success.
const MOSS_DEEP := Color("#426A3C")      ## Pressed primary.
const MOSS_SOFT := Color("#D9E5D2")      ## Tinted fills.
const TERRACOTTA := Color("#C4714A")     ## Pots, warm highlight.
const AMBER := Color("#DFA144")          ## Streaks, celebration.
const SKY := Color("#7FA8B8")            ## Breaks, calm states.
const CLAY := Color("#B5573F")           ## Destructive actions.

# --- Lines and shadow ---------------------------------------------------------
const BORDER_SOFT := Color("#DCD0B7")
const BORDER_STRONG := Color("#C4B698")
## Empty portion of a progress bar or slider. Deliberately darker than BG_SUNKEN:
## an earlier version reused BG_SUNKEN and the XP bar became invisible whenever it
## sat on a sunken card, because track and card were the same colour.
const TRACK := Color("#D3C4A6")
## Text on a disabled filled button. Dark rather than light — a pale label on a
## pale disabled fill is unreadable, and §74 requires disabled states to be clear.
const INK_ON_DISABLED := Color("#55634F")
const FOCUS_RING := Color("#5C8A54")     ## Keyboard focus (§50).
const SHADOW := Color("#3B342A1F")

# --- Rarity (§15) -------------------------------------------------------------
## §50 forbids communicating status by colour alone, so every rarity has a NAME
## that must be rendered alongside its colour. PlantSpecies.RARITY_NAMES supplies
## the text; these are only the accompanying tint.
const RARITY_COLORS: Array[Color] = [
	Color("#8C8171"),  # Common
	Color("#5C8A54"),  # Uncommon
	Color("#4A7FA5"),  # Rare
	Color("#8A5FA8"),  # Epic
	Color("#C98A2E"),  # Legendary
]

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
const RADIUS_SM: int = 6
const RADIUS_MD: int = 10
const RADIUS_LG: int = 16
const RADIUS_PILL: int = 999

# --- Type scale ---------------------------------------------------------------
const FONT_DISPLAY: int = 44   ## The focus countdown.
const FONT_TITLE: int = 28
const FONT_HEADING: int = 20
const FONT_BODY: int = 16
const FONT_SMALL: int = 14
const FONT_CAPTION: int = 12

# --- Motion (§43, §50) --------------------------------------------------------
## Durations in seconds. Multiply by `motion_scale()` so reduced motion and the
## animation-intensity slider apply everywhere without per-call checks.
## Base durations in seconds. These are raw constants — they do NOT account for
## the player's reduced-motion or animation-intensity settings. Always run them
## through `Motion.duration()`, which owns that policy. Keeping tokens free of
## any dependency on player state is what lets this file stay a pure constants
## table that anything (including tools and tests) can read.
const DURATION_INSTANT: float = 0.08
const DURATION_FAST: float = 0.15
const DURATION_NORMAL: float = 0.25
const DURATION_SLOW: float = 0.4

# --- Layout -------------------------------------------------------------------
const NAV_RAIL_WIDTH: int = 232
const CONTENT_MAX_WIDTH: int = 1180
const MIN_WINDOW_SIZE := Vector2i(1280, 720)


static func rarity_color(rarity: PlantSpecies.Rarity) -> Color:
	return RARITY_COLORS[clampi(int(rarity), 0, RARITY_COLORS.size() - 1)]
