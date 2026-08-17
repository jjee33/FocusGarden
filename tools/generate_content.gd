extends SceneTree
## Authors the game's static content as .tres resources.
##
##     ... --headless --path . --script res://tools/generate_content.gd
##
## WHY A GENERATOR RATHER THAN HAND-WRITTEN .tres: a species is a dozen fields
## plus three sub-resources. Hand-authoring sixteen of those in .tres syntax is
## unreviewable and easy to get subtly wrong, and the editor inspector is not
## available in this workflow. Defining them here keeps the whole catalogue
## readable and diffable in one place, while still producing the real Resource
## files ContentDB loads and that the Godot inspector can edit later.
##
## The generated .tres ARE committed. This script is re-run only when content
## changes, and it overwrites — never hand-edit the output, or the next run will
## silently discard the edit.
##
## §17: botanical text is real and lives in BotanicalInfo, deliberately separate
## from anything gameplay reads, so a factual correction can never alter balance.

const PLANTS_DIR: String = "res://data/plants"
const POTS_DIR: String = "res://data/pots"
const ACHIEVEMENTS_DIR: String = "res://data/achievements"

func _init() -> void:
	_ensure_dir(PLANTS_DIR)
	_ensure_dir(POTS_DIR)
	_ensure_dir(ACHIEVEMENTS_DIR)

	var species_count := _write_species()
	var pot_count := _write_pots()
	var achievement_count := _write_achievements()

	print("Generated %d species, %d pots, %d achievements." % [
		species_count, pot_count, achievement_count
	])
	quit(0)


# --- Species ------------------------------------------------------------------

