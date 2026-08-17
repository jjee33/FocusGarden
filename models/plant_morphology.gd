class_name PlantMorphology
extends Resource
## How a species is shaped, for PlantPainter to draw (§13's art fields).
##
## This is the art reference for a species. §13 lists stage sprites and a mature
## sprite; those fields still exist on PlantSpecies for when painted artwork is
## commissioned, and PlantPainter is used whenever they are empty. Keeping the
## description here rather than in drawing code means adding a species is
## authoring data, never editing a renderer (§13's "do NOT write individual plant
## behaviour directly into UI scenes").

## Overall growth habit — decides which layout routine draws the plant.
enum Form { ROSETTE, UPRIGHT, TRAILING, FROND, SPIKE, SUCCULENT, CACTUS, FLOWERING }

## Silhouette of a single leaf.
enum LeafShape { OVAL, LANCE, HEART, ROUND, STRAP, NEEDLE, SPLIT }

enum FlowerShape { DAISY, SPIRE, SPATHE, CLUSTER }

@export var form: Form = Form.ROSETTE
@export var leaf_shape: LeafShape = LeafShape.OVAL

@export_group("Foliage")
## Deeper shade at the base of each leaf.
@export var leaf_color_base: Color = Color("#4A7C3F")
## Lighter shade toward the tip, and toward newer growth.
@export var leaf_color_tip: Color = Color("#7FB069")
@export var stem_color: Color = Color("#5F7F42")
## Leaves on a fully grown plant. Growth interpolates up to this.
@export_range(2, 24) var leaf_count_max: int = 9
## Leaf length as a fraction of the plant's drawn height.
@export_range(0.1, 1.2) var leaf_length_ratio: float = 0.45
## Leaf width as a fraction of its own length.
@export_range(0.05, 1.0) var leaf_width_ratio: float = 0.34
## Sideways curve of the midrib. 0 is a straight blade; higher arcs over.
@export_range(-0.6, 0.6) var leaf_arc: float = 0.12
## How far foliage fans out from vertical, in radians.
@export_range(0.0, 1.6) var spread_radians: float = 0.9

@export_group("Variegation")
## 0 disables it. Cosmetic only — §20 forbids mutations affecting productivity.
@export_range(0.0, 1.0) var variegation: float = 0.0
@export var variegation_color: Color = Color("#E8E4C9")

@export_group("Flowers")
@export var has_flowers: bool = false
@export var flower_shape: FlowerShape = FlowerShape.DAISY
@export var flower_color: Color = Color("#E8C86A")
@export var flower_centre_color: Color = Color("#8A6A3A")
@export_range(1, 8) var flower_count: int = 3

@export_group("Motion")
## Idle sway amplitude (§43). Kept small — §43 warns against overanimating, and a
## plant that waves about is distracting on a screen meant for concentration.
@export_range(0.0, 0.25) var sway_amount: float = 0.05


## Builds a morphology in code, for the species dataset and for tests.
static func make(
	plant_form: Form,
	shape: LeafShape,
	base_color: String,
	tip_color: String,
	count: int,
	length_ratio: float,
	width_ratio: float
) -> PlantMorphology:
	var morphology := PlantMorphology.new()
	morphology.form = plant_form
	morphology.leaf_shape = shape
	morphology.leaf_color_base = Color(base_color)
	morphology.leaf_color_tip = Color(tip_color)
	morphology.stem_color = Color(base_color).lerp(Color("#6E8A4A"), 0.5)
	morphology.leaf_count_max = count
	morphology.leaf_length_ratio = length_ratio
	morphology.leaf_width_ratio = width_ratio
	return morphology
