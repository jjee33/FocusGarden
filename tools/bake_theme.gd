extends SceneTree
## Bakes DesignTokens into ui/theme/focus_garden.tres.
##
## Run after changing any design token:
##     tools/godot/Godot_v4.7.1-stable_win64_console.exe --headless --path . \
##         --script res://tools/bake_theme.gd
##
## The generated .tres is committed so project.godot can reference it and the
## editor previews the real styling while scenes are being built. It is a build
## artifact of DesignTokens — never edit it by hand, the next bake will overwrite.

const OUTPUT_PATH: String = "res://ui/theme/focus_garden.tres"


func _init() -> void:
	var theme := ThemeBuilder.build()
	# Sub-resources must be bundled or the saved theme would reference styleboxes
	# that do not exist on load.
	var error := ResourceSaver.save(theme, OUTPUT_PATH, ResourceSaver.FLAG_BUNDLE_RESOURCES)
	if error != OK:
		printerr("Theme bake FAILED: error %d writing %s" % [error, OUTPUT_PATH])
		quit(1)
		return
	print("Theme baked to %s" % OUTPUT_PATH)
	quit(0)