func _write_species() -> int:
	var written := 0

	# --- Common: the starters a new player meets first (§46). ---

	written += _species({
		"id": "pothos",
		"name": "Golden Pothos",
		"latin": "Epipremnum aureum",
		"rarity": PlantSpecies.Rarity.COMMON,
		"biome": "houseplant",
		"description": "Forgiving and eager. Trails happily from any shelf it is given, and asks for very little in return.",
		# §47: "Complete 4 Pomodoro-equivalent sessions."
		"requirement": Requirement.make(Requirement.Type.COMPLETED_SESSIONS, {"count": 4}, Requirement.Scope.ACTIVE_PLANT),
		"morphology": _morph(PlantMorphology.Form.TRAILING, PlantMorphology.LeafShape.HEART, "#3F7A3A", "#8CC06A", 10, 0.62, 0.80, {
			"variegation": 0.5, "variegation_color": "#E4DC9A", "arc": 0.18, "spread": 1.1,
		}),
		"botanical": {
			"family": "Araceae", "region": "French Polynesia",
			"light": "Low to bright indirect", "water": "When the top two inches dry out",
			"difficulty": "Very easy",
			"fact": "Pothos rarely flowers in cultivation — most plants grown indoors have never bloomed at all.",
		},
		"tags": ["trailing", "beginner"],
	})

	written += _species({
		"id": "aloe_vera",
		"name": "Aloe Vera",
		"latin": "Aloe barbadensis miller",
		"rarity": PlantSpecies.Rarity.COMMON,
		"biome": "desert",
		"description": "Thick, water-holding blades in a tidy rosette. Patient through neglect, unimpressed by fuss.",
		# §47: "Accumulate 100 valid focus minutes."
		"requirement": Requirement.make(Requirement.Type.TOTAL_FOCUS_MINUTES, {"amount": 100.0}, Requirement.Scope.ACTIVE_PLANT),
		"morphology": _morph(PlantMorphology.Form.ROSETTE, PlantMorphology.LeafShape.LANCE, "#5E8C5A", "#9BC08A", 9, 0.62, 0.20, {
			"arc": 0.10, "spread": 1.0, "sway": 0.035,
		}),
		"botanical": {
			"family": "Asphodelaceae", "region": "Arabian Peninsula",
			"light": "Bright, some direct sun", "water": "Sparingly; let it dry fully",
			"difficulty": "Easy",
			"fact": "Aloe has been cultivated so long that it no longer exists reliably in the wild.",
		},
		"tags": ["succulent", "beginner"],
	})

	written += _species({
		"id": "snake_plant",
		"name": "Snake Plant",
		"latin": "Dracaena trifasciata",
		"rarity": PlantSpecies.Rarity.COMMON,
		"biome": "desert",
		"description": "Upright banded blades that seem to grow while you are not looking. Nearly impossible to discourage.",
		"requirement": Requirement.make(Requirement.Type.TOTAL_FOCUS_MINUTES, {"amount": 120.0}, Requirement.Scope.ACTIVE_PLANT),
		"morphology": _morph(PlantMorphology.Form.SPIKE, PlantMorphology.LeafShape.STRAP, "#3D6B44", "#7FA556", 7, 0.80, 0.11, {
			"variegation": 0.35, "variegation_color": "#D8CE7E", "arc": 0.04, "spread": 0.85,
			"sway": 0.02,
		}),
		"botanical": {
			"family": "Asparagaceae", "region": "West Africa",
			"light": "Anything from shade to bright", "water": "Every few weeks at most",
			"difficulty": "Very easy",
			"fact": "It keeps its pores shut by day and opens them at night, losing far less water than most houseplants.",
		},
		"tags": ["architectural", "beginner"],
	})

	written += _species({
		"id": "spider_plant",
		"name": "Spider Plant",
		"latin": "Chlorophytum comosum",
		"rarity": PlantSpecies.Rarity.COMMON,
		"biome": "houseplant",
		"description": "Arching striped leaves that throw out little copies of themselves on long stems.",
		"requirement": Requirement.make(Requirement.Type.COMPLETED_SESSIONS, {"count": 6}, Requirement.Scope.ACTIVE_PLANT),
		"morphology": _morph(PlantMorphology.Form.ROSETTE, PlantMorphology.LeafShape.STRAP, "#4C8446", "#93C271", 14, 0.60, 0.13, {
			"variegation": 0.6, "variegation_color": "#F0EEC4", "arc": 0.30, "spread": 1.35,
			"sway": 0.07,
		}),
		"botanical": {
			"family": "Asparagaceae", "region": "Southern Africa",
			"light": "Bright indirect", "water": "Keep lightly moist",
			"difficulty": "Very easy",
			"fact": "The dangling plantlets are clones, and will root in a glass of water within a week or two.",
		},
		"tags": ["variegated", "beginner"],
	})

	written += _species({
		"id": "jade_plant",
		"name": "Jade Plant",
		"latin": "Crassula ovata",
		"rarity": PlantSpecies.Rarity.COMMON,
		"biome": "desert",
		"description": "A small tree of glossy coin-shaped leaves. Grows slowly, and lives a very long time.",
		"requirement": Requirement.make(Requirement.Type.TOTAL_FOCUS_MINUTES, {"amount": 150.0}, Requirement.Scope.ACTIVE_PLANT),
		"morphology": _morph(PlantMorphology.Form.UPRIGHT, PlantMorphology.LeafShape.ROUND, "#4B7D46", "#8FBB74", 7, 0.26, 0.78, {
			"arc": 0.05, "spread": 1.30, "sway": 0.03,
		}),
		"botanical": {
			"family": "Crassulaceae", "region": "Mozambique and South Africa",
			"light": "Bright, some direct sun", "water": "Deeply, then let it dry",
			"difficulty": "Easy",
			"fact": "Given enough decades a jade plant becomes genuinely tree-like, with a thick woody trunk.",
		},
		"tags": ["succulent", "slow"],
	})

	# --- Uncommon ---

	written += _species({
		"id": "echeveria",
		"name": "Echeveria",
		"latin": "Echeveria elegans",
		"rarity": PlantSpecies.Rarity.UNCOMMON,
		"biome": "desert",
		"description": "A geometric rosette of pale blue-green leaves, arranged with improbable precision.",
		"requirement": Requirement.make(Requirement.Type.TOTAL_FOCUS_MINUTES, {"amount": 180.0}, Requirement.Scope.ACTIVE_PLANT),
		"morphology": _morph(PlantMorphology.Form.SUCCULENT, PlantMorphology.LeafShape.OVAL, "#7D9E85", "#C3D6BE", 12, 0.40, 0.5, {
			"sway": 0.02,
		}),
		"botanical": {
			"family": "Crassulaceae", "region": "Semi-desert Mexico",
			"light": "Bright, direct sun", "water": "Rarely, at the soil only",
			"difficulty": "Moderate",
			"fact": "The pale bloom on the leaves is a wax coating; wiping it off removes the plant's sunscreen.",
		},
		"tags": ["succulent", "geometric"],
	})

	written += _species({
		"id": "boston_fern",
		"name": "Boston Fern",
		"latin": "Nephrolepis exaltata",
		"rarity": PlantSpecies.Rarity.UNCOMMON,
		"biome": "woodland",
		"description": "Soft arching fronds that fill a corner. Wants humidity, and will tell you when it is not getting it.",
		"requirement": Requirement.make(Requirement.Type.TOTAL_FOCUS_MINUTES, {"amount": 220.0}, Requirement.Scope.ACTIVE_PLANT),
		"morphology": _morph(PlantMorphology.Form.FROND, PlantMorphology.LeafShape.LANCE, "#3E7A42", "#84B564", 9, 0.52, 0.16, {
			"arc": 0.22, "spread": 0.95, "sway": 0.075,
		}),
		"botanical": {
			"family": "Nephrolepidaceae", "region": "Tropical Americas",
			"light": "Bright indirect, never direct", "water": "Constantly damp, never soggy",
			"difficulty": "Fussy about humidity",
			"fact": "Ferns reproduce by spores, not seeds — the brown dots under the fronds are not a disease.",
		},
		"tags": ["fern", "humidity"],
	})

	written += _species({
		"id": "rubber_plant",
		"name": "Rubber Plant",
		"latin": "Ficus elastica",
		"rarity": PlantSpecies.Rarity.UNCOMMON,
		"biome": "tropical",
		"description": "Broad lacquered leaves on a confident upright stem. Grows toward whatever light it can find.",
		"requirement": Requirement.make(Requirement.Type.TOTAL_FOCUS_MINUTES, {"amount": 260.0}, Requirement.Scope.ACTIVE_PLANT),
		"morphology": _morph(PlantMorphology.Form.UPRIGHT, PlantMorphology.LeafShape.OVAL, "#2F5F3B", "#5E8F4E", 8, 0.42, 0.50, {
			"arc": 0.08, "spread": 1.0, "sway": 0.035,
		}),
		"botanical": {
			"family": "Moraceae", "region": "Southeast Asia",
			"light": "Bright indirect", "water": "When the top inch dries",
			"difficulty": "Easy",
			"fact": "Its milky sap was once a commercial rubber source, before the Pará rubber tree displaced it.",
		},
		"tags": ["architectural", "ficus"],
	})

	written += _species({
		"id": "peace_lily",
		"name": "Peace Lily",
		"latin": "Spathiphyllum wallisii",
		"rarity": PlantSpecies.Rarity.UNCOMMON,
		"biome": "tropical",
		"description": "Deep green leaves and a single white bract that unfurls like a held breath.",
		"requirement": Requirement.make(Requirement.Type.TOTAL_FOCUS_MINUTES, {"amount": 200.0}, Requirement.Scope.ACTIVE_PLANT),
		"morphology": _morph(PlantMorphology.Form.FLOWERING, PlantMorphology.LeafShape.LANCE, "#2E6138", "#5C9150", 9, 0.52, 0.30, {
			"arc": 0.16, "spread": 1.0, "sway": 0.05,
			"flowers": true, "flower_shape": PlantMorphology.FlowerShape.SPATHE,
			"flower_color": "#F6F2E4", "flower_centre": "#D6D08E", "flower_count": 3,
		}),
		"botanical": {
			"family": "Araceae", "region": "Tropical Americas",
			"light": "Low to medium indirect", "water": "Keep evenly moist",
			"difficulty": "Easy",
			"fact": "The white 'flower' is a modified leaf; the true flowers are the tiny bumps on the spike it wraps.",
		},
		"tags": ["flowering", "low-light"],
	})

	# --- Rare ---

	written += _species({
		"id": "monstera",
		"name": "Monstera",
		"latin": "Monstera deliciosa",
		"rarity": PlantSpecies.Rarity.RARE,
		"biome": "tropical",
		"description": "Enormous split leaves that arrive one at a time, each bigger than the last. Worth the wait.",
		# §47: "Accumulate 250 valid focus minutes."
		"requirement": Requirement.make(Requirement.Type.TOTAL_FOCUS_MINUTES, {"amount": 250.0}, Requirement.Scope.ACTIVE_PLANT),
		"morphology": _morph(PlantMorphology.Form.UPRIGHT, PlantMorphology.LeafShape.SPLIT, "#2C5F35", "#63A054", 8, 0.48, 0.86, {
			"arc": 0.10, "spread": 1.1, "sway": 0.045,
		}),
		"botanical": {
			"family": "Araceae", "region": "Southern Mexico to Panama",
			"light": "Bright indirect", "water": "When the top two inches dry",
			"difficulty": "Easy once established",
			"fact": "The holes are called fenestrations, and are thought to let wind and light pass through to leaves below.",
		},
		"tags": ["statement", "fenestrated"],
	})

	written += _species({
		"id": "lavender",
		"name": "English Lavender",
		"latin": "Lavandula angustifolia",
		"rarity": PlantSpecies.Rarity.RARE,
		"biome": "mediterranean",
		"description": "Silver-grey foliage under a haze of purple spires. Smells like a warm afternoon.",
		"requirement": Requirement.make(Requirement.Type.UNIQUE_FOCUS_DAYS, {"count": 7}, Requirement.Scope.ACTIVE_PLANT),
		"morphology": _morph(PlantMorphology.Form.FLOWERING, PlantMorphology.LeafShape.NEEDLE, "#6E8168", "#A8B79A", 16, 0.50, 0.16, {
			"arc": 0.06, "spread": 1.05, "sway": 0.08,
			"flowers": true, "flower_shape": PlantMorphology.FlowerShape.SPIRE,
			"flower_color": "#8E7CB8", "flower_centre": "#6B5A96", "flower_count": 6,
		}),
		"botanical": {
			"family": "Lamiaceae", "region": "Mediterranean hillsides",
			"light": "Full sun", "water": "Drought tolerant once rooted",
			"difficulty": "Needs sharp drainage",
			"fact": "The scent comes from oil glands on the leaves, which is why brushing past a lavender bush releases it.",
		},
		"tags": ["flowering", "fragrant"],
	})

	written += _species({
		"id": "sunflower",
		"name": "Sunflower",
		"latin": "Helianthus annuus",
		"rarity": PlantSpecies.Rarity.RARE,
		"biome": "temperate",
		"description": "Grows fast, grows tall, and faces the morning. Best raised alongside early starts.",
		# §47: "Complete several morning sessions."
		"requirement": Requirement.make(
			Requirement.Type.SESSIONS_IN_TIME_WINDOW,
			{"count": 8, "start_hour": 5, "end_hour": 11},
			Requirement.Scope.ACTIVE_PLANT
		),
		"morphology": _morph(PlantMorphology.Form.FLOWERING, PlantMorphology.LeafShape.HEART, "#4C7A32", "#84AC52", 7, 0.54, 0.74, {
			"arc": 0.10, "spread": 0.9, "sway": 0.06,
			"flowers": true, "flower_shape": PlantMorphology.FlowerShape.DAISY,
			"flower_color": "#EFB63F", "flower_centre": "#7A4B22", "flower_count": 1,
		}),
		"botanical": {
			"family": "Asteraceae", "region": "North America",
			"light": "As much direct sun as possible", "water": "Generously; they drink hard",
			"difficulty": "Easy",
			"fact": "Young sunflowers track the sun across the sky, but mature heads settle facing east for good.",
		},
		"tags": ["morning", "annual"],
	})

	# --- Epic ---

	written += _species({
		"id": "orchid",
		"name": "Moth Orchid",
		"latin": "Phalaenopsis amabilis",
		"rarity": PlantSpecies.Rarity.EPIC,
		"biome": "tropical",
		"description": "Blooms that last for months on a single arching spike. Rewards steadiness over intensity.",
		# §47: "Focus on 5 separate days."
		"requirement": Requirement.make(Requirement.Type.UNIQUE_FOCUS_DAYS, {"count": 5}, Requirement.Scope.ACTIVE_PLANT),
		"morphology": _morph(PlantMorphology.Form.FLOWERING, PlantMorphology.LeafShape.OVAL, "#37663D", "#6D9B5C", 6, 0.52, 0.52, {
			"arc": 0.20, "spread": 1.25, "sway": 0.04,
			"flowers": true, "flower_shape": PlantMorphology.FlowerShape.CLUSTER,
			"flower_color": "#F0DCE8", "flower_centre": "#C08AAE", "flower_count": 5,
		}),
		"botanical": {
			"family": "Orchidaceae", "region": "Southeast Asia and northern Australia",
			"light": "Bright indirect, never direct", "water": "A thorough soak, then let the roots dry",
			"difficulty": "Moderate",
			"fact": "In the wild it grows on tree bark, not soil — its roots are green and photosynthesise.",
		},
		"tags": ["flowering", "epiphyte"],
		"hidden": true,
	})

	written += _species({
		"id": "moon_cactus",
		"name": "Moon Cactus",
		"latin": "Gymnocalycium mihanovichii",
		"rarity": PlantSpecies.Rarity.EPIC,
		"biome": "desert",
		"description": "A small, oddly cheerful cactus. Keeps company through late sessions.",
		# §47: "Complete several evening sessions."
		"requirement": Requirement.make(
			Requirement.Type.SESSIONS_IN_TIME_WINDOW,
			{"count": 8, "start_hour": 20, "end_hour": 3},
			Requirement.Scope.ACTIVE_PLANT
		),
		"morphology": _morph(PlantMorphology.Form.CACTUS, PlantMorphology.LeafShape.NEEDLE, "#5D8A54", "#A6C08C", 6, 0.35, 0.3, {
			"sway": 0.015,
			"flowers": true, "flower_shape": PlantMorphology.FlowerShape.DAISY,
			"flower_color": "#E9899B", "flower_centre": "#F3D9A0", "flower_count": 1,
		}),
		"botanical": {
			"family": "Cactaceae", "region": "Paraguay and northern Argentina",
			"light": "Bright, filtered", "water": "Very sparingly",
			"difficulty": "Moderate",
			"fact": "The brightly coloured tops sold in shops are mutants with no chlorophyll, grafted onto a green host to survive.",
		},
		"tags": ["evening", "cactus"],
		"hidden": true,
	})

	written += _species({
		"id": "calathea",
		"name": "Prayer Plant",
		"latin": "Calathea orbifolia",
		"rarity": PlantSpecies.Rarity.EPIC,
		"biome": "tropical",
		"description": "Broad silver-striped leaves that lift at dusk and lower again by morning.",
		"requirement": Requirement.make(Requirement.Type.TOTAL_FOCUS_MINUTES, {"amount": 420.0}, Requirement.Scope.ACTIVE_PLANT),
		"morphology": _morph(PlantMorphology.Form.ROSETTE, PlantMorphology.LeafShape.OVAL, "#2F6140", "#6FA05F", 8, 0.50, 0.68, {
			"variegation": 0.7, "variegation_color": "#CFE0C0", "arc": 0.14, "spread": 1.05,
			"sway": 0.05,
		}),
		"botanical": {
			"family": "Marantaceae", "region": "Bolivian rainforest",
			"light": "Medium indirect", "water": "Distilled or rainwater; it dislikes tap minerals",
			"difficulty": "Demanding",
			"fact": "The nightly leaf movement is called nyctinasty, driven by water pressure in a hinge at each leaf base.",
		},
		"tags": ["variegated", "demanding"],
		"hidden": true,
	})

	# --- Legendary ---

	written += _species({
		"id": "bonsai",
		"name": "Juniper Bonsai",
		"latin": "Juniperus procumbens",
		"rarity": PlantSpecies.Rarity.LEGENDARY,
		"biome": "temperate",
		"description": "A tree kept small on purpose, shaped over years. The only plant here that measures time in seasons.",
		# §47: "Focus on 14 separate days."
		"requirement": Requirement.make(Requirement.Type.UNIQUE_FOCUS_DAYS, {"count": 14}, Requirement.Scope.ACTIVE_PLANT),
		"morphology": _morph(PlantMorphology.Form.UPRIGHT, PlantMorphology.LeafShape.ROUND, "#39603A", "#7A9B57", 13, 0.22, 0.95, {
			"arc": 0.18, "spread": 1.45, "sway": 0.03,
		}),
		"botanical": {
			"family": "Cupressaceae", "region": "Japan",
			"light": "Full sun, outdoors where possible", "water": "Check daily; the pots are shallow",
			"difficulty": "A long commitment",
			"fact": "Bonsai is a cultivation practice, not a species — the tree is ordinary, and only the care is unusual.",
		},
		"tags": ["longterm", "tree"],
		"hidden": true,
		"unlock": Requirement.make(Requirement.Type.PLANTS_MATURED, {"count": 5}),
	})

	return written


