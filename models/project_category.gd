class_name ProjectCategory
extends RefCounted
## What the player is working on (§9): Studying, Network+, Reading, Work…
##
## Users create their own, so these are player data (JSON), not authored content.
## The built-in starters are seeded on first launch and are deletable like any
## other — nothing here is special-cased.

var id: String = ""
var display_name: String = ""
## Token name from the theme palette (e.g. "moss"), never a raw hex value.
## Keeps categories re-themeable and stops save files from pinning old colors.
var color_token: String = "moss"
var icon_id: String = "leaf"
var created_at_utc: float = 0.0
var archived: bool = false
## Total credited focus minutes, maintained as a convenience rollup. Sessions
## remain authoritative; StatisticsManager can rebuild this from them at any time.
var total_focus_minutes: float = 0.0


static func create(name: String, color: String = "moss", icon: String = "leaf") -> ProjectCategory:
	var category := ProjectCategory.new()
	category.id = Uid.generate("p")
	category.display_name = name
	category.color_token = color
	category.icon_id = icon
	category.created_at_utc = Time.get_unix_time_from_system()
	return category


func to_dict() -> Dictionary:
	return {
		"id": id,
		"display_name": display_name,
		"color_token": color_token,
		"icon_id": icon_id,
		"created_at_utc": created_at_utc,
		"archived": archived,
		"total_focus_minutes": total_focus_minutes,
	}


static func from_dict(data: Dictionary) -> ProjectCategory:
	var category := ProjectCategory.new()
	category.id = DictUtil.get_string(data, "id")
	category.display_name = DictUtil.get_string(data, "display_name", "Untitled")
	category.color_token = DictUtil.get_string(data, "color_token", "moss")
	category.icon_id = DictUtil.get_string(data, "icon_id", "leaf")
	category.created_at_utc = DictUtil.get_float(data, "created_at_utc")
	category.archived = DictUtil.get_bool(data, "archived")
	category.total_focus_minutes = maxf(0.0, DictUtil.get_float(data, "total_focus_minutes"))
	return category
