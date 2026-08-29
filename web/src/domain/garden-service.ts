/**
 * The authoritative garden expansion logic.
 * Port of systems/garden/garden_service.gd.
 *
 * Expansion unlocks must be DETERMINISTIC, and that is achieved by making this a
 * CONVERGENCE PASS rather than an event handler: `reconcile` recomputes which
 * expansions are earned and grants any that are missing. Running it twice changes
 * nothing, running it after a content update picks up new steps, and it cannot
 * double-grant because the layout refuses an id it already holds.
 *
 * The plot never shrinks. Grid size is the largest earned size, so retuning a
 * threshold downward in a future version cannot take ground away from someone who
 * already had it - and cannot strand a plant outside the new bounds.
 *
 * Content is passed IN rather than read from a global, exactly as the requirement
 * evaluator takes a context. That keeps this a pure function of its arguments.
 */

import { maxi } from "./gd.js";
import type { GardenLayout } from "./garden-layout.js";
import { grantExpansion, hasExpansion, isCellInBounds } from "./garden-layout.js";
import type { PlantInstance } from "./plant-instance.js";
import { Location } from "./plant-instance.js";
import type { RequirementContext } from "./requirement-context.js";
import { evaluate, isMet } from "./requirement-evaluator.js";
import type { DecorationDef, GardenExpansion } from "../content/content.js";

export interface ReconcileResult {
  newlyUnlocked: GardenExpansion[];
  gridWidth: number;
  gridHeight: number;
}

/**
 * Grants every earned expansion. Returns what changed, so the caller can
 * celebrate exactly the new ones and nothing else.
 */
export function reconcile(
  layout: GardenLayout,
  context: RequirementContext,
  expansions: readonly GardenExpansion[],
): ReconcileResult {
  const result: ReconcileResult = {
    newlyUnlocked: [],
    gridWidth: layout.gridWidth,
    gridHeight: layout.gridHeight,
  };

  let width = layout.gridWidth;
  let height = layout.gridHeight;
  for (const expansion of expansions) {
    if (!isMet(expansion.requirement, context)) continue;
    if (grantExpansion(layout, expansion.id)) result.newlyUnlocked.push(expansion);
    // Applied whether or not it was newly granted, so a save that recorded the id
    // but not the size still converges to the right plot.
    width = maxi(width, expansion.gridWidth);
    height = maxi(height, expansion.gridHeight);
  }

  layout.gridWidth = width;
  layout.gridHeight = height;
  result.gridWidth = width;
  result.gridHeight = height;
  return result;
}

/** The next expansion not yet earned, or null when all are unlocked. */
export function nextExpansion(
  layout: GardenLayout,
  context: RequirementContext,
  expansions: readonly GardenExpansion[],
): GardenExpansion | null {
  for (const expansion of expansions) {
    if (hasExpansion(layout, expansion.id)) continue;
    if (!isMet(expansion.requirement, context)) return expansion;
  }
  return null;
}

/** 0..1 progress toward the next expansion, for the progress bar. */
export function nextExpansionProgress(
  layout: GardenLayout,
  context: RequirementContext,
  expansions: readonly GardenExpansion[],
): number {
  const next = nextExpansion(layout, context, expansions);
  if (next === null) return 1;
  return evaluate(next.requirement, context);
}

/** Decorations the player may place, given which expansions they hold. */
export function availableDecorations(
  layout: GardenLayout,
  decorations: readonly DecorationDef[],
): DecorationDef[] {
  return decorations.filter(
    (d) => d.unlockExpansionId === "" || hasExpansion(layout, d.unlockExpansionId),
  );
}

/**
 * Plants whose saved cell now falls outside the plot. Should always be empty,
 * since the plot only ever grows - but a hand-edited save could contain one, and
 * the case must be defined rather than left to corrupt the view.
 */
export function findOutOfBounds(
  layout: GardenLayout,
  plants: readonly PlantInstance[],
): PlantInstance[] {
  return plants.filter(
    (p) => p.location === Location.GARDEN && !isCellInBounds(layout, p.gardenCellX, p.gardenCellY),
  );
}
