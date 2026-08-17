class_name ProgressRing
extends Control
## The circular countdown at the centre of the focus screen (§10).
##
## Drawn rather than assembled from textures, so it stays crisp at every
## resolution and DPI scale (§5) and needs no art to exist.
##
## The ring is deliberately calm: one track, one arc, one soft cap. §10 asks for
## "subtle progress indication" on a screen whose job is to not distract, so
## there is no pulsing, no gradient sweep and no tick marks.

const START_ANGLE: float = -PI / 2.0  ## Twelve o'clock.
const ARC_SEGMENTS: int = 128         ## Smooth at the sizes we draw.

## 0..1. Setting it redraws; nothing polls.
var progress: float = 0.0:
	set(value):
		var clamped := clampf(value, 0.0, 1.0)
		if is_equal_approx(clamped, progress):
			return
		progress = clamped
		queue_redraw()

var arc_color: Color = DesignTokens.MOSS:
	set(value):
		arc_color = value
		queue_redraw()

var track_color: Color = DesignTokens.TRACK:
	set(value):
		track_color = value
		queue_redraw()

var thickness: float = 14.0:
	set(value):
		thickness = value
		queue_redraw()


func _draw() -> void:
	var centre := size / 2.0
	# Inset by half the stroke so the ring never clips against the control's edge.
	var radius := minf(size.x, size.y) / 2.0 - thickness / 2.0
	if radius <= 0.0:
		return

	draw_arc(centre, radius, 0.0, TAU, ARC_SEGMENTS, track_color, thickness, true)

	if progress <= 0.0:
		return

	draw_arc(
		centre, radius,
		START_ANGLE, START_ANGLE + TAU * progress,
		ARC_SEGMENTS, arc_color, thickness, true
	)

	# Rounded cap on the leading end. draw_arc leaves a flat edge, which reads as
	# unfinished against the soft styling everywhere else.
	var head := centre + Vector2.from_angle(START_ANGLE + TAU * progress) * radius
	draw_circle(head, thickness / 2.0, arc_color)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
