/**
 * The completion chain.
 *
 * The individual rules are pinned against the engine elsewhere. What is tested
 * here is the two things a pipeline exists to guarantee and a set of listeners
 * cannot: that the steps run in the right ORDER, and that running the whole thing
 * twice changes nothing.
 *
 * The second one is not hypothetical. The first web implementation claimed a
 * guard that could never fire, and shipped. These tests exist so that cannot
 * happen quietly again.
 */

import { describe, expect, it } from "vitest";

import { LEVEL_UNLOCKS, applySession } from "../session-pipeline.js";
import type { PipelineContent, PipelineState } from "../session-pipeline.js";
import { Completion, Kind, makeFocusSession } from "../focus-session.js";
import type { FocusSession } from "../focus-session.js";
import { makePlayerProfile } from "../player-profile.js";
import { makeGameSettings } from "../game-settings.js";
import { makePlantInstance, Maturity } from "../plant-instance.js";
import { makeGardenLayout } from "../garden-layout.js";
import { makePlantSpecies } from "../species.js";
import { makeRequirement } from "../requirement.js";
import { JournalKind } from "../journal-entry.js";
import type { AchievementDef, GardenExpansion } from "../../content/content.js";

const SPECIES = makePlantSpecies({
  id: "fixture_species",
  displayName: "Fixture Fern",
  stageCount: 3,
  growthRequirement: makeRequirement("total_focus_minutes", { amount: 100 }, "active_plant"),
});

const ACHIEVEMENTS: AchievementDef[] = [
  {
    id: "first_hour", title: "First hour", description: "Focus for an hour.",
    category: "focus", rarity: "common", hidden: false, trackProgress: true,
    requirement: makeRequirement("total_focus_minutes", { amount: 60 }),
  },
  {
    id: "century", title: "Century", description: "Focus for a hundred hours.",
    category: "focus", rarity: "legendary", hidden: false, trackProgress: true,
    requirement: makeRequirement("total_focus_minutes", { amount: 6000 }),
  },
];

const EXPANSIONS: GardenExpansion[] = [
  {
    id: "plot_two", displayName: "A wider bed", description: "More room to grow.",
    gridWidth: 6, gridHeight: 4, unlocksDecorations: [],
    requirement: makeRequirement("total_focus_minutes", { amount: 50 }),
  },
];

function content(overrides: Partial<PipelineContent> = {}): PipelineContent {
  return {
    getSpecies: (id) => (id === SPECIES.id ? SPECIES : null),
    achievements: ACHIEVEMENTS,
    expansions: EXPANSIONS,
    speciesTotal: 16,
    ...overrides,
  };
}

function state(overrides: Partial<PipelineState> = {}): PipelineState {
  return {
    profile: makePlayerProfile({ activePlantUid: "pl_1" }),
    settings: makeGameSettings(),
    plants: [makePlantInstance({ uid: "pl_1", speciesId: SPECIES.id })],
    sessions: [],
    catalogue: [],
    achievements: [],
    journal: [],
    garden: makeGardenLayout(),
    expeditions: {},
    ...overrides,
  };
}

function session(overrides: Partial<FocusSession> = {}): FocusSession {
  return makeFocusSession({
    id: "s_1", kind: Kind.FOCUS, completion: Completion.COMPLETED,
    actualFocusMinutes: 25, intendedDurationMinutes: 25,
    dateKey: "2026-08-29", plantUid: "pl_1",
    ...overrides,
  });
}

