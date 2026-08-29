/**
 * A species definition - authored content, identical for every player.
 * Port of models/plant_species.gd, loaded from content.generated.json.
 *
 * What the player OWNS is a PlantInstance that points at one of these by id.
 *
 * `required_focus_minutes` is deliberately NOT a field: the maturity rule lives in
 * `growthRequirement` so that varied patterns (100 minutes, 4 sessions, 5 separate
 * days, morning sessions) all work through one mechanism. A plain minute count is
 * just the most common shape of that requirement, and getDisplayFocusMinutes
 * derives it for the UI. Storing both would be two sources of truth for one
 * threshold.
 */

import { clampi, maxi } from "./gd.js";
import type { Json } from "./dict-util.js";
import { getFloat } from "./dict-util.js";
import type { Requirement } from "./requirement.js";

export const RARITIES = ["common", "uncommon", "rare", "epic", "legendary"] as const;
export type Rarity = (typeof RARITIES)[number];

export const RARITY_NAMES: Record<Rarity, string> = {
  common: "Common", uncommon: "Uncommon", rare: "Rare", epic: "Epic", legendary: "Legendary",
};

/**
 * Focus minutes to maturity, by rarity - three hours for a common houseplant up to
 * ten for the bonsai.
 *
 * Rarity is the only input. Per-species tuning drifted into eleven arbitrary
 * numbers that no player could predict and no designer could remember, and a plant
 * whose cost you cannot guess from its badge is a plant you cannot plan around.
 */
export const MATURITY_MINUTES_BY_RARITY: Record<Rarity, number> = {
  common: 180, uncommon: 270, rare: 360, epic: 480, legendary: 600,
};

/**
 * Growth stages a species has when no art has been authored for it.
 *
 * Three, in equal thirds: seedling, young, mature. Few enough that each one is a
 * visibly different plant and the first is reached in a sitting or two, which is
 * what makes a growing plant worth putting on the shelf rather than hiding until
 * it is finished.
 */
export const DEFAULT_STAGE_COUNT = 3;

export interface PlantMorphology {
  form: string;
  leafShape: string;
  leafColorBase: string;
  leafColorTip: string;
  stemColor: string;
  leafCountMax: number;
  leafLengthRatio: number;
  leafWidthRatio: number;
  leafArc: number;
  spreadRadians: number;
  variegation: number;
  variegationColor: string;
  hasFlowers: boolean;
  flowerShape: string;
  flowerColor: string;
  flowerCentreColor: string;
  flowerCount: number;
  swayAmount: number;
}

export interface BotanicalInfo {
  family: string;
  nativeRegion: string;
  lightPreference: string;
  wateringPreference: string;
  careDifficulty: string;
  interestingFact: string;
}

export interface PlantSpecies {
  id: string;
  displayName: string;
  scientificName: string;
  description: string;
  rarity: Rarity;
  biomeId: string;
  tags: string[];
  growthRequirement: Requirement | null;
  unlockRequirement: Requirement | null;
  morphology: PlantMorphology | null;
  botanical: BotanicalInfo | null;
  preferredPotIds: string[];
  allowedMutationIds: string[];
  hiddenUntilDiscovered: boolean;
  seasonalMonths: number[];
  /** Derived by the exporter from the stage art count, minimum 2. */
  stageCount: number;
}

export function makePlantSpecies(overrides: Partial<PlantSpecies> = {}): PlantSpecies {
  return {
    id: "", displayName: "", scientificName: "", description: "",
    rarity: "common", biomeId: "houseplant", tags: [],
    growthRequirement: null, unlockRequirement: null,
    morphology: null, botanical: null,
    preferredPotIds: [], allowedMutationIds: [],
    hiddenUntilDiscovered: false, seasonalMonths: [],
    stageCount: DEFAULT_STAGE_COUNT,
    ...overrides,
  };
}

/** Number of visual growth stages, minimum 2 (a seed and a mature form). */
export function getStageCount(species: PlantSpecies): number {
  return maxi(2, species.stageCount);
}

/**
 * The authored cost of this species, from its rarity. Content generation reads
 * this to build the growth requirement, so the table above is the only place the
 * number is decided.
 */
export function getMaturityMinutes(species: PlantSpecies): number {
  return MATURITY_MINUTES_BY_RARITY[species.rarity] ?? MATURITY_MINUTES_BY_RARITY.common;
}

export function getRarityName(species: PlantSpecies): string {
  return RARITY_NAMES[species.rarity] ?? RARITY_NAMES.common;
}

/**
 * Approximate focus minutes to maturity, for catalogue and selection screens.
 * Derived from the requirement, never stored separately.
 *
 * Returns -1 when the requirement is not minute-shaped (e.g. "focus on 5 separate
 * days"), so the UI can show the requirement's own wording instead of a fake
 * minute figure.
 */
export function getDisplayFocusMinutes(species: PlantSpecies): number {
  const requirement = species.growthRequirement;
  if (requirement === null) return -1;
  if (requirement.type === "total_focus_minutes") {
    return getFloat(requirement.params as Json, "amount", -1);
  }
  return -1;
}

export function isSeasonal(species: PlantSpecies): boolean {
  return species.seasonalMonths.length > 0;
}

export function isValidSpecies(species: PlantSpecies): boolean {
  return species.id !== "" && species.displayName !== "";
}

/** Rarity tint index, for the catalogue badge. Named text always accompanies it. */
export function rarityIndex(rarity: Rarity): number {
  return clampi(RARITIES.indexOf(rarity), 0, RARITIES.length - 1);
}
