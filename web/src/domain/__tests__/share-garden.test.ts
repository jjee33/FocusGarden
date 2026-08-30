/**
 * @vitest-environment jsdom
 *
 * The composition, not the rasterising. Canvas is not implemented in jsdom, and
 * mocking it would only assert that the mock was called - what actually needs
 * pinning is the SVG this produces, because every failure mode here is silent:
 * a collided id draws the wrong leaf, an unescaped name breaks the document, and
 * both still return an image.
 */

import { describe, expect, it } from "vitest";

import { buildShareSvg } from "../../app/share-garden.js";
import { ALL_SPECIES } from "../../content/content.js";

const monstera = ALL_SPECIES.find((s) => s.id === "monstera");
const fern = ALL_SPECIES.find((s) => s.id === "boston_fern");

function plant(seed: string, growth: number, species = monstera) {
  return { morphology: species!.morphology!, growth, seed };
}

describe("buildShareSvg", () => {
  it("produces a document at the ratio every platform crops to", () => {
    const svg = buildShareSvg({ plants: [plant("a", 1)], subtitle: "2 hours of focus" });
    expect(svg).toContain('width="1200"');
    expect(svg).toContain('height="630"');
    expect(svg.startsWith("<svg")).toBe(true);
    expect(svg.endsWith("</svg>")).toBe(true);
  });

  it("draws an empty garden without throwing", () => {
    const svg = buildShareSvg({ plants: [], subtitle: "Just getting started" });
    expect(svg).toContain("Just getting started");
    expect(svg).toContain("thefocusgarden.com");
  });

  /*
   * The bug this feature would otherwise have shipped with. Two plants of the
   * same species and seed render byte-identical SVG including their <defs> ids;
   * nested in one document the second reference resolves to the first's shape.
   */
  it("gives every plant its own ids, even when two are identical", () => {
    const svg = buildShareSvg({
      plants: [plant("same", 1), plant("same", 1)],
      subtitle: "two",
    });
    const ids = [...svg.matchAll(/id="([^"]+)"/g)].map((m) => m[1]);
    expect(ids.length).toBeGreaterThan(1);
    expect(new Set(ids).size).toBe(ids.length);
  });

  it("prefixes references as well as definitions, or the rewrite breaks the art", () => {
    const svg = buildShareSvg({ plants: [plant("x", 1), plant("y", 1)], subtitle: "two" });
    const defined = new Set([...svg.matchAll(/id="([^"]+)"/g)].map((m) => m[1]));

    // Only real references. A looser `#(\w+)"` also matches every hex colour in
    // the document and reports fill="#4f8340" as a broken link to an element
    // called 4f8340 - which is how this test first failed, on nothing at all.
    const referenced = [
      ...[...svg.matchAll(/url\(#([^)]+)\)/g)].map((m) => m[1]),
      ...[...svg.matchAll(/(?:xlink:)?href="#([^"]+)"/g)].map((m) => m[1]),
    ];

    expect(referenced.length).toBeGreaterThan(0);
    for (const ref of referenced) expect(defined.has(ref)).toBe(true);
  });

  it("escapes the subtitle, so a name with an ampersand cannot break the document", () => {
    const svg = buildShareSvg({ plants: [], subtitle: 'Josh & "co" <tag>' });
    expect(svg).toContain("Josh &amp; &quot;co&quot; &lt;tag&gt;");
    expect(svg).not.toContain('<tag>');
  });

  it("caps how many plants are drawn, so a large garden is not a smudge", () => {
    const many = Array.from({ length: 40 }, (_, i) => plant(`p${i}`, 1));
    const svg = buildShareSvg({ plants: many, subtitle: "lots" });
    const groups = (svg.match(/<g transform="translate\(/g) ?? []).length;
    expect(groups).toBeLessThanOrEqual(7);
    expect(groups).toBeGreaterThan(0);
  });

  it("scales a plant by how grown it is, so the picture reads as progress", () => {
    // The group is positioned at groundY minus the plant's height, so a taller
    // plant sits at a smaller y. That is the observable consequence of the scale
    // and it is worth asserting directly rather than settling for "the strings
    // differ", which they would even if the size were ignored.
    const topOf = (svg: string): number =>
      Number(/<g transform="translate\(-?\d+ (-?\d+)\)"/.exec(svg)?.[1] ?? NaN);

    const seedling = topOf(buildShareSvg({ plants: [plant("s", 0)], subtitle: "" }));
    const grown = topOf(buildShareSvg({ plants: [plant("s", 1)], subtitle: "" }));

    expect(Number.isNaN(seedling)).toBe(false);
    expect(Number.isNaN(grown)).toBe(false);
    expect(grown).toBeLessThan(seedling);
  });

  it("handles different species side by side", () => {
    const svg = buildShareSvg({
      plants: [plant("a", 1, monstera), plant("b", 0.5, fern)],
      subtitle: "mixed",
    });
    const ids = [...svg.matchAll(/id="([^"]+)"/g)].map((m) => m[1]);
    expect(new Set(ids).size).toBe(ids.length);
  });
});
