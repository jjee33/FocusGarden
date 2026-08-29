/**
 * Loads the authored catalogue exported from the Godot project.
 *
 * `content.generated.json` is written by tools/export_content_json.gd from the
 * same data/*.tres the desktop app ships, so the two clients cannot disagree
 * about what a species costs or what a pot looks like. Never hand-edit it.
 *
 * This module is the only place that knows the file's snake_case shape. Everything
 * downstream sees typed camelCase objects, so a rename in the exporter fails here
 * loudly instead of producing `undefined` three layers away.
 */

import raw from "./content.generated.json";
import type { Json } from "../domain/dict-util.js";
import { getBool, getFloat, getInt, getString, getStringArray } from "../domain/dict-util.js";
import type { Requirement, RequirementScope, RequirementType } from "../domain/requirement.js";
import { REQUIREMENT_SCOPES, REQUIREMENT_TYPES } from "../domain/requirement.js";
import type { BotanicalInfo, PlantMorphology, PlantSpecies, Rarity } from "../domain/species.js";
import { RARITIES, makePlantSpecies } from "../domain/species.js";
import type { PotPattern, PotShape, PotStyle } from "../domain/pot.js";
import { DEFAULT_POT_ID, POT_PATTERNS, POT_SHAPES, makePotStyle } from "../domain/pot.js";

/** Bumped by the exporter when the file's shape changes, not its contents. */
export const SUPPORTED_CONTENT_FORMAT = 1;

export interface AchievementDef {
  id: string;
  title: string;
  description: string;
  category: string;
  rarity: Rarity;
  hidden: boolean;
  trackProgress: boolean;
  requirement: Requirement | null;
}

export interface DecorationDef {
  id: string;
  displayName: string;
  shape: string;
  primaryColor: string;
  accentColor: string;
  unlockExpansionId: string;
}

export interface GardenExpansion {
  id: string;
  displayName: string;
  description: string;
  gridWidth: number;
  gridHeight: number;
  unlocksDecorations: string[];
  requirement: Requirement | null;
}

// --- Parsing ----------------------------------------------------------------

function asJson(value: unknown): Json {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as Json)
    : {};
}

function oneOf<T extends string>(options: readonly T[], value: string, fallback: T): T {
  return (options as readonly string[]).includes(value) ? (value as T) : fallback;
}

function parseRequirement(value: unknown): Requirement | null {
  // Null stays null. An absent requirement means "available from the start", and
  // substituting an always-true stand-in would erase that distinction.
  if (value === null || value === undefined) return null;
  const data = asJson(value);
  return {
    type: oneOf<RequirementType>(
      REQUIREMENT_TYPES, getString(data, "type"), "total_focus_minutes",
    ),
    scope: oneOf<RequirementScope>(REQUIREMENT_SCOPES, getString(data, "scope"), "global"),
    params: asJson(data["params"]),
    descriptionOverride: getString(data, "description_override"),
  };
}

function parseMorphology(value: unknown): PlantMorphology | null {
  if (value === null || value === undefined) return null;
  const d = asJson(value);
  return {
    form: getString(d, "form", "rosette"),
    leafShape: getString(d, "leaf_shape", "oval"),
    leafColorBase: getString(d, "leaf_color_base", "#4A7C3F"),
    leafColorTip: getString(d, "leaf_color_tip", "#7FB069"),
    stemColor: getString(d, "stem_color", "#5F7F42"),
    leafCountMax: getInt(d, "leaf_count_max", 9),
    leafLengthRatio: getFloat(d, "leaf_length_ratio", 0.45),
    leafWidthRatio: getFloat(d, "leaf_width_ratio", 0.34),
    leafArc: getFloat(d, "leaf_arc", 0.12),
    spreadRadians: getFloat(d, "spread_radians", 0.9),
    variegation: getFloat(d, "variegation", 0),
    variegationColor: getString(d, "variegation_color", "#E8E4C9"),
    hasFlowers: getBool(d, "has_flowers"),
    flowerShape: getString(d, "flower_shape", "daisy"),
    flowerColor: getString(d, "flower_color", "#E8C86A"),
    flowerCentreColor: getString(d, "flower_centre_color", "#8A6A3A"),
    flowerCount: getInt(d, "flower_count", 3),
    swayAmount: getFloat(d, "sway_amount", 0.05),
  };
}

function parseBotanical(value: unknown): BotanicalInfo | null {
  if (value === null || value === undefined) return null;
  const d = asJson(value);
  return {
    family: getString(d, "family"),
    nativeRegion: getString(d, "native_region"),
    lightPreference: getString(d, "light_preference"),
    wateringPreference: getString(d, "watering_preference"),
    careDifficulty: getString(d, "care_difficulty"),
    interestingFact: getString(d, "interesting_fact"),
  };
}

function parseSpecies(value: unknown): PlantSpecies {
  const d = asJson(value);
  return makePlantSpecies({
    id: getString(d, "id"),
    displayName: getString(d, "display_name"),
    scientificName: getString(d, "scientific_name"),
    description: getString(d, "description"),
    rarity: oneOf<Rarity>(RARITIES, getString(d, "rarity"), "common"),
    biomeId: getString(d, "biome_id", "houseplant"),
    tags: getStringArray(d, "tags"),
    growthRequirement: parseRequirement(d["growth_requirement"]),
    unlockRequirement: parseRequirement(d["unlock_requirement"]),
    morphology: parseMorphology(d["morphology"]),
    botanical: parseBotanical(d["botanical"]),
    preferredPotIds: getStringArray(d, "preferred_pot_ids"),
    allowedMutationIds: getStringArray(d, "allowed_mutation_ids"),
    hiddenUntilDiscovered: getBool(d, "hidden_until_discovered"),
    seasonalMonths: (Array.isArray(d["seasonal_months"]) ? d["seasonal_months"] : [])
      .filter((m): m is number => typeof m === "number"),
    stageCount: getInt(d, "stage_count", 3),
  });
}

