class_name AppScreen
extends Control
## Base class for every top-level screen (§6).
##
## Gives all nine sections the same outer geometry: identical padding, a scrolling
## body, and a maximum content width that keeps text readable on ultrawide
## monitors instead of stretching a paragraph across 3440 pixels (§5 requires
## correct behaviour at larger resolutions, not merely a non-broken one).
##
## Subclasses override `build_content()` and fill `content` — they never touch
## anchors, margins or scrolling, so no screen can drift from the shared layout.

## Populated by the base class before `build_content()` runs. Add children here.
var content: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	# AUTO rather than DISABLED. With horizontal scrolling disabled, a screen
	# whose content is wider than the viewport is not squeezed — it is cut, with
	# no way to reach the missing part. That is invisible at 100% interface scale
	# and unmissable at 200%, where the logical viewport is half as wide. A
	# horizontal bar appears only when something genuinely does not fit.
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	add_child(scroll)

	var padding := MarginContainer.new()
	padding.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	padding.size_flags_vertical = Control.SIZE_EXPAND_FILL
	padding.add_theme_constant_override("margin_left", DesignTokens.SPACE_XL)
	padding.add_theme_constant_override("margin_right", DesignTokens.SPACE_XL)
	padding.add_theme_constant_override("margin_top", DesignTokens.SPACE_XL)
	padding.add_theme_constant_override("margin_bottom", DesignTokens.SPACE_XL)
	scroll.add_child(padding)

	# Centring wrapper: the content column stops growing at CONTENT_MAX_WIDTH and
	# the surplus becomes equal margins rather than over-long line lengths.
	var centre := HBoxContainer.new()
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	padding.add_child(centre)

	var left_gutter := Control.new()
	left_gutter.size_flags_horizontal = Control.SIZE_EXPAND
	centre.add_child(left_gutter)

	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_FILL
	content.custom_minimum_size.x = 0
	content.add_theme_constant_override("separation", DesignTokens.SPACE_LG)
	centre.add_child(content)

	var right_gutter := Control.new()
	right_gutter.size_flags_horizontal = Control.SIZE_EXPAND
	centre.add_child(right_gutter)

	# Resolved on resize so the column tracks the window instead of being fixed.
	resized.connect(_update_content_width)
	_update_content_width()

	build_content()


## Subclasses build their screen here by adding children to `content`.
func build_content() -> void:
	pass


## Called when the screen becomes visible again, so a screen can refresh values
## that changed while it was hidden. Cheaper than rebuilding, and event-driven
## updates (§44) handle everything else.
func on_shown() -> void:
	pass


func _update_content_width() -> void:
	if content == null:
		return
	var available := size.x - DesignTokens.SPACE_XL * 2
	content.custom_minimum_size.x = minf(float(DesignTokens.CONTENT_MAX_WIDTH), maxf(320.0, available))
