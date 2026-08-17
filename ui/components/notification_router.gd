class_name NotificationRouter
extends Node
## Decides which game events deserve to interrupt the player (§34).
##
## Lives in the UI layer, not an autoload: "should this be announced" is a
## presentation decision, and §40 keeps that out of the singletons. Systems emit
## facts (`session_completed`); this decides whether the player hears about them.
##
## §3 rules out excessive notifications, so the policy is deliberately narrow:
## only a session ending speaks, and only when the matching setting is on.
## Nothing celebrates a streak, nudges about a daily goal, or announces that the
## player has been idle.

func _ready() -> void:
	EventBus.session_completed.connect(_on_session_completed)
	EventBus.achievement_unlocked.connect(_on_achievement_unlocked)


func _on_session_completed(session_id: String) -> void:
	var session := _find_session(session_id)
	if session == null:
		return

	var settings := AppState.get_settings()
	if session.is_break():
		if settings.notify_break_complete:
			EventBus.toast_requested.emit(
				"Break over",
				"Ready for another session when you are.",
				"🌤"
			)
		return

	if not settings.notify_focus_complete:
		return

	# A cancelled session is not an accomplishment and must not be congratulated.
	if session.completion == FocusSession.Completion.CANCELLED:
		return

	EventBus.toast_requested.emit(
		"Session complete",
		"%s of focus recorded." % TimeUtil.format_duration(session.actual_focus_minutes),
		"🌱"
	)


func _on_achievement_unlocked(achievement_id: String) -> void:
	var definition := ContentDB.get_achievement(StringName(achievement_id))
	if definition == null:
		return
	EventBus.toast_requested.emit(definition.title, definition.description, "🏅")


## Sessions are looked up from recorded history rather than passed by value,
## because by the time this fires the pipeline has already stored the final
## record — which is the version with the credited minutes on it.
func _find_session(session_id: String) -> FocusSession:
	for session: FocusSession in AppState.sessions:
		if session.id == session_id:
			return session
	return null
