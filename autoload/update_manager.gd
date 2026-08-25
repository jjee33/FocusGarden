extends Node
## Finding, fetching and applying new releases (docs/UPDATES.md).
##
## Owns: the update check, the download, checksum verification, and handing the
## installer to the OS.
## Must never: touch player data, or act without the player having said yes.
##
## THE ONLY NETWORK CODE IN THE APP. Focus Garden is otherwise entirely offline —
## no accounts, no telemetry, no analytics — and that is a property worth keeping
## legible rather than eroding. Everything here talks to exactly one host, sends
## nothing but the HTTP request itself, runs only in exported builds, and stops
## dead if `check_for_updates` is off.
##
## WHY A MANIFEST AND NOT THE GITHUB API: `releases/latest/download/latest.json`
## is a plain file on a stable URL that always resolves to the newest release. It
## needs no token, has no rate limit worth hitting, and gives us somewhere to put
## the SHA-256 of each asset — which is the part that matters, because something
## we are about to execute must be verified before it is run.
##
## WHY IT NEVER INTERRUPTS: a focus session is the one thing this app exists to
## protect. If a check finishes mid-session the notice waits for the session to
## end (§3). Nothing here is urgent enough to be worth a lost session.

const MANIFEST_URL := "https://github.com/jjee33/FocusGarden/releases/latest/download/latest.json"
const RELEASES_URL := "https://github.com/jjee33/FocusGarden/releases/latest"

## Where downloads land. Under user://, so an update that is never applied is
## thrown away with the rest of the app data rather than left in Downloads.
const DOWNLOAD_DIR := "user://updates"

## Long enough after launch that a cold start is never waiting on a socket.
const CHECK_DELAY_SECONDS: float = 6.0
const REQUEST_TIMEOUT_SECONDS: float = 20.0
const DOWNLOAD_TIMEOUT_SECONDS: float = 600.0

## A manifest is a few hundred bytes. Anything near this size is not one, and
## refusing early means a wrong URL cannot stream indefinitely into memory.
const MAX_MANIFEST_BYTES: int = 64 * 1024

## The only hosts ever contacted. The manifest arrives over TLS from our own
## release page, so its URLs are already trustworthy — this is the second lock on
## the same door, and it costs nothing.
const ALLOWED_HOSTS: Array[String] = [
	"github.com",
	"objects.githubusercontent.com",
	"release-assets.githubusercontent.com",
]

enum State {
	IDLE,
	CHECKING,
	AVAILABLE,
	DOWNLOADING,
	READY,
	INSTALLING,
}

var state: State = State.IDLE

## Populated once a check finds something newer.
var available_version: String = ""
var available_notes: String = ""
var available_notes_url: String = RELEASES_URL

## Absolute path of a verified download, once there is one.
var ready_path: String = ""

var _request: HTTPRequest = null
var _platform_key: String = ""
var _asset: Dictionary = {}
var _manual_check: bool = false
## Set when a check succeeds during a focus session; announced when it ends.
var _deferred_announcement: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(false)

	_platform_key = _detect_platform()

	_request = HTTPRequest.new()
	_request.use_threads = true
	_request.request_completed.connect(_on_request_completed)
	add_child(_request)

	EventBus.session_completed.connect(_on_session_completed)

	# The editor never checks. Development runs and every headless gate must stay
	# offline, or the test suite acquires a dependency on GitHub being up.
	if not is_available():
		GameLog.debug(GameLog.Category.APP, "Update check skipped: not an exported build.")
		return

	_clear_stale_downloads()

	if not AppState.get_settings().check_for_updates:
		GameLog.info(GameLog.Category.APP, "Update check disabled in settings.")
		return

	# Deferred rather than immediate: launch is for getting the player to their
	# garden, not for network I/O.
	var delay := get_tree().create_timer(CHECK_DELAY_SECONDS, true, false, true)
	delay.timeout.connect(func() -> void: check_now(false))


# --- Checking -------------------------------------------------------------

## False in the editor. Nothing here runs from a development build, so neither a
## dev session nor a headless gate can reach the network — including through the
## "Check now" button, which is disabled rather than merely unused.
func is_available() -> bool:
	return OS.has_feature("template")


## Ask whether a newer release exists. `manual` marks a check the player asked
## for, which reports its result either way; a background check stays quiet
## unless there is something to say.
func check_now(manual: bool = true) -> bool:
	if not is_available():
		return false
	if state != State.IDLE and state != State.AVAILABLE:
		return false
	if _request == null:
		return false

	_manual_check = manual
	state = State.CHECKING
	GameLog.info(GameLog.Category.APP, "Checking for updates...")

	_request.download_file = ""
	_request.timeout = REQUEST_TIMEOUT_SECONDS
	_request.body_size_limit = MAX_MANIFEST_BYTES

	var error := _request.request(MANIFEST_URL, _headers())
	if error != OK:
		_fail("Could not start the update check (error %d)." % error)
		return false
	return true


