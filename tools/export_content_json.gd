extends SceneTree
## Exports the authored content in data/ as JSON for the web client.
##
##     ... --headless --path . --script res://tools/export_content_json.gd
##
## WHY THIS EXISTS: the web app needs the same species, pots, achievements,
## decorations and expansions the desktop app ships, but it cannot read .tres —
## that format is Godot's, and loading a resource can execute code besides
## (see DATA_MODEL.md). Re-authoring the catalogue in TypeScript would create a
## second source of truth for content the two clients have to agree on exactly,
## which is the same mistake §14 and §38 rule out everywhere else.
##
## So the chain stays one-directional and single-sourced:
##
##     tools/generate_content.gd  ->  data/*.tres  ->  THIS  ->  web/…/content.generated.json
##
## Adding a species is still one edit in generate_content.gd. Re-run both.
##
## The output IS committed, so a web build never depends on having Godot present.
## Never hand-edit it — the next run overwrites.
##
## ENUMS ARE EXPORTED AS NAMES, not ordinals. A save file stores enum ints and
## must keep doing so, but content is re-exported from source every time, so
## there is no compatibility reason to ship magic numbers into TypeScript — and
## a reordered enum would silently repaint every plant if we did.

const OUTPUT_PATH: String = "res://web/src/content/content.generated.json"

# Enum orderings, mirrored from the model classes. GDScript cannot reflect an
# enum name from its value, so these are written out and asserted for length
# below — a name list that drifts from its enum is caught on the next run
# rather than shipping a wrong label.
const RARITY_NAMES: Array[String] = ["common", "uncommon", "rare", "epic", "legendary"]
const FORM_NAMES: Array[String] = [
	"rosette", "upright", "trailing", "frond", "spike", "succulent", "cactus", "flowering",
]
const LEAF_SHAPE_NAMES: Array[String] = [
	"oval", "lance", "heart", "round", "strap", "needle", "split",
]
const FLOWER_SHAPE_NAMES: Array[String] = ["daisy", "spire", "spathe", "cluster"]
const POT_SHAPE_NAMES: Array[String] = ["tapered", "rounded", "cylinder", "bowl", "basket"]
const POT_PATTERN_NAMES: Array[String] = ["none", "bands", "chevron", "dots", "weave"]
const ACHIEVEMENT_CATEGORY_NAMES: Array[String] = [
	"focus", "collection", "consistency", "garden", "exploration",
]
const DECORATION_SHAPE_NAMES: Array[String] = [
	"bench", "pond", "lantern", "path", "fence", "birdbath", "planter", "stone",
]
const REQUIREMENT_TYPE_NAMES: Array[String] = [
	"total_focus_minutes", "completed_sessions", "unique_focus_days", "consecutive_days",
	"sessions_in_time_window", "session_length_at_least", "break_sessions", "plants_matured",
	"species_discovered", "player_level", "catalogue_completion", "achievement_unlocked",
	"expedition_completed",
]
const REQUIREMENT_SCOPE_NAMES: Array[String] = ["global", "active_plant"]


func _init() -> void:
	await process_frame
	await process_frame

	if not _assert_enum_names():
		quit(1)
		return

	var content_db := root.get_node("/root/ContentDB")
	var species: Array = content_db.get_all_species()
	if species.is_empty():
		printerr("No species loaded. Run tools/generate_content.gd first.")
		quit(1)
		return

	var payload := {
		# Bumped only when the SHAPE of this file changes, so the web build can
		# refuse a file it does not understand rather than silently misreading it.
		"content_format": 1,
		"generated_by": "tools/export_content_json.gd",
		"species": _export_species(species),
		"pots": _export_pots(content_db.get_all_pots()),
		"achievements": _export_achievements(content_db.get_all_achievements()),
		"decorations": _export_decorations(content_db.get_all_decorations()),
		"expansions": _export_expansions(content_db.get_all_expansions()),
	}

	var text := JSON.stringify(payload, "  ", false) + "\n"
	var file := FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if file == null:
		printerr("Could not open %s for writing: %s" % [
			OUTPUT_PATH, error_string(FileAccess.get_open_error())
		])
		quit(1)
		return
	file.store_string(text)
	file.close()

	print("Wrote %s — %d species, %d pots, %d achievements, %d decorations, %d expansions." % [
		OUTPUT_PATH,
		payload["species"].size(), payload["pots"].size(), payload["achievements"].size(),
		payload["decorations"].size(), payload["expansions"].size(),
	])
	quit(0)


