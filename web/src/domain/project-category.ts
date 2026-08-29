/**
 * What the player is working on: Studying, Network+, Reading, Work.
 * Port of models/project_category.gd.
 *
 * Users create their own, so these are player data, not authored content. The
 * built-in starters are seeded on first launch and are deletable like any other.
 */

import { maxf } from "./gd.js";
import type { Json } from "./dict-util.js";
import { getBool, getFloat, getString } from "./dict-util.js";
import { generate } from "./uid.js";

export interface ProjectCategory {
  id: string;
  displayName: string;
  /**
   * Token name from the theme palette (e.g. "moss"), never a raw hex value.
   * Keeps categories re-themeable and stops save files pinning old colours.
   */
  colorToken: string;
  iconId: string;
  createdAtUtc: number;
  archived: boolean;
  /**
   * Convenience rollup. Sessions remain authoritative and this can be rebuilt
   * from them at any time.
   */
  totalFocusMinutes: number;
}

export function makeProjectCategory(overrides: Partial<ProjectCategory> = {}): ProjectCategory {
  return {
    id: "", displayName: "", colorToken: "moss", iconId: "leaf",
    createdAtUtc: 0, archived: false, totalFocusMinutes: 0,
    ...overrides,
  };
}

export function createProjectCategory(
  name: string, color = "moss", icon = "leaf", nowUnixUtc = Date.now() / 1000,
): ProjectCategory {
  return makeProjectCategory({
    id: generate("p", nowUnixUtc),
    displayName: name,
    colorToken: color,
    iconId: icon,
    createdAtUtc: nowUnixUtc,
  });
}

export function projectCategoryToDict(p: ProjectCategory): Json {
  return {
    id: p.id,
    display_name: p.displayName,
    color_token: p.colorToken,
    icon_id: p.iconId,
    created_at_utc: p.createdAtUtc,
    archived: p.archived,
    total_focus_minutes: p.totalFocusMinutes,
  };
}

export function projectCategoryFromDict(data: Json): ProjectCategory {
  return makeProjectCategory({
    id: getString(data, "id"),
    displayName: getString(data, "display_name", "Untitled"),
    colorToken: getString(data, "color_token", "moss"),
    iconId: getString(data, "icon_id", "leaf"),
    createdAtUtc: getFloat(data, "created_at_utc"),
    archived: getBool(data, "archived"),
    totalFocusMinutes: maxf(0, getFloat(data, "total_focus_minutes")),
  });
}
