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

const MINIMUM: float = 0.75
const MAXIMUM: float = 2.0


static func apply(scale: float) -> void:
	var window := Engine.get_main_loop().root as Window
	if window == null:
		return
	window.content_scale_factor = clampf(scale, MINIMUM, MAXIMUM)


## Reapplies from the saved setting. Called at startup, once the save is loaded.
static func apply_from_settings(settings: GameSettings) -> void:
	if settings != null:
		apply(settings.ui_scale)
