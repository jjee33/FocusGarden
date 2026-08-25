class_name VersionUtil
extends RefCounted
## Comparing release versions.
##
## Versions are MAJOR.MINOR.PATCH and are compared component by component as
## integers, never as strings — "0.10.0" sorts before "0.9.0" lexically, which
## would strand every player on 0.9 the moment the tenth minor release shipped.
##
## Input arrives from a release manifest fetched over the network, so nothing here
## trusts its argument: anything unparseable reads as 0.0.0 and therefore never
## looks newer than what is already installed. A malformed manifest must not be
## able to trigger a download.

const PARTS: int = 3


## Splits a version into its numeric components, or returns an empty array if the
## string is not a version at all.
##
## `strict` demands exactly three components, which is what a manifest has to
## carry. The lenient form pads a short version with zeroes so that ordering is
## defined for anything that parses at all.
static func _components(version: String, strict: bool) -> Array[int]:
	# Declared rather than returned as a literal: `return []` from a function
	# typed Array[int] builds an untyped Array and Godot reports the mismatch at
	# runtime, on exactly the malformed-input path this exists to handle.
	var none: Array[int] = []

	var cleaned := version.strip_edges()
	# Git tags carry a leading v, and a manifest generated from one may keep it.
	if cleaned.begins_with("v") or cleaned.begins_with("V"):
		cleaned = cleaned.substr(1)

	# Drop a pre-release or build suffix: "1.2.3-beta.1" is compared as 1.2.3.
	# The truncation happens first and the numeric check second, so "1.-2.0" is
	# rejected as garbage rather than read as a bare "1" carrying a suffix.
	var cut := cleaned.length()
	for marker: String in ["-", "+"]:
		var found := cleaned.find(marker)
		if found != -1:
			cut = mini(cut, found)
	cleaned = cleaned.substr(0, cut)

	# allow_empty stays on so "1." and "1..2" surface as an empty component and
	# are refused, rather than quietly collapsing to something plausible.
	var pieces := cleaned.split(".")
	if pieces.size() > PARTS:
		return none
	if strict and pieces.size() != PARTS:
		return none

	var parsed: Array[int] = [0, 0, 0]
	for index in range(pieces.size()):
		var piece: String = pieces[index]
		if not _is_digits(piece):
			return none
		parsed[index] = piece.to_int()
	return parsed


## Digits and nothing else. `is_valid_int` accepts a leading sign, which would let
## a negative component through.
static func _is_digits(text: String) -> bool:
	if text.is_empty():
		return false
	for index in range(text.length()):
		var code := text.unicode_at(index)
		if code < 48 or code > 57:
			return false
	return true


## Three integers, padding a short version and reading anything unparseable as
## 0.0.0.
static func parse(version: String) -> Array[int]:
	var parsed := _components(version, false)
	if not parsed.is_empty():
		return parsed
	var zero: Array[int] = [0, 0, 0]
	return zero


## -1 if a is older than b, 0 if they match, 1 if a is newer.
static func compare(a: String, b: String) -> int:
	var left := parse(a)
	var right := parse(b)
	for index in range(PARTS):
		if left[index] < right[index]:
			return -1
		if left[index] > right[index]:
			return 1
	return 0


## True when `candidate` is a release the player does not have yet.
static func is_newer(candidate: String, current: String) -> bool:
	return compare(candidate, current) > 0


## True when the string is a well-formed MAJOR.MINOR.PATCH version. This is what
## a manifest is checked against before any of it is acted on.
static func is_valid(version: String) -> bool:
	return not _components(version, true).is_empty()


## The version this build reports, from project.godot.
static func current() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
