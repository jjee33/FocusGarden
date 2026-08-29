/**
 * The ONE condition engine. Port of systems/requirements/requirement_evaluator.gd.
 *
 * Plant unlocks, achievements, expeditions, garden upgrades and cosmetic unlocks
 * do not each grow their own evaluator. They all call `evaluate()` here with a
 * Requirement and a RequirementContext.
 *
 * Every requirement returns a 0..1 RATIO rather than a boolean. That single choice
 * is what lets one engine serve both "is this unlocked yet" and "how full is this
 * progress bar", and it is what drives plant growth stages: a plant's stage is its
 * maturity requirement's ratio quantized to the species' stage count, so growth
 * thresholds are never duplicated anywhere.
 */

import { clampf, clampi, gdRound, toInt } from "./gd.js";
import type { Json } from "./dict-util.js";
import { getFloat, getInt, getString } from "./dict-util.js";
import type { Requirement } from "./requirement.js";
import type { RequirementContext } from "./requirement-context.js";
import { longestConsecutiveDayRun } from "./requirement-context.js";
import { formatDuration } from "./time-util.js";

/**
 * 0..1 progress toward the requirement. Never returns NaN or a value outside the
 * range, because callers feed it straight into progress bars and stage indices.
 */
export function evaluate(
  requirement: Requirement | null, context: RequirementContext | null,
): number {
  if (requirement === null || context === null) return 0;
  const params = requirement.params as Json;
  const plantScoped = requirement.scope === "active_plant";

  switch (requirement.type) {
    case "total_focus_minutes": {
      const target = getFloat(params, "amount", 1.0);
      const actual = plantScoped ? context.plantFocusMinutes : context.totalFocusMinutes;
      return ratio(actual, target);
    }
    case "completed_sessions": {
      const target = getInt(params, "count", 1);
      const actual = plantScoped ? context.plantSessionCount : context.completedFocusSessions;
      return ratio(actual, target);
    }
    case "unique_focus_days": {
      const target = getInt(params, "count", 1);
      const days = plantScoped ? context.plantUniqueDays : context.uniqueFocusDays;
      return ratio(days.length, target);
    }
    case "consecutive_days": {
      const target = getInt(params, "count", 1);
      return ratio(longestConsecutiveDayRun(context), target);
    }
    case "sessions_in_time_window": {
      const target = getInt(params, "count", 1);
      const startHour = clampi(getInt(params, "start_hour", 0), 0, 23);
      const endHour = clampi(getInt(params, "end_hour", 23), 0, 23);
      const histogram = plantScoped
        ? context.plantSessionsByStartHour
        : context.sessionsByStartHour;
      return ratio(countInHourWindow(histogram, startHour, endHour), target);
    }
    case "session_length_at_least": {
      const minutes = getFloat(params, "minutes", 1.0);
      const target = getInt(params, "count", 1);
      const lengths = plantScoped ? context.plantSessionLengths : context.focusSessionLengths;
      let qualifying = 0;
      for (const length of lengths) if (length >= minutes) qualifying++;
      return ratio(qualifying, target);
    }
    case "break_sessions":
      return ratio(context.completedBreakSessions, getInt(params, "count", 1));
    case "plants_matured":
      return ratio(context.plantsMatured, getInt(params, "count", 1));
    case "species_discovered":
      return ratio(context.speciesDiscovered, getInt(params, "count", 1));
    case "player_level":
      return ratio(context.playerLevel, getInt(params, "level", 1));
    case "catalogue_completion": {
      const target = getFloat(params, "ratio", 1.0);
      if (context.speciesTotal <= 0) return 0;
      return ratio(context.speciesDiscovered / context.speciesTotal, target);
    }
    case "achievement_unlocked":
      return context.unlockedAchievementIds.includes(getString(params, "achievement_id")) ? 1 : 0;
    case "expedition_completed":
      return context.completedExpeditionIds.includes(getString(params, "expedition_id")) ? 1 : 0;
  }
  return 0;
}

export function isMet(
  requirement: Requirement | null, context: RequirementContext | null,
): boolean {
  return evaluate(requirement, context) >= 1.0;
}

/**
 * All requirements must pass. An empty list is met - a species with no unlock
 * requirement is available from the start, which is the sane default.
 */
export function allMet(requirements: Requirement[], context: RequirementContext): boolean {
  return requirements.every((r) => isMet(r, context));
}

/**
 * Human-readable text for catalogue and achievement cards. Authors can override
 * per requirement; this generates sensible copy for everything else so no
 * requirement ever renders as blank.
 */
export function describe(requirement: Requirement | null): string {
  if (requirement === null) return "";
  if (requirement.descriptionOverride !== "") return requirement.descriptionOverride;

  const params = requirement.params as Json;
  switch (requirement.type) {
    case "total_focus_minutes":
      return `Focus for ${formatDuration(getFloat(params, "amount", 0))}`;
    case "completed_sessions":
      return `Complete ${getInt(params, "count", 1)} focus sessions`;
    case "unique_focus_days":
      return `Focus on ${getInt(params, "count", 1)} separate days`;
    case "consecutive_days":
      return `Focus ${getInt(params, "count", 1)} days in a row`;
    case "sessions_in_time_window":
      return `Complete ${getInt(params, "count", 1)} sessions between `
        + `${formatHour(getInt(params, "start_hour", 0))} and `
        + `${formatHour(getInt(params, "end_hour", 23))}`;
    case "session_length_at_least":
      return `Complete ${getInt(params, "count", 1)} sessions of at least `
        + `${formatDuration(getFloat(params, "minutes", 0))}`;
    case "break_sessions":
      return `Take ${getInt(params, "count", 1)} breaks`;
    case "plants_matured":
      return `Grow ${getInt(params, "count", 1)} plants to maturity`;
    case "species_discovered":
      return `Discover ${getInt(params, "count", 1)} species`;
    case "player_level":
      return `Reach level ${getInt(params, "level", 1)}`;
    case "catalogue_completion":
      return `Complete ${toInt(gdRound(getFloat(params, "ratio", 1.0) * 100))}% of the catalogue`;
    case "achievement_unlocked":
      return "Unlock a required achievement";
    case "expedition_completed":
      return "Complete a required expedition";
  }
  return "";
}

function ratio(actual: number, target: number): number {
  // A zero or negative target is already satisfied. Returning 0/0 here would
  // produce NaN and poison every progress bar downstream.
  if (target <= 0) return 1.0;
  return clampf(actual / target, 0, 1);
}

/**
 * Counts a start..end hour window inclusive. Windows are allowed to wrap past
 * midnight (e.g. 20:00-02:00 for evening plants), which a naive range would miss.
 */
function countInHourWindow(histogram: number[], startHour: number, endHour: number): number {
  let total = 0;
  if (startHour <= endHour) {
    for (let hour = startHour; hour <= endHour; hour++) total += histogram[hour] ?? 0;
  } else {
    for (let hour = startHour; hour < 24; hour++) total += histogram[hour] ?? 0;
    for (let hour = 0; hour <= endHour; hour++) total += histogram[hour] ?? 0;
  }
  return total;
}

function formatHour(hour: number): string {
  const clamped = clampi(hour, 0, 23);
  if (clamped === 0) return "12 AM";
  if (clamped < 12) return `${clamped} AM`;
  if (clamped === 12) return "12 PM";
  return `${clamped - 12} PM`;
}
