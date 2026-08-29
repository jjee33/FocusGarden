/**
 * The spike's state: a real profile, real plants, real sessions, held in memory.
 *
 * Deliberately NOT the persistence layer - IndexedDB and sync are Phase 4/5. What
 * matters here is that every number on screen comes out of the ported domain
 * logic rather than being hardcoded, so the screens are being designed against
 * the real thing. Completing a session runs the same settle -> XP -> growth chain
 * the desktop's SessionPipeline runs, in the same order, with the same
 * idempotency guard.
 */

import { useCallback, useMemo, useState } from "react";

import { ALL_SPECIES, getPot, getSpecies } from "../content/content.js";
import type { FocusSession, Kind } from "../domain/focus-session.js";
import {
  Anomaly, Completion, Kind as K, countsTowardProgress, createFocusSession, generateUid,
} from "../domain/focus-session.js";
import type { PlantInstance } from "../domain/plant-instance.js";
import {
  GARDEN_ROTATIONS, Location, makePlantInstance, moveToGarden,
} from "../domain/plant-instance.js";
import { posmod } from "../domain/gd.js";
import type { PlayerProfile } from "../domain/player-profile.js";
import { makePlayerProfile } from "../domain/player-profile.js";
import { applyGrowth, progressRatio, stageName } from "../domain/plant-growth.js";
import { getStageCount } from "../domain/species.js";
import { earnsPlantGrowth, settle } from "../domain/session-credit.js";
import { nextBreakKind, position, shouldAdvance } from "../domain/session-cycle.js";
import { levelForXp, levelProgressRatio, xpForSession } from "../domain/xp-formula.js";
import { calculate as calculateStreak } from "../domain/streak-calculator.js";
import { ingestPlantSessions, makeRequirementContext } from "../domain/requirement-context.js";
import { shiftDateKey, todayKey } from "../domain/time-util.js";

export interface Project {
  id: string;
  name: string;
  /** A theme token NAME, never a hex value, so categories stay re-themeable. */
  colorToken: "moss" | "terracotta" | "amber" | "sky" | "clay";
}

export interface GardenState {
  profile: PlayerProfile;
  plants: PlantInstance[];
  sessions: FocusSession[];
  projects: Project[];
}

/** A plausible history, so the screens are designed against realistic numbers. */
function seedState(): GardenState {
  const today = todayKey();
  const sessions: FocusSession[] = [];
  // Twelve days of history with one gap, so the streak is interesting rather
  // than a round number.
  const pattern = [50, 75, 0, 25, 100, 50, 75, 25, 50, 90, 45, 165];
  pattern.forEach((minutes, index) => {
    if (minutes === 0) return;
    const dateKey = shiftDateKey(today, index - (pattern.length - 1));
    let remaining = minutes;
    let n = 0;
    while (remaining > 0) {
      const chunk = Math.min(25, remaining);
      remaining -= chunk;
      sessions.push({
        id: `s_seed_${index}_${n++}`,
        kind: K.FOCUS,
        startedAtUtc: 0, endedAtUtc: 0,
        dateKey, startHour: 9 + (n % 8),
        intendedDurationMinutes: 25, actualFocusMinutes: chunk, pausedMinutes: 0,
        completion: Completion.COMPLETED, anomaly: Anomaly.NONE, interruptionReason: "",
        projectId: index % 3 === 0 ? "p_networkplus" : "p_reading",
        plantUid: index > 6 ? "pl_monstera" : "pl_aloe",
        xpEarned: Math.floor(chunk * 2), awardsApplied: true,
      });
    }
  });

  const plants: PlantInstance[] = [
    makePlantInstance({
      uid: "pl_aloe", speciesId: "aloe_vera", accumulatedFocusMinutes: 180,
      growthStage: 2, maturity: 1, maturedAtUtc: 1, location: Location.GARDEN,
      gardenCellX: 1, gardenCellY: 0, gardenRotation: 0, primaryProjectId: "p_reading",
    }),
    makePlantInstance({
      uid: "pl_monstera", speciesId: "monstera", accumulatedFocusMinutes: 148,
      growthStage: 1, location: Location.GARDEN, gardenCellX: 2, gardenCellY: 1,
      gardenRotation: 1, primaryProjectId: "p_networkplus",
    }),
    makePlantInstance({
      uid: "pl_snake", speciesId: "snake_plant", accumulatedFocusMinutes: 95,
      growthStage: 1, location: Location.GARDEN, gardenCellX: 0, gardenCellY: 2,
      primaryProjectId: "p_reading",
    }),
    makePlantInstance({
      uid: "pl_lavender", speciesId: "lavender", accumulatedFocusMinutes: 240,
      growthStage: 2, location: Location.GARDEN, gardenCellX: 3, gardenCellY: 0,
      gardenRotation: 3, primaryProjectId: "p_networkplus",
    }),
    makePlantInstance({
      uid: "pl_fern", speciesId: "boston_fern", accumulatedFocusMinutes: 60,
      growthStage: 1, location: Location.SHELF, shelfSlot: 0,
    }),
    makePlantInstance({
      uid: "pl_pothos", speciesId: "pothos", accumulatedFocusMinutes: 12,
      growthStage: 0, location: Location.INVENTORY,
    }),
  ];

  const totalXp = sessions.reduce((sum, s) => sum + s.xpEarned, 0);
  const streak = calculateStreak(sessions, 20, today);

  return {
    profile: makePlayerProfile({
      displayName: "Joshua", totalXp,
      activePlantUid: "pl_monstera", activeProjectId: "p_networkplus",
      currentStreak: streak.current, longestStreak: streak.longest,
      lastFocusDateKey: streak.lastQualifyingDay, focusSessionsInCycle: 2,
      onboardingCompleted: true,
    }),
    plants,
    sessions,
    projects: [
      { id: "p_networkplus", name: "Network+ revision", colorToken: "sky" },
      { id: "p_reading", name: "Reading", colorToken: "terracotta" },
      { id: "p_sideproject", name: "Side project", colorToken: "amber" },
    ],
  };
}

