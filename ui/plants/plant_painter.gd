class_name PlantPainter
extends RefCounted
## Draws plants and pots procedurally, in the illustrated style of the reference art.
##
## WHY PROCEDURAL RATHER THAN SPRITES: sixteen species across three growth stages
## is eighty pieces of artwork, and every later species multiplies it again. Hand
## authoring that volume at a consistent quality is not achievable here, and §42
## forbids shipping ugly programmer art. Drawing from a compact morphology
## description instead gives every plant the same hand, scales cleanly to any DPI
## (§5), animates without a sprite sheet, and lets growth stages interpolate
## smoothly instead of popping between frames.
##
## §73 still applies: this IS the placeholder pipeline. Every species references
## its art through PlantMorphology, so a painted sprite set could replace these
## calls later without touching gameplay code.
##
## STYLE RULES, taken from the reference:
##   * Filled shapes carry a slightly darker outline, for an illustrated ink edge
##     rather than a flat vector look.
##   * Leaves gradate from a deeper base to a lighter tip.
##   * Pots are terracotta, glazed ceramic, or woven, with visible rim and soil.
##   * Nothing is pure black; the darkest line is a deep warm brown.

## Outline darkness applied to any fill. Enough to read as a drawn edge, not so
## much that it becomes a cartoon stroke.
const OUTLINE_DARKEN: float = 0.30
const OUTLINE_WIDTH: float = 1.6
## Samples along a leaf midrib. Higher looks smoother; 14 is indistinguishable
## from 30 at the sizes plants are drawn and costs half as much.
const LEAF_SEGMENTS: int = 14
## Pot height as a fraction of the plant's total drawn height.
const POT_HEIGHT_RATIO: float = 0.34
## Rim height as a fraction of pot height.
const RIM_HEIGHT_RATIO: float = 0.16
## How far the rim oversails the body on each side. Small: a rim that projects
## too far reads as a saucer balanced on the pot rather than part of it.
const RIM_OVERHANG: float = 0.515


# --- Public API ---------------------------------------------------------------

## Draws a complete potted plant into `canvas`.
##
## `origin` is the CENTRE OF THE POT BASE, so plants of different heights line up
## on a shelf edge. `scale_px` is the height in pixels a fully grown plant of this
## species occupies above that point.
## `growth` is 0..1 and drives both size and how much foliage has appeared.
## `sway` is a phase in radians for the idle animation (§43).
static func draw_plant(
	canvas: CanvasItem,
	morphology: PlantMorphology,
	origin: Vector2,
	scale_px: float,
	growth: float,
	sway: float,
	pot: PotStyle = null,
	bloom: bool = true
) -> void:
	if morphology == null:
		return
	var eased := clampf(growth, 0.0, 1.0)
	var pot_height := scale_px * POT_HEIGHT_RATIO

	if pot != null:
		draw_pot(canvas, pot, origin, pot_height)

	# Foliage rises from the SOIL SURFACE, which sits at the top of the pot — not
	# from inside its body. Getting this wrong makes every plant look like it was
	# pushed halfway through its container.
	var soil := origin + Vector2(0.0, -(pot_height + pot_height * RIM_HEIGHT_RATIO * 0.4))
	if pot == null:
		soil = origin
	# A seed has no foliage at all — just disturbed soil and a hint of a shoot.
	if eased <= 0.02:
		_draw_seed(canvas, soil, scale_px)
		return

	match morphology.form:
		PlantMorphology.Form.ROSETTE:
			_draw_rosette(canvas, morphology, soil, scale_px, eased, sway)
		PlantMorphology.Form.UPRIGHT:
			_draw_upright(canvas, morphology, soil, scale_px, eased, sway)
		PlantMorphology.Form.TRAILING:
			_draw_trailing(canvas, morphology, soil, scale_px, eased, sway)
		PlantMorphology.Form.FROND:
			_draw_frond(canvas, morphology, soil, scale_px, eased, sway)
		PlantMorphology.Form.SPIKE:
			_draw_spike(canvas, morphology, soil, scale_px, eased, sway)
		PlantMorphology.Form.SUCCULENT:
			_draw_succulent(canvas, morphology, soil, scale_px, eased, sway)
		PlantMorphology.Form.CACTUS:
			_draw_cactus(canvas, morphology, soil, scale_px, eased, sway, bloom)
		PlantMorphology.Form.FLOWERING:
			_draw_flowering(canvas, morphology, soil, scale_px, eased, sway, bloom)


