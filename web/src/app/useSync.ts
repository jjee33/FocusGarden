/**
 * Keeping one garden on more than one device.
 *
 * Pull, merge, push - in that order, and the order is the point. Pulling first
 * means a push is always built on top of what the server already had, so a
 * device that has been offline for a week cannot overwrite six days of work done
 * elsewhere with its own stale copy.
 *
 * The merge itself lives in `domain/sync.ts`, pure and tested without a network.
 * This module is the plumbing: what to send, what to write back, and what to do
 * when it fails.
 *
 * FAILURE IS NORMAL AND MUST BE HARMLESS. This is a local-first app on a phone:
 * connections drop mid-request constantly. Nothing here touches the local garden
 * unless the exchange completed, every push carries a request id so a retry
 * cannot apply twice, and a failed sync leaves the app exactly as usable as it
 * was - because the local copy was never the thing at risk.
 */

import { useCallback, useEffect, useRef, useState } from "react";

import type { SaveData } from "../domain/save-data.js";
import { saveDataToDict } from "../domain/save-data.js";
import type { FocusSession } from "../domain/focus-session.js";
import { focusSessionFromDict, focusSessionToDict } from "../domain/focus-session.js";
import { plantInstanceFromDict, plantInstanceToDict } from "../domain/plant-instance.js";
import { projectCategoryFromDict, projectCategoryToDict } from "../domain/project-category.js";
import { catalogueEntryFromDict, catalogueEntryToDict } from "../domain/catalogue-entry.js";
import { achievementStateFromDict, achievementStateToDict } from "../domain/achievement-state.js";
import { journalEntryFromDict, journalEntryToDict } from "../domain/journal-entry.js";
import { playerProfileFromDict } from "../domain/player-profile.js";
import { gameSettingsFromDict } from "../domain/game-settings.js";
import { shelfLayoutFromDict } from "../domain/shelf-layout.js";
import { gardenLayoutFromDict } from "../domain/garden-layout.js";
import { mergeAppendOnly, mergeCollection } from "../domain/sync.js";
import type { SyncRecord } from "../domain/sync.js";
import { generate } from "../domain/uid.js";
import type { Json } from "../domain/dict-util.js";
import { getDict } from "../domain/dict-util.js";
import { nextPullCursor } from "../domain/sync.js";
import type { SyncMeta } from "../storage/sync-meta.js";
import {
  acknowledgeRecord, contentHash, emptySyncMeta, isDirty, loadSyncMeta, metaForUser,
  revisionOf, saveSyncMeta,
} from "../storage/sync-meta.js";

export type SyncState = "idle" | "syncing" | "offline" | "error";

export interface SyncStatus {
  state: SyncState;
  lastSyncedAt: number;
  message: string;
  /** Ids changed in two places at once. Resolved, but surfaced rather than hidden. */
  conflicts: string[];
}

/** The collections that carry revisions, and how each one crosses the wire. */
const COLLECTIONS = {
  plants: {
    read: plantInstanceFromDict,
    write: plantInstanceToDict,
    idOf: (v: { uid: string }) => v.uid,
  },
  projects: {
    read: projectCategoryFromDict,
    write: projectCategoryToDict,
    idOf: (v: { id: string }) => v.id,
  },
  catalogue: {
    read: catalogueEntryFromDict,
    write: catalogueEntryToDict,
    idOf: (v: { speciesId: string }) => v.speciesId,
  },
  achievements: {
    read: achievementStateFromDict,
    write: achievementStateToDict,
    idOf: (v: { achievementId: string }) => v.achievementId,
  },
} as const;

interface WireRecord {
  id: string;
  revision: number;
  updatedAt: number;
  deletedAt: number | null;
  value: Json;
}

export interface SyncTarget {
  save: SaveData;
  sessions: FocusSession[];
  /** Called with the reconciled state. Only ever after a complete exchange. */
  onMerged: (save: SaveData, sessions: FocusSession[]) => void;
  db: IDBDatabase | null;
  userId: string | null;
  /** False when the local store refused to open; syncing would have nowhere to land. */
  enabled: boolean;
}

