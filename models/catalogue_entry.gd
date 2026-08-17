class_name CatalogueEntry
extends RefCounted
## Per-species collection record (§16). Player data — JSON.
##
## Backs the catalogue's discovered/undiscovered state and the per-species
## statistics in the detail view: number grown, first discovery date, fastest
## growth, total focus time associated with the species.

var species_id: StringName = &""
var discovered: bool = false
var first_discovered_at_utc: float = 0.0
var times_grown: int = 0
var total_focus_minutes: float = 0.0
## Fewest minutes taken to bring one of these to maturity. -1 until one matures.
var fastest_growth_minutes: float = -1.0
var favorite: bool = false


static func create(id: StringName) -> CatalogueEntry:
	var entry := CatalogueEntry.new()
	entry.species_id = id
	return entry


## Returns true only on first discovery, so the "new species!" reveal fires once.
func discover() -> bool:
	if discovered:
		return false
	discovered = true
	first_discovered_at_utc = Time.get_unix_time_from_system()
	return true


func record_maturity(growth_minutes: float) -> void:
	times_grown += 1
	if fastest_growth_minutes < 0.0 or growth_minutes < fastest_growth_minutes:
		fastest_growth_minutes = growth_minutes


func to_dict() -> Dictionary:
	return {
		"species_id": String(species_id),
		"discovered": discovered,
		"first_discovered_at_utc": first_discovered_at_utc,
		"times_grown": times_grown,
		"total_focus_minutes": total_focus_minutes,
		"fastest_growth_minutes": fastest_growth_minutes,
		"favorite": favorite,
	}


static func from_dict(data: Dictionary) -> CatalogueEntry:
	var entry := CatalogueEntry.new()
	entry.species_id = StringName(DictUtil.get_string(data, "species_id"))
	entry.discovered = DictUtil.get_bool(data, "discovered")
	entry.first_discovered_at_utc = DictUtil.get_float(data, "first_discovered_at_utc")
	entry.times_grown = maxi(0, DictUtil.get_int(data, "times_grown"))
	entry.total_focus_minutes = maxf(0.0, DictUtil.get_float(data, "total_focus_minutes"))
	entry.fastest_growth_minutes = DictUtil.get_float(data, "fastest_growth_minutes", -1.0)
	entry.favorite = DictUtil.get_bool(data, "favorite")
	return entry
