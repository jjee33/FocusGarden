class_name DictUtil
extends RefCounted
## Defensive readers for deserializing player data (§36 validation on load).
##
## Save files are JSON that may have been written by an older version, hand-edited,
## or truncated. Every read goes through here so a missing or wrong-typed key
## produces a sane default instead of a crash or a silently corrupt value.
##
## JSON has exactly one number type, so integers come back as floats. These
## helpers absorb that rather than making every call site remember it.


static func get_string(data: Dictionary, key: String, fallback: String = "") -> String:
	var value: Variant = data.get(key)
	return value if value is String else fallback


static func get_int(data: Dictionary, key: String, fallback: int = 0) -> int:
	var value: Variant = data.get(key)
	if value is float or value is int:
		return int(value)
	return fallback


static func get_float(data: Dictionary, key: String, fallback: float = 0.0) -> float:
	var value: Variant = data.get(key)
	if value is float or value is int:
		return float(value)
	return fallback


static func get_bool(data: Dictionary, key: String, fallback: bool = false) -> bool:
	var value: Variant = data.get(key)
	return value if value is bool else fallback


static func get_dict(data: Dictionary, key: String) -> Dictionary:
	var value: Variant = data.get(key)
	return value if value is Dictionary else {}


static func get_array(data: Dictionary, key: String) -> Array:
	var value: Variant = data.get(key)
	return value if value is Array else []


## String array with non-string entries dropped rather than coerced, so a
## corrupted entry cannot masquerade as a valid id.
static func get_string_array(data: Dictionary, key: String) -> PackedStringArray:
	var out := PackedStringArray()
	for entry: Variant in get_array(data, key):
		if entry is String:
			out.append(entry)
	return out


## Clamps a deserialized number into a legal range. Used for values where an
## out-of-range figure would corrupt downstream math (levels, stages, ratios).
static func get_clamped_float(
	data: Dictionary, key: String, minimum: float, maximum: float, fallback: float = 0.0
) -> float:
	return clampf(get_float(data, key, fallback), minimum, maximum)
