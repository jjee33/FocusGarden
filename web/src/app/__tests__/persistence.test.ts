// @vitest-environment jsdom
/**
 * Does a garden survive a reload.
 *
 * These go through the real hook against a real IndexedDB, because the failure
 * modes live in the wiring rather than in either half: hydrating before the seed
 * overwrites it, writing when the load said not to, and offering back a session
 * that was interrupted by the tab closing.
 */

import "fake-indexeddb/auto";
import { IDBFactory } from "fake-indexeddb";
import { act, renderHook, waitFor } from "@testing-library/react";
import { beforeEach, describe, expect, it, vi } from "vitest";

import { useGarden } from "../useGarden.js";
import { Completion, Kind, makeFocusSession } from "../../domain/focus-session.js";
import { GameClock } from "../../domain/game-clock.js";
import {
  SAVE_KEY, SAVE_STORE, get, openDatabase, put, transact,
} from "../../storage/db.js";
import { buildInFlight } from "../../domain/in-flight.js";
import type { Json } from "../../domain/dict-util.js";

beforeEach(() => {
  globalThis.indexedDB = new IDBFactory();
});

/** Renders the hook and waits for the first load to settle. */
async function mounted() {
  const rendered = renderHook(() => useGarden());
  await waitFor(() => expect(rendered.result.current.storage.ready).toBe(true));
  return rendered;
}

describe("hydration", () => {
  it("seeds and persists on a genuine first run", async () => {
    const { result } = await mounted();
    expect(result.current.storage.ephemeral).toBe(false);
    expect(result.current.save.plants.length).toBeGreaterThan(0);

    const db = await openDatabase();
    const stored = await transact(db, [SAVE_STORE], "readonly",
      (tx) => get<Json>(tx, SAVE_STORE, SAVE_KEY));
    expect(stored).toBeDefined();
  });

  it("restores what was stored instead of re-seeding over it", async () => {
    const first = await mounted();
    act(() => {
      first.result.current.completeSession(
        Kind.FOCUS, 25, 25, Completion.COMPLETED, "p_networkplus", "pl_monstera",
      );
    });
    const xp = first.result.current.save.profile.totalXp;
    const sessionCount = first.result.current.sessions.length;
    await waitFor(() => expect(xp).toBeGreaterThan(0));
    first.unmount();

    // A second mount is a reload: same database, new hook.
    const second = await mounted();
    await waitFor(() => {
      expect(second.result.current.save.profile.totalXp).toBe(xp);
    });
    expect(second.result.current.sessions).toHaveLength(sessionCount);
  });

  it("runs without storage rather than failing, and says so", async () => {
    // A private window, cleared site data, or a browser set to block storage.
    vi.spyOn(globalThis.indexedDB, "open").mockImplementation(() => {
      throw new Error("blocked");
    });
    const { result } = await mounted();
    expect(result.current.storage.ephemeral).toBe(true);
    expect(result.current.storage.blockedReason).toContain("not letting");
    // The app still works; it simply cannot remember.
    expect(result.current.save.plants.length).toBeGreaterThan(0);
    vi.restoreAllMocks();
  });

  it("refuses to overwrite a save from a newer build", async () => {
    const db = await openDatabase();
    const future: Json = { save_version: 99, player: { display_name: "Future", total_xp: 9999 } };
    await transact(db, [SAVE_STORE], "readwrite", async (tx) => {
      await put(tx, SAVE_STORE, future, SAVE_KEY);
    });

    const { result } = await mounted();
    expect(result.current.storage.blocked).toBe(true);
    expect(result.current.storage.blockedReason).toContain("newer version");

    // Make a change that would normally be written.
    act(() => {
      result.current.completeSession(
        Kind.FOCUS, 25, 25, Completion.COMPLETED, "p", "pl_monstera",
      );
    });
    await waitFor(() => expect(result.current.save.profile.totalXp).toBeGreaterThan(0));

    const stored = await transact(db, [SAVE_STORE], "readonly",
      (tx) => get<Json>(tx, SAVE_STORE, SAVE_KEY));
    // Untouched. A save is never silently erased.
    expect(stored).toEqual(future);
  });
});

