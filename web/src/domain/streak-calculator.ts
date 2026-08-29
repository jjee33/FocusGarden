/**
 * The one authoritative streak calculation.
 * Port of systems/analytics/streak_calculator.gd.
 *
 * A missed day resets a number and nothing else: no plants die, no XP is removed,
 * no garden is damaged, and the player is never shamed. Accordingly this module
 * only ever RETURNS values. It has no ability to modify anything, which makes the
 * "never punish" rule structural rather than a convention someone could break.
 *
 * TODAY IS NOT COUNTED AS A MISS. A streak stays alive while the most recent
 * qualifying day is today OR yesterday, because a day the player has not finished
 * yet is not a day they skipped. Without this, opening the app at 9am would show a
 * broken streak every single morning - precisely the anxiety mechanic the design
 * rules out.
 */

import { maxi } from "./gd.js";
import type { FocusSession } from "./focus-session.js";
import { countsTowardProgress, isFocus } from "./focus-session.js";
import { daysBetween, todayKey } from "./time-util.js";

export interface StreakResult {
  current: number;
  longest: number;
  qualifyingDays: string[];
  lastQualifyingDay: string;
}

/**
 * Credited focus minutes per local date key. Breaks do not count toward a focus
 * streak.
 */
export function minutesByDay(sessions: FocusSession[]): Map<string, number> {
  const totals = new Map<string, number>();
  for (const session of sessions) {
    if (!countsTowardProgress(session) || !isFocus(session)) continue;
    if (session.dateKey === "") continue;
    totals.set(session.dateKey, (totals.get(session.dateKey) ?? 0) + session.actualFocusMinutes);
  }
  return totals;
}

/**
 * Computes both streaks. `todayKeyOverride` is injectable so tests can pin "today"
 * instead of depending on when the suite happens to run.
 */
export function calculate(
  sessions: FocusSession[],
  thresholdMinutes: number,
  todayKeyOverride = "",
): StreakResult {
  const result: StreakResult = {
    current: 0, longest: 0, qualifyingDays: [], lastQualifyingDay: "",
  };
  const today = todayKeyOverride !== "" ? todayKeyOverride : todayKey();
  const totals = minutesByDay(sessions);

  const days: string[] = [];
  for (const [day, minutes] of totals) {
    if (minutes >= thresholdMinutes) days.push(day);
  }
  days.sort();
  result.qualifyingDays = [...days];

  if (days.length === 0) return result;

  result.lastQualifyingDay = days[days.length - 1]!;

  // Longest run of consecutive calendar days.
  let run = 1;
  result.longest = 1;
  for (let i = 1; i < days.length; i++) {
    if (daysBetween(days[i - 1]!, days[i]!) === 1) {
      run++;
      result.longest = maxi(result.longest, run);
    } else {
      run = 1;
    }
  }

  // Current streak: walk backwards from the most recent qualifying day, but only
  // if that day is today or yesterday.
  const gapToToday = daysBetween(result.lastQualifyingDay, today);
  if (gapToToday > 1) {
    result.current = 0;
    return result;
  }

  result.current = 1;
  for (let i = days.length - 1; i > 0; i--) {
    if (daysBetween(days[i - 1]!, days[i]!) === 1) {
      result.current++;
    } else {
      break;
    }
  }
  return result;
}
