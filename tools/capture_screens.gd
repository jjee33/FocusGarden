extends SceneTree
## Renders every screen to a PNG so the UI can be reviewed without a human
## sitting in front of the window.
##
##     tools/godot/Godot_v4.7.1-stable_win64_console.exe --path . \
##         --script res://tools/capture_screens.gd
##
## Must NOT be run with --headless: headless has no rendering, so every capture
## would come out blank.
##
## This is a development tool, not part of the game. It exists because §74 makes
## visual quality a gate ("no text is clipped, no elements overlap at supported
## resolutions"), and that gate is impossible to honestly check by reading code.
## Captures land in user://captures — the path is printed at the end.

const OUTPUT_DIR: String = "user://captures"
## §5's minimum and primary design resolutions. Anything that breaks between the
## two shows up as a difference between these pairs of images.
const RESOLUTIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080)]
## Frames to settle after a change. Enough for layout, the fade transition, and
## one full redraw.
const SETTLE_FRAMES: int = 12


func _init() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIR)

	var main_scene: PackedScene = load("res://scenes/main/main.tscn")
	if main_scene == null:
		printerr("Could not load the main scene.")
		quit(1)
		return

	var main := main_scene.instantiate()
	root.add_child(main)
	await process_frame

	var captured := 0
	for resolution: Vector2i in RESOLUTIONS:
		root.size = resolution
		DisplayServer.window_set_size(resolution)
		await _settle()

		for entry: Dictionary in main.SCREENS:
			var screen_id: String = entry["id"]
			main.navigate_to(screen_id)
			await _settle()

			var image := root.get_texture().get_image()
			var path := OUTPUT_DIR.path_join(
				"%dx%d_%s.png" % [resolution.x, resolution.y, screen_id]
			)
			if image.save_png(path) == OK:
				captured += 1
			else:
				printerr("Failed to save %s" % path)

	captured += await _capture_running_timer(main)

	print("Captured %d screenshots to %s" % [captured, ProjectSettings.globalize_path(OUTPUT_DIR)])
	quit(0)


## The running timer cannot be reached by navigation alone — a session has to
## actually be started. It is the screen the whole milestone is about, so it gets
## captured explicitly rather than being the one view nobody looks at.
func _capture_running_timer(main: Node) -> int:
	var timer_manager := root.get_node("/root/TimerManager")
	var app_state := root.get_node("/root/AppState")
	var projects: Array = app_state.get_active_projects()
	if projects.is_empty():
		return 0

	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	main.navigate_to("focus")
	await _settle()

	timer_manager.start_focus(projects[0].id, "", 25.0)
	await _settle()

	var image := root.get_texture().get_image()
	var saved := image.save_png(OUTPUT_DIR.path_join("1920x1080_focus_running.png")) == OK

	# Discarded rather than left running, so the capture never writes a bogus
	# session into the save it borrowed.
	timer_manager.cancel("screenshot capture")
	await _settle()
	return 1 if saved else 0


func _settle() -> void:
	for i in SETTLE_FRAMES:
		await process_frame
