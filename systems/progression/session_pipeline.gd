class_name SessionPipeline
extends RefCounted
## The nine ordered steps that run when a session completes (§11).
##
## WHY THIS EXISTS AS A PIPELINE RATHER THAN SIGNAL LISTENERS:
## The obvious design has each manager subscribe to `session_completed` and react.
## That silently breaks two of §11's guarantees. Signal handler order is not
## specified, so achievements could evaluate before the XP that satisfies them is
## awarded; and any handler that runs twice (a double-connected signal, a replayed
## event, a recovered session) double-awards. §63 requires "XP cannot double-award
## from one session" and "unlock events only trigger once".
##
## So completion is an explicit ordered function, and it is IDEMPOTENT: the guard
## is `session.awards_applied`, stored on the session record itself and persisted.
## Re-running the pipeline for an already-processed session is a no-op, whatever
## the reason it was re-run.

class Outcome extends RefCounted:
	var applied: bool = false
	var credited_minutes: float = 0.0
	var xp_awarded: int = 0
	var levels_gained: int = 0
	var growth: PlantGrowthService.GrowthResult = null
	var plant_matured: bool = false
	var species_discovered: bool = false
	var unlocked_achievement_ids: PackedStringArray = PackedStringArray()
	var streak_after: int = 0
	var skipped_reason: String = ""


## Runs the completion steps for `session`, in the order §11 specifies.
## Returns what actually happened so the completion screen can show it (§11's
## "polished completion screen" needs to know what to celebrate).
static func apply(session: FocusSession) -> Outcome:
	var outcome := Outcome.new()

	if session == null:
		outcome.skipped_reason = "No session."
		return outcome

	# THE IDEMPOTENCY GATE. Everything below mutates player state exactly once.
	if session.awards_applied:
		outcome.skipped_reason = "Awards already applied to this session."
		GameLog.warn(
			GameLog.Category.PROGRESSION,
			"Refused to re-apply awards for session %s." % session.id
		)
		return outcome

	var settings := AppState.get_settings()

	# --- 1 & 2. Record the session and settle its credited focus minutes. ---
	# The minutes were measured by GameClock; the only decision left is whether a
	# very short session earns growth (§12's configurable threshold).
	outcome.credited_minutes = session.actual_focus_minutes
	var earns_growth := SessionCredit.earns_plant_growth(
		session.kind, outcome.credited_minutes, settings.minimum_credit_minutes
	)

	# Mark before doing the work: if anything below fails, we must not leave the
	# session eligible for a second full pass.
	session.awards_applied = true
	outcome.applied = true

	if not session.counts_toward_progress():
		# Cancelled or zero-length. The record is still kept — §12 says never
		# silently lose time the user legitimately focused, and §37 wants the row
		# for analytics either way.
		AppState.record_session(session)
		AppState.save_now()
		outcome.skipped_reason = "Session earned no credit."
		return outcome

	AppState.record_session(session)
	EventBus.focus_time_recorded.emit(session.id, outcome.credited_minutes)

	# --- 3. Apply plant growth. ---
	if earns_growth:
		outcome.growth = _apply_plant_growth(session, outcome)

	# --- 4. Award XP. ---
	var xp := XpFormula.xp_for_session(session)
	if xp > 0:
		session.xp_earned = xp
		outcome.xp_awarded = xp
		outcome.levels_gained = ProgressionManager.award_xp(xp)

	# --- 6 & 7. Update streak and statistics. ---
	# Statistics are invalidated before achievements are evaluated, because
	# achievement requirements are measured against freshly aggregated data.
	StatisticsManager.invalidate()
	_update_streak(outcome)

	# --- 5. Evaluate achievements. ---
	var context := StatisticsManager.build_context(session.plant_uid)
	outcome.unlocked_achievement_ids = AchievementManager.evaluate_all(context)

	# --- 8. Evaluate unlocks. ---
	ProgressionManager.reconcile_level_unlocks()

	# --- 9. Save immediately. ---
	# Both the profile and the session row: the session was mutated above
	# (xp_earned, awards_applied) and that must survive a crash, or the guard
	# would be lost and the next launch could re-award it.
	AppState.record_session(session)
	AppState.save_now()

	GameLog.info(
		GameLog.Category.PROGRESSION,
		"Session %s applied: %s, %d XP." % [
			session.id, TimeUtil.format_duration(outcome.credited_minutes), xp
		]
	)
	return outcome


static func _apply_plant_growth(session: FocusSession, outcome: Outcome) -> PlantGrowthService.GrowthResult:
	var plant := AppState.get_plant(session.plant_uid)
	if plant == null:
		return null

	var species := ContentDB.get_species(plant.species_id)
	if species == null:
		# §54: a species removed in a future update must not destroy the plant.
		GameLog.warn(
			GameLog.Category.PLANT,
			"Species '%s' is missing; plant %s keeps its progress but cannot grow."
			% [plant.species_id, plant.uid]
		)
		return null

	plant.accumulated_focus_minutes += session.actual_focus_minutes
	if not plant.contributing_session_ids.has(session.id):
		plant.contributing_session_ids.append(session.id)

	# Plant-scoped only: a growth requirement never reads global figures, and the
	# full context would re-aggregate the entire session history on every
	# completed session (§44).
	var context := StatisticsManager.build_plant_context(plant.uid)
	var growth := PlantGrowthService.apply_growth(plant, species, context)

	EventBus.plant_growth_changed.emit(plant.uid, plant.accumulated_focus_minutes)
	if growth.stage_changed:
		EventBus.plant_stage_changed.emit(plant.uid, growth.new_stage)

	if growth.just_matured:
		outcome.plant_matured = true
		EventBus.plant_matured.emit(plant.uid)

		# A finished plant stops being the growth target. Leaving it selected
		# meant the next session poured time into something already complete,
		# and Home showed a permanent "100% grown" that nothing could advance.
		if AppState.data.profile.active_plant_uid == plant.uid:
			AppState.data.profile.active_plant_uid = ""
			EventBus.active_plant_changed.emit("")

		var entry := AppState.ensure_catalogue_entry(plant.species_id)
		entry.total_focus_minutes += plant.accumulated_focus_minutes
		entry.record_maturity(plant.accumulated_focus_minutes)
		if entry.discover():
			outcome.species_discovered = true
			EventBus.catalogue_entry_discovered.emit(String(plant.species_id))

		AppState.add_journal_entry(
			JournalEntry.create(
				JournalEntry.Kind.PLANT_MATURED,
				"%s reached maturity" % species.display_name,
				"Grown over %s of focus." % TimeUtil.format_duration(plant.accumulated_focus_minutes),
				plant.uid
			)
		)

	return growth


static func _update_streak(outcome: Outcome) -> void:
	var profile := AppState.data.profile
	var streak := StatisticsManager.get_streak()
	profile.current_streak = streak.current
	profile.longest_streak = maxi(profile.longest_streak, streak.longest)
	profile.last_focus_date_key = streak.last_qualifying_day
	outcome.streak_after = streak.current
	EventBus.streak_changed.emit(streak.current)
