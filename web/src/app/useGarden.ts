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

import { useCallback, useEffect, useMemo, useRef, useState } from "react";

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
import { buildInFlight, recoverInFlight } from "../domain/in-flight.js";
import type { GameClock } from "../domain/game-clock.js";
import {
  loadGarden, openDatabase, putSessions, replaceAll, saveGarden,
} from "../storage/save-store.js";
import { buildBundle, readBundle } from "../domain/save-bundle.js";
import { migrate, MigrationStatus } from "../domain/migrations.js";
import type { Json } from "../domain/dict-util.js";

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

/**
 * A plausible history, so the screens are designed against realistic numbers.
 *
 * THIS IS DEMO DATA and it is written on a genuine first run, which is not what
 * a real first run should do. Onboarding replaces it in 4c: a new player names
 * themselves, picks a first species and a first project, and starts with an
 * empty garden. Seeding here in the meantime is the difference between screens
 * that can be judged and screens that look broken.
 */
function seedDemoGarden(): GardenState {
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

export interface StorageStatus {
  /** False until the first load finishes. Screens wait rather than flash empty. */
  ready: boolean;
  /** True when the stored garden must not be overwritten. */
  blocked: boolean;
  blockedReason: string;
  /** True when storage itself is unavailable - a private window, or blocked. */
  ephemeral: boolean;
}

export function useGarden() {
  const [state, setState] = useState<GardenState>(seedDemoGarden);
  const [lastOutcome, setLastOutcome] = useState<SessionOutcome | null>(null);
  const [storage, setStorage] = useState<StorageStatus>({
    ready: false, blocked: false, blockedReason: "", ephemeral: false,
  });
  /** A session interrupted by the tab closing, offered back but not applied. */
  const [recovered, setRecovered] = useState<FocusSession | null>(null);
  const db = useRef<IDBDatabase | null>(null);
  /** Session ids already written, so a re-render does not rewrite the history. */
  const persistedSessions = useRef(new Set<string>());
  const { save, sessions } = state;

  // --- hydrate ---------------------------------------------------------------
  useEffect(() => {
    let cancelled = false;
    void (async () => {
      try {
        const opened = await openDatabase();
        if (cancelled) return;
        db.current = opened;
        const result = await loadGarden(opened);
        if (cancelled) return;

        if (result.existed) {
          setState({ save: result.save, sessions: result.sessions });
          for (const s of result.sessions) persistedSessions.current.add(s.id);
          // Offered, never applied: only the player knows whether they were
          // actually focusing while the tab was shut.
          const interrupted = recoverInFlight(result.save.inFlightSession);
          if (interrupted !== null) setRecovered(interrupted);
        } else {
          const seeded = seedDemoGarden();
          setState(seeded);
          if (!result.blocked) {
            await saveGarden(opened, seeded.save);
            await putSessions(opened, seeded.sessions);
            for (const s of seeded.sessions) persistedSessions.current.add(s.id);
          }
        }
        setStorage({
          ready: true,
          blocked: result.blocked,
          blockedReason: result.blockedReason,
          ephemeral: false,
        });
      } catch {
        // A private window, cleared site data, or a browser set to block storage.
        // The app still runs; it simply cannot remember. Saying so is better than
        // pretending to save.
        if (cancelled) return;
        setStorage({
          ready: true, blocked: false, ephemeral: true,
          blockedReason: "This browser is not letting Focus Garden store anything, "
            + "so this session will not be remembered.",
        });
      }
    })();
    return () => { cancelled = true; };
  }, []);

  const canWrite = storage.ready && !storage.blocked && !storage.ephemeral;

  // --- persist ---------------------------------------------------------------
  // The container on every change; sessions only when new. That split is the
  // whole reason they live in separate stores - finishing a pomodoro must not
  // rewrite a decade of history.
  useEffect(() => {
    if (!canWrite || db.current === null) return;
    void saveGarden(db.current, save, storage.blocked);
  }, [save, canWrite, storage.blocked]);

  useEffect(() => {
    if (!canWrite || db.current === null) return;
    const unwritten = sessions.filter((s) => !persistedSessions.current.has(s.id));
    if (unwritten.length === 0) return;
    for (const s of unwritten) persistedSessions.current.add(s.id);
    void putSessions(db.current, unwritten, storage.blocked);
  }, [sessions, canWrite, storage.blocked]);

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
   * Runs the completion chain over an already-settled session record.
   *
   * The timer owns the record and settles it; everything from here belongs to
   * SessionPipeline, in the order it defines, gated on the record itself.
   */
  const applyFinished = useCallback((record: FocusSession) => {
    setState((prev) => {
      const pipeline = cloneForPipeline(prev);
      const outcome = applySession(pipeline, record, PIPELINE_CONTENT, Date.now() / 1000);
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
          // The session is settled, so nothing is in flight any more.
          inFlightSession: {},
        },
        sessions: pipeline.sessions,
      };
    });
  }, []);

  /**
   * Builds and applies a session in one step, for callers that never had a timer
   * running - the tests, and later the manual "log some focus" path.
   */
  const completeSession = useCallback((
    kind: Kind, intendedMinutes: number, rawMinutes: number,
    completion: Completion, projectId: string, plantUid: string,
  ) => {
    const now = Date.now() / 1000;
    const record = createFocusSession(
      kind, intendedMinutes, projectId, plantUid, generate("s", now), now,
    );
    record.actualFocusMinutes = settle(completion, rawMinutes, intendedMinutes);
    record.completion = completion;
    record.endedAtUtc = now;
    applyFinished(record);
  }, [applyFinished]);

  // --- in-flight session ------------------------------------------------------

  /**
   * Writes the running session so it survives the tab closing.
   *
   * Called on every STATE CHANGE, not every tick: a tick-rate write would hammer
   * storage for hours. The browser also gets a `pagehide` write, which is the
   * last reliable moment before a tab goes away - `beforeunload` is not fired on
   * mobile when the OS reclaims a backgrounded page.
   */
  const persistInFlight = useCallback((session: FocusSession, clock: GameClock) => {
    setState((prev) => ({
      ...prev,
      save: { ...prev.save, inFlightSession: buildInFlight(session, clock) },
    }));
  }, []);

  const clearInFlight = useCallback(() => {
    setState((prev) => (
      Object.keys(prev.save.inFlightSession).length === 0
        ? prev
        : { ...prev, save: { ...prev.save, inFlightSession: {} } }
    ));
  }, []);

  /** Credits a recovered session. The player has said yes. */
  const acceptRecovered = useCallback(() => {
    const session = recovered;
    if (session === null) return;
    setRecovered(null);
    setState((prev) => {
      const pipeline = cloneForPipeline(prev);
      const outcome = applySession(pipeline, session, PIPELINE_CONTENT, Date.now() / 1000);
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
          inFlightSession: {},
        },
        sessions: pipeline.sessions,
      };
    });
  }, [recovered]);

  /** Throws a recovered session away. The record goes too; nothing was credited. */
  const discardRecovered = useCallback(() => {
    setRecovered(null);
    clearInFlight();
  }, [clearInFlight]);

  // --- transfer ---------------------------------------------------------------

  /**
   * The whole garden as one bundle: the same format the desktop reads and the
   * same payload sync will push. Building it here rather than in a screen keeps
   * one definition of what "a copy of my garden" means.
   */
  const exportBundle = useCallback((appVersion = "0.1.0"): Json =>
    buildBundle(save, sessions, appVersion), [save, sessions]);

  /**
   * Reads a bundle and REPLACES everything with it.
   *
   * Validates completely before destroying anything: the file is migrated, read
   * and summarised while the existing garden is still untouched, so a caller can
   * show what it contains and let the player refuse. Only then is anything
   * written.
   */
  const importBundle = useCallback(async (raw: Json) => {
    const migration = migrate(raw);
    if (migration.status !== MigrationStatus.OK) {
      return {
        ok: false as const,
        reason: migration.status === MigrationStatus.FUTURE_VERSION
          ? "That file was written by a newer version of Focus Garden."
          : "That file's save format cannot be read by this version.",
      };
    }
    const imported = readBundle(migration.data);
    if (db.current !== null && !storage.blocked && !storage.ephemeral) {
      await replaceAll(db.current, imported.save, imported.sessions);
    }
    persistedSessions.current = new Set(imported.sessions.map((s) => s.id));
    setState({ save: imported.save, sessions: imported.sessions });
    setRecovered(null);
    return { ok: true as const, summary: imported.summary };
  }, [storage.blocked, storage.ephemeral]);

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
    expansion, lastOutcome, storage, recovered,
    completeSession, applyFinished, setActivePlant, setActiveProject, placeInGarden, rotatePlant,
    persistInFlight, clearInFlight, acceptRecovered, discardRecovered,
    exportBundle, importBundle,
    getPot,
    /** Sessions that count, for anything wanting the filtered view. */
    countedSessions: sessions.filter(countsTowardProgress),
  };
}