export function useSync(target: SyncTarget) {
  const [status, setStatus] = useState<SyncStatus>({
    state: "idle", lastSyncedAt: 0, message: "", conflicts: [],
  });
  /** Held in a ref so the callback is stable and cannot capture a stale garden. */
  const latest = useRef(target);
  latest.current = target;
  const running = useRef(false);

  const sync = useCallback(async (): Promise<void> => {
    const { save, sessions, onMerged, db, userId, enabled } = latest.current;
    if (!enabled || db === null || userId === null) return;
    // One exchange at a time. Two overlapping pushes would each build on the
    // pre-sync state and the second would undo the first.
    if (running.current) return;
    running.current = true;
    setStatus((s) => ({ ...s, state: "syncing", message: "" }));

    try {
      const meta = metaForUser(await loadSyncMeta(db), userId);

      // --- pull ---------------------------------------------------------------
      const pulled = await fetchJson(
        `/api/sync/pull?since=${meta.lastRevision}&sessionsSince=${meta.lastAppendAt}`,
      );

      const nextSave: SaveData = { ...save };
      const conflicts: string[] = [];

      /*
       * The profile is one record, so last-write-wins is the whole rule. A pulled
       * copy only replaces the local one when this device has nothing unsent.
       *
       * A DEVICE THAT HAS NEVER SYNCED IS NOT A DEVICE WITH UNSENT WORK, and
       * conflating the two destroyed gardens. `knownHash` is undefined before the
       * first sync, so `knownHash === localHash` was false, the remote profile was
       * never applied, and the untouched local default was then pushed straight
       * over the real one. Signing in on a second device did not just show
       * onboarding again - it wiped the first device's garden from the server.
       *
       * The distinction that matters is whether the local save has actually been
       * USED. Someone who played anonymously and then made an account has a real
       * garden here that must be uploaded, not overwritten - that is the whole
       * promise of "you can add an account later without losing anything". A
       * pristine save has nothing to protect, so the server wins outright.
       */
      const remoteProfile = pulled["profile"];
      if (remoteProfile !== null && remoteProfile !== undefined) {
        const wire = remoteProfile as { data: Json; revision: number };
        const localHash = contentHash(profilePayload(save));
        const knownHash = meta.records["profile"]?.["self"]?.hash;
        const neverSyncedAndUnused = knownHash === undefined && isPristine(save, sessions);
        if (knownHash === localHash || neverSyncedAndUnused) {
          const data = wire.data;
          nextSave.profile = playerProfileFromDict(getDict(data, "player"));
          nextSave.settings = gameSettingsFromDict(getDict(data, "settings"));
          nextSave.shelf = shelfLayoutFromDict(getDict(data, "shelf"));
          nextSave.garden = gardenLayoutFromDict(getDict(data, "garden"));
          acknowledgeRecord(meta, "profile", "self", wire.revision, profilePayload(nextSave));
        } else {
          conflicts.push("profile");
        }
      }

      for (const name of Object.keys(COLLECTIONS) as (keyof typeof COLLECTIONS)[]) {
        const spec = COLLECTIONS[name];
        const localList = collectionOf(nextSave, name) as unknown[];
        const local: SyncRecord<unknown>[] = localList.map((value) => {
          const id = (spec.idOf as (v: unknown) => string)(value);
          return {
            id,
            revision: revisionOf(meta, name, id),
            dirty: isDirty(meta, name, id, (spec.write as (v: unknown) => Json)(value)),
            updatedAt: meta.records[name]?.[id] === undefined ? nowSeconds() : meta.lastSyncedAt,
            deletedAt: null,
            value,
          };
        });

        // A record this device had synced and then removed is a delete, and has
        // to travel as one - dropping it silently would let the next pull bring
        // it straight back.
        const presentIds = new Set(local.map((r) => r.id));
        for (const [id, at] of Object.entries(meta.tombstones[name] ?? {})) {
          if (presentIds.has(id)) continue;
          local.push({
            id, revision: revisionOf(meta, name, id), dirty: true,
            updatedAt: at, deletedAt: at, value: null,
          });
        }

        const remote: SyncRecord<unknown>[] = ((pulled[name] as WireRecord[] | undefined) ?? [])
          .map((row) => ({
            id: row.id,
            revision: row.revision,
            dirty: false,
            updatedAt: row.updatedAt,
            deletedAt: row.deletedAt,
            value: row.deletedAt === null ? (spec.read as (d: Json) => unknown)(row.value) : null,
          }));

        const outcome = mergeCollection(local, remote);
        conflicts.push(...outcome.conflicted.map((id) => `${name}:${id}`));

        setCollection(nextSave, name, outcome.merged
          .filter((r) => r.deletedAt === null && r.value !== null)
          .map((r) => r.value));

        for (const record of outcome.toApply) {
          if (record.deletedAt === null && record.value !== null) {
            acknowledgeRecord(
              meta, name, record.id, record.revision,
              (spec.write as (v: unknown) => Json)(record.value),
            );
          }
        }
      }

      // Append-only. No revisions, no conflicts, and a union by id - a duplicate
      // would permanently double every figure derived from it.
      const remoteSessions = ((pulled["sessions"] as { data: Json }[] | undefined) ?? [])
        .map((row) => focusSessionFromDict(row.data));
      const sessionMerge = mergeAppendOnly(sessions, remoteSessions);

      const remoteJournal = ((pulled["journal"] as { data: Json }[] | undefined) ?? [])
        .map((row) => journalEntryFromDict(row.data));
      const journalMerge = mergeAppendOnly(nextSave.journal, remoteJournal);
      nextSave.journal = journalMerge.merged;

      // --- push ---------------------------------------------------------------
      const body: Json = { requestId: generate("push") };
      let hasWork = false;

      const localProfileHash = contentHash(profilePayload(nextSave));
      if (meta.records["profile"]?.["self"]?.hash !== localProfileHash) {
        body["profile"] = {
          data: profilePayload(nextSave),
          saveVersion: nextSave.saveVersion,
          revision: revisionOf(meta, "profile", "self"),
          updatedAt: nowSeconds(),
        };
        hasWork = true;
      }

      const pushedByCollection: Record<string, { id: string; value: Json }[]> = {};
      for (const name of Object.keys(COLLECTIONS) as (keyof typeof COLLECTIONS)[]) {
        const spec = COLLECTIONS[name];
        const outgoing: WireRecord[] = [];
        pushedByCollection[name] = [];
        for (const value of collectionOf(nextSave, name) as unknown[]) {
          const id = (spec.idOf as (v: unknown) => string)(value);
          const payload = (spec.write as (v: unknown) => Json)(value);
          if (!isDirty(meta, name, id, payload)) continue;
          outgoing.push({
            id, revision: revisionOf(meta, name, id),
            updatedAt: nowSeconds(), deletedAt: null, value: payload,
          });
          pushedByCollection[name]!.push({ id, value: payload });
        }
        for (const [id, at] of Object.entries(meta.tombstones[name] ?? {})) {
          outgoing.push({
            id, revision: revisionOf(meta, name, id),
            updatedAt: at, deletedAt: at, value: {},
          });
        }
        if (outgoing.length > 0) {
          body[name] = outgoing;
          hasWork = true;
        }
      }

      if (sessionMerge.toPush.length > 0) {
        body["sessions"] = sessionMerge.toPush.map((s) => ({
          id: s.id, dateKey: s.dateKey, data: focusSessionToDict(s),
          createdAt: Math.floor(s.startedAtUtc || nowSeconds()),
        }));
        hasWork = true;
      }
      if (journalMerge.toPush.length > 0) {
        body["journal"] = journalMerge.toPush.map((j) => ({
          id: j.id, data: journalEntryToDict(j), createdAt: Math.floor(j.createdAtUtc),
        }));
        hasWork = true;
      }

      /*
       * TWO REVISIONS, AND CONFLATING THEM LOSES OTHER DEVICES' WORK.
       *
       * `pullRevision` is how far this device has actually READ. `revision` is
       * where its own push landed. They are not the same number, and the pull
       * cursor must be the former.
       *
       * This used to store the push revision as the cursor, which silently
       * skipped anything another device committed in the gap between our pull
       * and our push:
       *
       *   A pulls, sees revision 3
       *   B pushes a new plant       -> revision 4
       *   A pushes an unrelated edit -> revision 5
       *   A stores 5 as its cursor, asks for "everything after 5",
       *   and never sees revision 4 again.
       *
       * Reproduced end to end against the deployed server before this comment
       * was written; B's plant was permanently invisible to A. It needs no
       * unusual timing - two devices syncing within a few seconds is the normal
       * case for the feature that justifies having an account at all.
       *
       * Advancing only to what we read re-pulls this device's own writes on the
       * next sync. That costs a little bandwidth and nothing else: the merge
       * hashes them, finds them identical, and does nothing.
       */
      const pullRevision = Number(pulled["revision"] ?? meta.lastRevision);
      let revision = pullRevision;
      if (hasWork) {
        const pushed = await fetchJson("/api/sync/push", body);
        revision = Number(pushed["revision"] ?? revision);

        // Only now is anything recorded as agreed. Doing it before the response
        // would leave a failed push looking synced, and the record would never
        // be sent again.
        if (body["profile"] !== undefined) {
          acknowledgeRecord(meta, "profile", "self", revision, profilePayload(nextSave));
        }
        for (const [name, records] of Object.entries(pushedByCollection)) {
          for (const record of records) {
            acknowledgeRecord(meta, name, record.id, revision, record.value);
          }
        }
        // The server has the deletes now, so this device can stop carrying them.
        meta.tombstones = {};
      }

      meta.lastRevision = nextPullCursor(pullRevision, revision);
      meta.lastAppendAt = Math.floor(nowSeconds());
      meta.lastSyncedAt = Math.floor(nowSeconds());
      await saveSyncMeta(db, meta);

      onMerged(nextSave, sessionMerge.merged);
      setStatus({
        state: "idle",
        lastSyncedAt: meta.lastSyncedAt,
        message: "",
        conflicts,
      });
    } catch (caught) {
      const offline = typeof navigator !== "undefined" && !navigator.onLine;
      setStatus((s) => ({
        ...s,
        state: offline ? "offline" : "error",
        message: offline
          ? "No connection. Your garden is safe on this device and will sync when you are back."
          : messageFor(caught),
      }));
    } finally {
      running.current = false;
    }
  }, []);

  // Sync on sign-in, on coming back online, and when the tab is looked at again.
  // Not on a timer: a habit app sits open for hours, and polling an idle server
  // is the kind of background chatter that empties a phone battery.
  //
  // AND ON PAGEHIDE, which is the moment data actually goes missing. `unload`
  // is not fired reliably on mobile - a backgrounded tab is often killed without
  // it - and pagehide is.
  useEffect(() => {
    if (!target.enabled || target.userId === null) return;
    void sync();
    const onOnline = (): void => void sync();
    const onVisible = (): void => {
      if (document.visibilityState === "visible") void sync();
    };
    const onHide = (): void => void sync();
    window.addEventListener("online", onOnline);
    window.addEventListener("pagehide", onHide);
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      window.removeEventListener("online", onOnline);
      window.removeEventListener("pagehide", onHide);
      document.removeEventListener("visibilitychange", onVisible);
    };
  }, [target.enabled, target.userId, sync]);

  /*
   * AND WHENEVER THE GARDEN ACTUALLY CHANGES, which was the missing trigger and
   * very nearly shipped.
   *
   * The list above looks complete until you notice what is not in it: finishing
   * a session, planting something, completing onboarding. None of them synced.
   * Driving the real app on production, sign-in pushed an empty profile and then
   * the first plant, the first project and the first completed session all
   * stayed on the device - server had profiles:1, plants:0, projects:0,
   * sessions:0. Close the tab, open your phone, and the work is simply not
   * there, which is the one promise an account makes.
   *
   * Debounced rather than immediate: a finishing session writes the session, the
   * plant, the profile and the statistics in quick succession, and each of those
   * is a React render. Syncing per render would be four round trips for one
   * logical event.
   *
   * The signature guard is what stops this looping. A completed sync calls
   * onMerged, which changes `save`, which re-runs this effect - so the signature
   * at the end of a sync is recorded, and an unchanged one schedules nothing.
   */
  const lastSignature = useRef("");
  useEffect(() => {
    if (!target.enabled || target.userId === null) return;
    const signature = localSignature(target.save, target.sessions);
    if (signature === lastSignature.current) return;

    const timer = setTimeout(() => {
      lastSignature.current = localSignature(latest.current.save, latest.current.sessions);
      void sync();
    }, CHANGE_DEBOUNCE_MS);
    return () => clearTimeout(timer);
  }, [target.enabled, target.userId, target.save, target.sessions, sync]);

  return { status, sync };
}

