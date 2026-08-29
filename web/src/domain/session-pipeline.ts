/**
 * The nine ordered steps that run when a session completes.
 * Port of systems/progression/session_pipeline.gd.
 *
 * WHY THIS IS A PIPELINE RATHER THAN A SET OF LISTENERS. The obvious design has
 * each concern subscribe to a "session completed" event and react. That silently
 * breaks two guarantees. Handler order is not specified, so achievements could
 * evaluate before the XP that satisfies them is awarded; and any handler that
 * runs twice - a double-connected signal, a replayed event, a recovered session -
 * double-awards.
 *
 * So completion is an explicit ordered function, and it is IDEMPOTENT. The gate
 * is `session.awardsApplied`, stored on the session record itself and persisted
 * with it. Re-running for an already-processed session is a no-op, whatever the
 * reason it was re-run.
 *
 * That gate is the real thing. An earlier version of the web app claimed one at
 * the call site by generating a fresh id and asking whether it had been seen -
 * which it never had, so nothing was guarded. Keying on the record is what makes
 * "XP cannot double-award from one session" a structural property rather than a
 * hope.
 *
 * STATE IS PASSED IN AND MUTATED IN PLACE, rather than read from globals as the
 * GDScript does. That keeps the whole chain testable with a handful of fabricated
 * records and no running app.
 */

import { maxi } from "./gd.js";
import type { FocusSession } from "./focus-session.js";
import { countsTowardProgress } from "./focus-session.js";
import type { PlayerProfile } from "./player-profile.js";
import { grantUnlock } from "./player-profile.js";
import type { GameSettings } from "./game-settings.js";
import type { PlantInstance } from "./plant-instance.js";
import type { CatalogueEntry } from "./catalogue-entry.js";
import { discover, makeCatalogueEntry, recordMaturity } from "./catalogue-entry.js";
import type { AchievementState } from "./achievement-state.js";
import { makeAchievementState, unlock } from "./achievement-state.js";
import type { JournalEntry } from "./journal-entry.js";
import { JournalKind, createJournalEntry } from "./journal-entry.js";
import type { GardenLayout } from "./garden-layout.js";
import type { GrowthResult } from "./plant-growth.js";
import { applyGrowth } from "./plant-growth.js";
import { earnsPlantGrowth } from "./session-credit.js";
import { shouldAdvance } from "./session-cycle.js";
import { levelForXp, xpForSession } from "./xp-formula.js";
import { evaluate } from "./requirement-evaluator.js";
import { buildContext, buildPlantContext } from "./statistics.js";
import { calculate } from "./streak-calculator.js";
import { reconcile } from "./garden-service.js";
import { formatDuration } from "./time-util.js";
import type { PlantSpecies } from "./species.js";
import type { AchievementDef, GardenExpansion } from "../content/content.js";
import type { Json } from "./dict-util.js";

/**
 * Unlocks keyed by level. One table, because scattering level thresholds across
 * files is how they drift apart.
 */
export const LEVEL_UNLOCKS: Record<number, string> = {
  2: "pot_ceramic_sage",
  3: "shelf_style_pale_birch",
  5: "ambient_rain",
  8: "pot_stoneware_cream",
  12: "shelf_background_studio",
  16: "ambient_fireplace",
  20: "garden_decor_lantern",
};

/** Everything the chain may read or write. Mutated in place. */
export interface PipelineState {
  profile: PlayerProfile;
  settings: GameSettings;
  plants: PlantInstance[];
  sessions: FocusSession[];
  catalogue: CatalogueEntry[];
  achievements: AchievementState[];
  journal: JournalEntry[];
  garden: GardenLayout;
  expeditions: Json;
}

/** Authored content, passed in so this stays a function of its arguments. */
export interface PipelineContent {
  getSpecies: (id: string) => PlantSpecies | null;
  achievements: readonly AchievementDef[];
  expansions: readonly GardenExpansion[];
  speciesTotal: number;
}

