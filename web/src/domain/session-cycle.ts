/**
 * The pomodoro cycle rules. Port of systems/progression/session_cycle.gd.
 *
 * Extracted from the timer so it can be tested without a save file or a running
 * clock - the same reason every other formula lives on its own.
 */

import { maxi } from "./gd.js";
import type { Completion, Kind } from "./focus-session.js";
import { Completion as C, Kind as K } from "./focus-session.js";

/**
 * Which break is due after `completedInCycle` focus sessions.
 *
 * The long break lands on each multiple of the cycle length. Zero completed
 * sessions is deliberately NOT a long break: `0 % 4 === 0` is true, so without
 * the guard a player's very first break would be the long one.
 */
export function nextBreakKind(completedInCycle: number, sessionsBeforeLong: number): Kind {
  const span = maxi(1, sessionsBeforeLong);
  if (completedInCycle > 0 && completedInCycle % span === 0) return K.LONG_BREAK;
  return K.SHORT_BREAK;
}

/** 1-based position in the current cycle, for a "session 3 of 4" indicator. */
export function position(completedInCycle: number, sessionsBeforeLong: number): number {
  const span = maxi(1, sessionsBeforeLong);
  return (maxi(0, completedInCycle) % span) + 1;
}

/**
 * Whether a finished session should advance the cycle counter.
 *
 * Only a focus session the player saw through counts. Counting an abandoned or
 * cancelled session would hand out a long break that was not earned, and counting
 * breaks would make the cycle meaningless.
 */
export function shouldAdvance(kind: Kind, completion: Completion): boolean {
  return kind === K.FOCUS && completion === C.COMPLETED;
}
