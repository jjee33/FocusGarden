/**
 * The save container. Port of models/save_data.gd.
 *
 * CURRENT_VERSION is shared with the desktop build and must move in lockstep
 * with it. The web is not inventing a save format - it writes version 2 of the
 * existing one, because SaveBundle is the transfer format between the two
 * clients. A web build writing version 3 would make every shipped desktop build
 * classify the file as FUTURE_VERSION and refuse to write it.
 *
 * Session history is deliberately NOT here. It is the authoritative analytics
 * dataset and grows forever; keeping it inside the profile would mean rewriting
 * years of records every time a 25-minute pomodoro ends. An export BUNDLE is
 * this plus the sessions - see save-bundle.ts.
 */

import type { Json } from "./dict-util.js";
import { getArray, getDict, getInt } from "./dict-util.js";
import type { PlayerProfile } from "./player-profile.js";
import { makePlayerProfile, playerProfileFromDict, playerProfileToDict } from "./player-profile.js";
import type { GameSettings } from "./game-settings.js";
import { gameSettingsFromDict, gameSettingsToDict, makeGameSettings } from "./game-settings.js";
import type { PlantInstance } from "./plant-instance.js";
import { plantInstanceFromDict, plantInstanceToDict } from "./plant-instance.js";
import type { ProjectCategory } from "./project-category.js";
import { projectCategoryFromDict, projectCategoryToDict } from "./project-category.js";
import type { CatalogueEntry } from "./catalogue-entry.js";
import { catalogueEntryFromDict, catalogueEntryToDict } from "./catalogue-entry.js";
import type { AchievementState } from "./achievement-state.js";
import { achievementStateFromDict, achievementStateToDict } from "./achievement-state.js";
import type { JournalEntry } from "./journal-entry.js";
import { journalEntryFromDict, journalEntryToDict } from "./journal-entry.js";
import type { ShelfLayout } from "./shelf-layout.js";
import { makeShelfLayout, shelfLayoutFromDict, shelfLayoutToDict } from "./shelf-layout.js";
import type { GardenLayout } from "./garden-layout.js";
import { gardenLayoutFromDict, gardenLayoutToDict, makeGardenLayout } from "./garden-layout.js";

export const CURRENT_VERSION = 2;

export interface SaveData {
  saveVersion: number;
  profile: PlayerProfile;
  settings: GameSettings;
  plants: PlantInstance[];
  projects: ProjectCategory[];
  catalogue: CatalogueEntry[];
  achievements: AchievementState[];
  journal: JournalEntry[];
  shelf: ShelfLayout;
  garden: GardenLayout;
  expeditions: Json;
  /**
   * A running session plus its wall-clock anchor, so a crash can be offered back
   * on next launch. Emptied by an export: offering to resume a pomodoro that was
   * interrupted on a different machine three weeks ago is nonsense.
   */
  inFlightSession: Json;
}

export function makeSaveData(overrides: Partial<SaveData> = {}): SaveData {
  return {
    saveVersion: CURRENT_VERSION,
    profile: makePlayerProfile(),
    settings: makeGameSettings(),
    plants: [], projects: [], catalogue: [], achievements: [], journal: [],
    shelf: makeShelfLayout(),
    garden: makeGardenLayout(),
    expeditions: {},
    inFlightSession: {},
    ...overrides,
  };
}

/**
 * A fresh save for a brand-new player. Content seeding - starter projects, a
 * starter plant - belongs to the app layer, not here. This owns shape only.
 */
export function createNewSave(nowUnixUtc = Date.now() / 1000): SaveData {
  return makeSaveData({
    profile: makePlayerProfile({ displayName: "Gardener", createdAtUtc: nowUnixUtc }),
  });
}

export function saveDataToDict(save: SaveData): Json {
  return {
    save_version: save.saveVersion,
    player: playerProfileToDict(save.profile),
    settings: gameSettingsToDict(save.settings),
    plants: save.plants.map(plantInstanceToDict),
    projects: save.projects.map(projectCategoryToDict),
    catalogue: save.catalogue.map(catalogueEntryToDict),
    achievements: save.achievements.map(achievementStateToDict),
    journal: save.journal.map(journalEntryToDict),
    shelf: shelfLayoutToDict(save.shelf),
    garden: gardenLayoutToDict(save.garden),
    expeditions: { ...save.expeditions },
    in_flight_session: { ...save.inFlightSession },
  };
}

/**
 * Duplicate ids are a case that must not be left undefined: a dupe makes lookups
 * nondeterministic. First occurrence wins, the rest are dropped at the boundary.
 * An entry with an empty key is dropped too.
 */
function dedupe<T>(items: T[], keyOf: (item: T) => string): T[] {
  const seen = new Set<string>();
  const out: T[] = [];
  for (const item of items) {
    const key = keyOf(item);
    if (key === "" || seen.has(key)) continue;
    seen.add(key);
    out.push(item);
  }
  return out;
}

function isJson(value: unknown): value is Json {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function saveDataFromDict(data: Json): SaveData {
  const save = makeSaveData({
    // Defaults to 1, not CURRENT_VERSION: a file with no version is from before
    // versioning, and claiming it is current would skip every migration step.
    saveVersion: getInt(data, "save_version", 1),
    profile: playerProfileFromDict(getDict(data, "player")),
    settings: gameSettingsFromDict(getDict(data, "settings")),
    shelf: shelfLayoutFromDict(getDict(data, "shelf")),
    garden: gardenLayoutFromDict(getDict(data, "garden")),
    expeditions: getDict(data, "expeditions"),
    inFlightSession: getDict(data, "in_flight_session"),
  });

  // Entries that fail to deserialise are skipped rather than aborting the whole
  // load: losing one malformed plant is recoverable, losing the save is not.
  for (const entry of getArray(data, "plants")) {
    if (!isJson(entry)) continue;
    const plant = plantInstanceFromDict(entry);
    if (plant.uid !== "") save.plants.push(plant);
  }
  for (const entry of getArray(data, "projects")) {
    if (!isJson(entry)) continue;
    const project = projectCategoryFromDict(entry);
    if (project.id !== "") save.projects.push(project);
  }
  for (const entry of getArray(data, "catalogue")) {
    if (!isJson(entry)) continue;
    const catalogueEntry = catalogueEntryFromDict(entry);
    if (catalogueEntry.speciesId !== "") save.catalogue.push(catalogueEntry);
  }
  for (const entry of getArray(data, "achievements")) {
    if (!isJson(entry)) continue;
    const achievement = achievementStateFromDict(entry);
    if (achievement.achievementId !== "") save.achievements.push(achievement);
  }
  for (const entry of getArray(data, "journal")) {
    if (isJson(entry)) save.journal.push(journalEntryFromDict(entry));
  }

  save.plants = dedupe(save.plants, (p) => p.uid);
  save.projects = dedupe(save.projects, (p) => p.id);
  save.catalogue = dedupe(save.catalogue, (c) => c.speciesId);
  save.achievements = dedupe(save.achievements, (a) => a.achievementId);
  save.journal = dedupe(save.journal, (j) => j.id);
  return save;
}