## A pot on its own, for the pot picker.
static func draw_pot(canvas: CanvasItem, pot: PotStyle, origin: Vector2, height: float) -> void:
	if pot == null:
		return
	var top_w := height * pot.top_width_ratio
	var bottom_w := height * pot.bottom_width_ratio
	var rim_h := height * RIM_HEIGHT_RATIO

	var body := PackedVector2Array()
	match pot.shape:
		PotStyle.Shape.TAPERED:
			body = PackedVector2Array([
				origin + Vector2(-bottom_w * 0.5, 0.0),
				origin + Vector2(-top_w * 0.5, -height),
				origin + Vector2(top_w * 0.5, -height),
				origin + Vector2(bottom_w * 0.5, 0.0),
			])
		PotStyle.Shape.ROUNDED, PotStyle.Shape.BOWL:
			body = _rounded_pot_outline(origin, top_w, bottom_w, height, pot.shape == PotStyle.Shape.BOWL)
		PotStyle.Shape.CYLINDER:
			body = PackedVector2Array([
				origin + Vector2(-top_w * 0.5, 0.0),
				origin + Vector2(-top_w * 0.5, -height),
				origin + Vector2(top_w * 0.5, -height),
				origin + Vector2(top_w * 0.5, 0.0),
			])
		PotStyle.Shape.BASKET:
			body = PackedVector2Array([
				origin + Vector2(-bottom_w * 0.5, 0.0),
				origin + Vector2(-top_w * 0.5, -height),
				origin + Vector2(top_w * 0.5, -height),
				origin + Vector2(bottom_w * 0.5, 0.0),
			])

	_fill(canvas, body, pot.body_color)
	_draw_pattern(canvas, pot, origin, top_w, bottom_w, height)

	# Rim: a band across the top, slightly wider than the body, which is what
	# makes a flat shape read as a container with an opening.
	var rim := PackedVector2Array([
		origin + Vector2(-top_w * RIM_OVERHANG, -height),
		origin + Vector2(-top_w * RIM_OVERHANG, -height - rim_h),
		origin + Vector2(top_w * RIM_OVERHANG, -height - rim_h),
		origin + Vector2(top_w * RIM_OVERHANG, -height),
	])
	_fill(canvas, rim, pot.rim_color)
	_outline(canvas, body, pot.body_color)
	_outline(canvas, rim, pot.rim_color)

	# Soil last, so it sits in the opening rather than behind the rim outline.
	_fill_ellipse(
		canvas, origin + Vector2(0.0, -height - rim_h * 0.55),
		top_w * 0.47, rim_h * 0.5, pot.soil_color
	)


# --- Growth forms -------------------------------------------------------------

## Leaves radiating from a single crown: aloe, echeveria, spider plant.
static func _draw_rosette(
	canvas: CanvasItem, m: PlantMorphology, base: Vector2, scale_px: float, growth: float, sway: float
) -> void:
	var count := _leaf_count(m, growth)
	var length := scale_px * m.leaf_length_ratio * _size_curve(growth)

	# Drawn back-to-front: outer lower leaves first, so the newest central growth
	# sits on top the way a real rosette does.
	for i in count:
		var t := float(i) / maxf(1.0, float(count - 1))
		# Alternating outward so the rosette fills evenly rather than sweeping.
		var side := 1.0 if i % 2 == 0 else -1.0
		var rank := floorf(float(i) * 0.5) / maxf(1.0, float(count) * 0.5)
		var angle := side * lerpf(0.15, m.spread_radians, rank)
		var leaf_len := length * lerpf(1.0, 0.68, rank)
		var phase := sway + float(i) * 0.7
		angle += sin(phase) * m.sway_amount * (0.4 + rank)
		_draw_leaf(canvas, m, base, leaf_len, angle, t, growth)


