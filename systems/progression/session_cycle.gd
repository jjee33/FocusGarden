class_name SessionCycle
extends RefCounted
## The pomodoro cycle rules (§8: "sessions before long break").
##
## Extracted from TimerManager so it can be tested without autoloads, a save
## file, or a scene tree — the same reason every other formula lives in systems/.
## TimerManager supplies the numbers and renders the answer.

## Which break is due after `completed_in_cycle` focus sessions.
##
## The long break lands on each multiple of the cycle length. Zero completed
## sessions is deliberately NOT a long break: `0 % 4 == 0` is true, so without
## the guard a player's very first break would be the long one.
static func next_break_kind(completed_in_cycle: int, sessions_before_long: int) -> FocusSession.Kind:
	var span := maxi(1, sessions_before_long)
	if completed_in_cycle > 0 and completed_in_cycle % span == 0:
		return FocusSession.Kind.LONG_BREAK
	return FocusSession.Kind.SHORT_BREAK


## 1-based position in the current cycle, for a "session 3 of 4" indicator.
static func position(completed_in_cycle: int, sessions_before_long: int) -> int:
	var span := maxi(1, sessions_before_long)
	return (maxi(0, completed_in_cycle) % span) + 1


## Whether a finished session should advance the cycle counter.
##
## Only a focus session the player saw through counts. Counting an abandoned or
## cancelled session would hand out a long break that was not earned, and
## counting breaks would make the cycle meaningless.
static func should_advance(kind: FocusSession.Kind, completion: FocusSession.Completion) -> bool:
	return kind == FocusSession.Kind.FOCUS and completion == FocusSession.Completion.COMPLETED
