/**
 * Layout rules jsdom cannot measure, held as declarations.
 *
 * jsdom has no layout engine, so these assert the CSS that produces the
 * behaviour rather than the behaviour. Each was found by measuring the built
 * app in Chromium at phone size; the comment beside each rule in app.css says
 * what it measured.
 */

import { describe, expect, it } from "vitest";
// The project's tsconfig is the browser's and carries no Node types; this file
// runs under Vitest in Node. (A `?raw` import does not work here: Vitest stubs
// CSS modules to an empty string.)
// @ts-expect-error -- node:fs has no type declarations in this project.
import { readFileSync } from "node:fs";

const css: string = readFileSync(new URL("../app.css", import.meta.url), "utf8");

/** The body of the first rule whose selector is exactly `selector`. */
function rule(selector: string): string {
  const escaped = selector.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = new RegExp(`(?:^|\\n)${escaped}\\s*\\{([^}]*)\\}`).exec(css);
  if (match === null) throw new Error(`no rule for ${selector}`);
  return match[1]!;
}

describe("the phone tab bar", () => {
  it("is pinned to the bottom of the viewport, not left after the content", () => {
    // The document scrolls on a phone, so an unpinned bar sat below every long
    // screen: off-screen on four of five screens at 390x844.
    const body = rule(".tabbar");
    expect(body).toMatch(/position:\s*sticky/);
    expect(body).toMatch(/bottom:\s*0/);
  });
});
