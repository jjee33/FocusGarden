/**
 * The idle heading, held to the desktop's boundaries (home_screen.gd).
 */

import { describe, expect, it } from "vitest";

import { greetingForHour } from "../greeting.js";

describe("greetingForHour", () => {
  it("matches the desktop's noon and six o'clock boundaries", () => {
    expect(greetingForHour(0)).toBe("Good morning");
    expect(greetingForHour(11)).toBe("Good morning");
    expect(greetingForHour(12)).toBe("Good afternoon");
    expect(greetingForHour(17)).toBe("Good afternoon");
    expect(greetingForHour(18)).toBe("Good evening");
    expect(greetingForHour(23)).toBe("Good evening");
  });
});
