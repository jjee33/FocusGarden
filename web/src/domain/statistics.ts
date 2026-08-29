/**
 * Session aggregation and analytics. Port of autoload/statistics_manager.gd.
 *
 * Reads and summarises. It must never mutate a session, a plant, or the profile.
 *
 * EVERYTHING HERE IS DERIVED. The full session history exists precisely so that
 * no total is ever authoritative on its own - if a cached figure and the session
 * rows disagree, the rows win and the cache is rebuilt. That is what makes
 * "totals match the underlying session records" verifiable rather than
 * aspirational.
 *
 * The GDScript version is a stateful autoload with a dirty flag, because it lives
 * next to mutable global state. Here it is a set of pure functions over the
 * arrays it is handed: the caller (a React store, later an IndexedDB-backed one)
 * owns memoisation, which is a thing React is already good at and this module has
 * no business duplicating.
 */

import { maxf } from "./gd.js";
import type { FocusSession } from "./focus-session.js";
import { countsTowardProgress, isBreak, isFocus } from "./focus-session.js";
import type { PlantInstance } from "./plant-instance.js";
import { isMature } from "./plant-instance.js";
import type { CatalogueEntry } from "./catalogue-entry.js";
import type { AchievementState } from "./achievement-state.js";
import type { RequirementContext } from "./requirement-context.js";
import {
  ingestPlantSessions, ingestSessions, makeRequirementContext,
} from "./requirement-context.js";
import { calculate, minutesByDay } from "./streak-calculator.js";
import { levelForXp } from "./xp-formula.js";
import { daysBetween, shiftDateKey, todayKey } from "./time-util.js";
import type { Json } from "./dict-util.js";
import { getBool } from "./dict-util.js";

export interface StatisticsSummary {
  focusToday: number;
  focusWeek: number;
  focusMonth: number;
  focusYear: number;
  focusLifetime: number;
  sessionCount: number;
  breakCount: number;
  averageSessionMinutes: number;
  longestSessionMinutes: number;
  daysFocused: number;
  currentStreak: number;
  longestStreak: number;
  plantsMatured: number;
  speciesDiscovered: number;
  totalXp: number;
}

export interface StatisticsInput {
  sessions: readonly FocusSession[];
  plants: readonly PlantInstance[];
  catalogue: readonly CatalogueEntry[];
  totalXp: number;
  streakThresholdMinutes: number;
  /** Injectable so a summary can be pinned in tests instead of drifting daily. */
  today?: string;
}

export function buildSummary(input: StatisticsInput): StatisticsSummary {
  const today = input.today ?? todayKey();
  const weekStart = shiftDateKey(today, -6);
  const monthStart = shiftDateKey(today, -29);
  const yearStart = shiftDateKey(today, -364);

  const summary: StatisticsSummary = {
    focusToday: 0, focusWeek: 0, focusMonth: 0, focusYear: 0, focusLifetime: 0,
    sessionCount: 0, breakCount: 0, averageSessionMinutes: 0, longestSessionMinutes: 0,
    daysFocused: 0, currentStreak: 0, longestStreak: 0,
    plantsMatured: 0, speciesDiscovered: 0, totalXp: input.totalXp,
  };

  let focusTotal = 0;
  for (const session of input.sessions) {
    if (!countsTowardProgress(session)) continue;
    if (isBreak(session)) {
      summary.breakCount += 1;
      continue;
    }
    const minutes = session.actualFocusMinutes;
    summary.sessionCount += 1;
    focusTotal += minutes;
    summary.longestSessionMinutes = maxf(summary.longestSessionMinutes, minutes);

    if (session.dateKey === today) summary.focusToday += minutes;
    // daysBetween returns 0 for an unparseable key, which would wrongly include a
    // damaged record in every window. The stored key is validated on load, so by
    // the time a session reaches here its key either parses or was rebuilt.
    if (daysBetween(weekStart, session.dateKey) >= 0) summary.focusWeek += minutes;
    if (daysBetween(monthStart, session.dateKey) >= 0) summary.focusMonth += minutes;
    if (daysBetween(yearStart, session.dateKey) >= 0) summary.focusYear += minutes;
  }

  summary.focusLifetime = focusTotal;
  if (summary.sessionCount > 0) {
    summary.averageSessionMinutes = focusTotal / summary.sessionCount;
  }

  const streak = calculate(input.sessions as FocusSession[], input.streakThresholdMinutes, today);
  summary.currentStreak = streak.current;
  summary.longestStreak = streak.longest;
  summary.daysFocused = minutesByDay(input.sessions as FocusSession[]).size;

  for (const plant of input.plants) if (isMature(plant)) summary.plantsMatured += 1;
  for (const entry of input.catalogue) if (entry.discovered) summary.speciesDiscovered += 1;

  return summary;
}

