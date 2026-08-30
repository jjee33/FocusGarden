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
import { discover as discoverSpecies, makeCatalogueEntry } from "../domain/catalogue-entry.js";
import { JournalKind, createJournalEntry } from "../domain/journal-entry.js";
import {
  Anomaly, Completion as C, Kind as K, countsTowardProgress, createFocusSession,
} from "../domain/focus-session.js";
import { generate } from "../domain/uid.js";
import type { PlantInstance } from "../domain/plant-instance.js";
import {
  GARDEN_ROTATIONS, Location, makePlantInstance, moveToGarden, moveToInventory, moveToShelf,
} from "../domain/plant-instance.js";
import { posmod } from "../domain/gd.js";
import { makePlayerProfile } from "../domain/player-profile.js";
import type { GameSettings } from "../domain/game-settings.js";
import { makeGameSettings } from "../domain/game-settings.js";
import { makeGardenLayout } from "../domain/garden-layout.js";
import { makeShelfLayout } from "../domain/shelf-layout.js";
import { createProjectCategory } from "../domain/project-category.js";
import type { SaveData } from "../domain/save-data.js";
import { createNewSave, makeSaveData } from "../domain/save-data.js";
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

/**
 * Starter project categories, so a brand-new player can start a session
 * immediately instead of being made to invent a taxonomy first.
 *
 * Ordinary categories: deletable, renamable, and not special-cased anywhere.
 */