describe("in-flight recovery", () => {
  it("offers back a session the tab closed on, without crediting it", async () => {
    const db = await openDatabase();
    const clock = new GameClock({
      monotonic: () => 1000,
      wall: () => Date.now() / 1000 - 600,
    });
    clock.start();
    const interrupted = makeFocusSession({
      id: "s_interrupted", kind: Kind.FOCUS, intendedDurationMinutes: 25,
      dateKey: "2026-08-29", plantUid: "pl_monstera",
    });
    await transact(db, [SAVE_STORE], "readwrite", async (tx) => {
      await put(tx, SAVE_STORE, {
        save_version: 2,
        in_flight_session: buildInFlight(interrupted, clock),
      }, SAVE_KEY);
    });

    const { result } = await mounted();
    await waitFor(() => expect(result.current.recovered).not.toBeNull());
    expect(result.current.recovered!.id).toBe("s_interrupted");
    // Offered, not applied: only the player knows whether they were focusing.
    expect(result.current.save.profile.totalXp).toBe(0);
    expect(result.current.sessions).toHaveLength(0);
  });

  it("credits a recovered session when the player accepts it", async () => {
    const db = await openDatabase();
    const clock = new GameClock({
      monotonic: () => 1000,
      wall: () => Date.now() / 1000 - 600,
    });
    clock.start();
    await transact(db, [SAVE_STORE], "readwrite", async (tx) => {
      await put(tx, SAVE_STORE, {
        save_version: 2,
        in_flight_session: buildInFlight(makeFocusSession({
          id: "s_interrupted", kind: Kind.FOCUS, intendedDurationMinutes: 25,
          dateKey: "2026-08-29",
        }), clock),
      }, SAVE_KEY);
    });

    const { result } = await mounted();
    await waitFor(() => expect(result.current.recovered).not.toBeNull());
    act(() => result.current.acceptRecovered());

    await waitFor(() => expect(result.current.sessions).toHaveLength(1));
    expect(result.current.recovered).toBeNull();
    expect(result.current.save.profile.totalXp).toBeGreaterThan(0);
    // Cleared, so a second reload does not offer the same session again.
    expect(result.current.save.inFlightSession).toEqual({});
  });

  it("throws a recovered session away when the player declines", async () => {
    const db = await openDatabase();
    const clock = new GameClock({ monotonic: () => 1000, wall: () => Date.now() / 1000 - 60 });
    clock.start();
    await transact(db, [SAVE_STORE], "readwrite", async (tx) => {
      await put(tx, SAVE_STORE, {
        save_version: 2,
        in_flight_session: buildInFlight(makeFocusSession({
          id: "s_interrupted", intendedDurationMinutes: 25, dateKey: "2026-08-29",
        }), clock),
      }, SAVE_KEY);
    });

    const { result } = await mounted();
    await waitFor(() => expect(result.current.recovered).not.toBeNull());
    act(() => result.current.discardRecovered());

    expect(result.current.recovered).toBeNull();
    expect(result.current.sessions).toHaveLength(0);
    expect(result.current.save.profile.totalXp).toBe(0);
  });
});

describe("transfer", () => {
  it("exports a bundle and imports it back over a different garden", async () => {
    const first = await mounted();
    act(() => {
      first.result.current.completeSession(
        Kind.FOCUS, 25, 25, Completion.COMPLETED, "p_networkplus", "pl_monstera",
      );
    });
    await waitFor(() => expect(first.result.current.save.profile.totalXp).toBeGreaterThan(0));
    const bundle = first.result.current.exportBundle("0.1.0");
    const expectedXp = first.result.current.save.profile.totalXp;
    const expectedSessions = first.result.current.sessions.length;
    first.unmount();

    // A different browser, a fresh database.
    globalThis.indexedDB = new IDBFactory();
    const second = await mounted();
    let outcome: Awaited<ReturnType<typeof second.result.current.importBundle>> | null = null;
    await act(async () => {
      outcome = await second.result.current.importBundle(bundle);
    });

    expect(outcome!.ok).toBe(true);
    await waitFor(() => {
      expect(second.result.current.save.profile.totalXp).toBe(expectedXp);
    });
    expect(second.result.current.sessions).toHaveLength(expectedSessions);
  });

  it("refuses a bundle from a newer build without touching the garden", async () => {
    const { result } = await mounted();
    const before = result.current.save.profile.totalXp;

    let outcome: { ok: boolean; reason?: string } | null = null;
    await act(async () => {
      outcome = await result.current.importBundle({ save_version: 99 });
    });

    expect(outcome!.ok).toBe(false);
    expect(outcome!.reason).toContain("newer version");
    expect(result.current.save.profile.totalXp).toBe(before);
  });

  it("empties the in-flight session on export, so it does not travel", async () => {
    const { result } = await mounted();
    const clock = new GameClock();
    clock.start();
    act(() => {
      result.current.persistInFlight(
        makeFocusSession({ id: "s_running", intendedDurationMinutes: 25 }), clock,
      );
    });
    await waitFor(() =>
      expect(Object.keys(result.current.save.inFlightSession).length).toBeGreaterThan(0));

    const bundle = result.current.exportBundle("0.1.0");
    // Offering to resume a pomodoro interrupted on another machine is nonsense.
    expect(bundle["in_flight_session"]).toEqual({});
  });
});
