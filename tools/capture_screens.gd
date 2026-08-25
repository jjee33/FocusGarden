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

## Interface scales to sweep, at the minimum resolution — the combination that
## squeezes the layout hardest. This exists because a scaled-up interface used to
## push the top-left corner of the app off screen entirely, which every capture at
## 100% looked completely fine through.
const SCALES: Array[float] = [0.75, 1.0, 1.5, 2.0]

## The screens most likely to break under a squeeze: the two widest, plus the one
## with the largest single element. Sweeping all nine at four scales in two themes
## would be 72 more images to look through for no extra signal.
const SQUEEZE_SCREENS: Array[String] = ["garden", "shelf", "focus"]
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
	captured += await _capture_dark_mode(main)
	captured += await _capture_scale_sweep(main)

	print("Captured %d screenshots to %s" % [captured, ProjectSettings.globalize_path(OUTPUT_DIR)])
	quit(0)


## Every screen again in dark mode. Half the app's surfaces are drawn by hand, and
## a `_draw` that reaches for a literal colour looks perfectly correct in light and
## invisible in dark — which is only findable by looking.
func _capture_dark_mode(main: Node) -> int:
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	main.apply_theme_mode("dark")
	await _settle()

	var captured := 0
	for entry: Dictionary in main.SCREENS:
		var screen_id: String = entry["id"]
		main.navigate_to(screen_id)
		await _settle()
		var image := root.get_texture().get_image()
		if image.save_png(OUTPUT_DIR.path_join("dark_1920x1080_%s.png" % screen_id)) == OK:
			captured += 1

	main.apply_theme_mode("light")
	await _settle()
	return captured


## The widest screens at every supported interface scale, at the minimum window
## size. What to look for: the navigation rail intact, the section heading present,
## and nothing cut off at the top or the left — content that overflows to the
## right or the bottom is reachable by scrolling, content past the origin is not.
func _capture_scale_sweep(main: Node) -> int:
	var captured := 0
	var minimum := Vector2i(1280, 720)

	for scale: float in SCALES:
		UiScale.apply(scale)
		root.size = minimum
		DisplayServer.window_set_size(minimum)
		await _settle()

		for screen_id: String in SQUEEZE_SCREENS:
			main.navigate_to(screen_id)
			await _settle()
			var image := root.get_texture().get_image()
			var path := OUTPUT_DIR.path_join(
				"scale%03d_%s.png" % [int(scale * 100.0), screen_id]
			)
			if image.save_png(path) == OK:
				captured += 1
			else:
				printerr("Failed to save %s" % path)

	UiScale.apply(1.0)
	await _settle()
	return captured


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
