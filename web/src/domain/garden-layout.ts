/**
 * The expandable garden. Port of models/garden_layout.gd.
 *
 * As with the shelf, plant placement lives on PlantInstance, not here. This holds
 * the plot size, which expansions have been unlocked, and where decorations sit.
 *
 * Expansions are recorded BY ID rather than by a plot size number, so
 * re-evaluating the cumulative-focus milestones can only ever add ids that are
 * already there - it can never double-grant.
 */

import { clampi, posmod } from "./gd.js";
import type { Json } from "./dict-util.js";
import { getDict, getInt, getString, getStringArray } from "./dict-util.js";

/** Quarter turns an ornament can take. */
export const ROTATIONS = 4;

export interface DecorationPlacement {
  id: string;
  rotation: number;
}

export interface GardenLayout {
  environmentId: string;
  gridWidth: number;
  gridHeight: number;
  unlockedExpansionIds: string[];
  /** Keyed by "x,y" - JSON object keys cannot be a coordinate pair. */
  decorations: Record<string, DecorationPlacement>;
}

export function makeGardenLayout(overrides: Partial<GardenLayout> = {}): GardenLayout {
  return {
    environmentId: "cottage_garden", gridWidth: 4, gridHeight: 3,
    unlockedExpansionIds: [], decorations: {},
    ...overrides,
  };
}

export function cellKey(x: number, y: number): string {
  return `${x},${y}`;
}

export function keyToCell(key: string): { x: number; y: number } {
  const parts = key.split(",");
  if (parts.length !== 2) return { x: -1, y: -1 };
  const x = Number(parts[0]);
  const y = Number(parts[1]);
  if (!Number.isInteger(x) || !Number.isInteger(y)) return { x: -1, y: -1 };
  return { x, y };
}

export function hasExpansion(layout: GardenLayout, expansionId: string): boolean {
  return layout.unlockedExpansionIds.includes(expansionId);
}

/** True only on first grant, so the expansion celebration fires once. */
export function grantExpansion(layout: GardenLayout, expansionId: string): boolean {
  if (expansionId === "" || layout.unlockedExpansionIds.includes(expansionId)) return false;
  layout.unlockedExpansionIds.push(expansionId);
  return true;
}

export function setDecoration(
  layout: GardenLayout, x: number, y: number, decorationId: string, rotation = 0,
): void {
  layout.decorations[cellKey(x, y)] = {
    id: decorationId,
    rotation: posmod(rotation, ROTATIONS),
  };
}

export function clearDecoration(layout: GardenLayout, x: number, y: number): void {
  delete layout.decorations[cellKey(x, y)];
}

export function getDecoration(
  layout: GardenLayout, x: number, y: number,
): DecorationPlacement | null {
  return layout.decorations[cellKey(x, y)] ?? null;
}

/**
 * Turns an ornament a quarter turn. False when the cell is empty, so a caller can
 * fall through to whatever else a rotate gesture might mean.
 *
 * Ornaments genuinely rotate - unlike plants, which mirror and lean, because a
 * side-on plant tipped onto its side stops looking like a plant.
 */
export function rotateDecoration(
  layout: GardenLayout, x: number, y: number, steps = 1,
): boolean {
  const existing = layout.decorations[cellKey(x, y)];
  if (existing === undefined) return false;
  layout.decorations[cellKey(x, y)] = {
    id: existing.id,
    rotation: posmod(existing.rotation + steps, ROTATIONS),
  };
  return true;
}

export function isCellInBounds(layout: GardenLayout, x: number, y: number): boolean {
  return x >= 0 && y >= 0 && x < layout.gridWidth && y < layout.gridHeight;
}

export function gardenLayoutToDict(g: GardenLayout): Json {
  const decorations: Record<string, Json> = {};
  for (const [key, entry] of Object.entries(g.decorations)) {
    decorations[key] = { id: entry.id, rotation: entry.rotation };
  }
  return {
    environment_id: g.environmentId,
    grid_size_x: g.gridWidth,
    grid_size_y: g.gridHeight,
    unlocked_expansion_ids: [...g.unlockedExpansionIds],
    decorations,
  };
}

/**
 * Accepts BOTH shapes a decoration has ever had: format 1 stored a bare id
 * string, format 2 stores {id, rotation}. Reading the old shape directly means a
 * save that somehow skipped the migration still opens rather than crashing.
 */
function readEntry(entry: unknown): DecorationPlacement | null {
  if (typeof entry === "string") {
    return entry === "" ? null : { id: entry, rotation: 0 };
  }
  if (typeof entry === "object" && entry !== null && !Array.isArray(entry)) {
    const record = entry as Json;
    const id = getString(record, "id");
    if (id === "") return null;
    return { id, rotation: posmod(getInt(record, "rotation"), ROTATIONS) };
  }
  return null;
}

export function gardenLayoutFromDict(data: Json): GardenLayout {
  const layout = makeGardenLayout({
    environmentId: getString(data, "environment_id", "cottage_garden"),
    gridWidth: clampi(getInt(data, "grid_size_x", 4), 1, 64),
    gridHeight: clampi(getInt(data, "grid_size_y", 3), 1, 64),
    unlockedExpansionIds: getStringArray(data, "unlocked_expansion_ids"),
  });
  // Normalised on the way in, so nothing downstream needs to know two shapes ever
  // existed. An entry with no id at all is DROPPED rather than kept as an
  // invisible occupant of a cell the player then cannot use.
  const raw = getDict(data, "decorations");
  for (const [key, value] of Object.entries(raw)) {
    const entry = readEntry(value);
    if (entry !== null) layout.decorations[key] = entry;
  }
  return layout;
}