# --- Pots ---------------------------------------------------------------------

func _write_pots() -> int:
	var pots: Array[PotStyle] = [
		PotStyle.make(
			"terracotta_basic", "Terracotta", PotStyle.Shape.TAPERED, PotStyle.Pattern.NONE,
			"#C26A45", "#A9563A", "#E8C9A0"
		),
		PotStyle.make(
			"ceramic_sage", "Sage Ceramic", PotStyle.Shape.ROUNDED, PotStyle.Pattern.BANDS,
			"#7FA08B", "#66876F", "#E4EDE0"
		),
		PotStyle.make(
			"stoneware_cream", "Cream Stoneware", PotStyle.Shape.CYLINDER, PotStyle.Pattern.NONE,
			"#E4D6BC", "#CDBB9B", "#B7A385"
		),
		PotStyle.make(
			"painted_chevron", "Painted Chevron", PotStyle.Shape.TAPERED, PotStyle.Pattern.CHEVRON,
			"#D9A05B", "#B67F3E", "#5C4A32"
		),
		PotStyle.make(
			"woven_basket", "Woven Basket", PotStyle.Shape.BASKET, PotStyle.Pattern.WEAVE,
			"#CBA871", "#B08F5A", "#9C7C4C"
		),
		PotStyle.make(
			"speckled_bowl", "Speckled Bowl", PotStyle.Shape.BOWL, PotStyle.Pattern.DOTS,
			"#8FA5B5", "#75899A", "#E9EFF2"
		),
	]
	# Later pots are level unlocks, matching ProgressionManager's LEVEL_UNLOCKS ids.
	pots[1].unlock_requirement = Requirement.make(Requirement.Type.PLAYER_LEVEL, {"level": 2})
	pots[3].unlock_requirement = Requirement.make(Requirement.Type.PLAYER_LEVEL, {"level": 8})
	pots[4].unlock_requirement = Requirement.make(Requirement.Type.PLANTS_MATURED, {"count": 3})
	pots[5].unlock_requirement = Requirement.make(Requirement.Type.PLAYER_LEVEL, {"level": 14})

	for pot: PotStyle in pots:
		_save(pot, "%s/%s.tres" % [POTS_DIR, pot.id])
	return pots.size()