export interface PlantSummary {
  plant: PlantInstance;
  speciesName: string;
  scientificName: string;
  ratio: number;
  stage: number;
  stageLabel: string;
}

export function useGarden() {
  const [state, setState] = useState<GardenState>(seedState);

  const describePlant = useCallback((plant: PlantInstance): PlantSummary | null => {
    const species = getSpecies(plant.speciesId);
    if (species === null) return null;
    // Plant-scoped only: a growth requirement never reads global figures, and the
    // full context would re-aggregate the whole session history per plant.
    const context = makeRequirementContext();
    ingestPlantSessions(
      context,
      state.sessions.filter((s) => s.plantUid === plant.uid),
    );
    // The stored total is authoritative for a plant's own progress; the seeded
    // history is only a sample of it.
    context.plantFocusMinutes = plant.accumulatedFocusMinutes;
    const ratio = progressRatio(plant, species, context);
    const stageCount = getStageCount(species);
    return {
      plant,
      speciesName: species.displayName,
      scientificName: species.scientificName,
      ratio,
      stage: plant.growthStage,
      stageLabel: stageName(plant.growthStage, stageCount),
    };
  }, [state.sessions]);

  const summaries = useMemo(
    () => state.plants.map(describePlant).filter((s): s is PlantSummary => s !== null),
    [state.plants, describePlant],
  );

  const stats = useMemo(() => {
    const today = todayKey();
    const streak = calculateStreak(state.sessions, 20, today);
    const focusedToday = state.sessions
      .filter((s) => s.dateKey === today && countsTowardProgress(s) && s.kind === K.FOCUS)
      .reduce((sum, s) => sum + s.actualFocusMinutes, 0);
    const lifetime = state.sessions
      .filter((s) => countsTowardProgress(s) && s.kind === K.FOCUS)
      .reduce((sum, s) => sum + s.actualFocusMinutes, 0);
    return {
      focusedToday,
      lifetime,
      streak: streak.current,
      longestStreak: streak.longest,
      qualifyingDays: streak.qualifyingDays,
      level: levelForXp(state.profile.totalXp),
      levelRatio: levelProgressRatio(state.profile.totalXp),
      cyclePosition: position(state.profile.focusSessionsInCycle, 4),
      nextBreak: nextBreakKind(state.profile.focusSessionsInCycle, 4),
    };
  }, [state.sessions, state.profile]);

  /**
   * The completion chain, in the order SessionPipeline defines it: settle credit,
   * record, apply growth, award XP, update the cycle.
   *
   * NO IDEMPOTENCY GATE LIVES HERE YET, and an earlier version of this comment
   * claimed otherwise. It generated a fresh uid and then checked whether that
   * fresh uid was already in an applied set - which it never can be, so the guard
   * could not fire. What actually prevents a double award today is one layer up:
   * useFocusTimer.finish returns early once the clock is IDLE, so a second call
   * for the same finish is a no-op.
   *
   * The structural gate is `session.awardsApplied` on the record itself, and it
   * arrives with the real SessionPipeline port. Until then this is a convention,
   * not a guarantee - which is exactly the distinction the desktop's pipeline
   * exists to remove.
   */
  const completeSession = useCallback((
    kind: Kind, intendedMinutes: number, rawMinutes: number,
    completion: Completion, projectId: string, plantUid: string,
  ) => {
    const id = generateUid("s");
    const credited = settle(completion, rawMinutes, intendedMinutes);
    const session = createFocusSession(
      kind, intendedMinutes, projectId, plantUid, id, Date.now() / 1000,
    );
    session.actualFocusMinutes = credited;
    session.completion = completion;
    session.endedAtUtc = Date.now() / 1000;
    session.xpEarned = xpForSession(session);
    session.awardsApplied = true;

    setState((prev) => {
      const sessions = [...prev.sessions, session];
      let plants = prev.plants;

      if (earnsPlantGrowth(kind, credited, 1) && plantUid !== "") {
        plants = prev.plants.map((p) => {
          if (p.uid !== plantUid) return p;
          const species = getSpecies(p.speciesId);
          if (species === null) return p;
          const next = { ...p, contributingSessionIds: [...p.contributingSessionIds] };
          next.accumulatedFocusMinutes += credited;
          if (!next.contributingSessionIds.includes(session.id)) {
            next.contributingSessionIds.push(session.id);
          }
          const context = makeRequirementContext({
            plantFocusMinutes: next.accumulatedFocusMinutes,
          });
          applyGrowth(next, species, context);
          return next;
        });
      }

      const profile = { ...prev.profile, totalXp: prev.profile.totalXp + session.xpEarned };
      if (shouldAdvance(kind, completion)) profile.focusSessionsInCycle += 1;
      const streak = calculateStreak(sessions, 20, todayKey());
      profile.currentStreak = streak.current;
      profile.longestStreak = Math.max(profile.longestStreak, streak.longest);
      profile.lastFocusDateKey = streak.lastQualifyingDay;

      return { ...prev, sessions, plants, profile };
    });
  }, []);

  const setActivePlant = useCallback((uid: string) => {
    setState((prev) => ({ ...prev, profile: { ...prev.profile, activePlantUid: uid } }));
  }, []);

  const setActiveProject = useCallback((id: string) => {
    setState((prev) => ({ ...prev, profile: { ...prev.profile, activeProjectId: id } }));
  }, []);

  const placeInGarden = useCallback((uid: string, x: number, y: number) => {
    setState((prev) => ({
      ...prev,
      plants: prev.plants.map((p) => {
        if (p.uid !== uid) return p;
        const next = { ...p };
        moveToGarden(next, x, y, next.gardenRotation);
        return next;
      }),
    }));
  }, []);

  const rotatePlant = useCallback((uid: string) => {
    setState((prev) => ({
      ...prev,
      plants: prev.plants.map((p) =>
        p.uid === uid
          ? { ...p, gardenRotation: posmod(p.gardenRotation + 1, GARDEN_ROTATIONS) }
          : p),
    }));
  }, []);

  const activePlant = summaries.find((s) => s.plant.uid === state.profile.activePlantUid) ?? null;
  const activeProject = state.projects.find((p) => p.id === state.profile.activeProjectId) ?? null;

  return {
    state, summaries, stats, activePlant, activeProject,
    completeSession, setActivePlant, setActiveProject, placeInGarden, rotatePlant,
    getPot, allSpecies: ALL_SPECIES,
  };
}
