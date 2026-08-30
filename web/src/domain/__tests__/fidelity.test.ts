/**
 * The fidelity harness: every case here was produced by the real Godot engine
 * running the real GDScript, via tools/export_domain_fixtures.gd.
 *
 * These tests do not assert what the behaviour OUGHT to be. They assert that the
 * TypeScript port produces byte-identical answers to the desktop app for ~3,900
 * inputs, including the ones nobody would think to write a test for. A failure
 * here means the two clients would disagree about a player's garden.
 *
 * Hand-written tests live alongside these in behaviour.test.ts. Both layers stay:
 * these catch divergence, those document intent.
 */

import { describe, expect, it } from "vitest";

import xpFixture from "../__fixtures__/xp_formula.json";
import creditFixture from "../__fixtures__/session_credit.json";
import cycleFixture from "../__fixtures__/session_cycle.json";
import timeFixture from "../__fixtures__/time_util.json";
import growthFixture from "../__fixtures__/plant_growth.json";
import requirementFixture from "../__fixtures__/requirements.json";
import streakFixture from "../__fixtures__/streak.json";
import modelFixture from "../__fixtures__/models.json";

import * as Xp from "../xp-formula.js";
import * as Credit from "../session-credit.js";
import * as Cycle from "../session-cycle.js";
import * as T from "../time-util.js";
import * as Growth from "../plant-growth.js";
import * as Evaluator from "../requirement-evaluator.js";
import * as Streak from "../streak-calculator.js";

import type { Completion, Kind } from "../focus-session.js";
import { focusSessionFromDict, focusSessionToDict, makeFocusSession } from "../focus-session.js";
import { plantInstanceFromDict, plantInstanceToDict, makePlantInstance, Maturity } from "../plant-instance.js";
import { playerProfileFromDict, playerProfileToDict } from "../player-profile.js";
import { makeRequirement, requirementScopeFromOrdinal, requirementTypeFromOrdinal } from "../requirement.js";
import { makeRequirementContext } from "../requirement-context.js";
import { makePlantSpecies } from "../species.js";

/**
 * Floats crossed a JSON boundary, so exact bit equality is not the right test;
 * anything looser than this would let a real formula difference through.
 */
const EPSILON = 1e-9;

function closeEnough(actual: number, expected: number): boolean {
  if (Number.isNaN(actual) || Number.isNaN(expected)) return false;
  return Math.abs(actual - expected) <= EPSILON;
}

/** Reports the offending case rather than just "expected 3, got 4". */
function check(condition: boolean, label: string, actual: unknown, expected: unknown): void {
  if (!condition) {
    throw new Error(
      `${label}\n  expected: ${JSON.stringify(expected)}\n  actual:   ${JSON.stringify(actual)}`,
    );
  }
}

function checkNumber(actual: number, expected: number, label: string): void {
  check(closeEnough(actual, expected), label, actual, expected);
}

// ---------------------------------------------------------------------------

describe("XpFormula", () => {
  it("matches the engine's constants", () => {
    const c = xpFixture.constants;
    expect(Xp.XP_PER_FOCUS_MINUTE).toBe(c.XP_PER_FOCUS_MINUTE);
    expect(Xp.XP_PER_BREAK_MINUTE).toBe(c.XP_PER_BREAK_MINUTE);
    expect(Xp.LINEAR_TERM).toBe(c.LINEAR_TERM);
    expect(Xp.QUADRATIC_TERM).toBe(c.QUADRATIC_TERM);
    expect(Xp.MAX_LEVEL).toBe(c.MAX_LEVEL);
  });

  it(`cumulativeXpForLevel over ${xpFixture.cumulative_xp_for_level.length} levels`, () => {
    for (const c of xpFixture.cumulative_xp_for_level) {
      checkNumber(Xp.cumulativeXpForLevel(c.level), c.out, `cumulativeXpForLevel(${c.level})`);
    }
  });

  it(`levelForXp over ${xpFixture.level_for_xp.length} XP values, incl. every threshold edge`, () => {
    for (const c of xpFixture.level_for_xp) {
      checkNumber(Xp.levelForXp(c.total_xp), c.out, `levelForXp(${c.total_xp})`);
    }
  });

  it(`levelProgress over ${xpFixture.level_progress.length} XP values`, () => {
    for (const c of xpFixture.level_progress) {
      const p = Xp.levelProgress(c.total_xp);
      checkNumber(p.earnedInLevel, c.earned_in_level, `levelProgress(${c.total_xp}).earnedInLevel`);
      checkNumber(p.levelSpan, c.level_span, `levelProgress(${c.total_xp}).levelSpan`);
      checkNumber(Xp.levelProgressRatio(c.total_xp), c.ratio, `levelProgressRatio(${c.total_xp})`);
    }
  });

  it(`xpForSession over ${xpFixture.xp_for_session.length} session shapes`, () => {
    for (const c of xpFixture.xp_for_session) {
      const session = makeFocusSession({
        kind: c.kind as Kind,
        completion: c.completion as Completion,
        actualFocusMinutes: c.actual_focus_minutes,
      });
      checkNumber(
        Xp.xpForSession(session), c.out,
        `xpForSession(kind=${c.kind}, completion=${c.completion}, min=${c.actual_focus_minutes})`,
      );
    }
  });
});