## A central stem with leaves stepping up it: rubber plant, jade, monstera.
static func _draw_upright(
	canvas: CanvasItem, m: PlantMorphology, base: Vector2, scale_px: float, growth: float, sway: float
) -> void:
	var count := _leaf_count(m, growth)
	var height := scale_px * 0.62 * _size_curve(growth)
	var lean := sin(sway) * m.sway_amount * 0.5

	var stem := PackedVector2Array()
	for i in 9:
		var t := float(i) / 8.0
		stem.append(base + Vector2(lean * t * height * 0.25, -height * t))
	canvas.draw_polyline(stem, m.stem_color, maxf(2.0, scale_px * 0.018), true)

	for i in count:
		var t := float(i + 1) / float(count + 1)
		var attach := base + Vector2(lean * t * height * 0.25, -height * t)
		var side := 1.0 if i % 2 == 0 else -1.0
		var angle := side * lerpf(m.spread_radians, m.spread_radians * 0.45, t)
		angle += sin(sway + float(i) * 0.8) * m.sway_amount
		var leaf_len := scale_px * m.leaf_length_ratio * _size_curve(growth) * lerpf(1.0, 0.6, t)
		_draw_leaf(canvas, m, attach, leaf_len, angle, t, growth)

	# Crown leaf, so an upright plant does not end in a bare stem tip.
	_draw_leaf(
		canvas, m, base + Vector2(lean * height * 0.25, -height),
		scale_px * m.leaf_length_ratio * _size_curve(growth) * 0.55,
		sin(sway) * m.sway_amount, 1.0, growth
	)


## Stems arcing outward and down: pothos, string-of-hearts, ivy.
static func _draw_trailing(
	canvas: CanvasItem, m: PlantMorphology, base: Vector2, scale_px: float, growth: float, sway: float
) -> void:
	var strands := clampi(3 + int(growth * 4.0), 3, 7)
	var reach := scale_px * 0.42 * _size_curve(growth)

	for s in strands:
		var side := 1.0 if s % 2 == 0 else -1.0
		var spread := (float(s / 2) + 1.0) / float(strands)
		var phase := sway + float(s) * 0.9
		# Strands rise a little, then fall away past the pot rim — that downward
		# turn is what makes a trailing plant read as trailing rather than as a
		# shrub with wide arms.
		var tip := base + Vector2(
			side * reach * (0.7 + spread * 1.0) + sin(phase) * scale_px * m.sway_amount * 0.5,
			scale_px * 0.16 * spread + cos(phase) * scale_px * 0.012
		)
		var control := base + Vector2(side * reach * 0.5, -scale_px * 0.30)

		var strand := PackedVector2Array()
		for i in 13:
			strand.append(_bezier(base, control, tip, float(i) / 12.0))
		canvas.draw_polyline(strand, m.stem_color, maxf(1.5, scale_px * 0.011), true)

		# Leaves hang from the strand, alternating above and below it.
		var leaves := clampi(int(4.0 + growth * 4.0), 3, 8)
		for i in leaves:
			var t := lerpf(0.22, 0.98, float(i) / float(maxi(1, leaves - 1)))
			var point := _bezier(base, control, tip, t)
			var next := _bezier(base, control, tip, minf(1.0, t + 0.06))
			var along := (next - point).normalized()
			# Perpendicular to the strand, flipped each leaf so they alternate.
			var angle := atan2(along.x, -along.y) + (PI * 0.5 * (1.0 if i % 2 == 0 else -1.0))
			angle += sin(phase + float(i)) * m.sway_amount * 1.2
			_draw_leaf(
				canvas, m, point,
				scale_px * m.leaf_length_ratio * 0.34 * _size_curve(growth),
				angle, t, growth
			)


## Arching compound fronds: ferns, palms.
static func _draw_frond(
	canvas: CanvasItem, m: PlantMorphology, base: Vector2, scale_px: float, growth: float, sway: float
) -> void:
	var count := clampi(2 + int(growth * float(m.leaf_count_max - 2)), 2, m.leaf_count_max)
	var length := scale_px * m.leaf_length_ratio * 1.05 * _size_curve(growth)

	for i in count:
		var side := 1.0 if i % 2 == 0 else -1.0
		var rank := floorf(float(i) * 0.5) / maxf(1.0, float(count) * 0.5)
		var angle := side * lerpf(0.12, m.spread_radians, rank)
		angle += sin(sway + float(i) * 0.6) * m.sway_amount

		var tip := base + Vector2(sin(angle), -cos(angle)) * length
		# Fronds arch: the control point sits high and inside, pulling the tip over.
		var control := base + Vector2(sin(angle) * length * 0.30, -cos(angle) * length * 0.85)

		var rib := PackedVector2Array()
		for j in 10:
			rib.append(_bezier(base, control, tip, float(j) / 9.0))
		canvas.draw_polyline(rib, m.stem_color, maxf(1.4, scale_px * 0.010), true)

		# Leaflets in opposed pairs along the rib. Densely packed and overlapping,
		# because a fern frond reads as one soft mass — spaced-out triangles look
		# like a fish skeleton instead.
		var leaflets := 12
		for j in range(1, leaflets):
			var t := float(j) / float(leaflets)
			var point := _bezier(base, control, tip, t)
			var next := _bezier(base, control, tip, minf(1.0, t + 0.06))
			var along := (next - point).normalized()
			var normal := Vector2(-along.y, along.x)
			# Widest in the middle of the frond, tapering at both ends.
			var leaflet := length * 0.30 * sin(PI * clampf(t * 0.85 + 0.15, 0.0, 1.0))
			var shade := m.leaf_color_base.lerp(m.leaf_color_tip, t)
			for dir: float in [1.0, -1.0]:
				var blade := PackedVector2Array([
					point - along * leaflet * 0.16,
					point + normal * dir * leaflet * 0.30 + along * leaflet * 0.30,
					point + normal * dir * leaflet * 0.86 + along * leaflet * 0.62,
					point + along * leaflet * 0.52,
				])
				_fill(canvas, blade, shade)
				_outline(canvas, blade, shade)


