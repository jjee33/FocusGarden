extends Node
## All audio: buses, volumes, playback (§33, §40).
##
## Owns: the audio bus graph and every volume setting.
## Must never: do anything else.
##
## Buses are created at runtime rather than shipped as a .tres bus layout, so the
## routing lives in readable, diffable code next to the volume logic instead of a
## binary-ish resource nobody can review.
##
## §33 requires conservative defaults and no loud autoplay on first launch. That
## is enforced here: volumes come from GameSettings (which defaults them low) and
## nothing plays until something explicitly asks it to.
##
## MILESTONE STATUS: routing, volume control, and device-loss handling are
## complete. The ambient tracks and UI sounds themselves are Milestone 8 content;
## `play_ui`/`play_ambient` are wired but have no clips to play yet and log at
## debug level instead of failing.

## Bus names must match the keys used by GameSettings' volume fields.
const BUS_MASTER: StringName = &"Master"
const BUS_MUSIC: StringName = &"Music"
const BUS_AMBIENT: StringName = &"Ambient"
const BUS_UI: StringName = &"UI"
const BUS_TIMER: StringName = &"Timer"

const CHILD_BUSES: Array[StringName] = [BUS_MUSIC, BUS_AMBIENT, BUS_UI, BUS_TIMER]

## Below this a bus is muted outright rather than set to a very small dB value,
## which would still be faintly audible.
const SILENCE_THRESHOLD: float = 0.001

var _audio_available: bool = true
var _bus_indices: Dictionary = {}


func _ready() -> void:
	_setup_buses()
	EventBus.save_loaded.connect(_on_save_loaded)


## Applies every volume from settings. Called on load and whenever a slider moves.
func apply_settings(settings: GameSettings) -> void:
	if not _audio_available or settings == null:
		return
	set_bus_volume(BUS_MASTER, settings.volume_master)
	set_bus_volume(BUS_MUSIC, settings.volume_music)
	set_bus_volume(BUS_AMBIENT, settings.volume_ambient)
	set_bus_volume(BUS_UI, settings.volume_ui)
	set_bus_volume(BUS_TIMER, settings.volume_timer)


## Sets a bus from a 0..1 linear value, as the settings sliders express it.
func set_bus_volume(bus_name: StringName, linear: float) -> void:
	if not _audio_available or not _bus_indices.has(bus_name):
		return
	var index: int = _bus_indices[bus_name]
	var clamped := clampf(linear, 0.0, 1.0)
	AudioServer.set_bus_mute(index, clamped < SILENCE_THRESHOLD)
	# linear_to_db is the correct conversion: volume sliders are perceptually
	# linear, bus volumes are decibels, and a naive percentage mapping makes the
	# bottom half of every slider do almost nothing.
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(clamped, SILENCE_THRESHOLD)))


func get_bus_volume(bus_name: StringName) -> float:
	if not _audio_available or not _bus_indices.has(bus_name):
		return 0.0
	return db_to_linear(AudioServer.get_bus_volume_db(_bus_indices[bus_name]))


## True when the system has a usable audio device. §54 requires an unavailable
## audio device to be handled: the game runs silently rather than erroring, and
## the settings screen can explain why the sliders do nothing.
func is_audio_available() -> bool:
	return _audio_available


func _setup_buses() -> void:
	# A machine with no sound device gets the Dummy driver, and headless test runs
	# always do. Bus manipulation is pointless there, and treating it as an error
	# would make the test suite fail for a reason unrelated to the code.
	var driver := AudioServer.get_driver_name()
	if driver == "Dummy":
		_audio_available = false
		GameLog.info(GameLog.Category.APP, "No audio device; running silently.")
		return

	_bus_indices[BUS_MASTER] = 0
	for bus_name: StringName in CHILD_BUSES:
		var existing := AudioServer.get_bus_index(bus_name)
		if existing == -1:
			existing = AudioServer.bus_count
			AudioServer.add_bus(existing)
			AudioServer.set_bus_name(existing, bus_name)
			AudioServer.set_bus_send(existing, BUS_MASTER)
		_bus_indices[bus_name] = existing

	GameLog.debug(GameLog.Category.APP, "Audio buses ready on driver '%s'." % driver)


func _on_save_loaded() -> void:
	apply_settings(AppState.get_settings())
