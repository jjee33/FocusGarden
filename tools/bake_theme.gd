extends SceneTree
## Bakes DesignTokens and Palette into the two committed Theme resources.
##
## Run after changing any design token:
##     tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless --path . \
##         --script res://tools/bake_theme.gd
##
## The generated .tres files are committed so project.godot can reference the
## light one and the editor previews the real styling while scenes are being
## built. They are build artifacts of DesignTokens and Palette — never edit one by
## hand, the next bake will overwrite it.
##
## Both modes are always baked together. A theme that exists in one mode and not
## the other is the failure this tool is shaped to prevent: the app would fall
## back to Godot's default styling the moment a player switched appearance.

const OUTPUTS: Array[Dictionary] = [
	{"mode": Palette.Mode.LIGHT, "path": "res://ui/theme/focus_garden_light.tres"},
	{"mode": Palette.Mode.DARK, "path": "res://ui/theme/focus_garden_dark.tres"},
]


func _init() -> void:
	for output: Dictionary in OUTPUTS:
		var path: String = output["path"]
		var theme := ThemeBuilder.build(output["mode"])
		# Sub-resources must be bundled or the saved theme would reference
		# styleboxes that do not exist on load.
		var error := ResourceSaver.save(theme, path, ResourceSaver.FLAG_BUNDLE_RESOURCES)
		if error != OK:
			printerr("Theme bake FAILED: error %d writing %s" % [error, path])
			quit(1)
			return
		print("Theme baked to %s" % path)
	quit(0)