## Tall stiff blades: snake plant.
static func _draw_spike(
	canvas: CanvasItem, m: PlantMorphology, base: Vector2, scale_px: float, growth: float, sway: float
) -> void:
	var count := _leaf_count(m, growth)
	# No extra multiplier here: spike species already carry a long leaf ratio, and
	# stacking a second one made them overflow whatever box they were drawn in.
	var length := scale_px * m.leaf_length_ratio * _size_curve(growth)

	for i in count:
		var spread := (float(i) / maxf(1.0, float(count - 1))) - 0.5
		var angle := spread * m.spread_radians * 0.9
		angle += sin(sway + float(i) * 0.5) * m.sway_amount * 0.35
		var leaf_len := length * (0.75 + 0.25 * cos(spread * PI))
		_draw_leaf(canvas, m, base, leaf_len, angle, float(i) / maxf(1.0, float(count)), growth)


## Tight fleshy rosette: echeveria, jade offsets.
static func _draw_succulent(
	canvas: CanvasItem, m: PlantMorphology, base: Vector2, scale_px: float, growth: float, sway: float
) -> void:
	var rings := 3
	var length := scale_px * m.leaf_length_ratio * _size_curve(growth)
	var breathe := 1.0 + sin(sway) * m.sway_amount * 0.15

	for ring in rings:
		var ring_t := float(ring) / float(rings - 1)
		var per_ring := 8 - ring * 2
		var ring_len := length * lerpf(1.0, 0.45, ring_t) * breathe
		if growth < ring_t * 0.8:
			continue
		for i in per_ring:
			var angle := TAU * float(i) / float(per_ring) + ring_t * 0.4
			# Projected to an ellipse so the rosette reads as seen from above and
			# slightly in front, matching the reference's three-quarter view.
			var direction := Vector2(sin(angle), -cos(angle) * 0.55)
			var tip := base + direction * ring_len
			var normal := Vector2(-direction.y, direction.x).normalized()
			var width := ring_len * 0.42
			var blade := PackedVector2Array([
				base,
				base + normal * width * 0.5 + direction * ring_len * 0.45,
				tip,
				base - normal * width * 0.5 + direction * ring_len * 0.45,
			])
			_fill(canvas, blade, m.leaf_color_base.lerp(m.leaf_color_tip, ring_t))
			_outline(canvas, blade, m.leaf_color_base)


## Columnar body with areoles: moon cactus and friends.
static func _draw_cactus(
	canvas: CanvasItem, m: PlantMorphology, base: Vector2, scale_px: float, growth: float,
	sway: float, bloom: bool = true
) -> void:
	var height := scale_px * 0.5 * _size_curve(growth)
	var width := height * 0.52
	var lean := sin(sway) * m.sway_amount * 0.25

	var body := PackedVector2Array()
	for i in 21:
		var t := float(i) / 20.0
		var w := width * 0.5 * sin(PI * clampf(t * 0.92 + 0.08, 0.0, 1.0))
		body.append(base + Vector2(-w + lean * t * height * 0.1, -height * t))
	for i in range(20, -1, -1):
		var t := float(i) / 20.0
		var w := width * 0.5 * sin(PI * clampf(t * 0.92 + 0.08, 0.0, 1.0))
		body.append(base + Vector2(w + lean * t * height * 0.1, -height * t))
	_fill(canvas, body, m.leaf_color_base)
	_outline(canvas, body, m.leaf_color_base)

	# Ribs, then spines on them.
	for rib in 3:
		var offset := (float(rib) - 1.0) * width * 0.22
		var line := PackedVector2Array()
		for i in 9:
			var t := lerpf(0.12, 0.92, float(i) / 8.0)
			line.append(base + Vector2(offset * sin(PI * t) + lean * t * height * 0.1, -height * t))
		canvas.draw_polyline(line, m.leaf_color_tip, maxf(1.0, scale_px * 0.008), true)

	# Flowers are the reward for finishing, not for getting close. Gating them on
	# maturity rather than on a growth threshold is what gives the last third of a
	# plant's life something to look forward to.
	if m.has_flowers and bloom and growth > 0.75:
		_draw_bloom(canvas, m, base + Vector2(lean * height * 0.1, -height), scale_px * 0.10, sway)


