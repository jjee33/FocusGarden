/**
 * Persistence, against a real IndexedDB implementation.
 *
 * The cases that matter are not "does a write round-trip" - they are the ones
 * where the right answer is to REFUSE. A save from a newer build, or one with a
 * gap in its migration chain, must survive contact with this build completely
 * untouched, because guessing what its fields mean risks destroying real
 * progress. A save is never silently erased.
 */

import "fake-indexeddb/auto";
import { IDBFactory } from "fake-indexeddb";
import { beforeEach, describe, expect, it } from "vitest";

import {
  SAVE_KEY, SAVE_STORE, SESSION_STORE, get, getAll, openDatabase, put, transact,
} from "../db.js";
import {
  deleteSession, loadGarden, putSession, putSessions, replaceAll, saveGarden,
} from "../save-store.js";
import { CURRENT_VERSION, makeSaveData, saveDataToDict } from "../../domain/save-data.js";
import { makePlayerProfile } from "../../domain/player-profile.js";
import { makePlantInstance } from "../../domain/plant-instance.js";
import { makeGardenLayout } from "../../domain/garden-layout.js";
import { Completion, Kind, makeFocusSession } from "../../domain/focus-session.js";
import type { Json } from "../../domain/dict-util.js";

let db: IDBDatabase;

beforeEach(async () => {
  // A fresh factory per test: IndexedDB is process-global, and a leaked database
  // between tests is the kind of shared state that makes a suite lie.
  globalThis.indexedDB = new IDBFactory();
  db = await openDatabase();
});

function sessionAt(id: string, dateKey: string, minutes = 25) {
  return makeFocusSession({
    id, dateKey, actualFocusMinutes: minutes,
    kind: Kind.FOCUS, completion: Completion.COMPLETED, awardsApplied: true,
  });
}

async function writeRawSave(data: Json): Promise<void> {
  await transact(db, [SAVE_STORE], "readwrite", async (tx) => {
    await put(tx, SAVE_STORE, data, SAVE_KEY);
  });
}

describe("loadGarden", () => {
  it("reports a first run rather than inventing a save", async () => {
    const result = await loadGarden(db);
    expect(result.existed).toBe(false);
    expect(result.blocked).toBe(false);
    expect(result.sessions).toHaveLength(0);
  });

  it("round-trips a save and its sessions", async () => {
    const save = makeSaveData({
      profile: makePlayerProfile({ displayName: "Joshua", totalXp: 4200 }),
      plants: [makePlantInstance({ uid: "pl_1", speciesId: "aloe_vera" })],
    });
    await saveGarden(db, save);
    await putSessions(db, [sessionAt("s_1", "2026-08-28"), sessionAt("s_2", "2026-08-29")]);

    const result = await loadGarden(db);
    expect(result.existed).toBe(true);
    expect(result.save.profile.displayName).toBe("Joshua");
    expect(result.save.profile.totalXp).toBe(4200);
    expect(result.save.plants).toHaveLength(1);
    expect(result.sessions.map((s) => s.id).sort()).toEqual(["s_1", "s_2"]);
  });

  it("migrates an old save on the way in", async () => {
    // A format-1 garden: decorations were bare id strings and there was no theme.
    await writeRawSave({
      save_version: 1,
      garden: { decorations: { "0,0": "stone_bench" } },
      settings: {},
    });

    const result = await loadGarden(db);
    expect(result.blocked).toBe(false);
    expect(result.migratedFrom).toBe(1);
    expect(result.save.saveVersion).toBe(CURRENT_VERSION);
    expect(result.save.garden.decorations["0,0"]).toEqual({ id: "stone_bench", rotation: 0 });
    expect(result.save.settings.themeMode).toBe("light");
  });

  it("REFUSES a save from a newer build and leaves it untouched", async () => {
    const future = { save_version: 99, player: { display_name: "Future", total_xp: 9999 } };
    await writeRawSave(future);

    const result = await loadGarden(db);
    expect(result.blocked).toBe(true);
    expect(result.existed).toBe(true);
    expect(result.blockedReason).toContain("newer version");
    // A fresh save in memory, so the app still runs...
    expect(result.save.profile.totalXp).toBe(0);
    // ...but the stored bytes are exactly as they were.
    const stored = await transact(db, [SAVE_STORE], "readonly",
      (tx) => get<Json>(tx, SAVE_STORE, SAVE_KEY));
    expect(stored).toEqual(future);
  });

  it("refuses when the migration chain has a gap", async () => {
    // Version 0 is below every step's `from`, so nothing can carry it forward.
    await writeRawSave({ save_version: 0 });
    const result = await loadGarden(db);
    expect(result.blocked).toBe(true);
    expect(result.blockedReason).toContain("cannot be upgraded");
  });

  it("drops an id-less session row rather than loading a record nothing can address", async () => {
    await saveGarden(db, makeSaveData());
    await transact(db, [SESSION_STORE], "readwrite", async (tx) => {
      await put(tx, SESSION_STORE, { id: "s_good", date_key: "2026-08-29" });
      // Written straight past putSession, the way a corrupted store would look.
      await put(tx, SESSION_STORE, { id: " ", date_key: "2026-08-29" });
    });
    const result = await loadGarden(db);
    expect(result.sessions.map((s) => s.id)).toContain("s_good");
  });
});

