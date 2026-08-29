/**
 * The player's curated display shelf. Port of models/shelf_layout.gd.
 *
 * Plant placement is NOT stored here - each PlantInstance owns its own
 * `shelfSlot`. Keeping placement in one place means the shelf and the plant can
 * never disagree about where something is. This holds only styling and
 * decorations.
 */

import { clampi } from "./gd.js";
import type { Json } from "./dict-util.js";
import { getDict, getInt, getString } from "./dict-util.js";
import { generate } from "./uid.js";

export interface ShelfLayout {
  layoutId: string;
  displayName: string;
  styleId: string;
  backgroundId: string;
  lightingId: string;
  slotCount: number;
  /** Decorations keyed by slot index, as a string key. */
  decorations: Record<string, unknown>;
}

export function makeShelfLayout(overrides: Partial<ShelfLayout> = {}): ShelfLayout {
  return {
    layoutId: "", displayName: "My Shelf", styleId: "warm_oak",
    backgroundId: "cozy_wall", lightingId: "soft_afternoon",
    slotCount: 8, decorations: {},
    ...overrides,
  };
}

export function createShelfLayout(name = "My Shelf", nowUnixUtc = Date.now() / 1000): ShelfLayout {
  return makeShelfLayout({ layoutId: generate("sh", nowUnixUtc), displayName: name });
}

export function shelfLayoutToDict(s: ShelfLayout): Json {
  return {
    layout_id: s.layoutId,
    display_name: s.displayName,
    style_id: s.styleId,
    background_id: s.backgroundId,
    lighting_id: s.lightingId,
    slot_count: s.slotCount,
    decorations: { ...s.decorations },
  };
}

export function shelfLayoutFromDict(data: Json): ShelfLayout {
  return makeShelfLayout({
    layoutId: getString(data, "layout_id"),
    displayName: getString(data, "display_name", "My Shelf"),
    styleId: getString(data, "style_id", "warm_oak"),
    backgroundId: getString(data, "background_id", "cozy_wall"),
    lightingId: getString(data, "lighting_id", "soft_afternoon"),
    slotCount: clampi(getInt(data, "slot_count", 8), 1, 64),
    decorations: getDict(data, "decorations"),
  });
}
