class_name PlantView
extends Control
## Renders one plant, with an idle sway (§43).
##
## Prefers authored artwork when a species has it and falls back to PlantPainter
## otherwise, so commissioning sprites later is a content change rather than a
## code change.
##
## MOTION BUDGET (§43, §44): the sway is a single sine, and `_process` is disabled
## entirely when animation is off or the view is off-screen. §43 asks for reduced
## motion support and §44 asks that idle CPU stay low — a garden of thirty plants
## each running its own animation would violate both.
##
## This component deliberately touches NO autoloads. It renders what it is told
## to render, and `animate` is set by whoever hosts it (in practice from the
## reduced-motion setting). That keeps it usable from tool scripts and tests,
## which compile before autoloads exist, and keeps a drawing component from
## reaching into global state to make a policy decision.

## Full sway cycle length. Slow: this is a plant in still air, not a flag.
const SWAY_PERIOD_SECONDS: float = 5.5

## How often the plant is actually redrawn, in hertz.
##
## Every redraw re-runs PlantPainter: building leaf polygons, triangulating them,
## and issuing a draw call per triangle. That is real CPU work, and doing it 60
## times a second for every plant on screen pinned a full core — a garden or a
## shelf can hold a dozen of them at once.
##
## Over a 5.5-second cycle, 12 Hz is 66 distinct positions. The motion is
## indistinguishable from 60 Hz at this speed, and costs a fifth as much (§44).
const REDRAW_HZ: float = 12.0

var species: PlantSpecies:
	set(value):
		species = value
		queue_redraw()

## 0..1 toward maturity. Drives both size and foliage count.
var growth: float = 1.0:
	set(value):
		var clamped := clampf(value, 0.0, 1.0)
		if is_equal_approx(clamped, growth):
			return
		growth = clamped
		queue_redraw()

var pot: PotStyle:
	set(value):
		pot = value
		queue_redraw()

## Drawn height of a mature plant. Defaults to the control's height.
var plant_height: float = 0.0:
	set(value):
		plant_height = value
		queue_redraw()

var show_pot: bool = true:
	set(value):
		show_pot = value
		queue_redraw()

## Renders as a flat silhouette, for undiscovered catalogue entries (§16).
var silhouette: bool = false:
	set(value):
		silhouette = value
		queue_redraw()

## Idle sway. OFF by default, and switched on only for the one plant a screen is
## actually featuring.
##
## This is a design decision before it is a performance one: §43 warns against
## overanimating, and a shelf of twelve plants all swaying at once is visual
## noise on a screen meant to feel calm. One plant moving reads as alive; twelve
## reads as restless.
##
## It is also where the idle CPU went. Every animated plant re-runs the painter,
## and a dozen of them together cost half a core (§44). One featured plant costs
## almost nothing.
var animate: bool = false:
	set(value):
		animate = value
		_apply_motion_setting()

var _sway_phase: float = 0.0
var _redraw_accumulator: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Each plant starts at a different point in the cycle, so a shelf of them does
	# not sway in unison like a chorus line.
	_sway_phase = randf() * TAU
	_apply_motion_setting()


func _process(delta: float) -> void:
	_sway_phase = fmod(_sway_phase + delta * TAU / SWAY_PERIOD_SECONDS, TAU)

	# Nobody is looking at a window that is not focused — minimised, or behind the
	# thing the player is actually working in, which for this app is the normal
	# case. §44 asks for low CPU exactly then, and redrawing foliage for an
	# audience of no one is the clearest possible waste.
	if not get_window().has_focus():
		return

	# The phase advances every frame so the motion stays smooth in time, but the
	# expensive redraw is throttled to REDRAW_HZ.
	_redraw_accumulator += delta
	if _redraw_accumulator < 1.0 / REDRAW_HZ:
		return
	_redraw_accumulator = 0.0
	queue_redraw()


func _draw() -> void:
	if species == null:
		return

	var height := plant_height if plant_height > 0.0 else size.y
	# The pot base sits on the bottom edge, so plants of different heights align
	# along a shelf line rather than floating at different depths.
	var origin := Vector2(size.x * 0.5, size.y)

	if silhouette:
		_draw_silhouette(origin, height)
		return

	var texture := species.get_stage_texture(_stage_index())
	if texture != null:
		var target := Vector2(height * 0.8, height)
		draw_texture_rect(texture, Rect2(origin - Vector2(target.x * 0.5, target.y), target), false)
		return

	PlantPainter.draw_plant(
		self, species.morphology, origin, height, growth, _sway_phase,
		pot if show_pot else null
	)


## An undiscovered species shows as a shape without detail (§16). Drawn from the
## same morphology so the silhouette genuinely matches the plant it hides —
## a generic blob would make every locked entry look identical.
func _draw_silhouette(origin: Vector2, height: float) -> void:
	if species.morphology == null:
		return
	var shadow := species.morphology.duplicate() as PlantMorphology
	var veil := DesignTokens.INK_MUTED
	shadow.leaf_color_base = veil
	shadow.leaf_color_tip = veil
	shadow.stem_color = veil
	shadow.variegation = 0.0
	shadow.has_flowers = false
	PlantPainter.draw_plant(self, shadow, origin, height, 1.0, 0.0, null)


func _stage_index() -> int:
	if species == null:
		return 0
	return PlantGrowthService.stage_for_ratio(growth, species.get_stage_count())


func _apply_motion_setting() -> void:
	if not is_inside_tree():
		return
	var should_run := animate and is_visible_in_tree()
	set_process(should_run)
	if not should_run:
		queue_redraw()


## Pauses animation while off-screen, so plants on a screen the player is not
## looking at cost nothing (§44).
func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		_apply_motion_setting()
