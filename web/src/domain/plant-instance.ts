/**
 * A plant the player actually owns. Port of models/plant_instance.gd.
 *
 * Strictly separate from a species definition: the species is the shared
 * definition, this is one player's individual plant with its own history.
 *
 * PLACEMENT INVARIANT: a plant is in exactly one place, expressed by a single
 * `location` field. Shelf and garden positions are not independent, so "placed in
 * two spots at once" cannot be represented at all. Use the move helpers - writing
 * the fields directly is what would reintroduce the duplicate-placement bug.
 */

import { maxf, maxi, posmod, toInt } from "./gd.js";
import type { Json } from "./dict-util.js";
import { getBool, getFloat, getInt, getString, getStringArray } from "./dict-util.js";
import { DISPLAY_STAGE } from "./plant-growth.js";

export const Location = { INVENTORY: 0, SHELF: 1, GARDEN: 2 } as const;
export type Location = (typeof Location)[keyof typeof Location];

export const Maturity = { GROWING: 0, MATURE: 1 } as const;
export type Maturity = (typeof Maturity)[keyof typeof Maturity];

/** Quarter turns a planted specimen can take. */
export const GARDEN_ROTATIONS = 4;

export interface PlantInstance {
  uid: string;
  speciesId: string;
  nickname: string;
  plantedAtUtc: number;
  maturedAtUtc: number;
  /** Credited focus minutes grown into THIS plant. Authoritative for its progress. */
  accumulatedFocusMinutes: number;
  growthStage: number;
  maturity: Maturity;
  /** Sessions that contributed, for plant history and plant-scoped requirements. */
  contributingSessionIds: string[];
  primaryProjectId: string;
  /** Cosmetic only. Never affects growth rate or focus productivity. */
  mutationIds: string[];
  potId: string;
  favorite: boolean;
  location: Location;
  /** Shelf slot index when location is SHELF, else -1. */
  shelfSlot: number;
  /** Garden cell when location is GARDEN, else (-1, -1). */
  gardenCellX: number;
  gardenCellY: number;
  /** Quarter turns, 0-3. Cosmetic, like the pot. */
  gardenRotation: number;
  /** Mystery seed support. While unrevealed the UI must not show speciesId. */
  isMystery: boolean;
  mysteryRevealed: boolean;
}

export function makePlantInstance(overrides: Partial<PlantInstance> = {}): PlantInstance {
  return {
    uid: "", speciesId: "", nickname: "", plantedAtUtc: 0, maturedAtUtc: 0,
    accumulatedFocusMinutes: 0, growthStage: 0, maturity: Maturity.GROWING,
    contributingSessionIds: [], primaryProjectId: "", mutationIds: [],
    potId: "terracotta_basic", favorite: false,
    location: Location.INVENTORY, shelfSlot: -1, gardenCellX: -1, gardenCellY: -1,
    gardenRotation: 0, isMystery: false, mysteryRevealed: false,
    ...overrides,
  };
}

/** True when the species identity should be hidden from the player. */
export function isSpeciesHidden(plant: PlantInstance): boolean {
  return plant.isMystery && !plant.mysteryRevealed;
}

export function isMature(plant: PlantInstance): boolean {
  return plant.maturity === Maturity.MATURE;
}

/**
 * True once the plant is far enough along to go on the shelf or into the garden.
 *
 * Waiting for full maturity meant a plant spent hours as a row in a list with
 * nowhere to be seen, which is the opposite of what a game about watching things
 * grow should do. Placement has never had anything to do with growth.
 */
export function canBeDisplayed(plant: PlantInstance): boolean {
  return isMature(plant) || plant.growthStage >= DISPLAY_STAGE;
}

export function moveToInventory(plant: PlantInstance): void {
  plant.location = Location.INVENTORY;
  plant.shelfSlot = -1;
  plant.gardenCellX = -1;
  plant.gardenCellY = -1;
  plant.gardenRotation = 0;
}

export function moveToShelf(plant: PlantInstance, slot: number): void {
  plant.location = Location.SHELF;
  plant.shelfSlot = slot;
  plant.gardenCellX = -1;
  plant.gardenCellY = -1;
}