export interface SessionOutcome {
  applied: boolean;
  creditedMinutes: number;
  xpAwarded: number;
  levelsGained: number;
  growth: GrowthResult | null;
  plantMatured: boolean;
  speciesDiscovered: boolean;
  unlockedAchievementIds: string[];
  grantedUnlockIds: string[];
  newlyUnlockedExpansionIds: string[];
  streakAfter: number;
  skippedReason: string;
}

function emptyOutcome(): SessionOutcome {
  return {
    applied: false, creditedMinutes: 0, xpAwarded: 0, levelsGained: 0,
    growth: null, plantMatured: false, speciesDiscovered: false,
    unlockedAchievementIds: [], grantedUnlockIds: [], newlyUnlockedExpansionIds: [],
    streakAfter: 0, skippedReason: "",
  };
}

function ensureCatalogueEntry(state: PipelineState, speciesId: string): CatalogueEntry {
  const existing = state.catalogue.find((e) => e.speciesId === speciesId);
  if (existing !== undefined) return existing;
  const entry = makeCatalogueEntry(speciesId);
  state.catalogue.push(entry);
  return entry;
}

function ensureAchievementState(state: PipelineState, id: string): AchievementState {
  const existing = state.achievements.find((a) => a.achievementId === id);
  if (existing !== undefined) return existing;
  const created = makeAchievementState(id);
  state.achievements.push(created);
  return created;
}

/**
 * Runs the completion steps for `session`, in order. Returns what actually
 * happened, so the completion screen knows what to celebrate.
 */
export function applySession(
  state: PipelineState,
  session: FocusSession,
  content: PipelineContent,
  nowUnixUtc = Date.now() / 1000,
): SessionOutcome {
  const outcome = emptyOutcome();

  // THE IDEMPOTENCY GATE. Everything below mutates player state exactly once.
  if (session.awardsApplied) {
    outcome.skippedReason = "Awards already applied to this session.";
    return outcome;
  }

  // --- 1 & 2. Record the session and settle its credited focus minutes. ---
  // The minutes were measured by the clock; the only decision left is whether a
  // very short session earns growth.
  outcome.creditedMinutes = session.actualFocusMinutes;
  const earnsGrowth = earnsPlantGrowth(
    session.kind, outcome.creditedMinutes, state.settings.minimumCreditMinutes,
  );

  // Marked BEFORE the work: if anything below fails, the session must not be left
  // eligible for a second full pass.
  session.awardsApplied = true;
  outcome.applied = true;

  if (!state.sessions.includes(session)) state.sessions.push(session);

  if (!countsTowardProgress(session)) {
    // Cancelled or zero-length. The record is still kept - legitimately focused
    // time is never silently lost, and the row is wanted for analytics either way.
    outcome.skippedReason = "Session earned no credit.";
    return outcome;
  }

  // --- 3. Apply plant growth. ---
  if (earnsGrowth && session.plantUid !== "") {
    outcome.growth = applyPlantGrowth(state, session, content, outcome, nowUnixUtc);
  }

  // --- 4. Award XP. ---
  const xp = xpForSession(session);
  if (xp > 0) {
    session.xpEarned = xp;
    outcome.xpAwarded = xp;
    const previousLevel = levelForXp(state.profile.totalXp);
    state.profile.totalXp += xp;
    const newLevel = levelForXp(state.profile.totalXp);
    outcome.levelsGained = maxi(0, newLevel - previousLevel);
  }

  if (shouldAdvance(session.kind, session.completion)) {
    state.profile.focusSessionsInCycle += 1;
  }

  // --- 6 & 7. Update streak and statistics. ---
  // Statistics are refreshed BEFORE achievements are evaluated, because
  // achievement requirements are measured against freshly aggregated data. This
  // ordering is the whole reason the chain is a function and not a set of
  // listeners.
  const streak = calculate(state.sessions, state.settings.streakThresholdMinutes);
  state.profile.currentStreak = streak.current;
  state.profile.longestStreak = maxi(state.profile.longestStreak, streak.longest);
  state.profile.lastFocusDateKey = streak.lastQualifyingDay;
  outcome.streakAfter = streak.current;

  // --- 5. Evaluate achievements. ---
  const context = buildContext({
    sessions: state.sessions,
    plants: state.plants,
    catalogue: state.catalogue,
    achievements: state.achievements,
    expeditions: state.expeditions,
    totalXp: state.profile.totalXp,
    streakThresholdMinutes: state.settings.streakThresholdMinutes,
    speciesTotal: content.speciesTotal,
  });

  for (const definition of content.achievements) {
    const achievementState = ensureAchievementState(state, definition.id);
    if (achievementState.unlocked) continue;
    const ratio = evaluate(definition.requirement, context);
    achievementState.progressRatio = ratio;
    if (ratio >= 1 && unlock(achievementState, nowUnixUtc)) {
      outcome.unlockedAchievementIds.push(definition.id);
      state.journal.push(createJournalEntry(
        JournalKind.ACHIEVEMENT_UNLOCKED, definition.title, definition.description,
        definition.id, nowUnixUtc,
      ));
    }
  }

  if (outcome.levelsGained > 0) {
    const level = levelForXp(state.profile.totalXp);
    state.journal.push(createJournalEntry(
      JournalKind.LEVEL_UP,
      `Reached level ${level}`,
      `Grown from ${formatDuration(context.totalFocusMinutes)} of focus so far.`,
      String(level), nowUnixUtc,
    ));
  }

  // --- 8. Evaluate unlocks. ---
  // A convergence pass, not an event: re-running grants nothing twice, and a
  // table extended in a future update reaches existing players without
  // duplicating anything.
  const level = levelForXp(state.profile.totalXp);
  for (const [unlockLevel, unlockId] of Object.entries(LEVEL_UNLOCKS)) {
    if (level >= Number(unlockLevel) && grantUnlock(state.profile, unlockId)) {
      outcome.grantedUnlockIds.push(unlockId);
    }
  }

  const expansions = reconcile(state.garden, context, content.expansions);
  for (const expansion of expansions.newlyUnlocked) {
    outcome.newlyUnlockedExpansionIds.push(expansion.id);
    state.journal.push(createJournalEntry(
      JournalKind.GARDEN_EXPANSION, expansion.displayName, expansion.description,
      expansion.id, nowUnixUtc,
    ));
  }

  // --- 9. Persisting is the caller's job. ---
  return outcome;
}

