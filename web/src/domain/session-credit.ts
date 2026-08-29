/**
 * How much of a measured session actually counts.
 * Port of systems/progression/session_credit.gd.
 *
 * The policy: completed sessions get full credit, manually ended sessions get the
 * time actually focused, and legitimately focused time is never silently lost.
 * This is the one place that policy is expressed.
 */

import { maxf, minf } from "./gd.js";
import type { Completion, Kind } from "./focus-session.js";
import { Completion as C, Kind as K } from "./focus-session.js";

/**
 * Final credited minutes for a finished session.
 *
 * `rawMinutes` is what the clock measured; `intendedMinutes` is the length the
 * player asked for.
 */
export function settle(
  completion: Completion, rawMinutes: number, intendedMinutes: number,
): number {
  if (completion === C.CANCELLED) return 0;

  const credited = maxf(0, rawMinutes);
  if (completion === C.COMPLETED) {
    // A completed session is worth its intended duration exactly. The raw
    // measurement overshoots by whatever fraction of a tick elapsed past the
    // finish line, which would record a "25 minute" session as 25.02.
    return minf(credited, maxf(0, intendedMinutes));
  }
  return credited;
}

/**
 * Credited minutes for a session recovered after the app closed mid-run.
 *
 * Capped at the intended duration because the app may have been shut for days,
 * and a three-day "focus session" is obviously not three days of focus. The
 * player is asked before any of this is applied.
 */
export function settleRecovered(rawMinutes: number, intendedMinutes: number): number {
  return minf(maxf(0, rawMinutes), maxf(0, intendedMinutes));
}

/**
 * Whether a session is long enough to grow a plant. Time below the threshold is
 * still recorded and still earns XP - it simply does not advance a plant.
 */
export function earnsPlantGrowth(
  kind: Kind, creditedMinutes: number, minimumMinutes: number,
): boolean {
  return kind === K.FOCUS && creditedMinutes >= maxf(0, minimumMinutes);
}
