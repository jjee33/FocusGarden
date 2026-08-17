extends Control
## The application shell: persistent navigation and screen hosting (§6).
##
## §6 asks navigation to feel like moving around a cozy game rather than
## switching web pages, so the rail is always present and the content
## cross-fades rather than snapping.
##
## Routing lives here, in the scene, NOT in an autoload — §40 is explicit that
## autoloads must not contain UI logic. Other systems request navigation by
## emitting `EventBus.navigation_requested`, so nothing needs a reference to this
## node to move the player between screens.

## The nine sections from §6, in navigation order. Adding a section means adding
## one row here — the rail, the routing and the keyboard order all follow from it.
const SCREENS: Array[Dictionary] = [
	{"id": "home", "label": "Home", "glyph": "🏡"},
	{"id": "focus", "label": "Focus", "glyph": "⏳"},
	{"id": "catalogue", "label": "Catalogue", "glyph": "📖"},
	{"id": "shelf", "label": "Shelf", "glyph": "🪴"},
	{"id": "garden", "label": "Garden", "glyph": "🌳"},
	{"id": "journal", "label": "Journal", "glyph": "📔"},
	{"id": "statistics", "label": "Statistics", "glyph": "📊"},
	{"id": "achievements", "label": "Achievements", "glyph": "🏅"},
	{"id": "settings", "label": "Settings", "glyph": "⚙"},
]

const DEFAULT_SCREEN: String = "home"

## Shown in the navigation footer. Bump it when a milestone lands, so the running
## build always states how far along it actually is rather than overstating it.
const CURRENT_MILESTONE: String = "Milestone 10"

## Frame cap. 60 is smooth for UI motion and leaves the machine alone (§44).
const TARGET_FPS: int = 60

var _screen_host: Control
var _nav_rail: PanelContainer
var _nav_buttons: Dictionary = {}   ## id -> Button
var _screen_cache: Dictionary = {}  ## id -> AppScreen
var _current_id: String = ""


func _ready() -> void:
	# §5's minimum supported resolution, enforced by the OS window manager so the
	# layout can never be squeezed below what it was designed for.
	DisplayServer.window_set_min_size(DesignTokens.MIN_WINDOW_SIZE)

	# A productivity app has no reason to render faster than the display, and an
	# uncapped loop burns a core for nothing (§44). Asserted in code as well as
	# in project.godot so the cap cannot be lost to an editor-side settings edit.
	if Engine.max_fps <= 0 or Engine.max_fps > TARGET_FPS:
		Engine.max_fps = TARGET_FPS
	GameLog.debug(GameLog.Category.APP, "Frame cap: %d fps." % Engine.max_fps)

	# Display preferences are restored before the first frame is shown, so the
	# window does not visibly jump from default to the player's choice.
	WindowMode.apply(AppState.get_settings().window_mode)
	UiScale.apply_from_settings(AppState.get_settings())

	_build_layout()
	_build_overlays()
	EventBus.navigation_requested.connect(navigate_to)
	EventBus.focus_mode_changed.connect(_on_focus_mode_changed)
	# Screens read the motion setting when they build their plants, so turning it
	# on or off has to rebuild them rather than just flipping a flag somewhere.
	EventBus.reduced_motion_changed.connect(func(_enabled: bool) -> void: _refresh_all_screens())
	navigate_to(DEFAULT_SCREEN)

	# Onboarding takes over the whole window on a fresh save (§45). The
	# interrupted-session prompt waits until it is done, so a first-time player
	# is never asked about a session they could not possibly have run.
	if not AppState.data.profile.onboarding_completed:
		_show_onboarding()
	else:
		_offer_interrupted_session()


func _show_onboarding() -> void:
	var onboarding := OnboardingScreen.new()
	onboarding.completed.connect(func() -> void:
		_refresh_all_screens()
		_offer_interrupted_session())
	add_child(onboarding)


