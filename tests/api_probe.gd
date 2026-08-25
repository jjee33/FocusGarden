extends SceneTree
## Verifies every engine API this project depends on actually exists (§71).
##
##     tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless --path . \
##         --script res://tests/api_probe.gd
##
## §71 says never invent APIs Godot does not provide, and to verify against the
## real engine rather than from memory. This file is the mechanism for that: it
## asserts each singleton method, class method and constant the codebase calls,
## and exits non-zero if any is missing.
##
## It earns its keep on an ENGINE UPGRADE. If Godot 4.8 renames or removes
## something, this reports exactly which call to fix in seconds, instead of the
## failure surfacing later as a runtime error on a screen nobody opened yet.
##
## Add a line here whenever the project starts depending on a new engine API.

var _missing: PackedStringArray = PackedStringArray()
var _checked: int = 0


func _init() -> void:
	print("\n=== Engine API probe (Godot %s) ===\n" % Engine.get_version_info()["string"])

	_probe_time()
	_probe_filesystem()
	_probe_json()
	_probe_display()
	_probe_audio()
	_probe_resources()
	_probe_theme()
	_probe_backups()
	_probe_updates()
	_probe_globals()

	print("\n--------------------------------------------")
	print("%d APIs checked, %d missing" % [_checked, _missing.size()])
	if _missing.is_empty():
		print("RESULT: PASS")
		print("--------------------------------------------\n")
		quit(0)
		return

	print("RESULT: FAIL")
	for entry: String in _missing:
		print("  - MISSING: %s" % entry)
	print("--------------------------------------------\n")
	quit(1)


## Checks a method on a singleton Object (Time, DisplayServer, AudioServer…).
func _singleton(name: String, object: Object, method: String) -> void:
	_checked += 1
	if not object.has_method(method):
		_missing.append("%s.%s()" % [name, method])


## Checks a method on a class that is instantiated rather than used as a
## singleton (Theme, Tween, FileAccess…).
func _class_method(class_name_string: String, method: String) -> void:
	_checked += 1
	if not ClassDB.class_has_method(class_name_string, method, true):
		_missing.append("%s.%s()" % [class_name_string, method])


func _probe_time() -> void:
	# The timer's correctness rests entirely on these (§8).
	_singleton("Time", Time, "get_ticks_usec")
	_singleton("Time", Time, "get_ticks_msec")
	_singleton("Time", Time, "get_unix_time_from_system")
	_singleton("Time", Time, "get_datetime_dict_from_unix_time")
	_singleton("Time", Time, "get_unix_time_from_datetime_string")
	_singleton("Time", Time, "get_time_zone_from_system")

	# Behavioural check, not just presence: a monotonic clock that went backwards
	# would break every elapsed-time calculation while still "existing".
	_checked += 1
	var first := Time.get_ticks_usec()
	var second := Time.get_ticks_usec()
	if second < first:
		_missing.append("Time.get_ticks_usec() is not monotonic")

	_checked += 1
	var zone: Dictionary = Time.get_time_zone_from_system()
	if not zone.has("bias"):
		_missing.append("Time.get_time_zone_from_system() has no 'bias' key")


func _probe_filesystem() -> void:
	# The atomic save sequence depends on each of these (§36).
	_class_method("DirAccess", "dir_exists_absolute")
	_class_method("DirAccess", "make_dir_recursive_absolute")
	_class_method("DirAccess", "remove_absolute")
	_class_method("DirAccess", "rename_absolute")
	_class_method("DirAccess", "copy_absolute")
	_class_method("DirAccess", "get_files_at")
	_class_method("FileAccess", "file_exists")
	_class_method("FileAccess", "open")
	_class_method("FileAccess", "get_open_error")
	_class_method("FileAccess", "store_string")
	_class_method("FileAccess", "get_as_text")
	_class_method("FileAccess", "close")
	_class_method("ConfigFile", "load")
	_class_method("ConfigFile", "get_value")


func _probe_json() -> void:
	_class_method("JSON", "stringify")
	_class_method("JSON", "parse")
	_class_method("JSON", "get_error_message")

	# Behavioural: confirms parse() REPORTS malformed input rather than accepting
	# it, which is exactly what corruption recovery keys on. Uses the instance
	# parser rather than parse_string() so a deliberate bad-input check does not
	# push a scary engine error into the log.
	_checked += 1
	var json := JSON.new()
	if json.parse("{ truncated") == OK:
		_missing.append("JSON.parse() accepts malformed JSON")


func _probe_display() -> void:
	_singleton("DisplayServer", DisplayServer, "window_set_min_size")
	_singleton("DisplayServer", DisplayServer, "window_get_mode")
	_singleton("DisplayServer", DisplayServer, "window_set_mode")
	# Used instead of an OS toast notification, which Godot has no API for (§34).
	_singleton("DisplayServer", DisplayServer, "window_request_attention")
	_singleton("DisplayServer", DisplayServer, "screen_get_scale")


func _probe_audio() -> void:
	_singleton("AudioServer", AudioServer, "get_driver_name")
	_singleton("AudioServer", AudioServer, "add_bus")
	_singleton("AudioServer", AudioServer, "set_bus_name")
	_singleton("AudioServer", AudioServer, "set_bus_send")
	_singleton("AudioServer", AudioServer, "set_bus_volume_db")
	_singleton("AudioServer", AudioServer, "get_bus_volume_db")
	_singleton("AudioServer", AudioServer, "set_bus_mute")
	_singleton("AudioServer", AudioServer, "get_bus_index")


