/**
 * The app's state: a real SaveData plus the session history, held in memory.
 *
 * The shape deliberately matches the save format's own split - the container in
 * one field, sessions in another - because that is exactly what a SaveBundle is,
 * and it is what IndexedDB will store in Phase 4b. Matching it now means
 * persistence becomes a serialisation step rather than a reshaping one.
 *
 * Session completion goes through the real SessionPipeline. An earlier version
 * ran the chain inline here behind a guard that could never fire; the gate now
 * lives where it belongs, on `session.awardsApplied`.
 */

import { useCallback, useMemo, useState } from "react";

import {
  ALL_ACHIEVEMENTS, ALL_EXPANSIONS, getPot, getSpecies, speciesCount,
} from "../content/content.js";
import type { Completion, FocusSession, Kind } from "../domain/focus-session.js";
import {
  Anomaly, Completion as C, Kind as K, countsTowardProgress, createFocusSession,
} from "../domain/focus-session.js";
import { generate } from "../domain/uid.js";
import type { PlantInstance } from "../domain/plant-instance.js";
import {
  GARDEN_ROTATIONS, Location, makePlantInstance, moveToGarden,
} from "../domain/plant-instance.js";
import { posmod } from "../domain/gd.js";
import { makePlayerProfile } from "../domain/player-profile.js";
import { makeGameSettings } from "../domain/game-settings.js";
import { makeGardenLayout } from "../domain/garden-layout.js";
import { makeShelfLayout } from "../domain/shelf-layout.js";
import { createProjectCategory } from "../domain/project-category.js";
import type { SaveData } from "../domain/save-data.js";
import { makeSaveData } from "../domain/save-data.js";
import { progressRatio, stageName } from "../domain/plant-growth.js";
import { getStageCount } from "../domain/species.js";
import { settle } from "../domain/session-credit.js";
import { nextBreakKind, position } from "../domain/session-cycle.js";
import { levelForXp, levelProgressRatio } from "../domain/xp-formula.js";
import {
  buildPlantContext, buildSummary, dailyTotals, totalsByProject,
} from "../domain/statistics.js";
import { nextExpansion, nextExpansionProgress } from "../domain/garden-service.js";
import { applySession } from "../domain/session-pipeline.js";
import type { PipelineContent, PipelineState, SessionOutcome } from "../domain/session-pipeline.js";
import { shiftDateKey, todayKey } from "../domain/time-util.js";

export interface GardenState {
  save: SaveData;
  /** Kept beside the save, exactly as the on-disk format keeps them apart. */
  sessions: FocusSession[];
}

/** Content the pipeline reads. Stable, so it is built once. */
const PIPELINE_CONTENT: PipelineContent = {
  getSpecies,
  achievements: ALL_ACHIEVEMENTS,
  expansions: ALL_EXPANSIONS,
  speciesTotal: speciesCount(),
};

