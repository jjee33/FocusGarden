class_name ShelfLayout
extends RefCounted
## The player's curated display shelf (§21). Player data — JSON.
##
## Plant placement is NOT stored here — each PlantInstance owns its own
## `shelf_slot`. Keeping placement in one place means the shelf and the plant can
## never disagree about where something is (§62's duplicate-placement bug).
## This resource holds only styling and decorations.

var layout_id: String = ""
var display_name: String = "My Shelf"
var style_id: StringName = &"warm_oak"
var background_id: StringName = &"cozy_wall"
var lighting_id: StringName = &"soft_afternoon"
var slot_count: int = 8
## Decorations keyed by slot index: { slot: int -> decoration_id: String }.
var decorations: Dictionary = {}


static func create(name: String = "My Shelf") -> ShelfLayout:
	var layout := ShelfLayout.new()
	layout.layout_id = Uid.generate("sh")
	layout.display_name = name
	return layout


func to_dict() -> Dictionary:
	return {
		"layout_id": layout_id,
		"display_name": display_name,
		"style_id": String(style_id),
		"background_id": String(background_id),
		"lighting_id": String(lighting_id),
		"slot_count": slot_count,
		"decorations": decorations.duplicate(true),
	}


static func from_dict(data: Dictionary) -> ShelfLayout:
	var layout := ShelfLayout.new()
	layout.layout_id = DictUtil.get_string(data, "layout_id")
	layout.display_name = DictUtil.get_string(data, "display_name", "My Shelf")
	layout.style_id = StringName(DictUtil.get_string(data, "style_id", "warm_oak"))
	layout.background_id = StringName(DictUtil.get_string(data, "background_id", "cozy_wall"))
	layout.lighting_id = StringName(DictUtil.get_string(data, "lighting_id", "soft_afternoon"))
	layout.slot_count = clampi(DictUtil.get_int(data, "slot_count", 8), 1, 64)
	layout.decorations = DictUtil.get_dict(data, "decorations")
	return layout
