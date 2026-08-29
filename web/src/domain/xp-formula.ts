/**
 * The one authoritative XP and level calculation. Port of systems/progression/xp_formula.gd.
 *
 * Everything that needs a level asks here; nothing else may derive one.
 *
 * Levels never change the effectiveness of focus time, so XP per minute is a flat
 * constant. There is no multiplier, no bonus tier, and no way for progression to
 * make a later minute worth more than an early one - that would quietly turn a
 * productivity tool into a grind.
 */

import { clampi, floorToInt, maxi, toInt } from "./gd.js";
import type { FocusSession } from "./focus-session.js";
import { countsTowardProgress, isFocus } from "./focus-session.js";

export const XP_PER_FOCUS_MINUTE = 2.0;
/** Breaks earn a token amount: resting is rewarded, but must not compete with focusing. */
export const XP_PER_BREAK_MINUTE = 0.25;

/**
 * Cumulative XP for level L is: LINEAR*(L-1) + QUADRATIC*(L-1)^2
 * Quadratic so early levels arrive quickly and later ones represent real
 * investment, without ever becoming unreachable.
 */
export const LINEAR_TERM = 50.0;
export const QUADRATIC_TERM = 25.0;
export const MAX_LEVEL = 100;

/** XP awarded for a session. The single place session XP is decided. */
export function xpForSession(session: FocusSession): number {
  if (!countsTowardProgress(session)) return 0;
  const rate = isFocus(session) ? XP_PER_FOCUS_MINUTE : XP_PER_BREAK_MINUTE;
  return floorToInt(session.actualFocusMinutes * rate);
}

/** Total XP needed to have reached `level`. Level 1 costs nothing. */
export function cumulativeXpForLevel(level: number): number {
  const steps = maxi(1, level) - 1;
  return toInt(LINEAR_TERM * steps + QUADRATIC_TERM * steps * steps);
}

/**
 * Level for a given total XP. Closed-form inverse of the quadratic above, then
 * corrected by direct comparison so floating-point error can never place the
 * player on the wrong side of a threshold.
 */
export function levelForXp(totalXp: number): number {
  if (totalXp <= 0) return 1;
  const discriminant = LINEAR_TERM * LINEAR_TERM + 4.0 * QUADRATIC_TERM * totalXp;
  const steps = (-LINEAR_TERM + Math.sqrt(discriminant)) / (2.0 * QUADRATIC_TERM);
  let level = clampi(floorToInt(steps) + 1, 1, MAX_LEVEL);

  // Correct off-by-one in either direction.
  while (level < MAX_LEVEL && cumulativeXpForLevel(level + 1) <= totalXp) level++;
  while (level > 1 && cumulativeXpForLevel(level) > totalXp) level--;
  return level;
}

export interface LevelProgress {
  earnedInLevel: number;
  levelSpan: number;
}

/**
 * XP earned inside the current level, and how much that level costs in total.
 * At MAX_LEVEL the span is 0 and callers should render a maxed-out bar rather
 * than dividing.
 */
export function levelProgress(totalXp: number): LevelProgress {
  const level = levelForXp(totalXp);
  if (level >= MAX_LEVEL) return { earnedInLevel: 0, levelSpan: 0 };
  const floorXp = cumulativeXpForLevel(level);
  const ceilXp = cumulativeXpForLevel(level + 1);
  return {
    earnedInLevel: maxi(0, totalXp - floorXp),
    levelSpan: maxi(1, ceilXp - floorXp),
  };
}

/** 0..1 progress through the current level, for the XP bar. */
export function levelProgressRatio(totalXp: number): number {
  const { earnedInLevel, levelSpan } = levelProgress(totalXp);
  if (levelSpan <= 0) return 1.0;
  const ratio = earnedInLevel / levelSpan;
  return ratio < 0 ? 0 : ratio > 1 ? 1 : ratio;
}
