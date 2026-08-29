/**
 * Surviving an interrupted session. Port of TimerManager's in-flight handling.
 *
 * On the desktop the interruption is a crash or a kill. In a browser it is far
 * more ordinary: a closed tab, a reload, a phone deciding to reclaim memory from
 * a backgrounded page. So this matters MORE here, not less - without it, closing
 * the tab twenty minutes into a session silently throws that time away, which is
 * precisely the outcome "never silently lose time the user legitimately focused"
 * rules out.
 *
 * THE RECOVERED SESSION IS NOT APPLIED. Only the player knows whether they were
 * actually focusing while the tab was shut, so this returns the record and the
 * UI asks. `settleRecovered` caps it at the intended duration, because the tab
 * may have been closed for days and a three-day "focus session" is obviously not
 * three days of focus.
 *
 * The stored shape is the desktop's, unchanged: { session, clock }.
 */

import type { Json } from "./dict-util.js";
import { getDict } from "./dict-util.js";
import type { FocusSession } from "./focus-session.js";
import { Completion, focusSessionFromDict, focusSessionToDict } from "./focus-session.js";
import type { TimeProviders } from "./game-clock.js";
import { GameClock } from "./game-clock.js";
import { settleRecovered } from "./session-credit.js";
import { SECONDS_PER_MINUTE } from "./time-util.js";

export const INTERRUPTION_REASON = "The tab was closed during the session.";

/**
 * Serialises a running session so it survives an unexpected exit.
 *
 * Written on every STATE CHANGE, not every tick: a tick-rate write would hammer
 * storage for hours. In a browser it is also written on `pagehide`, which is the
 * last reliable moment before a tab goes away.
 */
export function buildInFlight(session: FocusSession, clock: GameClock): Json {
  return { session: focusSessionToDict(session), clock: clock.toDict() };
}

/**
 * Restores a session interrupted by the tab closing, or null when there is
 * nothing to recover.
 *
 * Returns it WITHOUT applying it. The caller asks the player first.
 */
export function recoverInFlight(
  stored: Json,
  nowUnixUtc = Date.now() / 1000,
  providers: Partial<TimeProviders> = {},
): FocusSession | null {
  if (Object.keys(stored).length === 0) return null;

  const session = focusSessionFromDict(getDict(stored, "session"));
  // An id-less record cannot be de-duplicated or credited to a plant, and one
  // already applied must never be offered a second time.
  if (session.id === "" || session.awardsApplied) return null;

  const clock = GameClock.fromDict(getDict(stored, "clock"), providers);
  const sample = clock.sample();

  session.completion = Completion.ABANDONED;
  session.endedAtUtc = nowUnixUtc;
  session.pausedMinutes = sample.pausedSeconds / SECONDS_PER_MINUTE;
  session.actualFocusMinutes = settleRecovered(
    sample.creditedSeconds / SECONDS_PER_MINUTE,
    session.intendedDurationMinutes,
  );
  session.anomaly = sample.anomaly;
  session.interruptionReason = INTERRUPTION_REASON;
  return session;
}

/** True when there is a session worth offering back. */
export function hasInFlight(stored: Json): boolean {
  if (Object.keys(stored).length === 0) return false;
  const session = getDict(stored, "session");
  return typeof session["id"] === "string" && session["id"] !== "";
}
