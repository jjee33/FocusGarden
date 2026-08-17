class_name Uid
extends RefCounted
## Unique identifier generation for player-owned records.
##
## Godot has no built-in UUID type. IDs here are time-prefixed so they sort
## chronologically when listed, with random suffix bits for collision resistance
## (§54 explicitly calls out duplicated IDs as a case to handle).

const _RANDOM_BITS: int = 8


## Returns an id like "s_1m9k3xq2-4f7a1c9e". The prefix names the record kind so
## a stray id in a log or save file is self-describing.
static func generate(prefix: String) -> String:
	var stamp := Time.get_unix_time_from_system()
	var stamp_part := String.num_int64(int(stamp * 1000.0), 36)
	var random_part := ""
	for i in _RANDOM_BITS:
		random_part += "0123456789abcdef"[randi() % 16]
	return "%s_%s-%s" % [prefix, stamp_part, random_part]


## True when `id` looks like something we generated. Used on load to reject
## malformed ids rather than letting them poison lookups.
static func is_valid(id: String) -> bool:
	return not id.is_empty() and id.contains("_") and id.contains("-")
