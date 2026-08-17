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
	# Example of the shape a future step takes:
	# chain.append({
	#     "from": 1, "to": 2,
	#     "apply": func(data: Dictionary) -> Dictionary:
	#         data["settings"] = DictUtil.get_dict(data, "settings")
	#         data["settings"]["new_option"] = true
	#         return data,
	# })
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