function parsePot(value: unknown): PotStyle {
  const d = asJson(value);
  return makePotStyle({
    id: getString(d, "id"),
    displayName: getString(d, "display_name"),
    shape: oneOf<PotShape>(POT_SHAPES, getString(d, "shape"), "tapered"),
    pattern: oneOf<PotPattern>(POT_PATTERNS, getString(d, "pattern"), "none"),
    bodyColor: getString(d, "body_color", "#C26A45"),
    rimColor: getString(d, "rim_color", "#A9563A"),
    accentColor: getString(d, "accent_color", "#E8C9A0"),
    soilColor: getString(d, "soil_color", "#4A3B2A"),
    topWidthRatio: getFloat(d, "top_width_ratio", 1.05),
    bottomWidthRatio: getFloat(d, "bottom_width_ratio", 0.78),
    unlockRequirement: parseRequirement(d["unlock_requirement"]),
  });
}

function parseAchievement(value: unknown): AchievementDef {
  const d = asJson(value);
  return {
    id: getString(d, "id"),
    title: getString(d, "title"),
    description: getString(d, "description"),
    category: getString(d, "category", "focus"),
    rarity: oneOf<Rarity>(RARITIES, getString(d, "rarity"), "common"),
    hidden: getBool(d, "hidden"),
    trackProgress: getBool(d, "track_progress", true),
    requirement: parseRequirement(d["requirement"]),
  };
}

function parseDecoration(value: unknown): DecorationDef {
  const d = asJson(value);
  return {
    id: getString(d, "id"),
    displayName: getString(d, "display_name"),
    shape: getString(d, "shape", "stone"),
    primaryColor: getString(d, "primary_color", "#C69A63"),
    accentColor: getString(d, "accent_color", "#A2743F"),
    unlockExpansionId: getString(d, "unlock_expansion_id"),
  };
}

function parseExpansion(value: unknown): GardenExpansion {
  const d = asJson(value);
  return {
    id: getString(d, "id"),
    displayName: getString(d, "display_name"),
    description: getString(d, "description"),
    gridWidth: getInt(d, "grid_width", 4),
    gridHeight: getInt(d, "grid_height", 3),
    unlocksDecorations: getStringArray(d, "unlocks_decorations"),
    requirement: parseRequirement(d["requirement"]),
  };
}

// --- The loaded catalogue ---------------------------------------------------

const source = raw as unknown as Json;

if (getInt(source, "content_format") !== SUPPORTED_CONTENT_FORMAT) {
  throw new Error(
    `content.generated.json is format ${getInt(source, "content_format")}, `
    + `this build understands ${SUPPORTED_CONTENT_FORMAT}. Re-run `
    + `tools/export_content_json.gd.`,
  );
}

function list(key: string): unknown[] {
  const value = source[key];
  return Array.isArray(value) ? value : [];
}

/** Insertion-ordered, so screens have a stable order not tied to a hash map. */
export const ALL_SPECIES: readonly PlantSpecies[] = list("species").map(parseSpecies);
export const ALL_POTS: readonly PotStyle[] = list("pots").map(parsePot);
export const ALL_ACHIEVEMENTS: readonly AchievementDef[] =
  list("achievements").map(parseAchievement);
export const ALL_DECORATIONS: readonly DecorationDef[] =
  list("decorations").map(parseDecoration);

/**
 * Ordered smallest first by plot area, so "the largest earned" is a simple scan.
 * The exporter already sorts them; re-sorting here means a hand-edited file
 * cannot make the ladder depend on its own line order.
 */
export const ALL_EXPANSIONS: readonly GardenExpansion[] = list("expansions")
  .map(parseExpansion)
  .sort((a, b) => a.gridWidth * a.gridHeight - b.gridWidth * b.gridHeight);

const speciesById = new Map(ALL_SPECIES.map((s) => [s.id, s]));
const potsById = new Map(ALL_POTS.map((p) => [p.id, p]));
const achievementsById = new Map(ALL_ACHIEVEMENTS.map((a) => [a.id, a]));
const decorationsById = new Map(ALL_DECORATIONS.map((d) => [d.id, d]));

export function getSpecies(id: string): PlantSpecies | null {
  return speciesById.get(id) ?? null;
}

/**
 * True when a species id in a save no longer exists in this build. Callers must
 * keep the plant and render a graceful placeholder rather than deleting it.
 */
export function isSpeciesMissing(id: string): boolean {
  return !speciesById.has(id);
}

/**
 * A pot by id, falling back to the default so a plant whose saved pot was removed
 * in an update still renders instead of losing its container.
 */
export function getPot(id: string): PotStyle | null {
  return potsById.get(id) ?? potsById.get(DEFAULT_POT_ID) ?? null;
}

export function getAchievement(id: string): AchievementDef | null {
  return achievementsById.get(id) ?? null;
}

export function getDecoration(id: string): DecorationDef | null {
  return decorationsById.get(id) ?? null;
}

export function speciesCount(): number {
  return ALL_SPECIES.length;
}
