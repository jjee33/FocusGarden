/**
 * Loading and saving the garden. The web counterpart of autoload/save_manager.gd.
 *
 * THE REFUSAL PATH IS THE IMPORTANT PART. A save written by a newer build, or one
 * with a gap in its migration chain, must never be overwritten: we cannot know
 * what its fields mean, and guessing risks destroying real progress. The desktop
 * handles this by returning a fresh save in memory and setting `save_blocked`, so
 * every write path refuses. That flag is reproduced here as `blocked` on the load
 * result, and `saveGarden` checks it. A save is never silently erased.
 *
 * Everything is stored as the same dictionaries the desktop writes, so a record
 * pulled out of IndexedDB and handed to the desktop importer is already the right
 * shape.
 */

import type { Json } from "../domain/dict-util.js";
import type { SaveData } from "../domain/save-data.js";
import { CURRENT_VERSION, createNewSave, saveDataFromDict, saveDataToDict } from "../domain/save-data.js";
import type { FocusSession } from "../domain/focus-session.js";
import { focusSessionFromDict, focusSessionToDict } from "../domain/focus-session.js";
import { MigrationStatus, migrate } from "../domain/migrations.js";
import {
  SAVE_KEY, SAVE_STORE, SESSION_STORE, clearAll, get, getAll, openDatabase, put, remove, transact,
} from "./db.js";

export interface LoadResult {
  save: SaveData;
  sessions: FocusSession[];
  /**
   * True when the stored data must not be overwritten. Every write path checks
   * this first; the in-memory save is a fresh one so the app still runs, but it
   * will never replace what is on disk.
   */
  blocked: boolean;
  /** Empty unless blocked. Shown to the player rather than swallowed. */
  blockedReason: string;
  /** False on a first run, so the caller knows to seed rather than restore. */
  existed: boolean;
  migratedFrom: number;
}

export function emptyLoadResult(nowUnixUtc = Date.now() / 1000): LoadResult {
  return {
    save: createNewSave(nowUnixUtc), sessions: [],
    blocked: false, blockedReason: "", existed: false, migratedFrom: CURRENT_VERSION,
  };
}

export async function loadGarden(
  db: IDBDatabase, nowUnixUtc = Date.now() / 1000,
): Promise<LoadResult> {
  const stored = await transact(db, [SAVE_STORE, SESSION_STORE], "readonly", async (tx) => ({
    save: await get<Json>(tx, SAVE_STORE, SAVE_KEY),
    sessions: await getAll<Json>(tx, SESSION_STORE),
  }));

  // Sessions are read whether or not the container is there. The desktop loads
  // the profile and the session shards independently, so a missing profile with
  // surviving history yields a fresh profile AND the history - and an early
  // return here would silently discard someone's entire record because one
  // record was absent.
  const sessions = stored.sessions
    .map((row) => focusSessionFromDict(row))
    // An id-less row cannot be replaced by a later write or credited to a plant.
    .filter((session) => session.id !== "");

  if (stored.save === undefined) {
    return { ...emptyLoadResult(nowUnixUtc), sessions, existed: sessions.length > 0 };
  }

  const migration = migrate(stored.save);
  if (migration.status !== MigrationStatus.OK) {
    const reason = migration.status === MigrationStatus.FUTURE_VERSION
      ? `This garden was saved by a newer version of Focus Garden `
        + `(save format ${migration.fromVersion}, this build understands ${CURRENT_VERSION}). `
        + `Update to open it. Nothing has been changed.`
      : `This garden's save format (${migration.fromVersion}) cannot be upgraded by this `
        + `build. Nothing has been changed.`;
    return {
      ...emptyLoadResult(nowUnixUtc),
      blocked: true,
      blockedReason: reason,
      existed: true,
      migratedFrom: migration.fromVersion,
    };
  }

  return {
    save: saveDataFromDict(migration.data),
    sessions,
    blocked: false,
    blockedReason: "",
    existed: true,
    migratedFrom: migration.fromVersion,
  };
}

/**
 * Writes the container. Sessions are NOT rewritten here - they are appended
 * individually, which is the whole reason they live in their own store.
 */
export async function saveGarden(
  db: IDBDatabase, save: SaveData, blocked = false,
): Promise<boolean> {
  if (blocked) return false;
  await transact(db, [SAVE_STORE], "readwrite", async (tx) => {
    await put(tx, SAVE_STORE, saveDataToDict(save), SAVE_KEY);
  });
  return true;
}

/**
 * Records one session. Replaces an entry with the same id rather than appending
 * a duplicate - a repeated id would permanently double every figure derived from
 * it.
 */
export async function putSession(
  db: IDBDatabase, session: FocusSession, blocked = false,
): Promise<boolean> {
  if (blocked || session.id === "") return false;
  await transact(db, [SESSION_STORE], "readwrite", async (tx) => {
    await put(tx, SESSION_STORE, focusSessionToDict(session));
  });
  return true;
}

export async function putSessions(
  db: IDBDatabase, sessions: readonly FocusSession[], blocked = false,
): Promise<boolean> {
  if (blocked) return false;
  await transact(db, [SESSION_STORE], "readwrite", async (tx) => {
    for (const session of sessions) {
      if (session.id === "") continue;
      await put(tx, SESSION_STORE, focusSessionToDict(session));
    }
  });
  return true;
}

export async function deleteSession(db: IDBDatabase, id: string): Promise<void> {
  await transact(db, [SESSION_STORE], "readwrite", async (tx) => {
    await remove(tx, SESSION_STORE, id);
  });
}

/**
 * Replaces everything with an imported bundle.
 *
 * Import REPLACES rather than merges, and it validates completely before it
 * destroys anything - which is why the caller reads and summarises the bundle
 * first, shows the player what it contains, and only then calls this.
 */
export async function replaceAll(
  db: IDBDatabase, save: SaveData, sessions: readonly FocusSession[],
): Promise<void> {
  await clearAll(db);
  await saveGarden(db, save);
  await putSessions(db, sessions);
}

export { openDatabase };