## Guards the hand-written name lists against their enums drifting apart.
func _assert_enum_names() -> bool:
	var checks := [
		["Rarity", RARITY_NAMES.size(), PlantSpecies.Rarity.size()],
		["Form", FORM_NAMES.size(), PlantMorphology.Form.size()],
		["LeafShape", LEAF_SHAPE_NAMES.size(), PlantMorphology.LeafShape.size()],
		["FlowerShape", FLOWER_SHAPE_NAMES.size(), PlantMorphology.FlowerShape.size()],
		["PotStyle.Shape", POT_SHAPE_NAMES.size(), PotStyle.Shape.size()],
		["PotStyle.Pattern", POT_PATTERN_NAMES.size(), PotStyle.Pattern.size()],
		["AchievementDef.Category", ACHIEVEMENT_CATEGORY_NAMES.size(), AchievementDef.Category.size()],
		["DecorationDef.Shape", DECORATION_SHAPE_NAMES.size(), DecorationDef.Shape.size()],
		["Requirement.Type", REQUIREMENT_TYPE_NAMES.size(), Requirement.Type.size()],
		["Requirement.Scope", REQUIREMENT_SCOPE_NAMES.size(), Requirement.Scope.size()],
	]
	var ok := true
	for check: Array in checks:
		if int(check[1]) != int(check[2]):
			printerr("Enum name list for %s has %d entries but the enum has %d." % [
				check[0], int(check[1]), int(check[2])
			])
			ok = false
	return ok


# --- Exporters ----------------------------------------------------------------

func _export_species(list: Array) -> Array:
	var out: Array = []
	for s: PlantSpecies in list:
		out.append({
			"id": String(s.id),
			"display_name": s.display_name,
			"scientific_name": s.scientific_name,
			"description": s.description,
			"rarity": _name_at(RARITY_NAMES, int(s.rarity)),
			"biome_id": String(s.biome_id),
			"tags": _string_names(s.tags),
			"growth_requirement": _requirement(s.growth_requirement),
			"unlock_requirement": _requirement(s.unlock_requirement),
			"morphology": _morphology(s.morphology),
			"botanical": _botanical(s.botanical),
			"preferred_pot_ids": _string_names(s.preferred_pot_ids),
			"allowed_mutation_ids": _string_names(s.allowed_mutation_ids),
			"hidden_until_discovered": s.hidden_until_discovered,
			"seasonal_months": s.seasonal_months.duplicate(),
			# Derived on this side so the two clients cannot disagree about a
			# figure that is computed, never authored (see PlantSpecies).
			"stage_count": s.get_stage_count(),
			"maturity_minutes": s.get_maturity_minutes(),
			"display_focus_minutes": s.get_display_focus_minutes(),
		})
	return out


func _export_pots(list: Array) -> Array:
	var out: Array = []
	for p: PotStyle in list:
		out.append({
			"id": String(p.id),
			"display_name": p.display_name,
			"shape": _name_at(POT_SHAPE_NAMES, int(p.shape)),
			"pattern": _name_at(POT_PATTERN_NAMES, int(p.pattern)),
			"body_color": _color(p.body_color),
			"rim_color": _color(p.rim_color),
			"accent_color": _color(p.accent_color),
			"soil_color": _color(p.soil_color),
			"top_width_ratio": p.top_width_ratio,
			"bottom_width_ratio": p.bottom_width_ratio,
			"unlock_requirement": _requirement(p.unlock_requirement),
		})
	return out