func _on_manifest(body: PackedByteArray) -> void:
	var parsed: Variant = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("The update manifest was not readable.")
		return

	var manifest: Dictionary = parsed
	var version := DictUtil.get_string(manifest, "version")
	if not VersionUtil.is_valid(version):
		_fail("The update manifest had no usable version.")
		return

	var current := VersionUtil.current()
	if not VersionUtil.is_newer(version, current):
		state = State.IDLE
		GameLog.info(GameLog.Category.APP, "Up to date (%s)." % current)
		EventBus.update_check_completed.emit(true)
		return

	var platforms: Dictionary = DictUtil.get_dict(manifest, "platforms")
	var asset: Dictionary = DictUtil.get_dict(platforms, _platform_key)
	var url := DictUtil.get_string(asset, "url")
	var checksum := DictUtil.get_string(asset, "sha256")

	if url.is_empty() or checksum.is_empty():
		# A real release, but with nothing built for this platform. Say so rather
		# than pretending there is nothing there.
		_asset = {}
	elif not _is_allowed_url(url):
		_fail("The update manifest pointed somewhere unexpected.")
		return
	else:
		_asset = {"url": url, "sha256": checksum.to_lower()}

	available_version = version
	available_notes = DictUtil.get_string(manifest, "notes")
	var notes_url := DictUtil.get_string(manifest, "notes_url")
	available_notes_url = notes_url if _is_allowed_url(notes_url) else RELEASES_URL

	state = State.AVAILABLE
	GameLog.info(GameLog.Category.APP, "Update available: %s (running %s)." % [version, current])
	EventBus.update_check_completed.emit(false)

	if _is_session_running() and not _manual_check:
		_deferred_announcement = true
		return
	_announce()


func _announce() -> void:
	_deferred_announcement = false
	EventBus.update_available.emit(available_version, available_notes)
	EventBus.toast_requested.emit(
		"Version %s is available" % available_version,
		"Install it from Settings whenever suits you.",
		"✨"
	)


func _on_session_completed(_session_id: String) -> void:
	if _deferred_announcement and state == State.AVAILABLE:
		_announce()


# --- Downloading ----------------------------------------------------------

## True when this build can replace itself: a Windows install, or a Linux
## AppImage. An extracted AppDir or a distribution package is updated by whatever
## installed it, and we must not overwrite files we do not own.
func can_self_install() -> bool:
	if not is_available():
		return false
	if _platform_key == "windows":
		return true
	return _platform_key == "linux" and not OS.get_environment("APPIMAGE").is_empty()


func has_asset() -> bool:
	return not _asset.is_empty()


## Fetch the update. Emits progress, then `update_ready_to_install` once the
## download's checksum matches the manifest.
func download() -> bool:
	if state != State.AVAILABLE or _asset.is_empty():
		return false
	if _request == null:
		return false

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DOWNLOAD_DIR))
	var url: String = _asset["url"]
	var target := "%s/%s" % [DOWNLOAD_DIR, url.get_file()]

	state = State.DOWNLOADING
	_request.download_file = target
	_request.timeout = DOWNLOAD_TIMEOUT_SECONDS
	# No cap: the installer is over 100 MB, and HTTPRequest aborts on whatever
	# limit it is given rather than streaming past it.
	_request.body_size_limit = -1

	var error := _request.request(url, _headers())
	if error != OK:
		_fail("Could not start the download (error %d)." % error)
		return false

	set_process(true)
	EventBus.update_download_started.emit(available_version)
	GameLog.info(GameLog.Category.APP, "Downloading %s" % url.get_file())
	return true


func _process(_delta: float) -> void:
	if state != State.DOWNLOADING or _request == null:
		set_process(false)
		return
	EventBus.update_download_progress.emit(
		_request.get_downloaded_bytes(), _request.get_body_size()
	)


func _on_download_finished(path: String) -> void:
	set_process(false)

	if not FileAccess.file_exists(path):
		_fail("The download did not arrive.")
		return

	# Verify BEFORE anything is made executable or handed to the OS. This is the
	# whole reason the manifest carries a checksum: what came down the wire is
	# about to run with the player's privileges.
	var expected: String = _asset.get("sha256", "")
	var actual := FileAccess.get_sha256(path).to_lower()
	if actual != expected:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		GameLog.error(
			GameLog.Category.APP,
			"Checksum mismatch: expected %s, got %s" % [expected, actual]
		)
		_fail("The download did not match its checksum and was discarded.")
		return

	ready_path = ProjectSettings.globalize_path(path)
	state = State.READY
	GameLog.info(GameLog.Category.APP, "Update %s verified." % available_version)
	EventBus.update_ready_to_install.emit(available_version, ready_path)


# --- Installing -----------------------------------------------------------

