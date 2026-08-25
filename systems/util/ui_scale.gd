class_name UiScale
extends RefCounted
## Applies the interface scale setting (§35, §50).
##
## §50 lists UI scaling as foundational accessibility, and §5 requires correct
## DPI behaviour. Both are served by the same mechanism: the viewport's content
## scale factor, which multiplies the whole interface without any layout code
## needing to know about it.
##
## This is why nothing in the codebase hardcodes a pixel position (§5) — scaling
## works precisely because every screen is built from containers and anchors.
##
## THE MINIMUM WINDOW SIZE IS PART OF THIS, NOT OF THE SHELL.
## `content_scale_factor` does not resize the window; it shrinks the LOGICAL
## viewport the layout is measured in. A 1280x720 window at 200% is a 640x360
## layout, which is half of §5's supported minimum, and the widest screens
## (Garden, Shelf) simply do not fit — controls overflow, and anything that
## overflows is either clipped or pushed off an edge. So the enforced minimum has
## to scale with the factor, and the window has to be grown to meet it. Setting
## the factor without doing this was the cause of the app's top-left corner
## disappearing at high scales.

const MINIMUM: float = 0.75
const MAXIMUM: float = 2.0


static func apply(scale: float) -> void:
	var window := Engine.get_main_loop().root as Window
	if window == null:
		return

	var clamped := clampf(scale, MINIMUM, MAXIMUM)
	window.content_scale_factor = clamped
	_enforce_minimum_window(clamped)


## Reapplies from the saved setting. Called at startup, once the save is loaded.
static func apply_from_settings(settings: GameSettings) -> void:
	if settings != null:
		apply(settings.ui_scale)


## The size the layout is actually measured in, after both the stretch mode and
## the scale factor. Screens do not need this — they are built from containers —
## but tools and captures do, because it is what "the window is big enough"
## really means.
static func logical_viewport_size() -> Vector2i:
	var window := Engine.get_main_loop().root as Window
	if window == null:
		return DesignTokens.MIN_WINDOW_SIZE
	return window.get_visible_rect().size


## Raises the OS-enforced minimum to whatever the current scale needs, and grows
## the window if it is now under it. Only ever grows: shrinking a window the
## player sized themselves would be worse than the problem being solved.
static func _enforce_minimum_window(scale: float) -> void:
	if DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED:
		# Fullscreen and borderless are the size of the screen; forcing a minimum
		# larger than the display would be refused anyway, and on a small laptop
		# panel it would fight the window manager on every mode change.
		DisplayServer.window_set_min_size(DesignTokens.MIN_WINDOW_SIZE)
		return

	var required := Vector2i(
		int(ceil(float(DesignTokens.MIN_WINDOW_SIZE.x) * scale)),
		int(ceil(float(DesignTokens.MIN_WINDOW_SIZE.y) * scale))
	)
	# Never ask for more than the screen can show, or the window becomes
	# unusable on exactly the machines that need a large interface scale most.
	var usable := DisplayServer.screen_get_usable_rect(
		DisplayServer.window_get_current_screen()
	).size
	required = Vector2i(mini(required.x, usable.x), mini(required.y, usable.y))

	DisplayServer.window_set_min_size(required)
	var current := DisplayServer.window_get_size()
	var grown := Vector2i(maxi(current.x, required.x), maxi(current.y, required.y))
	if grown != current:
		DisplayServer.window_set_size(grown)
