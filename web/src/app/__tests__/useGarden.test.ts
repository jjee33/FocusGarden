// @vitest-environment jsdom
/**
 * The completion chain, at the app layer.
 *
 * The individual rules are already pinned against the engine in the fidelity
 * suite. What is tested here is that they are wired together in the right order
 * and that the numbers land on the right records - which is exactly what was
 * never covered when the fake idempotency guard shipped.
 */

import { act, renderHook } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { useGarden } from "../useGarden.js";
import { Completion, Kind } from "../../domain/focus-session.js";
import { levelForXp } from "../../domain/xp-formula.js";

function plantOf(result: { current: ReturnType<typeof useGarden> }, uid: string) {
  return result.current.save.plants.find((p) => p.uid === uid)!;
}

describe("useGarden", () => {
  it("seeds a plausible garden from the real content set", () => {
    const { result } = renderHook(() => useGarden());
    expect(result.current.save.plants.length).toBeGreaterThan(0);
    // Every seeded plant must name a species that actually exists, or it silently
    // vanishes from every screen - the bug that hid the Monstera on the focus card.
    expect(result.current.summaries).toHaveLength(result.current.save.plants.length);
    expect(result.current.activePlant).not.toBeNull();
  });

  it("credits a completed session and grows the active plant", () => {
    const { result } = renderHook(() => useGarden());
    const before = plantOf(result, "pl_monstera");
    const xpBefore = result.current.save.profile.totalXp;

    act(() => {
      result.current.completeSession(
        Kind.FOCUS, 25, 25, Completion.COMPLETED, "p_networkplus", "pl_monstera",
      );
    });

    const after = plantOf(result, "pl_monstera");
    expect(after.accumulatedFocusMinutes).toBe(before.accumulatedFocusMinutes + 25);
    // 2 XP per focus minute, flat. No multipliers, ever.
    expect(result.current.save.profile.totalXp).toBe(xpBefore + 50);
    expect(after.contributingSessionIds.length).toBe(
      before.contributingSessionIds.length + 1,
    );
  });

  it("gives a cancelled session no credit but still keeps the record", () => {
    const { result } = renderHook(() => useGarden());
    const before = plantOf(result, "pl_monstera");
    const xpBefore = result.current.save.profile.totalXp;
    const sessionsBefore = result.current.sessions.length;

    act(() => {
      result.current.completeSession(
        Kind.FOCUS, 25, 20, Completion.CANCELLED, "p_networkplus", "pl_monstera",
      );
    });

    expect(plantOf(result, "pl_monstera").accumulatedFocusMinutes)
      .toBe(before.accumulatedFocusMinutes);
    expect(result.current.save.profile.totalXp).toBe(xpBefore);
    // Never silently lose a record: the row is kept for analytics either way.
    expect(result.current.sessions.length).toBe(sessionsBefore + 1);
  });

  it("caps a completed session at its intended duration", () => {
    // The raw measurement overshoots by whatever fraction of a tick elapsed past
    // the finish line, which would record a "25 minute" session as 25.02.
    const { result } = renderHook(() => useGarden());
    const before = plantOf(result, "pl_monstera");

    act(() => {
      result.current.completeSession(
        Kind.FOCUS, 25, 25.4, Completion.COMPLETED, "p_networkplus", "pl_monstera",
      );
    });

    expect(plantOf(result, "pl_monstera").accumulatedFocusMinutes)
      .toBe(before.accumulatedFocusMinutes + 25);
  });

  it("grows no plant from a break, but still awards its token XP", () => {
    const { result } = renderHook(() => useGarden());
    const before = plantOf(result, "pl_monstera");
    const xpBefore = result.current.save.profile.totalXp;

    act(() => {
      result.current.completeSession(
        Kind.SHORT_BREAK, 5, 5, Completion.COMPLETED, "p_networkplus", "pl_monstera",
      );
    });

    expect(plantOf(result, "pl_monstera").accumulatedFocusMinutes)
      .toBe(before.accumulatedFocusMinutes);
    // 0.25 XP per break minute: resting is rewarded, but must not compete with
    // focusing as an XP source.
    expect(result.current.save.profile.totalXp).toBe(xpBefore + 1);
  });

  it("advances the cycle only on a completed focus session", () => {
    const { result } = renderHook(() => useGarden());
    const before = result.current.save.profile.focusSessionsInCycle;

    act(() => {
      result.current.completeSession(
        Kind.FOCUS, 25, 25, Completion.ENDED_EARLY, "p", "pl_monstera",
      );
    });
    expect(result.current.save.profile.focusSessionsInCycle).toBe(before);

    act(() => {
      result.current.completeSession(
        Kind.FOCUS, 25, 25, Completion.COMPLETED, "p", "pl_monstera",
      );
    });
    expect(result.current.save.profile.focusSessionsInCycle).toBe(before + 1);
  });

  it("keeps the derived level in step with total XP", () => {
    const { result } = renderHook(() => useGarden());
    expect(result.current.stats.level)
      .toBe(levelForXp(result.current.save.profile.totalXp));

    act(() => {
      result.current.completeSession(
        Kind.FOCUS, 90, 90, Completion.COMPLETED, "p", "pl_monstera",
      );
    });
    expect(result.current.stats.level)
      .toBe(levelForXp(result.current.save.profile.totalXp));
  });

  it("treats two completions as two sessions, because that is what they are", () => {
    // The note this replaces said the app was not idempotent yet, and promised to
    // invert when the real gate landed. It has, so here is the honest position.
    //
    // Two calls to completeSession are two DIFFERENT sessions and must award
    // twice - anything else would lose someone's second pomodoro. The gate the
    // pipeline adds protects against re-applying THE SAME record, which is the
    // replay and recovery case, and is tested directly in session-pipeline.test.ts.
    const { result } = renderHook(() => useGarden());
    const xpBefore = result.current.save.profile.totalXp;
    const sessionsBefore = result.current.sessions.length;

    act(() => {
      result.current.completeSession(Kind.FOCUS, 25, 25, Completion.COMPLETED, "p", "pl_monstera");
    });
    act(() => {
      result.current.completeSession(Kind.FOCUS, 25, 25, Completion.COMPLETED, "p", "pl_monstera");
    });

    expect(result.current.save.profile.totalXp).toBe(xpBefore + 100);
    expect(result.current.sessions.length).toBe(sessionsBefore + 2);
    // Every recorded session carries the gate, so a later replay of either one
    // cannot award it again.
    expect(result.current.sessions.every((s) => s.awardsApplied)).toBe(true);
  });

  it("runs the real pipeline, not an inline chain", () => {
    // Reaching a level threshold must grant its unlock, which only the pipeline
    // does. If this passes, useGarden is genuinely delegating rather than
    // reimplementing the parts it happens to need.
    const { result } = renderHook(() => useGarden());
    act(() => {
      result.current.completeSession(Kind.FOCUS, 90, 90, Completion.COMPLETED, "p", "pl_monstera");
    });
    expect(result.current.save.profile.unlockedIds.length).toBeGreaterThan(0);
    expect(result.current.lastOutcome?.applied).toBe(true);
  });

  it("places a plant in the garden and turns it without tipping it over", () => {
    const { result } = renderHook(() => useGarden());

    act(() => result.current.placeInGarden("pl_fern", 3, 2));
    const placed = plantOf(result, "pl_fern");
    expect(placed.gardenCellX).toBe(3);
    expect(placed.gardenCellY).toBe(2);
    // The placement invariant: a plant is in exactly one place.
    expect(placed.shelfSlot).toBe(-1);

    act(() => result.current.rotatePlant("pl_fern"));
    expect(plantOf(result, "pl_fern").gardenRotation).toBe(1);
    act(() => result.current.rotatePlant("pl_fern"));
    act(() => result.current.rotatePlant("pl_fern"));
    act(() => result.current.rotatePlant("pl_fern"));
    // Wraps rather than running to 4, via posmod.
    expect(plantOf(result, "pl_fern").gardenRotation).toBe(0);
  });
});
