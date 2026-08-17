extends Node
## Leveled, category-tagged logging (§52).
##
## Owns: formatting and emitting diagnostic output.
## Must never: contain game logic, mutate player state, or touch the UI.
##
## Debug builds log everything from DEBUG up. Release builds start at WARN, so a
## shipped game does not spend frames formatting strings nobody reads.

enum Level { DEBUG, INFO, WARN, ERROR }

## Categories from §52. Kept as an enum rather than free strings so a typo is a
## parse error instead of a silently unfilterable log line.
enum Category { SAVE, TIMER, PLANT, PROGRESSION, ACHIEVEMENT, UI, DATA, APP }

const _LEVEL_NAMES: Array[String] = ["DEBUG", "INFO", "WARN", "ERROR"]
const _CATEGORY_NAMES: Array[String] = [
	"SAVE", "TIMER", "PLANT", "PROGRESSION", "ACHIEVEMENT", "UI", "DATA", "APP",
]

## Ring buffer of recent lines, surfaced in the in-app error dialog so users can
## report a problem without hunting for a log file (§51).
const _HISTORY_LIMIT: int = 400

var min_level: Level = Level.DEBUG
var _history: PackedStringArray = PackedStringArray()


func _ready() -> void:
	min_level = Level.DEBUG if OS.is_debug_build() else Level.WARN


func debug(category: Category, message: String) -> void:
	_write(Level.DEBUG, category, message)


func info(category: Category, message: String) -> void:
	_write(Level.INFO, category, message)


func warn(category: Category, message: String) -> void:
	_write(Level.WARN, category, message)


func error(category: Category, message: String) -> void:
	_write(Level.ERROR, category, message)


## Recent log lines, oldest first. For the error dialog's "technical details".
func get_history() -> PackedStringArray:
	return _history.duplicate()


func _write(level: Level, category: Category, message: String) -> void:
	# History is recorded regardless of min_level: when something goes wrong we
	# want the debug lines that led up to it, even in a release build.
	var line := "[%s][%s] %s" % [_LEVEL_NAMES[level], _CATEGORY_NAMES[category], message]
	_history.append(line)
	if _history.size() > _HISTORY_LIMIT:
		_history.remove_at(0)

	if level < min_level:
		return

	match level:
		Level.ERROR:
			push_error(line)
		Level.WARN:
			push_warning(line)
		_:
			print(line)