func _export_achievements(list: Array) -> Array:
	var out: Array = []
	for a: AchievementDef in list:
		out.append({
			"id": String(a.id),
			"title": a.title,
			"description": a.description,
			"category": _name_at(ACHIEVEMENT_CATEGORY_NAMES, int(a.category)),
			"rarity": _name_at(RARITY_NAMES, int(a.rarity)),
			"hidden": a.hidden,
			"track_progress": a.track_progress,
			"requirement": _requirement(a.requirement),
		})
	return out


func _export_decorations(list: Array) -> Array:
	var out: Array = []
	for d: DecorationDef in list:
		out.append({
			"id": String(d.id),
			"display_name": d.display_name,
			"shape": _name_at(DECORATION_SHAPE_NAMES, int(d.shape)),
			"primary_color": _color(d.primary_color),
			"accent_color": _color(d.accent_color),
			"unlock_expansion_id": String(d.unlock_expansion_id),
		})
	return out


func _export_expansions(list: Array) -> Array:
	var out: Array = []
	for e: GardenExpansion in list:
		out.append({
			"id": String(e.id),
			"display_name": e.display_name,
			"description": e.description,
			"grid_width": e.grid_size.x,
			"grid_height": e.grid_size.y,
			"unlocks_decorations": _string_names(e.unlocks_decorations),
			"requirement": _requirement(e.requirement),
		})
	return out


# --- Value helpers ------------------------------------------------------------

## Null stays null. An absent requirement means "available from the start", and
## substituting an always-true stand-in here would hide that distinction from the
## web client exactly where it matters.
func _requirement(r: Requirement) -> Variant:
	if r == null:
		return null
	return {
		"type": _name_at(REQUIREMENT_TYPE_NAMES, int(r.type)),
		"scope": _name_at(REQUIREMENT_SCOPE_NAMES, int(r.scope)),
		"params": r.params.duplicate(true),
		"description_override": r.description_override,
	}


func _morphology(m: PlantMorphology) -> Variant:
	if m == null:
		return null
	return {
		"form": _name_at(FORM_NAMES, int(m.form)),
		"leaf_shape": _name_at(LEAF_SHAPE_NAMES, int(m.leaf_shape)),
		"leaf_color_base": _color(m.leaf_color_base),
		"leaf_color_tip": _color(m.leaf_color_tip),
		"stem_color": _color(m.stem_color),
		"leaf_count_max": m.leaf_count_max,
		"leaf_length_ratio": m.leaf_length_ratio,
		"leaf_width_ratio": m.leaf_width_ratio,
		"leaf_arc": m.leaf_arc,
		"spread_radians": m.spread_radians,
		"variegation": m.variegation,
		"variegation_color": _color(m.variegation_color),
		"has_flowers": m.has_flowers,
		"flower_shape": _name_at(FLOWER_SHAPE_NAMES, int(m.flower_shape)),
		"flower_color": _color(m.flower_color),
		"flower_centre_color": _color(m.flower_centre_color),
		"flower_count": m.flower_count,
		"sway_amount": m.sway_amount,
	}


func _botanical(b: BotanicalInfo) -> Variant:
	if b == null:
		return null
	return {
		"family": b.family,
		"native_region": b.native_region,
		"light_preference": b.light_preference,
		"watering_preference": b.watering_preference,
		"care_difficulty": b.care_difficulty,
		"interesting_fact": b.interesting_fact,
	}


## "#RRGGBB" — CSS wants 0-255 hex, Godot stores 0..1 floats. Alpha is dropped
## because no authored content colour uses it; a translucent leaf would be a
## content bug, not something to carry silently into the web build.
func _color(c: Color) -> String:
	return "#" + c.to_html(false).to_upper()


func _string_names(values: Array) -> Array:
	var out: Array = []
	for v: Variant in values:
		out.append(String(v))
	return out


## Out-of-range enum ints become an explicit marker rather than crashing or
## silently picking entry zero, so a bad value is visible in the output.
func _name_at(names: Array[String], index: int) -> String:
	if index < 0 or index >= names.size():
		return "unknown_%d" % index
	return names[index]
