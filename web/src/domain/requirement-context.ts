/**
 * Read-only snapshot of progress that the evaluator measures against.
 * Port of systems/requirements/requirement_context.gd.
 *
 * Deliberately a dumb data holder with no reference to app state. That is what
 * lets every requirement type be unit-tested by filling in a few fields, with no
 * save file and no running app.
 *
 * Aggregates are precomputed by the caller once per evaluation batch rather than
 * recomputed per requirement, so evaluating thirty achievements walks the session
 * list once instead of thirty times.
 */

import { clampi, maxi } from "./gd.js";
import type { FocusSession } from "./focus-session.js";
import { countsTowardProgress, isBreak } from "./focus-session.js";
import { daysBetween } from "./time-util.js";

export interface RequirementContext {
  // --- Global scope ---
  totalFocusMinutes: number;
  completedFocusSessions: number;
  completedBreakSessions: number;
  /** Distinct local date keys with any credited focus. Sorted ascending. */
  uniqueFocusDays: string[];
  currentStreak: number;
  longestStreak: number;
  /** 24 buckets counting focus sessions by local start hour. */
  sessionsByStartHour: number[];
  /** Credited lengths of every focus session, for "complete a 90-minute session". */
  focusSessionLengths: number[];

  playerLevel: number;
  plantsMatured: number;
  speciesDiscovered: number;
  speciesTotal: number;
  unlockedAchievementIds: string[];
  completedExpeditionIds: string[];

  // --- ACTIVE_PLANT scope: the same measures, narrowed to one plant's sessions ---
  plantFocusMinutes: number;
  plantSessionCount: number;
  plantUniqueDays: string[];
  plantSessionsByStartHour: number[];
  plantSessionLengths: number[];
}

export function makeRequirementContext(
  overrides: Partial<RequirementContext> = {},
): RequirementContext {
  return {
    totalFocusMinutes: 0, completedFocusSessions: 0, completedBreakSessions: 0,
    uniqueFocusDays: [], currentStreak: 0, longestStreak: 0,
    sessionsByStartHour: new Array<number>(24).fill(0),
    focusSessionLengths: [],
    playerLevel: 1, plantsMatured: 0, speciesDiscovered: 0, speciesTotal: 0,
    unlockedAchievementIds: [], completedExpeditionIds: [],
    plantFocusMinutes: 0, plantSessionCount: 0, plantUniqueDays: [],
    plantSessionsByStartHour: new Array<number>(24).fill(0),
    plantSessionLengths: [],
    ...overrides,
  };
}

/** Builds the global aggregates from raw session records. One pass over the list. */
export function ingestSessions(context: RequirementContext, sessions: FocusSession[]): void {
  const seenDays = new Set<string>();
  for (const session of sessions) {
    if (!countsTowardProgress(session)) continue;
    if (isBreak(session)) {
      context.completedBreakSessions++;
      continue;
    }
    context.totalFocusMinutes += session.actualFocusMinutes;
    context.completedFocusSessions++;
    context.focusSessionLengths.push(session.actualFocusMinutes);
    context.sessionsByStartHour[clampi(session.startHour, 0, 23)]! += 1;
    seenDays.add(session.dateKey);
  }
  context.uniqueFocusDays = [...seenDays].sort();
}

/** Builds the ACTIVE_PLANT aggregates from the sessions that grew one plant. */
export function ingestPlantSessions(
  context: RequirementContext, sessions: FocusSession[],
): void {
  const seenDays = new Set<string>();
  for (const session of sessions) {
    if (!countsTowardProgress(session) || isBreak(session)) continue;
    context.plantFocusMinutes += session.actualFocusMinutes;
    context.plantSessionCount++;
    context.plantSessionLengths.push(session.actualFocusMinutes);
    context.plantSessionsByStartHour[clampi(session.startHour, 0, 23)]! += 1;
    seenDays.add(session.dateKey);
  }
  context.plantUniqueDays = [...seenDays].sort();
}

/**
 * Longest run of consecutive calendar days present in `uniqueFocusDays`.
 * Computed here rather than trusting the cached streak, so consecutive-day
 * requirements stay correct even if the cache is stale.
 */
export function longestConsecutiveDayRun(context: RequirementContext): number {
  const days = context.uniqueFocusDays;
  if (days.length === 0) return 0;
  let best = 1;
  let run = 1;
  for (let i = 1; i < days.length; i++) {
    if (daysBetween(days[i - 1]!, days[i]!) === 1) {
      run++;
      best = maxi(best, run);
    } else {
      run = 1;
    }
  }
  return best;
}
