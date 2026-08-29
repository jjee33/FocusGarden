/**
 * The language differences themselves, pinned against the real engine.
 *
 * These are tested separately from the formulas that use them. Every current call
 * site passes non-negative values, where floor and trunc agree and where both
 * rounding rules agree - so porting `floorToInt` as `Math.trunc` passes the entire
 * fidelity suite today. It was verified that it does: injecting that exact fault
 * left all 29 fidelity tests green, while the same experiment caught the `posmod`
 * fault immediately.
 *
 * The first call site that ever hands one of these a negative number would then be
 * silently wrong, in save data, with no test to say so. Hence this file.
 */

import { describe, expect, it } from "vitest";

import fixture from "../__fixtures__/gd_semantics.json";
import { ceilToInt, floorToInt, gdRound, intdiv, posmod, toInt } from "../gd.js";

describe("GDScript numeric semantics", () => {
  it(`posmod over ${fixture.posmod.length} pairs, incl. negatives where JS % differs`, () => {
    for (const c of fixture.posmod) {
      expect(posmod(c.a, c.b), `posmod(${c.a}, ${c.b})`).toBe(c.out);
    }
  });

  it(`integer division truncates toward zero over ${fixture.int_division.length} pairs`, () => {
    for (const c of fixture.int_division) {
      expect(intdiv(c.a, c.b), `intdiv(${c.a}, ${c.b})`).toBe(c.out);
    }
  });

  it("int() casts truncate toward zero", () => {
    for (const c of fixture.int_cast) {
      expect(toInt(c.value), `toInt(${c.value})`).toBe(c.out);
    }
  });

  it("int(floor(x)) rounds down, which is NOT the same as truncating", () => {
    for (const c of fixture.floor_to_int) {
      expect(floorToInt(c.value), `floorToInt(${c.value})`).toBe(c.out);
    }
  });

  it("int(ceil(x)) rounds up", () => {
    for (const c of fixture.ceil_to_int) {
      expect(ceilToInt(c.value), `ceilToInt(${c.value})`).toBe(c.out);
    }
  });

  it("round() breaks ties away from zero, unlike Math.round", () => {
    for (const c of fixture.round) {
      expect(gdRound(c.value), `gdRound(${c.value})`).toBe(c.out);
    }
  });

  it("documents the three traps explicitly, for anyone reading this later", () => {
    // JavaScript's remainder keeps the sign of the dividend.
    expect(-1 % 4).toBe(-1);
    expect(posmod(-1, 4)).toBe(3);

    // Math.round sends -0.5 up to -0; GDScript sends it away from zero to -1.
    expect(Math.round(-0.5)).toBe(-0);
    expect(gdRound(-0.5)).toBe(-1);

    // trunc and floor part company below zero.
    expect(Math.trunc(-2.7)).toBe(-2);
    expect(floorToInt(-2.7)).toBe(-3);
  });
});
