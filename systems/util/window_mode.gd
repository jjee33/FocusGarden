class_name WindowMode
extends RefCounted
## Applies the window mode setting (§5, §35).
##
## §5 asks for a resizable window, a fullscreen option, and borderless fullscreen
## "if practical". All three are one DisplayServer call each, so all three are
## supported.
##
## Borderless is EXCLUSIVE_FULLSCREEN's gentler sibling: the window covers the
## screen at the desktop's own resolution, so alt-tabbing does not trigger a mode
## switch. For an app that sits open beside other work, that matters more than
## the marginal performance of exclusive fullscreen.

const WINDOWED: String = "windowed"
const FULLSCREEN: String = "fullscreen"
const BORDERLESS: String = "borderless"


static func apply(mode: String) -> void:
	match mode:
		FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
		BORDERLESS:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)


## Cycles windowed and fullscreen, for the F11 shortcut.
static func toggle_fullscreen() -> String:
	var current := DisplayServer.window_get_mode()
	var going_fullscreen := (
		current == DisplayServer.WINDOW_MODE_WINDOWED
		or current == DisplayServer.WINDOW_MODE_MAXIMIZED
	)
	var mode := FULLSCREEN if going_fullscreen else WINDOWED
	apply(mode)
	return mode
