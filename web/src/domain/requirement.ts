/**
 * One condition, evaluated by one engine. Port of models/requirement.gd.
 *
 * Plant unlocks, achievements, expeditions, garden upgrades and cosmetic unlocks
 * must NOT each grow their own condition engine. They all use this type, and the
 * evaluator is the only thing that interprets it.
 *
 * Requirements return a RATIO, not just a boolean. Plant growth needs a continuous
 * 0..1 progress value to pick a growth stage and drive a progress bar, and
 * achievements need the same number for "7 of 10 plants matured". One evaluation
 * path serves both, so a plant's maturity rule and an achievement's unlock rule
 * are literally the same kind of object.
 *
 * TYPES ARE STRINGS HERE, unlike the save-file enums in focus-session.ts. Content
 * is regenerated from source on every build, so there is no wire-compat reason to
 * carry ordinals into TypeScript - and a reordered enum would silently repoint
 * every requirement in the catalogue if we did. The ordinal tables below exist
 * only to read the GDScript fixtures, which record the enum's integer value.
 */

/** Declaration order IS the GDScript enum order. Do not reorder. */
export const REQUIREMENT_TYPES = [
  "total_focus_minutes",
  "completed_sessions",
  "unique_focus_days",
  "consecutive_days",
  "sessions_in_time_window",
  "session_length_at_least",
  "break_sessions",
  "plants_matured",
  "species_discovered",
  "player_level",
  "catalogue_completion",
  "achievement_unlocked",
  "expedition_completed",
] as const;
export type RequirementType = (typeof REQUIREMENT_TYPES)[number];

/**
 * Whether the requirement measures the whole profile or just one plant's own
 * contributing sessions. A Monstera needing 250 minutes means 250 minutes grown
 * into THAT plant, while "Century Garden" means 100 hours across everything.
 */
export const REQUIREMENT_SCOPES = ["global", "active_plant"] as const;
export type RequirementScope = (typeof REQUIREMENT_SCOPES)[number];

export interface Requirement {
  type: RequirementType;
  scope: RequirementScope;
  params: Record<string, unknown>;
  /** Optional author-written text. When empty, the evaluator generates a description. */
  descriptionOverride: string;
}

export function makeRequirement(
  type: RequirementType,
  params: Record<string, unknown> = {},
  scope: RequirementScope = "global",
  descriptionOverride = "",
): Requirement {
  return { type, scope, params, descriptionOverride };
}

/** Out-of-range ordinals fall back the way the GDScript `from_dict` does. */
export function requirementTypeFromOrdinal(value: number): RequirementType {
  return REQUIREMENT_TYPES[value] ?? "total_focus_minutes";
}

export function requirementScopeFromOrdinal(value: number): RequirementScope {
  return REQUIREMENT_SCOPES[value] ?? "global";
}

export function requirementTypeOrdinal(type: RequirementType): number {
  return REQUIREMENT_TYPES.indexOf(type);
}
