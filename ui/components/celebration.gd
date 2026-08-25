class_name Celebration
extends Control
## The brief particle flourish when something is earned (§75).
##
## §11 is explicit that the completion animation must be satisfying but SHORT —
## "never make the player wait through a long animation". So this runs for under
## a second, does not block anything, and frees itself.
##
## §3 rules out flashing rewards and casino effects, so the particles are drifting
## leaves and soft motes rather than confetti or sparks, and they fade rather
## than pop.

const DURATION: float = 1.1
const PARTICLE_COUNT: int = 18
const RISE_PIXELS: float = 70.0

class Mote extends RefCounted:
	var offset: Vector2
	var drift: Vector2
	var size: float
	var color: Color
	var spin: float
	var delay: float

var _motes: Array[Mote] = []
var _elapsed: float = 0.0


## Emits at `centre` within `parent`. Does nothing when reduced motion is on —
## §43 requires that setting to be honoured, and a burst of particles is exactly
## what it exists to prevent.
static func burst(parent: Node, centre: Vector2, tint: Color = Palette.moss()) -> void:
	if AppState.get_settings().reduced_motion:
		return
	var celebration := Celebration.new()
	celebration._tint = tint
	celebration.position = centre
	parent.add_child(celebration)


var _tint: Color = Palette.moss()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Sized generously and centred on the origin, so particles have room to drift
	# without the control clipping them.
	size = Vector2(240, 240)
	position -= size * 0.5

	for i in PARTICLE_COUNT:
		var mote := Mote.new()
		var angle := randf() * TAU
		mote.offset = Vector2(cos(angle), sin(angle)) * randf_range(0.0, 26.0)
		mote.drift = Vector2(randf_range(-26.0, 26.0), -randf_range(0.6, 1.4) * RISE_PIXELS)
		mote.size = randf_range(3.0, 7.0)
		mote.spin = randf_range(-2.0, 2.0)
		mote.delay = randf() * 0.25
		# Two greens and an amber, drawn from the palette rather than invented.
		var palette := [_tint, _tint.lightened(0.22), Palette.amber_glow()]
		mote.color = palette[randi() % palette.size()]
		_motes.append(mote)


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= DURATION:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var centre := size * 0.5
	for mote: Mote in _motes:
		var t := clampf((_elapsed - mote.delay) / (DURATION - mote.delay), 0.0, 1.0)
		if t <= 0.0:
			continue

		# Ease-out on the rise, so motes decelerate as they fade rather than
		# travelling at constant speed and vanishing abruptly.
		var eased := 1.0 - pow(1.0 - t, 2.2)
		var point := centre + mote.offset + mote.drift * eased
		var alpha := (1.0 - t) * 0.9
		var color := Color(mote.color.r, mote.color.g, mote.color.b, alpha)

		# A leaf shape rather than a dot: two arcs meeting at a point, rotated.
		var radius := mote.size * (1.0 - t * 0.35)
		var rotation := mote.spin * eased * PI
		var leaf := PackedVector2Array()
		for i in 9:
			var u := float(i) / 8.0
			var width := sin(PI * u) * radius * 0.6
			leaf.append(point + Vector2(width, -radius + radius * 2.0 * u).rotated(rotation))
		for i in range(8, -1, -1):
			var u := float(i) / 8.0
			var width := sin(PI * u) * radius * 0.6
			leaf.append(point + Vector2(-width, -radius + radius * 2.0 * u).rotated(rotation))
		draw_colored_polygon(leaf, color)