func _probe_resources() -> void:
	_class_method("ResourceSaver", "save")
	_class_method("ResourceLoader", "load")
	_checked += 1
	if not ("FLAG_BUNDLE_RESOURCES" in ResourceSaver):
		_missing.append("ResourceSaver.FLAG_BUNDLE_RESOURCES")


func _probe_theme() -> void:
	# The generated theme calls each of these (ui/theme/theme_builder.gd).
	_class_method("Theme", "set_stylebox")
	_class_method("Theme", "set_color")
	_class_method("Theme", "set_constant")
	_class_method("Theme", "set_font_size")
	_class_method("Theme", "set_type_variation")
	_class_method("Theme", "set_font")
	_class_method("Tween", "tween_property")
	_class_method("Tween", "set_parallel")
	_class_method("Tween", "set_ease")
	_class_method("Tween", "set_trans")
	_class_method("Node", "create_tween")

	# StyleBoxFlat properties are set by name; a rename would silently no-op
	# rather than erroring, so presence is checked explicitly.
	_checked += 1
	var box := StyleBoxFlat.new()
	for property: String in [
		"bg_color", "corner_radius_top_left", "border_width_left", "border_color",
		"shadow_color", "shadow_size", "expand_margin_left", "content_margin_left",
		"anti_aliasing",
	]:
		if not (property in box):
			_missing.append("StyleBoxFlat.%s" % property)

	# StyleBoxLine backs the dividers in the rail and the settings sections.
	_checked += 1
	var line := StyleBoxLine.new()
	for property: String in ["color", "thickness", "vertical"]:
		if not (property in line):
			_missing.append("StyleBoxLine.%s" % property)

	_probe_fonts()


## The interface font is resolved from the OS at runtime rather than bundled
## (ui/theme/design_tokens.gd), so the whole app's typography rests on these
## three classes existing and keeping their property names.
func _probe_fonts() -> void:
	_checked += 1
	var system := SystemFont.new()
	for property: String in ["font_names", "subpixel_positioning"]:
		if not (property in system):
			_missing.append("SystemFont.%s" % property)

	_checked += 1
	var variation := FontVariation.new()
	for property: String in ["base_font", "variation_embolden", "opentype_features"]:
		if not (property in variation):
			_missing.append("FontVariation.%s" % property)

	# A font chain that resolves to nothing would leave every label blank, and
	# that is a platform question rather than an API one — so it is checked here
	# rather than assumed.
	_checked += 1
	system.font_names = PackedStringArray(DesignTokens.FONT_FAMILIES)
	if system.get_height(DesignTokens.FONT_BODY) <= 0.0:
		_missing.append("SystemFont resolved no usable face from DesignTokens.FONT_FAMILIES")


## Where the player's backups go (systems/save/save_backup.gd). A missing or
## empty Documents path is handled at runtime, but the API itself must exist.
func _probe_backups() -> void:
	_singleton("OS", OS, "get_system_dir")
	_singleton("OS", OS, "shell_open")
	# Static, not singleton methods — checked through ClassDB for that reason.
	_class_method("DirAccess", "get_directories_at")
	_class_method("DirAccess", "get_files_at")
	_class_method("DirAccess", "copy_absolute")
	_class_method("DirAccess", "make_dir_recursive_absolute")
	_singleton("Time", Time, "get_unix_time_from_datetime_dict")


## The update path (docs/UPDATES.md). Worth probing precisely because it is the
## one part of the app that hands a downloaded file to the operating system: if
## the checksum call or the process call went missing in an engine upgrade, the
## failure would be a build that either cannot update or updates unverified.
func _probe_updates() -> void:
	_class_method("HTTPRequest", "request")
	_class_method("HTTPRequest", "get_downloaded_bytes")
	_class_method("HTTPRequest", "get_body_size")
	_class_method("FileAccess", "get_sha256")
	_singleton("OS", OS, "create_process")
	_singleton("OS", OS, "execute")
	_singleton("OS", OS, "get_environment")
	_singleton("OS", OS, "shell_open")
	_singleton("OS", OS, "has_feature")

	# Behavioural: "template" is how the updater tells an exported build from the
	# editor, and it is the single guard keeping development runs and every
	# headless gate off the network. A probe running under --script is not a
	# template, so this must be false right here.
	_checked += 1
	if OS.has_feature("template"):
		_missing.append("OS.has_feature(\"template\") is true outside an exported build")

	# Behavioural: a checksum that does not match the known digest of a known
	# string would silently disable verification rather than fail loudly.
	_checked += 1
	var probe_path := "user://api_probe_sha256.tmp"
	var file := FileAccess.open(probe_path, FileAccess.WRITE)
	if file == null:
		_missing.append("Could not write %s to check FileAccess.get_sha256()" % probe_path)
	else:
		file.store_string("abc")
		file.close()
		var expected := "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
		if FileAccess.get_sha256(probe_path) != expected:
			_missing.append("FileAccess.get_sha256() does not match the known digest of \"abc\"")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(probe_path))


func _probe_globals() -> void:
	# Global scope helpers used by AudioManager's volume conversion.
	_checked += 1
	if not is_equal_approx(linear_to_db(1.0), 0.0):
		_missing.append("linear_to_db() does not return 0 dB for unity gain")
	_checked += 1
	if not is_equal_approx(db_to_linear(0.0), 1.0):
		_missing.append("db_to_linear() does not return unity gain for 0 dB")