function applyPlantGrowth(
  state: PipelineState,
  session: FocusSession,
  content: PipelineContent,
  outcome: SessionOutcome,
  nowUnixUtc: number,
): GrowthResult | null {
  const plant = state.plants.find((p) => p.uid === session.plantUid);
  if (plant === undefined) return null;

  const species = content.getSpecies(plant.speciesId);
  if (species === null) {
    // A species removed in a future update must not destroy the plant. It keeps
    // its progress and simply cannot grow.
    return null;
  }

  plant.accumulatedFocusMinutes += session.actualFocusMinutes;
  if (!plant.contributingSessionIds.includes(session.id)) {
    plant.contributingSessionIds.push(session.id);
  }

  // Plant-scoped only: a growth requirement never reads global figures, and the
  // full context would re-aggregate the entire session history on every completed
  // session.
  const plantSessions = state.sessions.filter((s) => s.plantUid === plant.uid);
  const context = buildPlantContext(plantSessions);
  const growth = applyGrowth(plant, species, context, nowUnixUtc);

  if (growth.justMatured) {
    outcome.plantMatured = true;

    // A finished plant stops being the growth target. Leaving it selected meant
    // the next session poured time into something already complete, and Home
    // showed a permanent "100% grown" that nothing could advance.
    if (state.profile.activePlantUid === plant.uid) state.profile.activePlantUid = "";

    const entry = ensureCatalogueEntry(state, plant.speciesId);
    entry.totalFocusMinutes += plant.accumulatedFocusMinutes;
    recordMaturity(entry, plant.accumulatedFocusMinutes);
    if (discover(entry, nowUnixUtc)) outcome.speciesDiscovered = true;

    state.journal.push(createJournalEntry(
      JournalKind.PLANT_MATURED,
      `${species.displayName} reached maturity`,
      `Grown over ${formatDuration(plant.accumulatedFocusMinutes)} of focus.`,
      plant.uid, nowUnixUtc,
    ));
  }

  return growth;
}
