class_name SessionCredit
extends RefCounted
## How much of a measured session actually counts (§12).
##
## §12 sets the policy: completed sessions get full credit, manually ended
## sessions get the time actually focused, and legitimately focused time is never
## silently lost. This is the one place that policy is expressed.
##
## Separated from TimerManager so it is testable without a running clock.

## Final credited minutes for a finished session.
##
## `raw_minutes` is what GameClock measured; `intended_minutes` is the length the
## player asked for.
static func settle(
	completion: FocusSession.Completion, raw_minutes: float, intended_minutes: float
) -> float:
	if completion == FocusSession.Completion.CANCELLED:
		return 0.0

	var credited := maxf(0.0, raw_minutes)
	if completion == FocusSession.Completion.COMPLETED:
		# A completed session is worth its intended duration exactly. The raw
		# measurement overshoots by whatever fraction of a tick elapsed past the
		# finish line, which would record a "25 minute" session as 25.02.
		return minf(credited, maxf(0.0, intended_minutes))
	return credited


## Credited minutes for a session recovered after the app closed mid-run (§54).
##
## Capped at the intended duration because the app may have been shut for days,
## and a three-day "focus session" is obviously not three days of focus. The
## player is asked before any of this is applied.
static func settle_recovered(raw_minutes: float, intended_minutes: float) -> float:
	return minf(maxf(0.0, raw_minutes), maxf(0.0, intended_minutes))


## Whether a session is long enough to grow a plant (§12's configurable
## threshold). Time below the threshold is still recorded and still earns XP —
## it simply does not advance a plant.
static func earns_plant_growth(
	kind: FocusSession.Kind, credited_minutes: float, minimum_minutes: float
) -> bool:
	return kind == FocusSession.Kind.FOCUS and credited_minutes >= maxf(0.0, minimum_minutes)