/**
 * Has this device's save actually been used, or is it the untouched default?
 *
 * Only asked of a device that has never synced, and only to decide whether the
 * server's copy may replace it wholesale. Deliberately conservative: anything
 * that looks like real activity counts as used, because the cost of guessing
 * wrong in that direction is a redundant upload, and the cost of guessing wrong
 * in the other is somebody's garden.
 */
function isPristine(save: SaveData, sessions: FocusSession[]): boolean {
  return !save.profile.onboardingCompleted
    && sessions.length === 0
    && save.plants.length === 0
    && save.journal.length === 0
    && save.profile.totalXp === 0
    && save.profile.currentStreak === 0;
}

/** Long enough that one finishing session is one sync, short enough to feel live. */
const CHANGE_DEBOUNCE_MS = 2500;

/**
 * A cheap stand-in for "has anything worth syncing changed".
 *
 * Deliberately not a hash of the whole save: this runs on every render, and
 * serialising the entire garden to decide whether to do nothing would cost more
 * than the sync it is trying to avoid. Counts plus the newest timestamps catch
 * every real edit - a plant added, a session finished, a name changed - because
 * all of them move a count or a stamp.
 */
function localSignature(save: SaveData, sessions: FocusSession[]): string {
  const newest = (xs: number[]): number => (xs.length === 0 ? 0 : Math.max(...xs));
  return [
    sessions.length,
    newest(sessions.map((s) => s.endedAtUtc || s.startedAtUtc)),
    save.plants.length,
    newest(save.plants.map((p) => p.accumulatedFocusMinutes)),
    save.projects.length,
    save.catalogue.length,
    save.achievements.length,
    save.journal.length,
    save.profile.totalXp,
    save.profile.currentStreak,
    save.profile.displayName,
    save.profile.activePlantUid,
    save.profile.activeProjectId,
    String(save.profile.onboardingCompleted),
  ].join("|");
}

