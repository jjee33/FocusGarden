extends Node
## Sends this garden to thefocusgarden.com, or brings that one down.
##
## OPT-IN AND MANUAL, both by design. There is no timer and no automatic call
## anywhere in this file. The web client merges record by record; this exchanges
## a WHOLE bundle, which means each direction REPLACES the other side. That is a
## perfectly good primitive when a person presses a button having been told what
## it costs, and a catastrophe on a schedule.
##
## THE TOKEN IS NOT PART OF THE SAVE. It lives in its own config file beside the
## save-location one, and never in SaveData — a credential inside the save would
## be written into every exported bundle, and "export a copy" would quietly hand
## out the keys to the account along with the garden.

## Where the account lives. Overridable for a local server during development.
const DEFAULT_HOST: String = "https://thefocusgarden.com"
const CONFIG_PATH: String = "user://cloud_sync.cfg"
## Written and read back so the downloaded bundle goes through the same
## migration and validation as a file the player picked themselves.
const STAGING_PATH: String = "user://.cloud_incoming.json"

signal sync_started()
## ok, then a sentence fit to show a person.
signal sync_finished(ok: bool, message: String)

var _request: HTTPRequest = null
var _token: String = ""
var _host: String = DEFAULT_HOST
var _busy: bool = false
## What the in-flight request is doing, so the one callback can tell them apart.
var _mode: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_request = HTTPRequest.new()
	_request.use_threads = true
	_request.request_completed.connect(_on_request_completed)
	add_child(_request)
	_load_config()


## True once a token has been saved. Nothing in the UI should offer to sync
## before this.
func is_configured() -> bool:
	return not _token.is_empty()


func get_host() -> String:
	return _host


## Stores the token. Pass "" to forget it, which is what a player expects
## "disconnect" to mean and is the only removal this app performs.
func set_token(token: String, host: String = "") -> void:
	_token = token.strip_edges()
	if not host.strip_edges().is_empty():
		_host = host.strip_edges().trim_suffix("/")

	var config := ConfigFile.new()
	config.set_value("cloud", "token", _token)
	config.set_value("cloud", "host", _host)
	config.save(CONFIG_PATH)

	# Never the token itself, not even a prefix. A log file is a place people
	# paste into bug reports.
	GameLog.info(
		GameLog.Category.APP,
		"Cloud sync %s." % ("configured" if is_configured() else "disconnected")
	)


## A shape check, so an obviously wrong paste is refused before a round trip.
static func looks_like_token(token: String) -> bool:
	var trimmed := token.strip_edges()
	return trimmed.begins_with("fgt_") and trimmed.length() >= 44


## Uploads this garden, REPLACING whatever the account holds.
func push_now() -> bool:
	if not _begin("push"):
		return false

	var save: SaveData = AppState.data
	if save == null:
		_finish(false, "There is nothing here to send yet.")
		return false

	# Sessions go WITH it, for the same reason the file export does: plants
	# without their history is half a garden, and every statistic behind them
	# would arrive empty.
	var bundle := SaveBundle.build(save, AppState.sessions, VersionUtil.current())
	var error := _request.request(
		"%s/api/sync/bundle" % _host,
		_headers(),
		HTTPClient.METHOD_POST,
		JSON.stringify(bundle)
	)
	if error != OK:
		_finish(false, "Could not reach the server (error %d)." % error)
		return false
	return true


## Downloads the account's garden. Does NOT apply it: the caller is handed an
## Imported and shows the player what is in it first, exactly as a file import
## does. Emits sync_finished(false, ...) on failure.
func pull_now() -> bool:
	if not _begin("pull"):
		return false

	var error := _request.request("%s/api/sync/bundle" % _host, _headers(), HTTPClient.METHOD_GET)
	if error != OK:
		_finish(false, "Could not reach the server (error %d)." % error)
		return false
	return true


## Set by a completed pull, for the caller to inspect and then apply or discard.
var pulled: SaveBundle.Imported = null


func _begin(mode: String) -> bool:
	if _busy:
		return false
	if not is_configured():
		_finish(false, "Add a sync token in Settings first.")
		return false
	_busy = true
	_mode = mode
	pulled = null
	sync_started.emit()
	return true


func _finish(ok: bool, message: String) -> void:
	_busy = false
	_mode = ""
	sync_finished.emit(ok, message)


func _headers() -> PackedStringArray:
	return PackedStringArray([
		"Authorization: Bearer %s" % _token,
		"Content-Type: application/json",
		"Accept: application/json",
		"User-Agent: FocusGarden/%s" % VersionUtil.current(),
	])


func _on_request_completed(
	result: int, response_code: int, _headers_out: PackedStringArray, body: PackedByteArray
) -> void:
	var mode := _mode
	if result != HTTPRequest.RESULT_SUCCESS:
		_finish(false, "Could not reach the server. Your garden is untouched.")
		return

	if response_code == 401:
		# Worth naming precisely: a revoked or mistyped token is the most likely
		# failure here and the least obvious from a generic message.
		_finish(false, "That token was refused. It may have been revoked — create a new one on the website.")
		return
	if response_code < 200 or response_code >= 300:
		_finish(false, _server_message(body, response_code))
		return

	if mode == "push":
		_finish(true, "Your garden is now on the website.")
		return
	_handle_pulled(body)


func _handle_pulled(body: PackedByteArray) -> void:
	# Staged to disk and read back through SaveManager, so a downloaded bundle is
	# migrated and validated by exactly the same code as a file the player picked.
	# A second, network-only parsing path is a second place for the save format to
	# be got subtly wrong.
	var error := AtomicFile.write_json(STAGING_PATH, _parse_object(body), "", false)
	if error != OK:
		_finish(false, "The download could not be saved for reading (error %d)." % error)
		return

	var imported := SaveManager.read_bundle(STAGING_PATH)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(STAGING_PATH))
	if imported == null:
		_finish(false, SaveManager.last_error_detail)
		return

	pulled = imported
	_finish(true, "")


func _parse_object(body: PackedByteArray) -> Dictionary:
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	return parsed if parsed is Dictionary else {}


## Pulls the server's own wording out of an error body when there is one, because
## "the bundle was written by a newer version" is far more use than "HTTP 400".
func _server_message(body: PackedByteArray, code: int) -> String:
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if parsed is Dictionary and (parsed as Dictionary).has("error"):
		return String((parsed as Dictionary)["error"])
	return "The server refused that (HTTP %d)." % code


func _load_config() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return
	_token = String(config.get_value("cloud", "token", ""))
	_host = String(config.get_value("cloud", "host", DEFAULT_HOST))
