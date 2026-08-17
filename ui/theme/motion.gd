class_name Motion
extends RefCounted
## Animation timing policy: reduced motion and animation intensity (§43, §50).
##
## Split out from DesignTokens so tokens stay a pure constants table with no
## dependency on player state. This class is the one place that knows the
## accessibility settings exist, so honouring them is automatic rather than
## something each animation has to remember.
##
## Every tween in the game should get its duration from here:
##     tween.tween_property(node, "modulate:a", 1.0, Motion.duration(DesignTokens.DURATION_FAST))

## Below this, a tween is treated as instant. Godot tweens with a zero duration
## still apply their final value, which is exactly the behaviour reduced motion
## needs — the animation is skipped but the END STATE STILL APPLIES, so nothing
## is left half-faded or invisible (§50).
const INSTANT_EPSILON: float = 0.001


## Multiplier for every animation duration: 0 when reduced motion is on,
## otherwise the player's animation-intensity setting.
static func scale() -> float:
	# Before the save loads there are no settings to consult. Full motion is the
	# safe default: the alternative would freeze the startup transition for
	# everyone, including players who never asked for reduced motion.
	if not AppState.is_loaded:
		return 1.0
	var settings := AppState.get_settings()
	if settings.reduced_motion:
		return 0.0
	return clampf(settings.animation_intensity, 0.0, 1.0)


static func duration(base_seconds: float) -> float:
	return base_seconds * scale()


## True when animations should be skipped entirely. Use for effects that cannot
## simply be shortened — looping idle sway, drifting particles, parallax — which
## must be switched OFF rather than sped up.
static func is_reduced() -> bool:
	return scale() <= INSTANT_EPSILON


## Creates a tween already configured for the player's motion settings.
## Returns a tween whose durations the caller still scales via `duration()`.
static func create_tween_for(node: Node) -> Tween:
	var tween := node.create_tween()
	tween.set_ease(Tween.EASE_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)
	return tween