## Stems carrying blooms: peace lily, lavender, sunflower, orchid.
static func _draw_flowering(
	canvas: CanvasItem, m: PlantMorphology, base: Vector2, scale_px: float, growth: float,
	sway: float, bloom: bool = true
) -> void:
	# The foliage clump first, so blooms sit in front of their own leaves.
	var leaf_count := maxi(2, _leaf_count(m, growth) - 2)
	var leaf_len := scale_px * m.leaf_length_ratio * 0.8 * _size_curve(growth)
	for i in leaf_count:
		var side := 1.0 if i % 2 == 0 else -1.0
		var rank := floorf(float(i) * 0.5) / maxf(1.0, float(leaf_count) * 0.5)
		var angle := side * lerpf(0.2, m.spread_radians, rank)
		angle += sin(sway + float(i) * 0.7) * m.sway_amount * 0.7
		_draw_leaf(canvas, m, base, leaf_len * lerpf(1.0, 0.7, rank), angle, rank, growth)

	# Blooms only once the plant is established, and only once it has actually
	# finished — a seedling with flowers on it would undercut the whole point of
	# watching something grow, and so would a plant that peaked before maturity.
	if growth < 0.55 or not bloom:
		return
	var bloom_progress := inverse_lerp(0.55, 1.0, growth)
	var stalks := clampi(1 + int(bloom_progress * float(m.flower_count)), 1, m.flower_count)
	# Stalks clear the foliage by a little, not by a lot. Taller stalks left the
	# blooms floating in space, visually detached from the plant carrying them.
	var stalk_height := maxf(
		scale_px * 0.34, scale_px * m.leaf_length_ratio * 1.15
	) * _size_curve(growth)

	for i in stalks:
		var side := 1.0 if i % 2 == 0 else -1.0
		var offset := side * scale_px * 0.06 * float(i / 2 + 1)
		var phase := sway + float(i) * 1.1
		var tip := base + Vector2(offset + sin(phase) * scale_px * m.sway_amount * 0.6, -stalk_height)
		var control := base + Vector2(offset * 0.4, -stalk_height * 0.6)

		var stalk := PackedVector2Array()
		for j in 9:
			stalk.append(_bezier(base, control, tip, float(j) / 8.0))
		canvas.draw_polyline(stalk, m.stem_color, maxf(1.4, scale_px * 0.011), true)
		_draw_bloom(canvas, m, tip, scale_px * 0.085 * bloom_progress, phase)


# --- Primitives ---------------------------------------------------------------

## One leaf, grown from `attach` at `angle` (0 = straight up, + = right).
static func _draw_leaf(
	canvas: CanvasItem,
	m: PlantMorphology,
	attach: Vector2,
	length: float,
	angle: float,
	shade_t: float,
	growth: float
) -> void:
	if length <= 1.0:
		return
	var polygon := _leaf_polygon(m, length, angle, growth)
	for i in polygon.size():
		polygon[i] += attach

	var color := m.leaf_color_base.lerp(m.leaf_color_tip, clampf(shade_t, 0.0, 1.0))
	_fill(canvas, polygon, color)
	_outline(canvas, polygon, color)

	# Variegation: a lighter stripe following the midrib. Cosmetic only (§20).
	if m.variegation > 0.01:
		var midrib := PackedVector2Array()
		for i in 7:
			midrib.append(attach + _leaf_midrib(m, length, angle, float(i) / 6.0))
		canvas.draw_polyline(
			midrib, color.lerp(m.variegation_color, m.variegation),
			maxf(1.0, length * 0.05 * m.variegation), true
		)


