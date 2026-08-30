/**
 * The rate limit on the one mail endpoint an anonymous caller can reach.
 *
 * The database is faked rather than spun up, because nothing here is testing
 * SQLite - it is testing the arithmetic of two overlapping limits, and the
 * boundary cases (exactly at the interval, exactly at the window edge, one
 * second short of each) are the whole point.
 */

import { describe, expect, it } from "vitest";

import type { Database } from "../db/client.js";
import { MAX_PER_WINDOW, MIN_INTERVAL_SECONDS, consume, throttleKey } from "../throttle.js";

interface Row { key: string; lastSentAt: number; windowStart: number; count: number }

/**
 * The narrowest thing `consume` actually uses: select-one, insert, update.
 *
 * Deliberately not a spy. What matters is that the state stored after N calls
 * produces the right decision on call N+1, and a fake that really stores things
 * tests that; a spy only tests that the code was written the way the test
 * expected it to be written.
 *
 * It is built per key rather than parsing Drizzle's condition objects, which
 * would be a lot of machinery to re-derive a value the caller already has.
 */
function forKey(rows: Map<string, Row>, key: string): Database {
  return {
    select: () => ({
      from: () => ({
        where: () => ({
          limit: () => {
            const found = rows.get(key);
            return Promise.resolve(found === undefined ? [] : [found]);
          },
        }),
      }),
    }),
    insert: () => ({
      values: (row: Row) => {
        rows.set(row.key, { ...row });
        return Promise.resolve();
      },
    }),
    update: () => ({
      set: (patch: Partial<Row>) => ({
        where: () => {
          const existing = rows.get(key);
          if (existing !== undefined) rows.set(key, { ...existing, ...patch });
          return Promise.resolve();
        },
      }),
    }),
  } as unknown as Database;
}

function store(): Map<string, Row> {
  return new Map<string, Row>();
}

function call(rows: Map<string, Row>, key: string, now: number) {
  return consume(forKey(rows, key), key, now);
}

const KEY = "k";
const DAY = 60 * 60 * 24;

describe("throttleKey", () => {
  it("never contains the address it was built from", async () => {
    const key = await throttleKey("verify", "someone@example.com");
    expect(key).not.toContain("someone");
    expect(key).not.toContain("example");
    expect(key).toMatch(/^[0-9a-f]{64}$/);
  });

  it("ignores case and surrounding space, so one person is one bucket", async () => {
    expect(await throttleKey("verify", "  Someone@Example.COM ")).toBe(
      await throttleKey("verify", "someone@example.com"),
    );
  });

  it("separates purposes, so a verify limit cannot lock you out of a reset", async () => {
    expect(await throttleKey("verify", "a@b.com")).not.toBe(await throttleKey("reset", "a@b.com"));
  });
});

describe("consume", () => {
  it("allows the first send", async () => {
    const h = store();
    expect(await call(h, KEY, 1000)).toEqual({ allowed: true, retryAfter: 0 });
  });

  it("refuses a second send inside the minimum interval", async () => {
    const h = store();
    await call(h, KEY, 1000);
    const decision = await call(h, KEY, 1000 + MIN_INTERVAL_SECONDS - 1);
    expect(decision.allowed).toBe(false);
    expect(decision.retryAfter).toBe(1);
  });

  it("allows exactly at the interval boundary", async () => {
    const h = store();
    await call(h, KEY, 1000);
    expect(await call(h, KEY, 1000 + MIN_INTERVAL_SECONDS)).toEqual({ allowed: true, retryAfter: 0 });
  });

  it("refuses past the daily cap even when the interval is respected", async () => {
    const h = store();
    let now = 1000;
    for (let i = 0; i < MAX_PER_WINDOW; i++) {
      expect((await call(h, KEY, now)).allowed).toBe(true);
      now += MIN_INTERVAL_SECONDS;
    }
    // This is the attack the interval alone does not stop: a patient caller that
    // simply waits the minimum gap every time.
    expect((await call(h, KEY, now)).allowed).toBe(false);
  });

  it("rolls the window rather than banning forever", async () => {
    const h = store();
    let now = 1000;
    for (let i = 0; i < MAX_PER_WINDOW; i++) {
      await call(h, KEY, now);
      now += MIN_INTERVAL_SECONDS;
    }
    expect((await call(h, KEY, now)).allowed).toBe(false);

    // A day after the window opened, the budget is fresh. Without this the fifth
    // send of someone's life would lock the address out permanently.
    const afterWindow = 1000 + DAY;
    expect((await call(h, KEY, afterWindow)).allowed).toBe(true);
    expect(h.get(KEY)?.count).toBe(1);
  });

  it("reports how long to wait when the daily cap is what refused", async () => {
    const h = store();
    let now = 1000;
    for (let i = 0; i < MAX_PER_WINDOW; i++) {
      await call(h, KEY, now);
      now += MIN_INTERVAL_SECONDS;
    }
    const decision = await call(h, KEY, now);
    expect(decision.retryAfter).toBe(1000 + DAY - now);
  });

  it("keeps separate addresses on separate budgets", async () => {
    const h = store();
    let now = 1000;
    for (let i = 0; i < MAX_PER_WINDOW; i++) {
      await call(h, "a", now);
      now += MIN_INTERVAL_SECONDS;
    }
    expect((await call(h, "a", now)).allowed).toBe(false);
    expect((await call(h, "b", now)).allowed).toBe(true);
  });
});