/** Credited focus minutes on one local date. */
export function focusMinutesForDay(
  sessions: readonly FocusSession[], dateKey: string,
): number {
  let total = 0;
  for (const session of sessions) {
    if (session.dateKey === dateKey && countsTowardProgress(session) && isFocus(session)) {
      total += session.actualFocusMinutes;
    }
  }
  return total;
}

/**
 * Focus minutes per day, for the calendar heatmap. Days with no focus are
 * OMITTED, so a full year stays a small map rather than 365 zero entries.
 */
export function dailyTotals(sessions: readonly FocusSession[]): Map<string, number> {
  return minutesByDay(sessions as FocusSession[]);
}

/** Credited focus minutes grouped by project id. */
export function totalsByProject(sessions: readonly FocusSession[]): Map<string, number> {
  const totals = new Map<string, number>();
  for (const session of sessions) {
    if (!countsTowardProgress(session) || !isFocus(session)) continue;
    totals.set(session.projectId, (totals.get(session.projectId) ?? 0) + session.actualFocusMinutes);
  }
  return totals;
}

/**
 * A context covering ONE plant only, for evaluating that plant's growth.
 *
 * `buildContext` aggregates every session in the save and recomputes the streak,
 * which walks the whole history and parses date strings. Plant growth needs none
 * of that: a species' growth requirement is plant-scoped by construction.
 *
 * This is not a micro-optimisation. Growth is evaluated on every session
 * completion, and the full context is O(all sessions); using it here would make
 * progression cost grow with the size of someone's history for no reason.
 */
export function buildPlantContext(plantSessions: readonly FocusSession[]): RequirementContext {
  const context = makeRequirementContext();
  ingestPlantSessions(context, plantSessions as FocusSession[]);
  return context;
}

export interface ContextInput extends StatisticsInput {
  achievements: readonly AchievementState[];
  expeditions: Json;
  speciesTotal: number;
  /** Sessions belonging to the plant being grown, if any. */
  plantSessions?: readonly FocusSession[];
}

/**
 * The snapshot the requirement evaluator measures against.
 *
 * This is the seam between "what the player has done" and "what conditions are
 * satisfied". Supplying `plantSessions` additionally fills the plant scope, so a
 * species' growth requirement and a global achievement can be evaluated against
 * the same object in one pass.
 */
export function buildContext(input: ContextInput): RequirementContext {
  const context = makeRequirementContext();
  ingestSessions(context, input.sessions as FocusSession[]);
  if (input.plantSessions !== undefined) {
    ingestPlantSessions(context, input.plantSessions as FocusSession[]);
  }

  const today = input.today ?? todayKey();
  const streak = calculate(input.sessions as FocusSession[], input.streakThresholdMinutes, today);
  context.currentStreak = streak.current;
  context.longestStreak = streak.longest;

  context.playerLevel = levelForXp(input.totalXp);
  context.speciesTotal = input.speciesTotal;

  for (const plant of input.plants) if (isMature(plant)) context.plantsMatured += 1;
  for (const entry of input.catalogue) if (entry.discovered) context.speciesDiscovered += 1;
  for (const state of input.achievements) {
    if (state.unlocked) context.unlockedAchievementIds.push(state.achievementId);
  }
  for (const [expeditionId, progress] of Object.entries(input.expeditions)) {
    if (typeof progress === "object" && progress !== null && !Array.isArray(progress)) {
      if (getBool(progress as Json, "completed")) context.completedExpeditionIds.push(expeditionId);
    }
  }
  return context;
}
