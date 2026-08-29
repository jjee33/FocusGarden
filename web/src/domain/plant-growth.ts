/**
 * The one authoritative plant growth implementation.
 * Port of systems/plant_growth/plant_growth_service.gd.
 *
 * Nothing else may decide what stage a plant is in - UI asks this module and
 * renders the answer.
 *
 * Stages are derived, never stored as a threshold table: a plant's progress ratio
 * comes from its species' growth requirement through the evaluator, and the stage
 * is that ratio quantized to the species' stage count. Change a species'
 * requirement and every stage boundary moves with it automatically.
 */

import { ceilToInt, clampf, clampi, floorToInt, maxf, maxi } from "./gd.js";
import type { PlantInstance } from "./plant-instance.js";
import { Maturity, isMature } from "./plant-instance.js";
import type { RequirementContext } from "./requirement-context.js";
import { evaluate } from "./requirement-evaluator.js";
import type { PlantSpecies } from "./species.js";
import { getStageCount, getDisplayFocusMinutes } from "./species.js";

/**
 * Names for the three default stages, in order. Used wherever a stage is shown to
 * the player, so "Young" never becomes "stage 2" on one screen and "half-grown"
 * on another.
 */
export const STAGE_NAMES = ["Seedling", "Young", "Mature"] as const;

/**
 * The stage at which a plant may be put on the shelf or planted out.
 *
 * One, not zero: a seed in a pot is not a thing to display, and the point of the
 * gate is that reaching it means something. With three equal stages that is a
 * third of the way - one hour for a common species.
 */
export const DISPLAY_STAGE = 1;

export interface GrowthResult {
  previousStage: number;
  newStage: number;
  progressRatio: number;
  stageChanged: boolean;
  /** True only on the transition into maturity, so "plant matured" fires once. */
  justMatured: boolean;
}

/** 0..1 progress toward maturity for a plant. */
export function progressRatio(
  plant: PlantInstance | null,
  species: PlantSpecies | null,
  context: RequirementContext,
): number {
  if (plant === null || species === null) return 0;
  if (isMature(plant)) {
    // A plant that already finished is finished, whatever the requirement says
    // today. Maturity is permanent, and a content update that retuned a species
    // upward would otherwise re-open every specimen the player already grew - and
    // visibly shrink them back down on the shelf.
    return 1.0;
  }
  // A species with no authored requirement would otherwise be instantly mature.
  // It counts as un-growable rather than silently handing the player a free plant
  // - but the floor below still applies, because a content update that drops a
  // requirement is a bug and must not retroactively un-grow a plant somebody
  // watched grow. The floor can never reach 1.0, so "un-growable" still means
  // exactly that: no maturity from nothing.
  const evaluated = species.growthRequirement === null
    ? 0
    : evaluate(species.growthRequirement, context);

  // A plant is never DRAWN below the stage it has already reached.
  //
  // The floor is the LOWER EDGE of the reached band, so it can only ever restore a
  // plant to where it already was: stageForRatio maps it straight back to the same
  // stage, and because the highest stage index is one below the count it can never
  // reach 1.0 and hand out a maturity nothing earned.
  //
  // THE CLAMP IS LOAD-BEARING. plantInstanceFromDict only floors growthStage at
  // zero, so a hand-edited or foreign save can carry stage 99 - unclamped that
  // would return 33.0, applyGrowth would see a full ratio, and every plant in the
  // file would mature on load.
  const stages = maxi(2, getStageCount(species));
  const reached = clampi(plant.growthStage, 0, stages - 1) / stages;
  return maxf(evaluated, reached);
}

/**
 * Stage index for a progress ratio, in equal bands.
 *
 * Each stage occupies the same share of the requirement, so three stages really
 * are thirds. Reaching the last band is NOT maturity - applyGrowth still sets that
 * only at a full ratio. The final third is the plant filling out and coming into
 * flower, which is the difference the player watches for.
 */
export function stageForRatio(ratio: number, stageCount: number): number {
  const stages = maxi(2, stageCount);
  return clampi(floorToInt(clampf(ratio, 0, 1) * stages), 0, stages - 1);
}

/**
 * Human-readable name for a stage index. Falls back to a numbered form for a
 * species with authored art and more stages than the default three.
 */
export function stageName(stage: number, stageCount: number): string {
  if (stageCount === STAGE_NAMES.length) {
    return STAGE_NAMES[clampi(stage, 0, STAGE_NAMES.length - 1)]!;
  }
  return `Stage ${clampi(stage, 0, maxi(1, stageCount) - 1) + 1}`;
}

/**
 * Recomputes a plant's stage and maturity and writes the result onto the instance.
 *
 * Idempotent: calling it twice with the same context produces the same stage and
 * reports stageChanged/justMatured only on the real transition. Maturity is never
 * revoked, even if a requirement is later retuned downward in a content update.
 */
export function applyGrowth(
  plant: PlantInstance | null,
  species: PlantSpecies | null,
  context: RequirementContext,
  nowUnixUtc = Date.now() / 1000,
): GrowthResult {
  const result: GrowthResult = {
    previousStage: 0, newStage: 0, progressRatio: 0, stageChanged: false, justMatured: false,
  };
  if (plant === null || species === null) return result;

  result.previousStage = plant.growthStage;
  result.progressRatio = progressRatio(plant, species, context);

  const stageCount = getStageCount(species);
  const computedStage = stageForRatio(result.progressRatio, stageCount);

  // Growth never runs backwards. A plant that reached a stage keeps it, so a
  // retuned requirement or a recovered session cannot visibly shrink a plant the
  // player already watched grow.
  result.newStage = maxi(plant.growthStage, computedStage);
  result.stageChanged = result.newStage !== result.previousStage;
  plant.growthStage = result.newStage;

  if (!isMature(plant) && result.progressRatio >= 1.0) {
    plant.maturity = Maturity.MATURE;
    plant.maturedAtUtc = nowUnixUtc;
    result.justMatured = true;
  }

  return result;
}

/**
 * Sessions still needed at the player's usual session length.
 * Returns -1 when the requirement is not minute-shaped, because implying a
 * precision we do not have is worse than saying nothing - "5 separate days" has no
 * honest session estimate.
 */
export function estimatedSessionsRemaining(
  plant: PlantInstance | null,
  species: PlantSpecies | null,
  typicalSessionMinutes: number,
): number {
  if (plant === null || species === null || typicalSessionMinutes <= 0) return -1;
  const required = getDisplayFocusMinutes(species);
  if (required < 0) return -1;
  const remaining = required - plant.accumulatedFocusMinutes;
  if (remaining <= 0) return 0;
  return ceilToInt(remaining / typicalSessionMinutes);
}