/** A plausible history, so the screens are designed against realistic numbers. */
function seedState(): GardenState {
  const today = todayKey();
  const sessions: FocusSession[] = [];
  // Twelve days with one gap, so the streak is interesting rather than round.
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
        completion: C.COMPLETED, anomaly: Anomaly.NONE, interruptionReason: "",
        projectId: index % 3 === 0 ? "p_networkplus" : "p_reading",
        plantUid: index > 6 ? "pl_monstera" : "pl_aloe",
        xpEarned: Math.floor(chunk * 2),
        // Seeded history is already settled, and the gate has to say so or a
        // replay would award every minute of it again.
        awardsApplied: true,
      });
    }
  });

  const plants: PlantInstance[] = [
    makePlantInstance({
      uid: "pl_aloe", speciesId: "aloe_vera", accumulatedFocusMinutes: 180,
      growthStage: 2, maturity: 1, maturedAtUtc: 1, location: Location.GARDEN,
      gardenCellX: 1, gardenCellY: 0, primaryProjectId: "p_reading",
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

  return {
    save: makeSaveData({
      profile: makePlayerProfile({
        displayName: "Joshua", totalXp,
        activePlantUid: "pl_monstera", activeProjectId: "p_networkplus",
        focusSessionsInCycle: 2, onboardingCompleted: true,
      }),
      settings: makeGameSettings(),
      plants,
      projects: [
        { ...createProjectCategory("Network+ revision", "sky"), id: "p_networkplus" },
        { ...createProjectCategory("Reading", "terracotta"), id: "p_reading" },
        { ...createProjectCategory("Side project", "amber"), id: "p_sideproject" },
      ],
      shelf: makeShelfLayout(),
      garden: makeGardenLayout(),
    }),
    sessions,
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

/**
 * A deep-enough clone for the pipeline to mutate.
 *
 * The pipeline mutates in place, which is right for a domain function and wrong
 * for React state. The boundary between the two conventions lives here, in one
 * function, rather than smeared through either side.
 */
function cloneForPipeline(state: GardenState): PipelineState {
  const { save } = state;
  return {
    profile: { ...save.profile, unlockedIds: [...save.profile.unlockedIds] },
    settings: save.settings,
    plants: save.plants.map((p) => ({
      ...p,
      contributingSessionIds: [...p.contributingSessionIds],
      mutationIds: [...p.mutationIds],
    })),
    sessions: [...state.sessions],
    catalogue: save.catalogue.map((c) => ({ ...c })),
    achievements: save.achievements.map((a) => ({ ...a })),
    journal: [...save.journal],
    garden: {
      ...save.garden,
      unlockedExpansionIds: [...save.garden.unlockedExpansionIds],
      decorations: { ...save.garden.decorations },
    },
    expeditions: save.expeditions,
  };
}

export function useGarden() {
  const [state, setState] = useState<GardenState>(seedState);
  const [lastOutcome, setLastOutcome] = useState<SessionOutcome | null>(null);
  const { save, sessions } = state;

  const summaries = useMemo<PlantSummary[]>(() => {
    const out: PlantSummary[] = [];
    for (const plant of save.plants) {
      const species = getSpecies(plant.speciesId);
      if (species === null) continue;
      const context = buildPlantContext(sessions.filter((s) => s.plantUid === plant.uid));
      // The stored total is authoritative for a plant's own progress; the seeded
      // history is only a sample of it.
      context.plantFocusMinutes = plant.accumulatedFocusMinutes;
      out.push({
        plant,
        speciesName: species.displayName,
        scientificName: species.scientificName,
        ratio: progressRatio(plant, species, context),
        stage: plant.growthStage,
        stageLabel: stageName(plant.growthStage, getStageCount(species)),
      });
    }
    return out;
  }, [save.plants, sessions]);

  const stats = useMemo(() => {
    const summary = buildSummary({
      sessions,
      plants: save.plants,
      catalogue: save.catalogue,
      totalXp: save.profile.totalXp,
      streakThresholdMinutes: save.settings.streakThresholdMinutes,
    });
    return {
      ...summary,
      level: levelForXp(save.profile.totalXp),
      levelRatio: levelProgressRatio(save.profile.totalXp),
      cyclePosition: position(
        save.profile.focusSessionsInCycle, save.settings.sessionsBeforeLongBreak,
      ),
      nextBreak: nextBreakKind(
        save.profile.focusSessionsInCycle, save.settings.sessionsBeforeLongBreak,
      ),
      dailyTotals: dailyTotals(sessions),
      byProject: totalsByProject(sessions),
    };
  }, [sessions, save.plants, save.catalogue, save.profile, save.settings]);

  /**
   * Settles a finished session and runs the completion chain.
   *
   * Everything after the record is built belongs to SessionPipeline, in the order
   * it defines, gated on the record itself.
   */
  const completeSession = useCallback((
    kind: Kind, intendedMinutes: number, rawMinutes: number,
    completion: Completion, projectId: string, plantUid: string,
  ) => {
    setState((prev) => {
      const now = Date.now() / 1000;
      const record = createFocusSession(
        kind, intendedMinutes, projectId, plantUid, generate("s", now), now,
      );
      record.actualFocusMinutes = settle(completion, rawMinutes, intendedMinutes);
      record.completion = completion;
      record.endedAtUtc = now;

      const pipeline = cloneForPipeline(prev);
      const outcome = applySession(pipeline, record, PIPELINE_CONTENT, now);
      setLastOutcome(outcome);

      return {
        save: {
          ...prev.save,
          profile: pipeline.profile,
          plants: pipeline.plants,
          catalogue: pipeline.catalogue,
          achievements: pipeline.achievements,
          journal: pipeline.journal,
          garden: pipeline.garden,
        },
        sessions: pipeline.sessions,
      };
    });
  }, []);

  const mutateSave = useCallback((change: (draft: SaveData) => SaveData) => {
    setState((prev) => ({ ...prev, save: change(prev.save) }));
  }, []);

  const setActivePlant = useCallback((uid: string) => {
    mutateSave((s) => ({ ...s, profile: { ...s.profile, activePlantUid: uid } }));
  }, [mutateSave]);

  const setActiveProject = useCallback((id: string) => {
    mutateSave((s) => ({ ...s, profile: { ...s.profile, activeProjectId: id } }));
  }, [mutateSave]);

  const placeInGarden = useCallback((uid: string, x: number, y: number) => {
    mutateSave((s) => ({
      ...s,
      plants: s.plants.map((p) => {
        if (p.uid !== uid) return p;
        const next = { ...p };
        moveToGarden(next, x, y, next.gardenRotation);
        return next;
      }),
    }));
  }, [mutateSave]);

  const rotatePlant = useCallback((uid: string) => {
    mutateSave((s) => ({
      ...s,
      plants: s.plants.map((p) =>
        p.uid === uid
          ? { ...p, gardenRotation: posmod(p.gardenRotation + 1, GARDEN_ROTATIONS) }
          : p),
    }));
  }, [mutateSave]);

  const activePlant = summaries.find((s) => s.plant.uid === save.profile.activePlantUid) ?? null;
  const activeProject = save.projects.find((p) => p.id === save.profile.activeProjectId) ?? null;

  const expansion = useMemo(() => {
    // Only the global measure matters for the expansion ladder, so the context is
    // built cheaply rather than by re-aggregating the whole history.
    const context = buildPlantContext([]);
    context.totalFocusMinutes = stats.focusLifetime;
    return {
      next: nextExpansion(save.garden, context, ALL_EXPANSIONS),
      progress: nextExpansionProgress(save.garden, context, ALL_EXPANSIONS),
    };
  }, [save.garden, stats.focusLifetime]);

  return {
    state, save, sessions, summaries, stats, activePlant, activeProject,
    expansion, lastOutcome,
    completeSession, setActivePlant, setActiveProject, placeInGarden, rotatePlant,
    getPot,
    /** Sessions that count, for anything wanting the filtered view. */
    countedSessions: sessions.filter(countsTowardProgress),
  };
}