## Leaf outline as a closed polygon in local space, tip pointing along `angle`.
static func _leaf_polygon(
	m: PlantMorphology, length: float, angle: float, growth: float
) -> PackedVector2Array:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var max_width := length * m.leaf_width_ratio

	for i in LEAF_SEGMENTS + 1:
		var t := float(i) / float(LEAF_SEGMENTS)
		var point := _leaf_midrib(m, length, angle, t)
		var ahead := _leaf_midrib(m, length, angle, minf(1.0, t + 0.02))
		var behind := _leaf_midrib(m, length, angle, maxf(0.0, t - 0.02))
		var along := (ahead - behind)
		if along.length_squared() < 0.0001:
			along = Vector2(0.0, -1.0)
		var normal := Vector2(-along.y, along.x).normalized()
		var half := _width_profile(m, t, growth) * max_width * 0.5
		left.append(point + normal * half)
		right.append(point - normal * half)

	var polygon := PackedVector2Array()
	polygon.append_array(left)
	for i in range(right.size() - 1, -1, -1):
		polygon.append(right[i])
	return polygon


## Midrib position at `t` along the leaf. A quadratic curve, so leaves arc
## naturally instead of being straight spikes.
static func _leaf_midrib(m: PlantMorphology, length: float, angle: float, t: float) -> Vector2:
	var direction := Vector2(sin(angle), -cos(angle))
	var normal := Vector2(-direction.y, direction.x)
	var tip := direction * length
	var control := direction * (length * 0.55) + normal * (length * m.leaf_arc)
	return _bezier(Vector2.ZERO, control, tip, t)


## Half-width factor at `t`, defining the silhouette of each leaf shape.
static func _width_profile(m: PlantMorphology, t: float, growth: float) -> float:
	var base_profile := 0.0
	match m.leaf_shape:
		PlantMorphology.LeafShape.OVAL:
			base_profile = sin(PI * t)
		PlantMorphology.LeafShape.LANCE:
			base_profile = pow(sin(PI * t), 0.75) * (1.0 - t * 0.35)
		PlantMorphology.LeafShape.HEART:
			# Widest low down, with a notched base.
			base_profile = sin(PI * pow(t, 0.68))
		PlantMorphology.LeafShape.ROUND:
			base_profile = sin(PI * t) * 1.25
		PlantMorphology.LeafShape.STRAP:
			base_profile = clampf(sin(PI * t) * 2.6, 0.0, 1.0) * (1.0 - t * 0.2)
		PlantMorphology.LeafShape.NEEDLE:
			base_profile = sin(PI * t) * 0.35
		PlantMorphology.LeafShape.SPLIT:
			# Fenestration: the edge is pulled toward the midrib at intervals,
			# which reads as a monstera's splits without needing a concave
			# multi-part polygon.
			var notch := absf(sin(t * PI * 3.5))
			base_profile = sin(PI * t) * lerpf(0.42, 1.0, notch)
	# A young leaf is proportionally narrower, the way new growth actually looks.
	return base_profile * lerpf(0.72, 1.0, clampf(growth, 0.0, 1.0))


static func _draw_bloom(
	canvas: CanvasItem, m: PlantMorphology, centre: Vector2, radius: float, phase: float
) -> void:
	if radius <= 0.5:
		return
	match m.flower_shape:
		PlantMorphology.FlowerShape.DAISY:
			for i in 8:
				var angle := TAU * float(i) / 8.0 + phase * 0.15
				var petal_centre := centre + Vector2(cos(angle), sin(angle)) * radius * 0.72
				_fill_ellipse(canvas, petal_centre, radius * 0.52, radius * 0.36, m.flower_color)
			_fill_ellipse(canvas, centre, radius * 0.45, radius * 0.45, m.flower_centre_color)
		PlantMorphology.FlowerShape.SPIRE:
			# A lavender-style raceme: small florets stacked up the stem.
			for i in 7:
				var t := float(i) / 6.0
				var point := centre + Vector2(sin(phase + t * 3.0) * radius * 0.2, radius * 1.6 * t)
				_fill_ellipse(
					canvas, point, radius * 0.34 * (1.0 - t * 0.45),
					radius * 0.5 * (1.0 - t * 0.4), m.flower_color
				)
		PlantMorphology.FlowerShape.SPATHE:
			# Peace lily: a broad bract curling behind a narrow upright spadix.
			# Built as a pointed oval so it reads as a cupped petal rather than
			# the flat sliver a pair of arcs produces.
			var spathe := PackedVector2Array()
			for i in 15:
				var t := float(i) / 14.0
				var width := sin(PI * pow(t, 0.75)) * radius * 1.15
				spathe.append(centre + Vector2(width, -radius * 2.0 * t + radius * 0.4))
			for i in range(14, -1, -1):
				var t := float(i) / 14.0
				var width := sin(PI * pow(t, 0.75)) * radius * 0.5
				spathe.append(centre + Vector2(-width, -radius * 2.0 * t + radius * 0.4))
			_fill(canvas, spathe, m.flower_color)
			_outline(canvas, spathe, m.flower_color)
			# The spadix: a short pale column standing in front of the bract.
			_fill_ellipse(
				canvas, centre + Vector2(radius * 0.15, -radius * 0.55),
				radius * 0.20, radius * 0.75, m.flower_centre_color
			)
		PlantMorphology.FlowerShape.CLUSTER:
			# Five petals radiating outward, each an ellipse oriented along its
			# own spoke. Plain circles read as scattered dots rather than a bloom.
			for i in 5:
				var angle := TAU * float(i) / 5.0 - PI * 0.5
				var along := Vector2(cos(angle), sin(angle))
				_fill_oriented_ellipse(
					canvas, centre + along * radius * 0.62,
					along, radius * 0.66, radius * 0.40, m.flower_color
				)
			_fill_ellipse(canvas, centre, radius * 0.34, radius * 0.34, m.flower_centre_color)