describe("applySession", () => {
  it("credits, grows and awards in one pass", () => {
    const s = state();
    const focus = session();
    const outcome = applySession(s, focus, content(), 1_800_000_000);

    expect(outcome.applied).toBe(true);
    expect(outcome.creditedMinutes).toBe(25);
    expect(outcome.xpAwarded).toBe(50);
    expect(s.profile.totalXp).toBe(50);
    expect(s.plants[0]!.accumulatedFocusMinutes).toBe(25);
    expect(s.plants[0]!.contributingSessionIds).toEqual(["s_1"]);
    expect(s.sessions).toHaveLength(1);
  });

  it("IS IDEMPOTENT: re-running the whole chain changes nothing", () => {
    // The guarantee the previous implementation claimed and did not have. The
    // gate is awardsApplied on the record, which persists with it, so a replayed
    // event or a recovered session cannot award twice.
    const s = state();
    const focus = session();
    const c = content();

    const first = applySession(s, focus, c, 1_800_000_000);
    const snapshot = {
      xp: s.profile.totalXp,
      minutes: s.plants[0]!.accumulatedFocusMinutes,
      sessions: s.sessions.length,
      journal: s.journal.length,
      unlocks: [...s.profile.unlockedIds],
      cycle: s.profile.focusSessionsInCycle,
    };

    const second = applySession(s, focus, c, 1_800_000_000);

    expect(first.applied).toBe(true);
    expect(second.applied).toBe(false);
    expect(second.skippedReason).toBe("Awards already applied to this session.");
    expect(s.profile.totalXp).toBe(snapshot.xp);
    expect(s.plants[0]!.accumulatedFocusMinutes).toBe(snapshot.minutes);
    expect(s.sessions).toHaveLength(snapshot.sessions);
    expect(s.journal).toHaveLength(snapshot.journal);
    expect(s.profile.unlockedIds).toEqual(snapshot.unlocks);
    expect(s.profile.focusSessionsInCycle).toBe(snapshot.cycle);
  });

  it("keeps the record but awards nothing for a cancelled session", () => {
    const s = state();
    const outcome = applySession(
      s, session({ completion: Completion.CANCELLED }), content(), 1_800_000_000,
    );
    expect(outcome.applied).toBe(true);
    expect(outcome.skippedReason).toBe("Session earned no credit.");
    expect(s.profile.totalXp).toBe(0);
    expect(s.plants[0]!.accumulatedFocusMinutes).toBe(0);
    // Legitimately focused time is never silently lost, and the row is wanted for
    // analytics either way.
    expect(s.sessions).toHaveLength(1);
  });

  it("does not grow a plant from a session below the credit threshold", () => {
    const s = state({ settings: makeGameSettings({ minimumCreditMinutes: 10 }) });
    applySession(s, session({ actualFocusMinutes: 5 }), content(), 1_800_000_000);
    expect(s.plants[0]!.accumulatedFocusMinutes).toBe(0);
    // But the time still earns XP: below the threshold is not the same as wasted.
    expect(s.profile.totalXp).toBe(10);
  });

  it("evaluates achievements AFTER the XP and minutes land, not before", () => {
    // The ordering the pipeline exists to guarantee. "First hour" needs 60
    // minutes; a single 60-minute session must unlock it in the same pass, which
    // it cannot do if achievements are evaluated from stale aggregates.
    const s = state();
    const outcome = applySession(
      s, session({ actualFocusMinutes: 60 }), content(), 1_800_000_000,
    );
    expect(outcome.unlockedAchievementIds).toContain("first_hour");
    expect(outcome.unlockedAchievementIds).not.toContain("century");
    expect(s.achievements.find((a) => a.achievementId === "first_hour")?.unlocked).toBe(true);
    expect(s.journal.some((j) => j.kind === JournalKind.ACHIEVEMENT_UNLOCKED)).toBe(true);
  });

  it("caches partial achievement progress without unlocking", () => {
    const s = state();
    applySession(s, session({ actualFocusMinutes: 30 }), content(), 1_800_000_000);
    const state30 = s.achievements.find((a) => a.achievementId === "first_hour")!;
    expect(state30.unlocked).toBe(false);
    expect(state30.progressRatio).toBeCloseTo(0.5, 6);
  });

  it("matures a plant once: clears the target, discovers the species, writes the journal", () => {
    const s = state();
    const outcome = applySession(
      s, session({ actualFocusMinutes: 100 }), content(), 1_800_000_000,
    );

    expect(outcome.plantMatured).toBe(true);
    expect(s.plants[0]!.maturity).toBe(Maturity.MATURE);
    // A finished plant stops being the growth target, or the next session pours
    // time into something already complete.
    expect(s.profile.activePlantUid).toBe("");
    expect(outcome.speciesDiscovered).toBe(true);
    expect(s.catalogue[0]!.timesGrown).toBe(1);
    expect(s.catalogue[0]!.fastestGrowthMinutes).toBe(100);
    expect(s.journal.some((j) => j.kind === JournalKind.PLANT_MATURED)).toBe(true);
  });

  it("grants level unlocks by convergence, never twice", () => {
    const s = state();
    // Enough for several levels at once; each threshold below the new level must
    // be granted, not just the one landed on.
    applySession(s, session({ actualFocusMinutes: 400 }), content(), 1_800_000_000);

    expect(s.profile.unlockedIds).toContain(LEVEL_UNLOCKS[2]);
    expect(s.profile.unlockedIds).toContain(LEVEL_UNLOCKS[3]);
    const afterFirst = [...s.profile.unlockedIds];

    applySession(
      s, session({ id: "s_2", actualFocusMinutes: 30 }), content(), 1_800_000_000,
    );
    // The second pass re-runs the same convergence and must add nothing already held.
    expect(new Set(s.profile.unlockedIds).size).toBe(s.profile.unlockedIds.length);
    for (const id of afterFirst) expect(s.profile.unlockedIds).toContain(id);
  });

  it("grows the plot when an expansion is earned, and never shrinks it", () => {
    const s = state();
    const outcome = applySession(
      s, session({ actualFocusMinutes: 60 }), content(), 1_800_000_000,
    );
    expect(outcome.newlyUnlockedExpansionIds).toContain("plot_two");
    expect(s.garden.gridWidth).toBe(6);
    expect(s.garden.gridHeight).toBe(4);

    // Re-running must not re-grant, and a later pass must not take ground away.
    applySession(s, session({ id: "s_2", actualFocusMinutes: 5 }), content(), 1_800_000_000);
    expect(s.garden.unlockedExpansionIds).toEqual(["plot_two"]);
    expect(s.garden.gridWidth).toBe(6);
  });

  it("advances the cycle only on a completed focus session", () => {
    const s = state();
    applySession(
      s, session({ completion: Completion.ENDED_EARLY }), content(), 1_800_000_000,
    );
    expect(s.profile.focusSessionsInCycle).toBe(0);

    applySession(s, session({ id: "s_2" }), content(), 1_800_000_000);
    expect(s.profile.focusSessionsInCycle).toBe(1);
  });

  it("keeps a plant whose species vanished in a content update", () => {
    const s = state();
    const outcome = applySession(
      s, session(), content({ getSpecies: () => null }), 1_800_000_000,
    );
    // The plant is not deleted and not grown; the session still counts for XP.
    expect(s.plants).toHaveLength(1);
    expect(outcome.growth).toBeNull();
    expect(outcome.xpAwarded).toBe(50);
  });

  it("awards a break its token XP and grows nothing", () => {
    const s = state();
    const outcome = applySession(
      s, session({ kind: Kind.SHORT_BREAK, actualFocusMinutes: 5 }), content(), 1_800_000_000,
    );
    expect(outcome.xpAwarded).toBe(1);
    expect(s.plants[0]!.accumulatedFocusMinutes).toBe(0);
  });
});