/** The single-record half of the save: everything that is not a collection. */
function profilePayload(save: SaveData): Json {
  const full = saveDataToDict(save);
  return {
    save_version: full["save_version"],
    player: full["player"],
    settings: full["settings"],
    shelf: full["shelf"],
    garden: full["garden"],
    expeditions: full["expeditions"],
  };
}

function collectionOf(save: SaveData, name: keyof typeof COLLECTIONS): unknown[] {
  if (name === "plants") return save.plants;
  if (name === "projects") return save.projects;
  if (name === "catalogue") return save.catalogue;
  return save.achievements;
}

function setCollection(save: SaveData, name: keyof typeof COLLECTIONS, values: unknown[]): void {
  if (name === "plants") save.plants = values as SaveData["plants"];
  else if (name === "projects") save.projects = values as SaveData["projects"];
  else if (name === "catalogue") save.catalogue = values as SaveData["catalogue"];
  else save.achievements = values as SaveData["achievements"];
}

function nowSeconds(): number {
  return Date.now() / 1000;
}

async function fetchJson(url: string, body?: Json): Promise<Json> {
  const response = await fetch(url, {
    method: body === undefined ? "GET" : "POST",
    // The cookie is the session. Without this the request is anonymous and the
    // server correctly refuses it.
    credentials: "same-origin",
    ...(body === undefined ? {} : {
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    }),
  });
  if (!response.ok) {
    throw new Error(`${response.status}`);
  }
  return (await response.json()) as Json;
}

function messageFor(caught: unknown): string {
  const text = caught instanceof Error ? caught.message : "";
  if (text === "401") return "Signed out. Sign in again to keep syncing.";
  if (text.startsWith("5")) return "The server had a problem. Nothing on this device changed.";
  return "Could not sync just now. Your garden is safe on this device.";
}

export { emptySyncMeta };
export type { SyncMeta };