# --- Achievements (§26) -------------------------------------------------------

func _write_achievements() -> int:
	var defs: Array[Dictionary] = [
		# Focus
		{"id": "first_sprout", "title": "First Sprout", "desc": "Complete your first focus session.",
		 "cat": AchievementDef.Category.FOCUS, "rarity": PlantSpecies.Rarity.COMMON,
		 "req": Requirement.make(Requirement.Type.COMPLETED_SESSIONS, {"count": 1})},
		{"id": "deep_work", "title": "Deep Work", "desc": "Complete a 90-minute focus session.",
		 "cat": AchievementDef.Category.FOCUS, "rarity": PlantSpecies.Rarity.UNCOMMON,
		 "req": Requirement.make(Requirement.Type.SESSION_LENGTH_AT_LEAST, {"minutes": 90.0, "count": 1})},
		{"id": "twenty_five_sessions", "title": "Finding the Rhythm", "desc": "Complete 25 focus sessions.",
		 "cat": AchievementDef.Category.FOCUS, "rarity": PlantSpecies.Rarity.COMMON,
		 "req": Requirement.make(Requirement.Type.COMPLETED_SESSIONS, {"count": 25})},
		{"id": "hundred_sessions", "title": "Well Practised", "desc": "Complete 100 focus sessions.",
		 "cat": AchievementDef.Category.FOCUS, "rarity": PlantSpecies.Rarity.RARE,
		 "req": Requirement.make(Requirement.Type.COMPLETED_SESSIONS, {"count": 100})},
		{"id": "ten_hours", "title": "Ten Hours In", "desc": "Reach 10 hours of focus.",
		 "cat": AchievementDef.Category.FOCUS, "rarity": PlantSpecies.Rarity.COMMON,
		 "req": Requirement.make(Requirement.Type.TOTAL_FOCUS_MINUTES, {"amount": 600.0})},
		{"id": "century_garden", "title": "Century Garden", "desc": "Reach 100 hours of focus.",
		 "cat": AchievementDef.Category.FOCUS, "rarity": PlantSpecies.Rarity.EPIC,
		 "req": Requirement.make(Requirement.Type.TOTAL_FOCUS_MINUTES, {"amount": 6000.0})},
		{"id": "five_hundred_hours", "title": "A Real Garden", "desc": "Reach 500 hours of focus.",
		 "cat": AchievementDef.Category.FOCUS, "rarity": PlantSpecies.Rarity.LEGENDARY,
		 "req": Requirement.make(Requirement.Type.TOTAL_FOCUS_MINUTES, {"amount": 30000.0})},
		{"id": "marathon", "title": "Marathon", "desc": "Complete ten sessions of at least an hour.",
		 "cat": AchievementDef.Category.FOCUS, "rarity": PlantSpecies.Rarity.RARE,
		 "req": Requirement.make(Requirement.Type.SESSION_LENGTH_AT_LEAST, {"minutes": 60.0, "count": 10})},

		# Consistency
		{"id": "consistency", "title": "Consistency", "desc": "Focus on 7 consecutive days.",
		 "cat": AchievementDef.Category.CONSISTENCY, "rarity": PlantSpecies.Rarity.UNCOMMON,
		 "req": Requirement.make(Requirement.Type.CONSECUTIVE_DAYS, {"count": 7})},
		{"id": "month_of_days", "title": "A Month of Days", "desc": "Focus on 30 consecutive days.",
		 "cat": AchievementDef.Category.CONSISTENCY, "rarity": PlantSpecies.Rarity.EPIC,
		 "req": Requirement.make(Requirement.Type.CONSECUTIVE_DAYS, {"count": 30})},
		{"id": "fifty_days", "title": "Fifty Days", "desc": "Focus on 50 separate days.",
		 "cat": AchievementDef.Category.CONSISTENCY, "rarity": PlantSpecies.Rarity.RARE,
		 "req": Requirement.make(Requirement.Type.UNIQUE_FOCUS_DAYS, {"count": 50})},
		{"id": "night_owl", "title": "Night Owl", "desc": "Complete 25 sessions after 8 PM.",
		 "cat": AchievementDef.Category.CONSISTENCY, "rarity": PlantSpecies.Rarity.UNCOMMON,
		 "req": Requirement.make(Requirement.Type.SESSIONS_IN_TIME_WINDOW, {"count": 25, "start_hour": 20, "end_hour": 4})},
		{"id": "early_bird", "title": "Early Bird", "desc": "Complete 25 sessions before 9 AM.",
		 "cat": AchievementDef.Category.CONSISTENCY, "rarity": PlantSpecies.Rarity.UNCOMMON,
		 "req": Requirement.make(Requirement.Type.SESSIONS_IN_TIME_WINDOW, {"count": 25, "start_hour": 4, "end_hour": 8})},
		{"id": "taking_care", "title": "Taking Care", "desc": "Complete 100 breaks.",
		 "cat": AchievementDef.Category.CONSISTENCY, "rarity": PlantSpecies.Rarity.UNCOMMON,
		 "req": Requirement.make(Requirement.Type.BREAK_SESSIONS, {"count": 100})},

		# Collection
		{"id": "green_thumb", "title": "Green Thumb", "desc": "Bring 10 plants to maturity.",
		 "cat": AchievementDef.Category.COLLECTION, "rarity": PlantSpecies.Rarity.UNCOMMON,
		 "req": Requirement.make(Requirement.Type.PLANTS_MATURED, {"count": 10})},
		{"id": "first_bloom", "title": "First Bloom", "desc": "Bring your first plant to maturity.",
		 "cat": AchievementDef.Category.COLLECTION, "rarity": PlantSpecies.Rarity.COMMON,
		 "req": Requirement.make(Requirement.Type.PLANTS_MATURED, {"count": 1})},
		{"id": "fifty_plants", "title": "Overgrown", "desc": "Bring 50 plants to maturity.",
		 "cat": AchievementDef.Category.COLLECTION, "rarity": PlantSpecies.Rarity.EPIC,
		 "req": Requirement.make(Requirement.Type.PLANTS_MATURED, {"count": 50})},
		{"id": "botanist", "title": "Botanist", "desc": "Discover 8 species.",
		 "cat": AchievementDef.Category.COLLECTION, "rarity": PlantSpecies.Rarity.RARE,
		 "req": Requirement.make(Requirement.Type.SPECIES_DISCOVERED, {"count": 8})},
		{"id": "complete_catalogue", "title": "Complete Catalogue", "desc": "Discover every species.",
		 "cat": AchievementDef.Category.COLLECTION, "rarity": PlantSpecies.Rarity.LEGENDARY,
		 "req": Requirement.make(Requirement.Type.CATALOGUE_COMPLETION, {"ratio": 1.0})},
		{"id": "half_catalogue", "title": "Well Read", "desc": "Discover half the catalogue.",
		 "cat": AchievementDef.Category.COLLECTION, "rarity": PlantSpecies.Rarity.UNCOMMON,
		 "req": Requirement.make(Requirement.Type.CATALOGUE_COMPLETION, {"ratio": 0.5})},

		# Garden
		{"id": "level_five", "title": "Settling In", "desc": "Reach level 5.",
		 "cat": AchievementDef.Category.GARDEN, "rarity": PlantSpecies.Rarity.COMMON,
		 "req": Requirement.make(Requirement.Type.PLAYER_LEVEL, {"level": 5})},
		{"id": "level_twenty", "title": "Seasoned Gardener", "desc": "Reach level 20.",
		 "cat": AchievementDef.Category.GARDEN, "rarity": PlantSpecies.Rarity.RARE,
		 "req": Requirement.make(Requirement.Type.PLAYER_LEVEL, {"level": 20})},

		# Hidden (§26)
		{"id": "the_long_night", "title": "The Long Night", "desc": "Complete a session that starts after 2 AM.",
		 "cat": AchievementDef.Category.EXPLORATION, "rarity": PlantSpecies.Rarity.RARE,
		 "hidden": true,
		 "req": Requirement.make(Requirement.Type.SESSIONS_IN_TIME_WINDOW, {"count": 1, "start_hour": 2, "end_hour": 4})},
		{"id": "patient_gardener", "title": "The Patient Gardener", "desc": "Grow a plant that takes fourteen separate days.",
		 "cat": AchievementDef.Category.EXPLORATION, "rarity": PlantSpecies.Rarity.LEGENDARY,
		 "hidden": true,
		 "req": Requirement.make(Requirement.Type.UNIQUE_FOCUS_DAYS, {"count": 14})},
	]

	for entry: Dictionary in defs:
		var achievement := AchievementDef.new()
		achievement.id = StringName(entry["id"])
		achievement.title = entry["title"]
		achievement.description = entry["desc"]
		achievement.category = entry["cat"]
		achievement.rarity = entry["rarity"]
		achievement.hidden = entry.get("hidden", false)
		achievement.requirement = entry["req"]
		_save(achievement, "%s/%s.tres" % [ACHIEVEMENTS_DIR, achievement.id])
	return defs.size()


