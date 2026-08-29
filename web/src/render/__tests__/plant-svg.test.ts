/**
 * Structural tests for the plant renderer.
 *
 * There is no fixture to compare against here - the GDScript painter draws to a
 * canvas, not to markup, so "identical output" is not a thing that can be
 * asserted. What CAN be asserted is everything that makes a procedural renderer
 * fail in production:
 *
 *   - NaN reaching path data. An SVG with `M NaN 12` renders nothing, throws
 *     nothing, and logs nothing. It is the single most likely way this breaks.
 *   - Non-determinism. A plant must look the same on every redraw and every
 *     device, or the garden shimmers as React re-renders.
 *   - Payload size. Instancing was worth 10x; a regression would be invisible
 *     until a garden of thirty plants was assembled.
 *
 * Whether it looks GOOD is not testable here and is not pretended to be. That is
 * what the published prototype is for.
 */

import { describe, expect, it } from "vitest";

import { ALL_SPECIES, ALL_POTS, getPot } from "../../content/content.js";
import { POT_PATTERNS, POT_SHAPES, makePotStyle } from "../../domain/pot.js";
import type { PlantMorphology } from "../../domain/species.js";
import { FLAT_MATERIALS, FULL_MATERIALS, renderPlantSvg } from "../plant-svg.js";

const FORMS = [
  "rosette", "upright", "trailing", "frond", "spike", "succulent", "cactus", "flowering",
] as const;
const LEAF_SHAPES = ["oval", "lance", "heart", "round", "strap", "needle", "split"] as const;
const FLOWER_SHAPES = ["daisy", "spire", "spathe", "cluster"] as const;

/** Growth values chosen to straddle every threshold the painter branches on. */
const GROWTH_STEPS = [0, 0.02, 0.021, 0.1, 0.3, 0.5, 0.549, 0.55, 0.75, 0.751, 0.99, 1];

function morphology(overrides: Partial<PlantMorphology> = {}): PlantMorphology {
  return {
    form: "rosette", leafShape: "oval",
    leafColorBase: "#4A7C3F", leafColorTip: "#7FB069", stemColor: "#5F7F42",
    leafCountMax: 9, leafLengthRatio: 0.45, leafWidthRatio: 0.34,
    leafArc: 0.12, spreadRadians: 0.9,
    variegation: 0, variegationColor: "#E8E4C9",
    hasFlowers: true, flowerShape: "daisy", flowerColor: "#E8C86A",
    flowerCentreColor: "#8A6A3A", flowerCount: 3, swayAmount: 0.05,
    ...overrides,
  };
}

/** Any of these in markup means a shape silently vanished. */
function assertNoBadNumbers(svg: string, label: string): void {
  for (const token of ["NaN", "Infinity", "undefined", "null"]) {
    expect(svg.includes(token), `${label} contains "${token}"`).toBe(false);
  }
}