describe("SessionCredit", () => {
  it(`settle over ${creditFixture.settle.length} combinations`, () => {
    for (const c of creditFixture.settle) {
      checkNumber(
        Credit.settle(c.completion as Completion, c.raw_minutes, c.intended_minutes), c.out,
        `settle(${c.completion}, ${c.raw_minutes}, ${c.intended_minutes})`,
      );
    }
  });

  it(`settleRecovered over ${creditFixture.settle_recovered.length} combinations`, () => {
    for (const c of creditFixture.settle_recovered) {
      checkNumber(
        Credit.settleRecovered(c.raw_minutes, c.intended_minutes), c.out,
        `settleRecovered(${c.raw_minutes}, ${c.intended_minutes})`,
      );
    }
  });

  it(`earnsPlantGrowth over ${creditFixture.earns_plant_growth.length} combinations`, () => {
    for (const c of creditFixture.earns_plant_growth) {
      const actual = Credit.earnsPlantGrowth(c.kind as Kind, c.credited_minutes, c.minimum_minutes);
      check(actual === c.out,
        `earnsPlantGrowth(${c.kind}, ${c.credited_minutes}, ${c.minimum_minutes})`, actual, c.out);
    }
  });
});

describe("SessionCycle", () => {
  it(`nextBreakKind over ${cycleFixture.next_break_kind.length} combinations`, () => {
    for (const c of cycleFixture.next_break_kind) {
      checkNumber(
        Cycle.nextBreakKind(c.completed_in_cycle, c.sessions_before_long), c.out,
        `nextBreakKind(${c.completed_in_cycle}, ${c.sessions_before_long})`,
      );
    }
  });

  it(`position over ${cycleFixture.position.length} combinations`, () => {
    for (const c of cycleFixture.position) {
      checkNumber(
        Cycle.position(c.completed_in_cycle, c.sessions_before_long), c.out,
        `position(${c.completed_in_cycle}, ${c.sessions_before_long})`,
      );
    }
  });

  it("shouldAdvance over every kind and completion", () => {
    for (const c of cycleFixture.should_advance) {
      const actual = Cycle.shouldAdvance(c.kind as Kind, c.completion as Completion);
      check(actual === c.out, `shouldAdvance(${c.kind}, ${c.completion})`, actual, c.out);
    }
  });
});

describe("TimeUtil", () => {
  it(`formatDuration over ${timeFixture.format_duration.length} values`, () => {
    for (const c of timeFixture.format_duration) {
      const actual = T.formatDuration(c.total_minutes);
      check(actual === c.out, `formatDuration(${c.total_minutes})`, actual, c.out);
    }
  });

  it(`formatCountdown over ${timeFixture.format_countdown.length} values`, () => {
    for (const c of timeFixture.format_countdown) {
      const actual = T.formatCountdown(c.total_seconds);
      check(actual === c.out, `formatCountdown(${c.total_seconds})`, actual, c.out);
    }
  });

  it(`daysBetween over ${timeFixture.days_between.length} key pairs, incl. malformed`, () => {
    for (const c of timeFixture.days_between) {
      const actual = T.daysBetween(c.from_key, c.to_key);
      check(actual === c.out, `daysBetween(${JSON.stringify(c.from_key)}, ${JSON.stringify(c.to_key)})`,
        actual, c.out);
    }
  });

  it("isValidDateKey rejects rollover dates JavaScript would accept", () => {
    for (const c of timeFixture.is_valid_date_key) {
      const actual = T.isValidDateKey(c.key);
      check(actual === c.out, `isValidDateKey(${JSON.stringify(c.key)})`, actual, c.out);
    }
  });

  it(`formatDateKey over ${timeFixture.format_date_key.length} keys`, () => {
    for (const c of timeFixture.format_date_key) {
      const actual = T.formatDateKey(c.key);
      check(actual === c.out, `formatDateKey(${JSON.stringify(c.key)})`, actual, c.out);
    }
  });

  it(`shiftDateKey over ${timeFixture.shift_date_key.length} key/offset pairs`, () => {
    for (const c of timeFixture.shift_date_key) {
      const actual = T.shiftDateKey(c.key, c.offset);
      check(actual === c.out, `shiftDateKey(${JSON.stringify(c.key)}, ${c.offset})`, actual, c.out);
    }
  });

  // Added after the desktop was found rendering these in UTC while its own
  // comment promised local time. This function was the one TimeUtil member the
  // sweep did not cover, which is precisely how the two could disagree for
  // months without anything going red.
  it(`formatDatetime over ${timeFixture.format_datetime.length} stamp/offset pairs`, () => {
    for (const c of timeFixture.format_datetime) {
      const actual = T.formatDatetime(c.unix_seconds, c.offset_seconds);
      check(
        actual === c.out,
        `formatDatetime(${c.unix_seconds}, ${c.offset_seconds})`,
        actual, c.out,
      );
    }
  });
});