## Rebuilds cached screens after a change that alters everything they show.
## Cheaper than clearing the cache: the screens rebuild their own content and
## keep their scroll positions and filter state.
func _refresh_all_screens() -> void:
	for screen: AppScreen in _screen_cache.values():
		screen.on_shown()


## Toasts and notification policy live above every screen, so they survive
## navigation and never belong to one section.
func _build_overlays() -> void:
	add_child(NotificationRouter.new())
	add_child(ToastLayer.new())


func _build_layout() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var background := ColorRect.new()
	background.color = DesignTokens.BG_BASE
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 0)
	add_child(row)

	_nav_rail = _build_nav_rail()
	row.add_child(_nav_rail)

	_screen_host = Control.new()
	_screen_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_screen_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_screen_host.clip_contents = true
	row.add_child(_screen_host)


func _build_nav_rail() -> PanelContainer:
	var rail := PanelContainer.new()
	rail.theme_type_variation = &"NavPanel"
	rail.custom_minimum_size.x = DesignTokens.NAV_RAIL_WIDTH
	rail.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", DesignTokens.SPACE_XXS)
	rail.add_child(column)

	var brand := Label.new()
	brand.text = "Focus Garden"
	brand.theme_type_variation = &"NavBrand"
	column.add_child(brand)

	var tagline := Label.new()
	tagline.text = "grow what you give time to"
	tagline.theme_type_variation = &"NavCaption"
	column.add_child(tagline)

	var gap := Control.new()
	gap.custom_minimum_size.y = DesignTokens.SPACE_LG
	column.add_child(gap)

	for entry: Dictionary in SCREENS:
		var button := Button.new()
		# Glyph AND label: §50 forbids relying on an icon alone to convey meaning.
		button.text = "%s   %s" % [entry["glyph"], entry["label"]]
		button.theme_type_variation = &"NavButton"
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.toggle_mode = true
		button.focus_mode = Control.FOCUS_ALL
		button.tooltip_text = entry["label"]
		var id: String = entry["id"]
		button.pressed.connect(func() -> void: navigate_to(id))
		column.add_child(button)
		_nav_buttons[id] = button

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)

	var version := Label.new()
	version.text = "v%s · %s" % [
		ProjectSettings.get_setting("application/config/version", "0.0.0"),
		CURRENT_MILESTONE,
	]
	version.theme_type_variation = &"NavCaption"
	column.add_child(version)

	return rail


## Switches to a screen, creating it on first visit.
func navigate_to(screen_id: String) -> void:
	if screen_id == _current_id or not _nav_buttons.has(screen_id):
		return

	var incoming := _get_or_create_screen(screen_id)
	if incoming == null:
		GameLog.error(GameLog.Category.UI, "No screen registered for '%s'." % screen_id)
		return

	# Screens are kept alive once built rather than freed on every navigation:
	# rebuilding a screen would drop scroll position and re-run its queries each
	# time the player glanced at another tab (§44).
	for cached_id: String in _screen_cache:
		var screen: AppScreen = _screen_cache[cached_id]
		screen.visible = cached_id == screen_id

	for button_id: String in _nav_buttons:
		var button: Button = _nav_buttons[button_id]
		button.button_pressed = button_id == screen_id

	_current_id = screen_id
	incoming.on_shown()
	_play_enter_transition(incoming)
	GameLog.debug(GameLog.Category.UI, "Navigated to '%s'." % screen_id)


func _get_or_create_screen(screen_id: String) -> AppScreen:
	if _screen_cache.has(screen_id):
		return _screen_cache[screen_id]

	var screen := _instantiate_screen(screen_id)
	if screen == null:
		return null
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.visible = false
	_screen_host.add_child(screen)
	_screen_cache[screen_id] = screen
	return screen


func _instantiate_screen(screen_id: String) -> AppScreen:
	match screen_id:
		"home":
			return HomeScreen.new()
		"focus":
			return FocusScreen.new()
		"catalogue":
			return CatalogueScreen.new()
		"shelf":
			return ShelfScreen.new()
		"garden":
			return GardenScreen.new()
		"journal":
			return JournalScreen.new()
		"statistics":
			return StatisticsScreen.new()
		"achievements":
			return AchievementsScreen.new()
		"settings":
			return SettingsScreen.new()
	return null