describe("renderPlantSvg", () => {
  it("renders every shipped species across the whole growth curve without bad numbers", () => {
    for (const species of ALL_SPECIES) {
      if (species.morphology === null) continue;
      for (const growth of GROWTH_STEPS) {
        const svg = renderPlantSvg({
          morphology: species.morphology,
          pot: getPot("terracotta_basic"),
          growth, width: 240, height: 300, seed: species.id,
        });
        assertNoBadNumbers(svg, `${species.id} @ ${growth}`);
        expect(svg.startsWith("<svg"), species.id).toBe(true);
        expect(svg.endsWith("</svg>"), species.id).toBe(true);
      }
    }
  });

  it("renders all 8 forms x 7 leaf shapes x 4 flower shapes cleanly", () => {
    for (const form of FORMS) {
      for (const leafShape of LEAF_SHAPES) {
        for (const flowerShape of FLOWER_SHAPES) {
          const svg = renderPlantSvg({
            morphology: morphology({ form, leafShape, flowerShape, variegation: 0.4 }),
            pot: getPot("terracotta_basic"),
            growth: 1, width: 240, height: 300, seed: `${form}-${leafShape}`,
          });
          assertNoBadNumbers(svg, `${form}/${leafShape}/${flowerShape}`);
        }
      }
    }
  });

  it("renders all 5 pot shapes x 5 patterns cleanly", () => {
    for (const shape of POT_SHAPES) {
      for (const pattern of POT_PATTERNS) {
        const svg = renderPlantSvg({
          morphology: morphology(),
          pot: makePotStyle({ id: "t", displayName: "T", shape, pattern }),
          growth: 1, width: 240, height: 300, seed: `${shape}-${pattern}`,
        });
        assertNoBadNumbers(svg, `${shape}/${pattern}`);
      }
    }
  });

  it("survives a degenerate morphology rather than emitting broken paths", () => {
    const hostile = morphology({
      leafCountMax: 2, leafLengthRatio: 0, leafWidthRatio: 0,
      leafArc: 0, spreadRadians: 0, swayAmount: 0, flowerCount: 1,
    });
    for (const form of FORMS) {
      const svg = renderPlantSvg({
        morphology: { ...hostile, form }, pot: null,
        growth: 1, width: 100, height: 120, seed: "degenerate",
      });
      assertNoBadNumbers(svg, `degenerate ${form}`);
    }
  });

  it("renders with no pot at all", () => {
    const svg = renderPlantSvg({
      morphology: morphology(), pot: null, growth: 1, width: 200, height: 240,
    });
    assertNoBadNumbers(svg, "potless");
    expect(svg).toContain("<svg");
  });

  it("is deterministic for a given seed, and different across seeds", () => {
    const base = { morphology: morphology(), pot: getPot("terracotta_basic"), growth: 0.7, width: 200, height: 250 };
    const a1 = renderPlantSvg({ ...base, seed: "pl_alpha" });
    const a2 = renderPlantSvg({ ...base, seed: "pl_alpha" });
    const b = renderPlantSvg({ ...base, seed: "pl_beta" });
    expect(a1).toBe(a2);
    expect(a1).not.toBe(b);
  });

  it("produces identical output for every seed when variation is off", () => {
    const base = {
      morphology: morphology(), pot: getPot("terracotta_basic"),
      growth: 0.7, width: 200, height: 250,
      materials: { variation: false },
    };
    // The uid still salts the element-id prefix, so compare the geometry only.
    const strip = (svg: string): string => svg.replace(/p[0-9a-z]+(?=[LgfbroscW])/g, "ID");
    expect(strip(renderPlantSvg({ ...base, seed: "one" })))
      .toBe(strip(renderPlantSvg({ ...base, seed: "two" })));
  });

  it("instances leaves rather than repeating path data", () => {
    const svg = renderPlantSvg({
      morphology: morphology({ form: "rosette", leafCountMax: 12 }),
      pot: getPot("terracotta_basic"), growth: 1, width: 240, height: 300, seed: "instancing",
    });
    // Exactly one leaf outline is defined, however many leaves are drawn.
    const leafPaths = svg.match(/<path id="[^"]*L"/g) ?? [];
    const leafUses = svg.match(/<use href="#[^"]*L"/g) ?? [];
    expect(leafPaths).toHaveLength(1);
    expect(leafUses.length).toBeGreaterThan(8);
  });

  it("stays within budget at the sizes a garden actually renders", () => {
    // The budget that matters is the garden, not a single detail view. Thirty
    // plants at 110x140 is the load-bearing case; one fern at 240x300 is not.
    const measure = (w: number, h: number, lod: number) => {
      let worst = 0;
      let worstId = "";
      let total = 0;
      let nodes = 0;
      let counted = 0;
      for (const species of ALL_SPECIES) {
        if (species.morphology === null) continue;
        const svg = renderPlantSvg({
          morphology: species.morphology, pot: getPot("terracotta_basic"),
          growth: 1, width: w, height: h, seed: species.id, lod,
        });
        total += svg.length;
        nodes += (svg.match(/<\w+/g) ?? []).length;
        counted++;
        if (svg.length > worst) {
          worst = svg.length;
          worstId = species.id;
        }
      }
      return { worst, worstId, avg: total / counted, avgNodes: nodes / counted };
    };

    const garden = measure(110, 140, 0.4);
    expect(garden.worst, `garden worst is ${garden.worstId}`).toBeLessThan(10_000);
    expect(garden.avg).toBeLessThan(6_000);
    // DOM node count, not bytes, is what decides whether the garden scrolls at 60fps.
    expect(garden.avgNodes).toBeLessThan(70);
    expect(garden.avg * 30).toBeLessThan(200_000);

    // A single detail view is allowed to be richer. Pre-instancing one specimen
    // measured ~57 KB, so this still catches a regression to per-leaf path data.
    const detail = measure(240, 300, 1);
    expect(detail.worst, `detail worst is ${detail.worstId}`).toBeLessThan(32_000);
    expect(detail.avg).toBeLessThan(12_000);
  });

  it("drops detail at low LOD", () => {
    const base = {
      morphology: morphology({ form: "frond", leafCountMax: 13 }),
      pot: getPot("terracotta_basic"), growth: 1, width: 240, height: 300, seed: "lod",
    };
    const full = renderPlantSvg({ ...base, lod: 1 });
    const low = renderPlantSvg({ ...base, lod: 0.4 });
    const nodes = (svg: string): number => (svg.match(/<\w+/g) ?? []).length;
    // The point of LOD is fewer ELEMENTS. An earlier version only reduced path
    // precision, which left the node count untouched and saved 11% of bytes.
    expect(nodes(low)).toBeLessThan(nodes(full) * 0.7);
    expect(low.length).toBeLessThan(full.length * 0.6);
  });

  it("flat materials emit no gradients, shadow or highlight", () => {
    const base = {
      morphology: morphology(), pot: getPot("terracotta_basic"),
      growth: 1, width: 240, height: 300, seed: "flat",
    };
    const rich = renderPlantSvg({ ...base, materials: FULL_MATERIALS });
    const flat = renderPlantSvg({ ...base, materials: FLAT_MATERIALS });

    expect(rich).toContain("radialGradient");
    expect(rich).toContain("stroke-opacity");
    expect(flat).not.toContain("radialGradient");
    expect(flat).not.toContain("stroke-opacity");
    expect(flat.length).toBeLessThan(rich.length);
  });

  it("suppresses blooms when asked, and before the plant has earned them", () => {
    const flowering = morphology({ form: "flowering", flowerShape: "spire", hasFlowers: true });
    const withBloom = renderPlantSvg({
      morphology: flowering, pot: null, growth: 1, width: 200, height: 250, seed: "b", bloom: true,
    });
    const without = renderPlantSvg({
      morphology: flowering, pot: null, growth: 1, width: 200, height: 250, seed: "b", bloom: false,
    });
    const tooYoung = renderPlantSvg({
      morphology: flowering, pot: null, growth: 0.5, width: 200, height: 250, seed: "b", bloom: true,
    });
    expect(withBloom.length).toBeGreaterThan(without.length);
    expect(withBloom.length).toBeGreaterThan(tooYoung.length);
  });

  it("draws a bare shoot at seed stage and real foliage just past it", () => {
    const base = { morphology: morphology(), pot: getPot("terracotta_basic"), width: 200, height: 250, seed: "s" };
    const seedStage = renderPlantSvg({ ...base, growth: 0.02 });
    const sprouted = renderPlantSvg({ ...base, growth: 0.03 });
    expect(seedStage).not.toContain("<use href=");
    expect(sprouted).toContain("<use href=");
  });

  it("every shipped pot renders", () => {
    for (const pot of ALL_POTS) {
      const svg = renderPlantSvg({
        morphology: morphology(), pot, growth: 1, width: 200, height: 250, seed: pot.id,
      });
      assertNoBadNumbers(svg, pot.id);
    }
  });
});