## Hand the verified download to the OS and quit. Returns false if it could not
## be started, in which case the app keeps running and nothing has changed.
func install() -> bool:
	if state != State.READY or ready_path.is_empty():
		return false

	# Flush first. The process is about to end, and an update that costs someone
	# their last session is not one they will forgive.
	AppState.save_now()

	state = State.INSTALLING
	var started := false
	if _platform_key == "windows":
		started = _install_windows()
	elif _platform_key == "linux":
		started = _install_appimage()

	if not started:
		state = State.READY
		return false

	GameLog.info(GameLog.Category.APP, "Installing %s; quitting." % available_version)
	get_tree().quit()
	return true


func _install_windows() -> bool:
	# /SILENT rather than /VERYSILENT: a progress window is the only sign the
	# player gets that the thing they clicked is happening.
	# relaunch=1 is read by packaging/windows/FocusGarden.iss, which reopens the
	# app afterwards — a silent install skips the usual post-install [Run] entry.
	var arguments := PackedStringArray([
		"/SILENT", "/NORESTART", "/CLOSEAPPLICATIONS", "/relaunch=1",
	])
	if OS.create_process(ready_path, arguments) == -1:
		_fail("Windows would not start the installer.")
		return false
	return true


func _install_appimage() -> bool:
	var target := OS.get_environment("APPIMAGE")
	if target.is_empty():
		_fail("This build cannot replace itself. Download the new version instead.")
		return false

	# Stage beside the current file and rename over it. Rename is atomic, and the
	# running process keeps the old inode mounted, so replacing ourselves
	# mid-flight is safe in a way that writing over the top is not.
	var staged := "%s.new" % target
	if DirAccess.copy_absolute(ready_path, staged) != OK:
		_fail("Could not write next to the current AppImage. Is it somewhere writable?")
		return false
	if OS.execute("chmod", PackedStringArray(["+x", staged])) != 0:
		DirAccess.remove_absolute(staged)
		_fail("Could not make the new AppImage executable.")
		return false
	if DirAccess.rename_absolute(staged, target) != OK:
		DirAccess.remove_absolute(staged)
		_fail("Could not replace the current AppImage.")
		return false

	if OS.create_process(target, PackedStringArray()) == -1:
		# The new build is in place; it just did not start. Better to say so than
		# to quit and leave the player wondering what happened.
		_fail("Updated, but the new version would not start. Launch it yourself.")
		return false
	return true


## Open the release page. The fallback for builds we cannot self-install onto.
func open_release_page() -> void:
	OS.shell_open(available_notes_url)


# --- Plumbing -------------------------------------------------------------

func _on_request_completed(
	result: int, response_code: int, _response_headers: PackedStringArray, body: PackedByteArray
) -> void:
	var was_download := state == State.DOWNLOADING
	var download_path := _request.download_file
	_request.download_file = ""

	if result != HTTPRequest.RESULT_SUCCESS:
		_fail(_describe_result(result))
		return
	if response_code < 200 or response_code >= 300:
		_fail("The update server answered with %d." % response_code)
		return

	if was_download:
		_on_download_finished(download_path)
	else:
		_on_manifest(body)


func _fail(reason: String) -> void:
	set_process(false)
	# A failed background check is not news. Only a check the player asked for, or
	# a download they are watching, is worth interrupting them about.
	var loud := _manual_check or state == State.DOWNLOADING or state == State.INSTALLING
	state = State.AVAILABLE if not available_version.is_empty() else State.IDLE

	GameLog.warn(GameLog.Category.APP, "Update: %s" % reason)
	if loud:
		EventBus.update_failed.emit(reason)


func _headers() -> PackedStringArray:
	return PackedStringArray([
		"User-Agent: FocusGarden/%s" % VersionUtil.current(),
		"Accept: application/octet-stream, application/json",
	])


func _detect_platform() -> String:
	if OS.has_feature("windows"):
		return "windows"
	if OS.has_feature("linux"):
		return "linux"
	if OS.has_feature("macos"):
		return "macos"
	return ""


func _is_allowed_url(url: String) -> bool:
	if not url.begins_with("https://"):
		return false
	var authority := url.substr(8).split("/", true, 1)[0]
	# Strip any userinfo and port before matching, so a crafted
	# "github.com@evil.example" cannot pass for the real host.
	var host := authority.split("@")[-1].split(":")[0].to_lower()
	return ALLOWED_HOSTS.has(host)


func _is_session_running() -> bool:
	return TimerManager.state == TimerManager.State.RUNNING


## Anything left in user://updates is from a download that was never applied, or
## one that was and is now the running build. Neither is worth 100 MB.
func _clear_stale_downloads() -> void:
	var directory := DirAccess.open(DOWNLOAD_DIR)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if not directory.current_is_dir():
			directory.remove(entry)
		entry = directory.get_next()
	directory.list_dir_end()


func _describe_result(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CANT_CONNECT, HTTPRequest.RESULT_CANT_RESOLVE:
			return "Could not reach GitHub."
		HTTPRequest.RESULT_TIMEOUT:
			return "The connection timed out."
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "The secure connection could not be established."
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN, HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return "Could not write the download to disk."
		HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
			return "The response was larger than expected."
		_:
			return "The update request failed (result %d)." % result
