extends SceneTree
## Proves the desktop can actually talk to the account server.
##
##     tools/godot/Godot_v4.7.1-stable_win64.exe --headless --path . \
##         --script res://tools/verify_cloud_sync.gd -- <token> [host]
##
## Needs a real device token, created in the web app under Settings. It is passed
## on the command line rather than read from the saved config so this can be run
## against a throwaway account without disturbing whatever the player has set up.
##
## Pushes the current garden, pulls it back, and compares. A round trip that
## loses a plant is the whole thing this is here to catch — the format is shared
## between two clients written in different languages, and "it looked right" is
## not a check.

# Autoloads are fetched from the tree, never by name. A script run via --script
# is COMPILED BEFORE autoloads are registered, so writing `CloudSync` directly
# here is a compile error ("Identifier not found") - the same trap
# verify_save_transfer.gd documents, and the same workaround.
var _cloud: Node
var _app_state: Node

var _token: String = ""
var _host: String = ""


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		printerr("Usage: --script res://tools/verify_cloud_sync.gd -- <token> [host]")
		quit(2)
		return
	_token = args[0]

	# Autoloads also initialise after this script is constructed, so nothing they
	# hold is ready until at least one frame has passed.
	await process_frame

	_cloud = root.get_node_or_null("/root/CloudSync")
	_app_state = root.get_node_or_null("/root/AppState")
	if _cloud == null or _app_state == null:
		printerr("Autoloads are not available; cannot verify.")
		quit(1)
		return

	_host = args[1] if args.size() > 1 else String(_cloud.DEFAULT_HOST)
	await _run()


func _run() -> void:
	if not bool(_cloud.looks_like_token(_token)):
		printerr("That does not look like a device token (expected fgt_… of 44+ characters).")
		quit(1)
		return

	_cloud.set_token(_token, _host)
	print("Host: %s" % String(_cloud.get_host()))

	var save = _app_state.data
	if save == null:
		printerr("No save loaded; nothing to send.")
		quit(1)
		return

	# Explicit types throughout: the autoloads are held as plain Node, so nothing
	# reached through them carries a type the compiler can infer.
	var plants_before: int = save.plants.size()
	var sessions_before: int = _app_state.sessions.size()
	var name_before: String = save.profile.display_name
	print("Local garden: %d plants, %d sessions, name %s"
		% [plants_before, sessions_before, name_before])

	# --- push ---------------------------------------------------------------
	if not bool(_cloud.push_now()):
		printerr("Push refused before it started.")
		quit(1)
		return
	var pushed: Array = await _cloud.sync_finished
	if not bool(pushed[0]):
		printerr("PUSH FAILED: %s" % pushed[1])
		quit(1)
		return
	print("Pushed.")

	# --- pull ---------------------------------------------------------------
	if not bool(_cloud.pull_now()):
		printerr("Pull refused before it started.")
		quit(1)
		return
	var got: Array = await _cloud.sync_finished
	if not bool(got[0]):
		printerr("PULL FAILED: %s" % got[1])
		quit(1)
		return

	var imported = _cloud.pulled
	if imported == null:
		printerr("Pull reported success but produced nothing.")
		quit(1)
		return

	# --- compare -------------------------------------------------------------
	var ok := true
	ok = _expect("plants", plants_before, imported.save.plants.size()) and ok
	ok = _expect("sessions", sessions_before, imported.sessions.size()) and ok
	ok = _expect_text("display name", name_before, imported.save.profile.display_name) and ok
	ok = _expect("projects", save.projects.size(), imported.save.projects.size()) and ok
	ok = _expect("catalogue", save.catalogue.size(), imported.save.catalogue.size()) and ok
	ok = _expect("achievements", save.achievements.size(), imported.save.achievements.size()) and ok
	ok = _expect("journal", save.journal.size(), imported.save.journal.size()) and ok

	# Nothing was applied: a verification that overwrites the garden it is
	# verifying is a verification nobody dares run twice.
	print("Nothing was applied locally. The garden on this machine is untouched.")

	if ok:
		print("PASS: the garden survived a round trip through the account.")
		quit(0)
	else:
		printerr("FAIL: the round trip lost something.")
		quit(1)


func _expect(label: String, want: int, got: int) -> bool:
	if want == got:
		print("  ok    %s: %d" % [label, got])
		return true
	printerr("  LOST  %s: sent %d, got back %d" % [label, want, got])
	return false


func _expect_text(label: String, want: String, got: String) -> bool:
	if want == got:
		print("  ok    %s: %s" % [label, got])
		return true
	printerr("  LOST  %s: sent '%s', got back '%s'" % [label, want, got])
	return false
