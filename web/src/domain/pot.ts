/**
 * A pot design. Port of models/pot_style.gd.
 *
 * Pots are drawn from these parameters, matching the terracotta, glazed ceramic
 * and woven baskets in the reference art. Data-driven so new pots are content,
 * not code.
 */

import type { Requirement } from "./requirement.js";

export const POT_SHAPES = ["tapered", "rounded", "cylinder", "bowl", "basket"] as const;
export type PotShape = (typeof POT_SHAPES)[number];

export const POT_PATTERNS = ["none", "bands", "chevron", "dots", "weave"] as const;
export type PotPattern = (typeof POT_PATTERNS)[number];

/** The pot every plant starts in. Must exist in the content set. */
export const DEFAULT_POT_ID = "terracotta_basic";

export interface PotStyle {
  id: string;
  displayName: string;
  shape: PotShape;
  pattern: PotPattern;
  bodyColor: string;
  rimColor: string;
  accentColor: string;
  soilColor: string;
  /** Width at the rim, as a multiple of pot height. */
  topWidthRatio: number;
  /** Width at the base. Narrower than the top gives the classic tapered pot. */
  bottomWidthRatio: number;
  /** Condition to make this pot selectable. Null means available from the start. */
  unlockRequirement: Requirement | null;
}

export function makePotStyle(overrides: Partial<PotStyle> = {}): PotStyle {
  return {
    id: "", displayName: "", shape: "tapered", pattern: "none",
    bodyColor: "#C26A45", rimColor: "#A9563A", accentColor: "#E8C9A0", soilColor: "#4A3B2A",
    topWidthRatio: 1.05, bottomWidthRatio: 0.78, unlockRequirement: null,
    ...overrides,
  };
}

export function isValidPot(pot: PotStyle): boolean {
  return pot.id !== "" && pot.displayName !== "";
}
