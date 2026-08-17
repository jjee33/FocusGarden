class_name PotStyle
extends Resource
## A pot design (§21's "different pots", §76's "5+ pot designs").
##
## Pots are drawn by PlantPainter from these parameters, matching the variety of
## terracotta, glazed ceramic and woven baskets in the reference art. Data-driven
## so new pots are content, not code.

enum Shape { TAPERED, ROUNDED, CYLINDER, BOWL, BASKET }
enum Pattern { NONE, BANDS, CHEVRON, DOTS, WEAVE }

@export var id: StringName = &""
@export var display_name: String = ""
@export var shape: Shape = Shape.TAPERED
@export var pattern: Pattern = Pattern.NONE

@export_group("Colour")
@export var body_color: Color = Color("#C26A45")
@export var rim_color: Color = Color("#A9563A")
@export var accent_color: Color = Color("#E8C9A0")
@export var soil_color: Color = Color("#4A3B2A")

@export_group("Proportions")
## Width at the rim, as a multiple of pot height.
@export_range(0.5, 2.0) var top_width_ratio: float = 1.05
## Width at the base. Narrower than the top gives the classic tapered pot.
@export_range(0.3, 2.0) var bottom_width_ratio: float = 0.78

## Requirement to make this pot selectable. Null means available from the start.
@export var unlock_requirement: Requirement


static func make(
	pot_id: String,
	name: String,
	pot_shape: Shape,
	pot_pattern: Pattern,
	body: String,
	rim: String,
	accent: String
) -> PotStyle:
	var pot := PotStyle.new()
	pot.id = StringName(pot_id)
	pot.display_name = name
	pot.shape = pot_shape
	pot.pattern = pot_pattern
	pot.body_color = Color(body)
	pot.rim_color = Color(rim)
	pot.accent_color = Color(accent)
	return pot


func is_valid() -> bool:
	return id != &"" and not display_name.is_empty()