# --- Builders -----------------------------------------------------------------

func _species(entry: Dictionary) -> int:
	var species := PlantSpecies.new()
	species.id = StringName(entry["id"])
	species.display_name = entry["name"]
	species.scientific_name = entry["latin"]
	species.description = entry["description"]
	species.rarity = entry["rarity"]
	species.biome_id = StringName(entry["biome"])
	species.growth_requirement = entry["requirement"]
	species.morphology = entry["morphology"]
	species.hidden_until_discovered = entry.get("hidden", false)
	species.unlock_requirement = entry.get("unlock", null)

	var tags: Array[StringName] = []
	for tag: String in entry.get("tags", []):
		tags.append(StringName(tag))
	species.tags = tags

	var facts: Dictionary = entry["botanical"]
	var botanical := BotanicalInfo.new()
	botanical.family = facts["family"]
	botanical.native_region = facts["region"]
	botanical.light_preference = facts["light"]
	botanical.watering_preference = facts["water"]
	botanical.care_difficulty = facts["difficulty"]
	botanical.interesting_fact = facts["fact"]
	species.botanical = botanical

	_save(species, "%s/%s.tres" % [PLANTS_DIR, species.id])
	return 1


func _morph(
	form: PlantMorphology.Form,
	leaf: PlantMorphology.LeafShape,
	base: String,
	tip: String,
	count: int,
	length: float,
	width: float,
	options: Dictionary = {}
) -> PlantMorphology:
	var morphology := PlantMorphology.make(form, leaf, base, tip, count, length, width)
	morphology.leaf_arc = options.get("arc", 0.12)
	morphology.spread_radians = options.get("spread", 0.9)
	morphology.sway_amount = options.get("sway", 0.05)
	morphology.variegation = options.get("variegation", 0.0)
	if options.has("variegation_color"):
		morphology.variegation_color = Color(options["variegation_color"])
	morphology.has_flowers = options.get("flowers", false)
	if morphology.has_flowers:
		morphology.flower_shape = options.get("flower_shape", PlantMorphology.FlowerShape.DAISY)
		morphology.flower_color = Color(options.get("flower_color", "#E8C86A"))
		morphology.flower_centre_color = Color(options.get("flower_centre", "#8A6A3A"))
		morphology.flower_count = options.get("flower_count", 3)
	return morphology


func _save(resource: Resource, path: String) -> void:
	var error := ResourceSaver.save(resource, path)
	if error != OK:
		printerr("Failed to write %s (error %d)" % [path, error])


func _ensure_dir(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		DirAccess.make_dir_recursive_absolute(path)
