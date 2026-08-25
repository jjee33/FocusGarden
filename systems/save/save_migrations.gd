class_name SaveMigrations
extends RefCounted
## Versioned save migration chain (§36).
##
## §36 requires a migration framework "from the beginning", before there is
## anything to migrate. That is deliberate: the first time the save shape changes
## is exactly when it is too late to design this, because players already have
## files on disk.
##
## HOW TO ADD A MIGRATION
##   1. Bump SaveData.CURRENT_VERSION.
##   2. Append one step to `get_chain()` with the new from/to pair.
##   3. Add a test asserting an old fixture upgrades correctly.
## Steps are pure Dictionary -> Dictionary transforms so they can be tested
## without any file IO, and are applied strictly in order.
##
## Steps must never delete data they do not understand. An unknown key from a
## newer build that a downgrade left behind is harmless; deleting it is not.

enum Status {
	OK,             ## Already current, or migrated successfully.
	FUTURE_VERSION, ## Save is newer than this build. Refuse, never erase (§36).
	NO_PATH,        ## Version gap with no migration step covering it.
}

class Result extends RefCounted:
	var status: Status = Status.OK
	var data: Dictionary = {}
	var from_version: int = 0
	var to_version: int = 0
	var applied_steps: PackedStringArray = PackedStringArray()

	func is_ok() -> bool:
		return status == Status.OK


## The ordered migration chain. Empty at version 1 — there is nothing older than
## the first release. The framework around it is fully exercised by tests that
## supply their own chain.
static func get_chain() -> Array[Dictionary]:
	var chain: Array[Dictionary] = []

	# 1 -> 2: ornaments and planted specimens gained a facing, and the appearance
	# mode became a setting.
	#
	# Format 1 stored a garden cell as a bare decoration id string. Format 2
	# stores {"id", "rotation"} so an ornament can be turned. Rotation defaults to
	# 0, which is exactly how every existing garden already looks, so this step
	# cannot change what a player sees — it only makes the shape writable.
	chain.append({
		"from": 1, "to": 2,
		"apply": func(data: Dictionary) -> Dictionary:
			var garden := DictUtil.get_dict(data, "garden")
			var decorations := DictUtil.get_dict(garden, "decorations")
			var upgraded := {}
			for key: String in decorations:
				var entry: Variant = decorations[key]
				if entry is Dictionary:
					upgraded[key] = entry
				elif entry is String and not (entry as String).is_empty():
					upgraded[key] = {"id": entry, "rotation": 0}
			garden["decorations"] = upgraded
			data["garden"] = garden

			var settings := DictUtil.get_dict(data, "settings")
			if not settings.has("theme_mode"):
				settings["theme_mode"] = "light"
			data["settings"] = settings
			return data,
	})

	return chain


## Upgrades `data` to `target_version`, applying each step in order.
## `chain` is injectable so tests can exercise multi-step upgrades, gaps, and
## future-version refusal without waiting for the game to have real migrations.
static func migrate(
	data: Dictionary,
	target_version: int = SaveData.CURRENT_VERSION,
	chain: Array[Dictionary] = get_chain()
) -> Result:
	var result := Result.new()
	result.data = data.duplicate(true)
	result.from_version = DictUtil.get_int(data, "save_version", 1)
	result.to_version = result.from_version

	if result.from_version > target_version:
		# A save written by a NEWER build. We cannot know what its fields mean,
		# and guessing risks destroying real progress. Refuse and preserve (§36).
		result.status = Status.FUTURE_VERSION
		return result

	var version := result.from_version
	while version < target_version:
		var step := _find_step(chain, version)
		if step.is_empty():
			# A gap in the chain. Stop where we are and report it rather than
			# handing back data that is silently half-migrated.
			result.status = Status.NO_PATH
			result.to_version = version
			return result

		var apply: Callable = step["apply"]
		result.data = apply.call(result.data)
		version = DictUtil.get_int(step, "to", version + 1)
		result.data["save_version"] = version
		result.applied_steps.append("%d->%d" % [DictUtil.get_int(step, "from"), version])

	result.to_version = version
	result.data["save_version"] = version
	result.status = Status.OK
	return result


static func _find_step(chain: Array[Dictionary], from_version: int) -> Dictionary:
	for step: Dictionary in chain:
		if DictUtil.get_int(step, "from", -1) == from_version and step.has("apply"):
			return step
	return {}