describe("PlantGrowthService", () => {
  it("matches the engine's constants", () => {
    expect(Growth.DISPLAY_STAGE).toBe(growthFixture.constants.DISPLAY_STAGE);
    expect([...Growth.STAGE_NAMES]).toEqual(growthFixture.constants.STAGE_NAMES);
  });

  it(`stageForRatio over ${growthFixture.stage_for_ratio.length} ratio/count pairs`, () => {
    for (const c of growthFixture.stage_for_ratio) {
      const actual = Growth.stageForRatio(c.ratio, c.stage_count);
      check(actual === c.out, `stageForRatio(${c.ratio}, ${c.stage_count})`, actual, c.out);
    }
  });

  it(`stageName over ${growthFixture.stage_name.length} stage/count pairs`, () => {
    for (const c of growthFixture.stage_name) {
      const actual = Growth.stageName(c.stage, c.stage_count);
      check(actual === c.out, `stageName(${c.stage}, ${c.stage_count})`, actual, c.out);
    }
  });

  it("progressRatio honours the reached-stage floor and clamps a hostile stage", () => {
    for (const c of growthFixture.progress_ratio) {
      const species = syntheticSpecies(c.species_maturity_minutes, c.species_stage_count);
      const plant = makePlantInstance({
        growthStage: c.stored_stage,
        maturity: c.mature ? Maturity.MATURE : Maturity.GROWING,
        accumulatedFocusMinutes: c.plant_focus_minutes,
      });
      const context = makeRequirementContext({ plantFocusMinutes: c.plant_focus_minutes });
      checkNumber(
        Growth.progressRatio(plant, species, context), c.out,
        `progressRatio(stage=${c.stored_stage}, mature=${c.mature}, min=${c.plant_focus_minutes})`,
      );
    }
  });

  it(`estimatedSessionsRemaining over ${growthFixture.estimated_sessions_remaining.length} cases`, () => {
    for (const c of growthFixture.estimated_sessions_remaining) {
      const species = syntheticSpecies(c.species_display_focus_minutes, 3);
      const plant = makePlantInstance({ accumulatedFocusMinutes: c.accumulated_focus_minutes });
      const actual = Growth.estimatedSessionsRemaining(plant, species, c.typical_session_minutes);
      check(actual === c.out,
        `estimatedSessionsRemaining(${c.accumulated_focus_minutes}, ${c.typical_session_minutes})`,
        actual, c.out);
    }
  });

  it("applyGrowth is idempotent: running it twice reports the transition once", () => {
    for (const c of growthFixture.apply_growth_twice) {
      const species = syntheticSpecies(180, 3);
      const plant = makePlantInstance({
        growthStage: c.stored_stage,
        accumulatedFocusMinutes: c.plant_focus_minutes,
      });
      const context = makeRequirementContext({ plantFocusMinutes: c.plant_focus_minutes });
      const label = `applyGrowth(stage=${c.stored_stage}, min=${c.plant_focus_minutes})`;

      const first = Growth.applyGrowth(plant, species, context, 1_000_000);
      const second = Growth.applyGrowth(plant, species, context, 1_000_000);

      for (const [pass, actual, expected] of [
        ["first", first, c.first] as const,
        ["second", second, c.second] as const,
      ]) {
        check(actual.previousStage === expected.previous_stage,
          `${label} ${pass}.previousStage`, actual.previousStage, expected.previous_stage);
        check(actual.newStage === expected.new_stage,
          `${label} ${pass}.newStage`, actual.newStage, expected.new_stage);
        checkNumber(actual.progressRatio, expected.progress_ratio, `${label} ${pass}.progressRatio`);
        check(actual.stageChanged === expected.stage_changed,
          `${label} ${pass}.stageChanged`, actual.stageChanged, expected.stage_changed);
        check(actual.justMatured === expected.just_matured,
          `${label} ${pass}.justMatured`, actual.justMatured, expected.just_matured);
      }
    }
  });
});