## A seed stage: turned soil with the first shoot just breaking through (§14).
static func _draw_seed(canvas: CanvasItem, soil: Vector2, scale_px: float) -> void:
	var shoot := PackedVector2Array([
		soil + Vector2(-scale_px * 0.012, 0.0),
		soil + Vector2(-scale_px * 0.006, -scale_px * 0.05),
		soil + Vector2(scale_px * 0.006, -scale_px * 0.05),
		soil + Vector2(scale_px * 0.012, 0.0),
	])
	_fill(canvas, shoot, Palette.moss())


# --- Drawing helpers ----------------------------------------------------------

## Fills a polygon, triangulating first.
##
## `draw_colored_polygon` is unreliable on concave input, and leaf silhouettes
## with fenestration are concave. Triangulating and drawing convex triangles is
## correct for every shape this file produces.
static func _fill(canvas: CanvasItem, polygon: PackedVector2Array, color: Color) -> void:
	if polygon.size() < 3:
		return
	var indices := Geometry2D.triangulate_polygon(polygon)
	if indices.is_empty():
		# Degenerate or self-intersecting: fall back rather than drawing nothing,
		# so a bad morphology shows up as a rough shape instead of an invisible plant.
		canvas.draw_colored_polygon(polygon, color)
		return

	# ONE draw call for the whole shape, via the triangle-array primitive.
	#
	# The obvious version issues a draw_colored_polygon per triangle. A single
	# leaf triangulates to roughly thirty of them, a plant has a dozen leaves,
	# and a shelf shows twelve plants — which came to tens of thousands of draw
	# calls a second and pinned a full CPU core (§44). Handing the indices and
	# points over in one call instead is the same geometry at a fraction of the
	# cost, and is why `canvas_item_add_triangle_array` exists.
	var colors := PackedColorArray()
	colors.resize(polygon.size())
	colors.fill(color)
	RenderingServer.canvas_item_add_triangle_array(
		canvas.get_canvas_item(), indices, polygon, colors
	)


## The illustrated ink edge. Antialiased, unlike the fill, which is what keeps
## shapes from looking jagged.
static func _outline(canvas: CanvasItem, polygon: PackedVector2Array, color: Color) -> void:
	if polygon.size() < 3:
		return
	var closed := polygon.duplicate()
	closed.append(polygon[0])
	# Not antialiased. Godot builds antialiased polylines by generating extra
	# geometry on the CPU, and a plant has a dozen outlines redrawn continuously
	# — it measured as the single most expensive thing the painter did. The
	# project enables 2D MSAA instead, which smooths these edges on the GPU for
	# free (see project.godot).
	canvas.draw_polyline(closed, color.darkened(OUTLINE_DARKEN), OUTLINE_WIDTH, false)


static func _fill_ellipse(
	canvas: CanvasItem, centre: Vector2, radius_x: float, radius_y: float, color: Color
) -> void:
	var points := PackedVector2Array()
	for i in 24:
		var angle := TAU * float(i) / 24.0
		points.append(centre + Vector2(cos(angle) * radius_x, sin(angle) * radius_y))
	_fill(canvas, points, color)


