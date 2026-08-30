/**
 * @vitest-environment jsdom
 *
 * IndexedDB is specified to fire success, error or blocked. In practice it can
 * fire NONE of them and hang - a connection left half-closed by a crashed tab, a
 * delete that never finished, storage pressure. When that happened the whole app
 * sat on its loading screen forever, because the shell waits for storage before
 * rendering anything.
 *
 * These pin the deadline that turns that hang into a working app that admits it
 * cannot save.
 */

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { openDatabase } from "../db.js";

/** A factory whose open() never settles - the exact failure being guarded. */
function silentFactory(): IDBFactory {
  return {
    open: () => ({
      onsuccess: null, onerror: null, onblocked: null, onupgradeneeded: null,
      result: null, error: null,
    }),
  } as unknown as IDBFactory;
}

/** A factory that reports failure promptly, the ordinary error path. */
function failingFactory(): IDBFactory {
  return {
    open: () => {
      const req = {
        onsuccess: null as null | (() => void),
        onerror: null as null | (() => void),
        onblocked: null, onupgradeneeded: null,
        result: null, error: new Error("refused"),
      };
      queueMicrotask(() => { req.onerror?.(); });
      return req;
    },
  } as unknown as IDBFactory;
}

describe("openDatabase", () => {
  beforeEach(() => { vi.useFakeTimers(); });
  afterEach(() => { vi.useRealTimers(); });

  it("gives up on a request that never settles, rather than hanging forever", async () => {
    const promise = openDatabase(silentFactory());
    const assertion = expect(promise).rejects.toThrow(/did not respond/i);
    await vi.advanceTimersByTimeAsync(5000);
    await assertion;
  });

  it("says something a person could act on, not 'undefined'", async () => {
    const promise = openDatabase(silentFactory()).then(
      () => new Error("resolved when it should have timed out"),
      (e: unknown) => e as Error,
    );
    await vi.advanceTimersByTimeAsync(5000);
    const error = await promise;
    // The caller turns this into an on-screen notice, so it has to read as a
    // sentence rather than as a symbol.
    expect(error.message).toMatch(/garden/i);
    expect(error.message.length).toBeGreaterThan(40);
  });

  it("closes a connection that answers after the deadline, instead of leaking it", async () => {
    let closed = false;
    const req = {
      onsuccess: null as null | (() => void),
      onerror: null, onblocked: null, onupgradeneeded: null,
      result: { close: () => { closed = true; } },
      error: null,
    };
    const factory = { open: () => req } as unknown as IDBFactory;

    const promise = openDatabase(factory);
    const assertion = expect(promise).rejects.toThrow(/did not respond/i);
    await vi.advanceTimersByTimeAsync(5000);
    await assertion;

    // The browser finally answers, long after the app moved on. That late
    // connection would hold the upgrade lock forever if it were left open.
    req.onsuccess?.();
    expect(closed).toBe(true);
  });

  it("still rejects immediately when the browser answers with an error", async () => {
    const promise = openDatabase(failingFactory()).then(
      () => new Error("resolved when the browser reported an error"),
      (e: unknown) => e as Error,
    );
    // No timer advance: this must not wait for the deadline to report a failure
    // the browser already reported.
    await vi.advanceTimersByTimeAsync(0);
    const error = await promise;
    expect(error.message).toBe("refused");
  });
});