describe("RequirementEvaluator", () => {
  const context = makeRequirementContext({
    totalFocusMinutes: requirementFixture.context.total_focus_minutes,
    completedFocusSessions: requirementFixture.context.completed_focus_sessions,
    completedBreakSessions: requirementFixture.context.completed_break_sessions,
    uniqueFocusDays: requirementFixture.context.unique_focus_days,
    sessionsByStartHour: requirementFixture.context.sessions_by_start_hour,
    focusSessionLengths: requirementFixture.context.focus_session_lengths,
    playerLevel: requirementFixture.context.player_level,
    plantsMatured: requirementFixture.context.plants_matured,
    speciesDiscovered: requirementFixture.context.species_discovered,
    speciesTotal: requirementFixture.context.species_total,
    unlockedAchievementIds: requirementFixture.context.unlocked_achievement_ids,
    completedExpeditionIds: requirementFixture.context.completed_expedition_ids,
    plantFocusMinutes: requirementFixture.context.plant_focus_minutes,
    plantSessionCount: requirementFixture.context.plant_session_count,
    plantUniqueDays: requirementFixture.context.plant_unique_days,
    plantSessionsByStartHour: requirementFixture.context.plant_sessions_by_start_hour,
    plantSessionLengths: requirementFixture.context.plant_session_lengths,
  });

  it(`evaluate over ${requirementFixture.evaluate.length} type/scope/param combinations`, () => {
    for (const c of requirementFixture.evaluate) {
      const requirement = makeRequirement(
        requirementTypeFromOrdinal(c.type),
        c.params as Record<string, unknown>,
        requirementScopeFromOrdinal(c.scope),
      );
      const label = `evaluate(${requirement.type}/${requirement.scope}, ${JSON.stringify(c.params)})`;
      checkNumber(Evaluator.evaluate(requirement, context), c.out, label);
      const met = Evaluator.isMet(requirement, context);
      check(met === c.is_met, `${label} isMet`, met, c.is_met);
    }
  });

  it(`describe over ${requirementFixture.describe.length} requirements`, () => {
    for (const c of requirementFixture.describe) {
      const requirement = makeRequirement(
        requirementTypeFromOrdinal(c.type),
        c.params as Record<string, unknown>,
        "global",
        "description_override" in c ? (c as { description_override: string }).description_override : "",
      );
      const actual = Evaluator.describe(requirement);
      check(actual === c.out,
        `describe(${requirement.type}, ${JSON.stringify(c.params)})`, actual, c.out);
    }
  });
});

describe("StreakCalculator", () => {
  it(`calculate over ${streakFixture.calculate.length} scenarios`, () => {
    for (const scenario of streakFixture.calculate) {
      const sessions = scenario.sessions.map((row, index) =>
        makeFocusSession({
          id: `s_${index}`,
          dateKey: row[0] as string,
          actualFocusMinutes: row[1] as number,
          kind: row[2] as Kind,
          completion: row[3] as Completion,
        }),
      );
      const actual = Streak.calculate(sessions, scenario.threshold_minutes, scenario.today_key);
      const label = `calculate[${scenario.label}]`;
      check(actual.current === scenario.out.current, `${label}.current`, actual.current, scenario.out.current);
      check(actual.longest === scenario.out.longest, `${label}.longest`, actual.longest, scenario.out.longest);
      check(actual.lastQualifyingDay === scenario.out.last_qualifying_day,
        `${label}.lastQualifyingDay`, actual.lastQualifyingDay, scenario.out.last_qualifying_day);
      expect(actual.qualifyingDays, `${label}.qualifyingDays`).toEqual(scenario.out.qualifying_days);
    }
  });
});

describe("Defensive from_dict", () => {
  it("FocusSession repairs hostile saves identically", () => {
    for (const c of modelFixture.focus_session_from_dict) {
      const actual = focusSessionToDict(focusSessionFromDict(c.in as Record<string, unknown>));
      expect(actual, `focusSessionFromDict(${JSON.stringify(c.in)})`).toEqual(c.out);
    }
  });

  it("PlantInstance re-asserts the placement invariant and posmods rotation", () => {
    for (const c of modelFixture.plant_instance_from_dict) {
      const actual = plantInstanceToDict(plantInstanceFromDict(c.in as Record<string, unknown>));
      expect(actual, `plantInstanceFromDict(${JSON.stringify(c.in)})`).toEqual(c.out);
    }
  });

  it("PlayerProfile clamps and keeps longest at or above current", () => {
    for (const c of modelFixture.player_profile_from_dict) {
      const actual = playerProfileToDict(playerProfileFromDict(c.in as Record<string, unknown>));
      expect(actual, `playerProfileFromDict(${JSON.stringify(c.in)})`).toEqual(c.out);
    }
  });
});

/** Mirrors _synthetic_species in the exporter: fixtures must not depend on data/. */
function syntheticSpecies(maturityMinutes: number, stageCount: number) {
  return makePlantSpecies({
    id: "fixture_species",
    displayName: "Fixture Species",
    stageCount,
    growthRequirement: makeRequirement(
      "total_focus_minutes", { amount: maturityMinutes }, "active_plant",
    ),
  });
}