export function moveToGarden(plant: PlantInstance, x: number, y: number, rotation = -1): void {
  plant.location = Location.GARDEN;
  plant.gardenCellX = x;
  plant.gardenCellY = y;
  plant.shelfSlot = -1;
  if (rotation >= 0) plant.gardenRotation = posmod(rotation, GARDEN_ROTATIONS);
}

/** Turns the plant a quarter turn where it stands. */
export function rotateInGarden(plant: PlantInstance, steps = 1): void {
  plant.gardenRotation = posmod(plant.gardenRotation + steps, GARDEN_ROTATIONS);
}

export function plantInstanceToDict(p: PlantInstance): Json {
  return {
    uid: p.uid,
    species_id: p.speciesId,
    nickname: p.nickname,
    planted_at_utc: p.plantedAtUtc,
    matured_at_utc: p.maturedAtUtc,
    accumulated_focus_minutes: p.accumulatedFocusMinutes,
    growth_stage: p.growthStage,
    maturity: p.maturity,
    contributing_session_ids: [...p.contributingSessionIds],
    primary_project_id: p.primaryProjectId,
    mutation_ids: [...p.mutationIds],
    pot_id: p.potId,
    favorite: p.favorite,
    location: p.location,
    shelf_slot: p.shelfSlot,
    garden_cell_x: p.gardenCellX,
    garden_cell_y: p.gardenCellY,
    garden_rotation: p.gardenRotation,
    is_mystery: p.isMystery,
    mystery_revealed: p.mysteryRevealed,
  };
}

export function plantInstanceFromDict(data: Json): PlantInstance {
  const plant = makePlantInstance({
    uid: getString(data, "uid"),
    speciesId: getString(data, "species_id"),
    nickname: getString(data, "nickname"),
    plantedAtUtc: getFloat(data, "planted_at_utc"),
    maturedAtUtc: getFloat(data, "matured_at_utc"),
    accumulatedFocusMinutes: maxf(0, getFloat(data, "accumulated_focus_minutes")),
    growthStage: maxi(0, getInt(data, "growth_stage")),
    maturity: safeMaturity(getInt(data, "maturity", Maturity.GROWING)),
    contributingSessionIds: getStringArray(data, "contributing_session_ids"),
    primaryProjectId: getString(data, "primary_project_id"),
    mutationIds: getStringArray(data, "mutation_ids"),
    potId: getString(data, "pot_id", "terracotta_basic"),
    favorite: getBool(data, "favorite"),
    location: safeLocation(getInt(data, "location", Location.INVENTORY)),
    shelfSlot: getInt(data, "shelf_slot", -1),
    gardenCellX: getInt(data, "garden_cell_x", -1),
    gardenCellY: getInt(data, "garden_cell_y", -1),
    // posmod, NOT `%`: a stored -1 must become 3, and JavaScript's remainder
    // operator would leave it at -1 and rotate the plant into a wall.
    gardenRotation: posmod(getInt(data, "garden_rotation"), GARDEN_ROTATIONS),
    isMystery: getBool(data, "is_mystery"),
    mysteryRevealed: getBool(data, "mystery_revealed"),
  });

  // Re-assert the placement invariant. A save hand-edited or written by a buggy
  // build could carry a shelf slot AND a garden cell; `location` wins.
  switch (plant.location) {
    case Location.INVENTORY:
      plant.shelfSlot = -1;
      plant.gardenCellX = -1;
      plant.gardenCellY = -1;
      plant.gardenRotation = 0;
      break;
    case Location.SHELF:
      plant.gardenCellX = -1;
      plant.gardenCellY = -1;
      plant.gardenRotation = 0;
      break;
    case Location.GARDEN:
      plant.shelfSlot = -1;
      break;
  }
  return plant;
}

function safeMaturity(value: number): Maturity {
  return value >= 0 && value <= Maturity.MATURE
    ? (toInt(value) as Maturity)
    : Maturity.GROWING;
}

function safeLocation(value: number): Location {
  return value >= 0 && value <= Location.GARDEN
    ? (toInt(value) as Location)
    : Location.INVENTORY;
}
