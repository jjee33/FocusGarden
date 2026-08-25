extends TestCase
## Version comparison (§53).
##
## This is the gate on the whole update path: `is_newer` decides whether a build
## offers to replace itself. Two failure modes matter and neither is visible by
## inspection — a string comparison stranding everyone on 0.9 forever once 0.10
## ships, and a malformed manifest being read as a newer version and triggering a
## download. Both are cheap to test and expensive to discover in the field.


func test_ordering_is_numeric_not_lexical() -> void:
	# "0.10.0" < "0.9.0" as strings. If this ever regresses, every player stops
	# being offered updates at the tenth minor release and nothing looks broken.
	assert_true(VersionUtil.is_newer("0.10.0", "0.9.0"), "0.10.0 is newer than 0.9.0")
	assert_false(VersionUtil.is_newer("0.9.0", "0.10.0"), "0.9.0 is not newer than 0.10.0")
	assert_true(VersionUtil.is_newer("1.0.0", "0.99.99"), "a major bump beats anything below")


func test_each_component_is_compared_in_turn() -> void:
	assert_eq(VersionUtil.compare("1.2.3", "1.2.3"), 0, "identical versions")
	assert_eq(VersionUtil.compare("2.0.0", "1.9.9"), 1, "major wins")
	assert_eq(VersionUtil.compare("1.3.0", "1.2.9"), 1, "minor wins")
	assert_eq(VersionUtil.compare("1.2.4", "1.2.3"), 1, "patch wins")
	assert_eq(VersionUtil.compare("1.2.3", "1.2.4"), -1, "older patch")


func test_the_same_version_is_never_newer() -> void:
	# The common case: almost every launch compares a version to itself.
	assert_false(VersionUtil.is_newer("0.1.0", "0.1.0"), "no update when they match")


func test_a_leading_v_is_tolerated() -> void:
	# Git tags carry one, and a manifest generated from a tag may keep it.
	assert_eq(VersionUtil.compare("v1.2.3", "1.2.3"), 0, "v-prefixed tag")
	assert_true(VersionUtil.is_newer("v0.2.0", "0.1.0"), "v-prefixed and newer")


func test_prerelease_suffixes_compare_by_their_release() -> void:
	assert_eq(VersionUtil.compare("1.2.3-beta.1", "1.2.3"), 0, "beta of the same release")
	assert_true(VersionUtil.is_newer("0.3.0-rc1", "0.2.0"), "a newer release, pre-release or not")


func test_short_versions_pad_with_zeroes() -> void:
	assert_eq(VersionUtil.compare("1.2", "1.2.0"), 0, "two components")
	assert_eq(VersionUtil.compare("2", "1.9.9"), 1, "one component")


func test_garbage_never_looks_like_an_update() -> void:
	# The decisive property. Everything here arrives over the network, and
	# anything unparseable must compare as 0.0.0 so it can never trigger a
	# download.
	var current := "0.1.0"
	assert_false(VersionUtil.is_newer("", current), "empty")
	assert_false(VersionUtil.is_newer("latest", current), "a word")
	assert_false(VersionUtil.is_newer("9.9.9.9", current), "four components")
	assert_false(VersionUtil.is_newer("1.-2.0", current), "a negative component")
	assert_false(VersionUtil.is_newer("1.two.0", current), "a non-numeric component")
	assert_false(VersionUtil.is_newer("../../etc/passwd", current), "a path")


func test_validity_is_strict_where_comparison_is_forgiving() -> void:
	# `compare` pads and tolerates so ordering is always defined; `is_valid` is
	# what the manifest is actually checked against before anything is acted on.
	assert_true(VersionUtil.is_valid("0.2.0"), "a normal version")
	assert_true(VersionUtil.is_valid("v0.2.0"), "a tag")
	assert_false(VersionUtil.is_valid("1.2"), "too few components")
	assert_false(VersionUtil.is_valid("1.2.3.4"), "too many components")
	assert_false(VersionUtil.is_valid("1.2.x"), "not a number")
	assert_false(VersionUtil.is_valid(""), "empty")