describe("saveGarden", () => {
  it("refuses to write when the load was blocked", async () => {
    const future = { save_version: 99, player: { total_xp: 9999 } };
    await writeRawSave(future);
    const loaded = await loadGarden(db);

    const wrote = await saveGarden(db, makeSaveData(), loaded.blocked);
    expect(wrote).toBe(false);

    // The whole point: the newer save is still there, unharmed.
    const stored = await transact(db, [SAVE_STORE], "readonly",
      (tx) => get<Json>(tx, SAVE_STORE, SAVE_KEY));
    expect(stored).toEqual(future);
  });

  it("refuses to write sessions when blocked", async () => {
    const wrote = await putSession(db, sessionAt("s_1", "2026-08-29"), true);
    expect(wrote).toBe(false);
    const rows = await transact(db, [SESSION_STORE], "readonly",
      (tx) => getAll<Json>(tx, SESSION_STORE));
    expect(rows).toHaveLength(0);
  });
});

describe("putSession", () => {
  it("replaces a row with the same id rather than duplicating it", async () => {
    await putSession(db, sessionAt("s_1", "2026-08-29", 25));
    await putSession(db, sessionAt("s_1", "2026-08-29", 40));

    const rows = await transact(db, [SESSION_STORE], "readonly",
      (tx) => getAll<Json>(tx, SESSION_STORE));
    // A repeated id would permanently double every figure derived from it.
    expect(rows).toHaveLength(1);
    expect(rows[0]!["actual_focus_minutes"]).toBe(40);
  });

  it("refuses an id-less session", async () => {
    expect(await putSession(db, makeFocusSession({ id: "" }))).toBe(false);
  });

  it("writes one session without rewriting the rest", async () => {
    // The reason sessions live in their own store: finishing a pomodoro must not
    // rewrite a decade of history.
    const many = Array.from({ length: 200 }, (_, i) => sessionAt(`s_${i}`, "2026-08-29"));
    await putSessions(db, many);
    await putSession(db, sessionAt("s_new", "2026-08-30"));

    const rows = await transact(db, [SESSION_STORE], "readonly",
      (tx) => getAll<Json>(tx, SESSION_STORE));
    expect(rows).toHaveLength(201);
  });

  it("removes a session by id", async () => {
    await putSessions(db, [sessionAt("s_1", "2026-08-29"), sessionAt("s_2", "2026-08-29")]);
    await deleteSession(db, "s_1");
    const result = await loadGarden(db);
    expect(result.sessions.map((s) => s.id)).toEqual(["s_2"]);
  });
});

describe("replaceAll", () => {
  it("replaces rather than merges, leaving nothing of the old garden", async () => {
    await saveGarden(db, makeSaveData({
      profile: makePlayerProfile({ displayName: "Old", totalXp: 100 }),
      garden: makeGardenLayout({ gridWidth: 8, gridHeight: 8 }),
    }));
    await putSessions(db, [sessionAt("s_old_1", "2026-01-01"), sessionAt("s_old_2", "2026-01-02")]);

    await replaceAll(
      db,
      makeSaveData({ profile: makePlayerProfile({ displayName: "New", totalXp: 7 }) }),
      [sessionAt("s_new", "2026-08-29")],
    );

    const result = await loadGarden(db);
    expect(result.save.profile.displayName).toBe("New");
    expect(result.save.profile.totalXp).toBe(7);
    // Import replaces. A leftover session from the previous garden would inflate
    // every total in the imported one.
    expect(result.sessions.map((s) => s.id)).toEqual(["s_new"]);
  });
});

describe("stored shape", () => {
  it("is the same dictionary the desktop writes", async () => {
    // A record pulled out of IndexedDB and handed to the desktop importer must
    // already be the right shape - that is what makes the two clients share one
    // format rather than translate between two.
    const save = makeSaveData({ profile: makePlayerProfile({ displayName: "Joshua" }) });
    await saveGarden(db, save);
    const stored = await transact(db, [SAVE_STORE], "readonly",
      (tx) => get<Json>(tx, SAVE_STORE, SAVE_KEY));
    expect(stored).toEqual(saveDataToDict(save));
    expect(stored!["save_version"]).toBe(CURRENT_VERSION);
    expect(stored!["player"]).toBeDefined();
  });
});