## A short fade-and-rise. Respects reduced motion: at zero duration the tween
## still applies the end state, so the screen lands fully visible and in place.
func _play_enter_transition(screen: AppScreen) -> void:
	var duration := Motion.duration(DesignTokens.DURATION_NORMAL)
	if duration <= Motion.INSTANT_EPSILON:
		screen.modulate.a = 1.0
		screen.position.y = 0.0
		return

	screen.modulate.a = 0.0
	screen.position.y = 8.0
	var tween := Motion.create_tween_for(screen)
	tween.set_parallel(true)
	tween.tween_property(screen, "modulate:a", 1.0, duration)
	tween.tween_property(screen, "position:y", 0.0, duration)


## Focus Mode collapses the navigation rail so a running session has the screen
## to itself (§10). The rail is shrunk rather than hidden outright, so the
## content reflows smoothly instead of snapping sideways.
func _on_focus_mode_changed(enabled: bool) -> void:
	var target_width := 0.0 if enabled else float(DesignTokens.NAV_RAIL_WIDTH)
	var target_alpha := 0.0 if enabled else 1.0
	var duration := Motion.duration(DesignTokens.DURATION_NORMAL)

	if duration <= Motion.INSTANT_EPSILON:
		_nav_rail.custom_minimum_size.x = target_width
		_nav_rail.modulate.a = target_alpha
		# Kept out of the tab order while hidden, or keyboard focus could land on
		# an invisible button.
		_nav_rail.visible = not enabled
		return

	_nav_rail.visible = true
	var tween := Motion.create_tween_for(_nav_rail)
	tween.set_parallel(true)
	tween.tween_property(_nav_rail, "custom_minimum_size:x", target_width, duration)
	tween.tween_property(_nav_rail, "modulate:a", target_alpha, duration)
	tween.set_parallel(false)
	tween.tween_callback(func() -> void: _nav_rail.visible = not enabled)


## Offers back a session that was running when the app last closed (§54).
##
## The player is ASKED rather than credited automatically: only they know whether
## they kept working after the app went away, and silently awarding an unknown
## amount of time would corrupt the statistics the whole product rests on.
func _offer_interrupted_session() -> void:
	var session := TimerManager.recover_in_flight_session()
	if session == null:
		return

	var dialog := ConfirmDialog.open(
		self,
		"Pick up where you left off?",
		(
			"Focus Garden closed during a session on %s. "
			% AppState.get_project_name(session.project_id)
			+ "It looks like %s of focus. Keep it?"
			% TimeUtil.format_duration(session.actual_focus_minutes)
		),
		"Keep it",
		false,
		"Discard it"
	)
	dialog.confirmed.connect(
		func() -> void:
			SessionPipeline.apply(session)
			TimerManager.discard_in_flight_session()
			GameLog.info(GameLog.Category.TIMER, "Recovered session %s was kept." % session.id)
	)
	dialog.dismissed.connect(
		func() -> void:
			TimerManager.discard_in_flight_session()
			GameLog.info(GameLog.Category.TIMER, "Recovered session %s was discarded." % session.id)
	)


func _unhandled_input(event: InputEvent) -> void:
	# §49: sensible keyboard controls, and never a destructive action on a single
	# accidental keypress. Both of these are non-destructive by design.
	if event.is_action_pressed("toggle_fullscreen"):
		_toggle_fullscreen()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_back") and _current_id != DEFAULT_SCREEN:
		navigate_to(DEFAULT_SCREEN)
		get_viewport().set_input_as_handled()


## F11. Persists the result, so the window mode the player left in is the one
## they come back to — a shortcut that silently disagrees with the setting on the
## Settings screen would be worse than no shortcut.
func _toggle_fullscreen() -> void:
	AppState.get_settings().window_mode = WindowMode.toggle_fullscreen()
	AppState.save_now()
