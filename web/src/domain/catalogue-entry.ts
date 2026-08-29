/**
 * Per-species collection record. Port of models/catalogue_entry.gd.
 *
 * Backs the catalogue's discovered/undiscovered state and the per-species
 * statistics in the detail view: number grown, first discovery date, fastest
 * growth, total focus time associated with the species.
 */

import { maxf, maxi } from "./gd.js";
import type { Json } from "./dict-util.js";
import { getBool, getFloat, getInt, getString } from "./dict-util.js";

export interface CatalogueEntry {
  speciesId: string;
  discovered: boolean;
  firstDiscoveredAtUtc: number;
  timesGrown: number;
  totalFocusMinutes: number;
  /** Fewest minutes taken to bring one to maturity. -1 until one matures. */
  fastestGrowthMinutes: number;
  favorite: boolean;
}

export function makeCatalogueEntry(speciesId = ""): CatalogueEntry {
  return {
    speciesId, discovered: false, firstDiscoveredAtUtc: 0,
    timesGrown: 0, totalFocusMinutes: 0, fastestGrowthMinutes: -1, favorite: false,
  };
}

/** Returns true only on first discovery, so the "new species!" reveal fires once. */
export function discover(entry: CatalogueEntry, nowUnixUtc = Date.now() / 1000): boolean {
  if (entry.discovered) return false;
  entry.discovered = true;
  entry.firstDiscoveredAtUtc = nowUnixUtc;
  return true;
}

export function recordMaturity(entry: CatalogueEntry, growthMinutes: number): void {
  entry.timesGrown += 1;
  if (entry.fastestGrowthMinutes < 0 || growthMinutes < entry.fastestGrowthMinutes) {
    entry.fastestGrowthMinutes = growthMinutes;
  }
}

export function catalogueEntryToDict(e: CatalogueEntry): Json {
  return {
    species_id: e.speciesId,
    discovered: e.discovered,
    first_discovered_at_utc: e.firstDiscoveredAtUtc,
    times_grown: e.timesGrown,
    total_focus_minutes: e.totalFocusMinutes,
    fastest_growth_minutes: e.fastestGrowthMinutes,
    favorite: e.favorite,
  };
}

export function catalogueEntryFromDict(data: Json): CatalogueEntry {
  return {
    speciesId: getString(data, "species_id"),
    discovered: getBool(data, "discovered"),
    firstDiscoveredAtUtc: getFloat(data, "first_discovered_at_utc"),
    timesGrown: maxi(0, getInt(data, "times_grown")),
    totalFocusMinutes: maxf(0, getFloat(data, "total_focus_minutes")),
    fastestGrowthMinutes: getFloat(data, "fastest_growth_minutes", -1),
    favorite: getBool(data, "favorite"),
  };
}
