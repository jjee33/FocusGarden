class_name XpFormula
extends RefCounted
## The one authoritative XP and level calculation (§25, §38).
##
## §38 requires exactly one implementation of XP and level math, and §25 forbids
## hardcoding level thresholds across files. Everything that needs a level asks
## here; nothing else may derive one.
##
## §25 also requires that levels never change the effectiveness of focus time, so
## XP per minute is a flat constant. There is no multiplier, no bonus tier, and
## no way for progression to make a later minute worth more than an early one —
## that would quietly turn a productivity tool into a grind.

const XP_PER_FOCUS_MINUTE: float = 2.0
## Breaks earn a token amount: §26's "Taking Care" rewards resting, but resting
## must not compete with focusing as an XP source.
const XP_PER_BREAK_MINUTE: float = 0.25

## Cumulative XP for level L is: LINEAR*(L-1) + QUADRATIC*(L-1)^2
## Quadratic so early levels arrive quickly and later ones represent real
## investment, without ever becoming unreachable.
const LINEAR_TERM: float = 50.0
const QUADRATIC_TERM: float = 25.0
const MAX_LEVEL: int = 100


## XP awarded for a session. The single place session XP is decided.
static func xp_for_session(session: FocusSession) -> int:
	if not session.counts_toward_progress():
		return 0
	var rate := XP_PER_FOCUS_MINUTE if session.is_focus() else XP_PER_BREAK_MINUTE
	return int(floor(session.actual_focus_minutes * rate))


## Total XP needed to have reached `level`. Level 1 costs nothing.
static func cumulative_xp_for_level(level: int) -> int:
	var steps := float(maxi(1, level) - 1)
	return int(LINEAR_TERM * steps + QUADRATIC_TERM * steps * steps)


## Level for a given total XP. Closed-form inverse of the quadratic above, then
## corrected by direct comparison so floating-point error can never place the
## player on the wrong side of a threshold.
static func level_for_xp(total_xp: int) -> int:
	if total_xp <= 0:
		return 1
	var discriminant := (
		LINEAR_TERM * LINEAR_TERM + 4.0 * QUADRATIC_TERM * float(total_xp)
	)
	var steps := (-LINEAR_TERM + sqrt(discriminant)) / (2.0 * QUADRATIC_TERM)
	var level := clampi(int(floor(steps)) + 1, 1, MAX_LEVEL)

	# Correct off-by-one in either direction.
	while level < MAX_LEVEL and cumulative_xp_for_level(level + 1) <= total_xp:
		level += 1
	while level > 1 and cumulative_xp_for_level(level) > total_xp:
		level -= 1
	return level


## XP earned inside the current level, and how much that level costs in total.
## Returns [earned_in_level, level_span]. At MAX_LEVEL the span is 0 and callers
## should render a maxed-out bar rather than dividing.
static func level_progress(total_xp: int) -> Array[int]:
	var level := level_for_xp(total_xp)
	if level >= MAX_LEVEL:
		return [0, 0]
	var floor_xp := cumulative_xp_for_level(level)
	var ceil_xp := cumulative_xp_for_level(level + 1)
	return [maxi(0, total_xp - floor_xp), maxi(1, ceil_xp - floor_xp)]


## 0..1 progress through the current level, for the XP bar.
static func level_progress_ratio(total_xp: int) -> float:
	var progress := level_progress(total_xp)
	if progress[1] <= 0:
		return 1.0
	return clampf(float(progress[0]) / float(progress[1]), 0.0, 1.0)