## An ellipse whose long axis follows `along`, for petals that point outward.
static func _fill_oriented_ellipse(
	canvas: CanvasItem,
	centre: Vector2,
	along: Vector2,
	radius_along: float,
	radius_across: float,
	color: Color
) -> void:
	var axis := along.normalized()
	var cross := Vector2(-axis.y, axis.x)
	var points := PackedVector2Array()
	for i in 20:
		var angle := TAU * float(i) / 20.0
		points.append(
			centre + axis * (cos(angle) * radius_along) + cross * (sin(angle) * radius_across)
		)
	_fill(canvas, points, color)
	_outline(canvas, points, color)


static func _rounded_pot_outline(
	origin: Vector2, top_w: float, bottom_w: float, height: float, is_bowl: bool
) -> PackedVector2Array:
	var points := PackedVector2Array()
	var belly := 1.0 if is_bowl else 0.72
	for i in 15:
		var t := float(i) / 14.0
		var w := lerpf(bottom_w, top_w, t) * 0.5 + sin(PI * t) * height * 0.09 * belly
		points.append(origin + Vector2(-w, -height * t))
	for i in range(14, -1, -1):
		var t := float(i) / 14.0
		var w := lerpf(bottom_w, top_w, t) * 0.5 + sin(PI * t) * height * 0.09 * belly
		points.append(origin + Vector2(w, -height * t))
	return points


## Surface decoration, mirroring the painted and woven pots in the reference.
static func _draw_pattern(
	canvas: CanvasItem, pot: PotStyle, origin: Vector2, top_w: float, bottom_w: float, height: float
) -> void:
	match pot.pattern:
		PotStyle.Pattern.NONE:
			pass
		PotStyle.Pattern.BANDS:
			for i in 3:
				var t := 0.30 + float(i) * 0.18
				var w := lerpf(bottom_w, top_w, t) * 0.5
				canvas.draw_line(
					origin + Vector2(-w, -height * t), origin + Vector2(w, -height * t),
					pot.accent_color, maxf(1.5, height * 0.05), true
				)
		PotStyle.Pattern.CHEVRON:
			for i in 4:
				var t := 0.24 + float(i) * 0.17
				var w := lerpf(bottom_w, top_w, t) * 0.42
				var y := -height * t
				canvas.draw_polyline(
					PackedVector2Array([
						origin + Vector2(-w, y),
						origin + Vector2(0.0, y - height * 0.07),
						origin + Vector2(w, y),
					]),
					pot.accent_color, maxf(1.2, height * 0.028), true
				)
		PotStyle.Pattern.DOTS:
			for row in 3:
				for col in 3:
					var t := 0.28 + float(row) * 0.20
					var w := lerpf(bottom_w, top_w, t) * 0.5
					var x := lerpf(-w * 0.62, w * 0.62, float(col) / 2.0)
					_fill_ellipse(
						canvas, origin + Vector2(x, -height * t),
						height * 0.035, height * 0.035, pot.accent_color
					)
		PotStyle.Pattern.WEAVE:
			# Basketwork: close horizontals with a broken vertical rhythm.
			for i in 7:
				var t := 0.08 + float(i) * 0.13
				var w := lerpf(bottom_w, top_w, t) * 0.5
				canvas.draw_line(
					origin + Vector2(-w, -height * t), origin + Vector2(w, -height * t),
					pot.accent_color, maxf(1.0, height * 0.022), true
				)
			for i in 5:
				var x := lerpf(-top_w * 0.36, top_w * 0.36, float(i) / 4.0)
				canvas.draw_line(
					origin + Vector2(x, -height * 0.10), origin + Vector2(x, -height * 0.92),
					pot.accent_color.darkened(0.12), maxf(1.0, height * 0.016), true
				)


static func _bezier(from: Vector2, control: Vector2, to: Vector2, t: float) -> Vector2:
	var a := from.lerp(control, t)
	var b := control.lerp(to, t)
	return a.lerp(b, t)


## Foliage count for a growth value. Always at least two leaves once sprouted, so
## a young plant reads as a plant rather than a single blade.
static func _leaf_count(m: PlantMorphology, growth: float) -> int:
	return clampi(2 + int(growth * float(m.leaf_count_max - 2)), 2, m.leaf_count_max)


## Size easing. Early growth is visible quickly — the first session should show
## an obvious change — and later growth tapers, so maturity still feels earned.
static func _size_curve(growth: float) -> float:
	var t := clampf(growth, 0.0, 1.0)
	return lerpf(0.34, 1.0, sqrt(t))