const SEED_PROJECTS = [
  { name: "Studying", color: "moss", icon: "book" },
  { name: "Work", color: "sky", icon: "briefcase" },
  { name: "Reading", color: "amber", icon: "page" },
  { name: "Programming", color: "terracotta", icon: "code" },
  { name: "Personal", color: "clay", icon: "heart" },
] as const;

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
        { ...createProjectCategory("Piano practice", "sky"), id: "p_networkplus" },
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
  /** Result of the last import or export, shown once then dismissed. */
  const [transferMessage, setTransferMessage] = useState("");
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
          // A genuine first run gets an EMPTY garden and the onboarding screen,
          // not a demo someone else's plants are already growing in. The demo is
          // still reachable with ?demo=1, because judging a design against three
          // empty screens is not judging it at all.
          const wantsDemo = typeof location !== "undefined"
            && new URLSearchParams(location.search).get("demo") === "1";
          const fresh = wantsDemo ? seedDemoGarden() : { save: createNewSave(), sessions: [] };
          setState(fresh);
          if (!result.blocked) {
            await saveGarden(opened, fresh.save);
            await putSessions(opened, fresh.sessions);
            for (const s of fresh.sessions) persistedSessions.current.add(s.id);
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


  /**
   * Finishes first-run setup: a name, a first project, a first plant.
   *
   * The starter projects are seeded alongside the one they typed, exactly as the
   * desktop seeds them - ordinary categories, deletable and renamable, not
   * special-cased anywhere - so nobody has to invent a taxonomy before their
   * first session.
   */
  const completeOnboarding = useCallback((result: {
    displayName: string; projectName: string; speciesId: string;
  }) => {
    const now = Date.now() / 1000;
    const chosen = createProjectCategory(result.projectName, "moss", "leaf", now);
    const starters = SEED_PROJECTS
      .filter((p) => p.name.toLowerCase() !== result.projectName.trim().toLowerCase())
      .map((p) => createProjectCategory(p.name, p.color, p.icon, now));
    const plant = makePlantInstance({
      uid: generate("pl", now),
      speciesId: result.speciesId,
      plantedAtUtc: now,
      primaryProjectId: chosen.id,
    });

    /*
     * PLANTING DISCOVERS THE SPECIES, and writes the first journal entry.
     *
     * Both were missing here and neither is optional - the desktop does them in
     * the same breath as creating the plant (app_state.gd), and its comment is
     * explicit about why: "Seeing a species in your own pot counts as
     * discovering it (§16). Growing it to maturity is what fills in the rest of
     * its catalogue statistics."
     *
     * Without this the web catalogue read "0 of 12 found" while a Monstera stood
     * in a pot on the shelf, and the journal was empty on a day something plainly
     * happened. The pipeline calls discover() again at maturity, which is
     * idempotent - that call fills in the statistics, it is not the discovery.
     *
     * It only surfaced once there were screens reading these fields. Nothing was
     * wrong with the records; nothing had ever looked at them.
     */
    const species = getSpecies(result.speciesId);
    const entry = makeCatalogueEntry(result.speciesId);
    discoverSpecies(entry, now);

    setState((prev) => ({
      ...prev,
      save: {
        ...prev.save,
        profile: {
          ...prev.save.profile,
          displayName: result.displayName,
          createdAtUtc: now,
          activeProjectId: chosen.id,
          activePlantUid: plant.uid,
          onboardingCompleted: true,
        },
        projects: [chosen, ...starters],
        plants: [plant],
        catalogue: [entry],
        journal: [createJournalEntry(
          JournalKind.SEED_PLANTED,
          `Planted ${species?.displayName ?? "a plant"}`,
          `Started while working on ${chosen.displayName}.`,
          plant.uid,
          now,
        )],
      },
    }));
  }, []);


  /**
   * Replaces local state with a reconciled copy from the sync engine.
   *
   * Every merged session is marked as already persisted, because they came off
   * the wire and are about to be written here in one go - without that, the
   * persist effect would see the whole pulled history as new and rewrite it row
   * by row.
   */
  const applyMerged = useCallback((mergedSave: SaveData, mergedSessions: FocusSession[]) => {
    setState(() => {
      persistedSessions.current = new Set(mergedSessions.map((s) => s.id));
      return { save: mergedSave, sessions: mergedSessions };
    });
    if (db.current !== null && !storage.blocked && !storage.ephemeral) {
      void saveGarden(db.current, mergedSave, storage.blocked);
      void putSessions(db.current, mergedSessions, storage.blocked);
    }
  }, [storage.blocked, storage.ephemeral]);

  const mutateSave = useCallback((change: (draft: SaveData) => SaveData) => {
    setState((prev) => ({ ...prev, save: change(prev.save) }));
  }, []);


  const updateSettings = useCallback((patch: Partial<GameSettings>) => {
    mutateSave((s) => ({ ...s, settings: { ...s.settings, ...patch } }));
  }, [mutateSave]);

  /** Offers the bundle as a file. The browser decides where it lands. */
  const downloadBundle = useCallback(() => {
    const json = JSON.stringify(buildBundle(save, sessions, "0.1.0"), null, 2);
    const blob = new Blob([json], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = `focus-garden-${todayKey()}.json`;
    link.click();
    URL.revokeObjectURL(url);
  }, [save, sessions]);

  /**
   * Reads a file the player picks and imports it.
   *
   * The whole file is parsed, migrated and summarised BEFORE anything is
   * replaced, so a bad file changes nothing and a good one can be described
   * before it is accepted.
   */
  const pickBundleToImport = useCallback(() => {
    const input = document.createElement("input");
    input.type = "file";
    input.accept = "application/json,.json";
    input.onchange = () => {
      const file = input.files?.[0];
      if (file === undefined) return;
      void file.text().then(async (text) => {
        let parsed: unknown;
        try {
          parsed = JSON.parse(text);
        } catch {
          setTransferMessage("That file is not readable as a Focus Garden export.");
          return;
        }
        if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
          setTransferMessage("That file is not readable as a Focus Garden export.");
          return;
        }
        const outcome = await importBundle(parsed as Json);
        setTransferMessage(outcome.ok
          ? `Imported ${outcome.summary.plantCount} plants and `
            + `${outcome.summary.sessionCount} sessions.`
            + (outcome.summary.skippedCount > 0
              ? ` ${outcome.summary.skippedCount} rows could not be read.`
              : "")
          : outcome.reason);
      });
    };
    input.click();
  }, [importBundle]);

  const setActivePlant = useCallback((uid: string) => {
    mutateSave((s) => ({ ...s, profile: { ...s.profile, activePlantUid: uid } }));
  }, [mutateSave]);

  const setActiveProject = useCallback((id: string) => {
    mutateSave((s) => ({ ...s, profile: { ...s.profile, activeProjectId: id } }));
  }, [mutateSave]);


  const placeOnShelf = useCallback((uid: string, slot: number) => {
    mutateSave((s) => ({
      ...s,
      plants: s.plants.map((p) => {
        if (p.uid !== uid) return p;
        const next = { ...p };
        moveToShelf(next, slot);
        return next;
      }),
    }));
  }, [mutateSave]);

  const returnToInventory = useCallback((uid: string) => {
    mutateSave((s) => ({
      ...s,
      plants: s.plants.map((p) => {
        if (p.uid !== uid) return p;
        const next = { ...p };
        moveToInventory(next);
        return next;
      }),
    }));
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

  /**
   * Mark a species as a favourite, or stop.
   *
   * The only thing on the catalogue a person can change, and it is deliberately
   * the only thing: everything else there is a record of what happened, and a
   * record you can edit is not a record. `favorite` is already part of
   * CatalogueEntry and already syncs, so this is a flag flip rather than a
   * feature.
   *
   * An entry is created if the species has none. Favouriting something you have
   * grown but whose row predates the field costs nothing and avoids a silent
   * no-op that looks like a broken button.
   */
  const toggleFavouriteSpecies = useCallback((speciesId: string) => {
    mutateSave((s) => {
      const existing = s.catalogue.find((c) => c.speciesId === speciesId);
      if (existing === undefined) {
        return {
          ...s,
          catalogue: [...s.catalogue, { ...makeCatalogueEntry(speciesId), favorite: true }],
        };
      }
      return {
        ...s,
        catalogue: s.catalogue.map((c) =>
          c.speciesId === speciesId ? { ...c, favorite: !c.favorite } : c),
      };
    });
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
    expansion, lastOutcome, storage, recovered, transferMessage, setTransferMessage,
    db: db.current, applyMerged,
    completeSession, applyFinished, completeOnboarding,
    setActivePlant, setActiveProject, placeInGarden, rotatePlant,
    placeOnShelf, returnToInventory,
    persistInFlight, clearInFlight, acceptRecovered, discardRecovered,
    updateSettings, downloadBundle, pickBundleToImport,
    exportBundle, importBundle,
    toggleFavouriteSpecies,
    getPot,
    /** Sessions that count, for anything wanting the filtered view. */
    countedSessions: sessions.filter(countsTowardProgress),
  };
}
