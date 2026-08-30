/**
 * A rate limit for endpoints that send mail to whoever asks.
 *
 * Two limits, because one is not enough. A minimum interval stops the button
 * being held down; a daily cap stops a patient script from sending a hundred
 * messages an hour apart. Either alone leaves the other attack open.
 *
 * THE CLOCK IS PASSED IN, not read from `Date.now()` inside. Time is the one
 * input this module has, and a function that reads its own clock can only be
 * tested by sleeping - so the tests would either be slow or would not test the
 * window boundary at all, which is the only part worth testing.
 */

import { eq } from "drizzle-orm";

import type { Database } from "./db/client.js";
import { mailThrottle } from "./db/schema.js";

/** Shortest gap between two sends to the same address. */
export const MIN_INTERVAL_SECONDS = 60;

/** Most sends to one address in a rolling day. */
export const MAX_PER_WINDOW = 5;

const WINDOW_SECONDS = 60 * 60 * 24;

/**
 * The row key: a hash, never the address itself.
 *
 * The purpose is folded in so a verification limit and a password-reset limit
 * do not share a budget - being throttled out of resetting your password
 * because you asked for a verification link is a lockout, not a rate limit.
 */
export async function throttleKey(purpose: string, email: string): Promise<string> {
  const input = `${purpose}:${email.trim().toLowerCase()}`;
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

export interface ThrottleDecision {
  allowed: boolean;
  /** Seconds until the next send would be allowed. Zero when allowed. */
  retryAfter: number;
}

/**
 * Decide, and record the send if it is allowed.
 *
 * Deciding and recording are one call on purpose. Split into `check()` then
 * `record()`, every caller has to remember the second half, and the one that
 * forgets has no rate limit at all while looking like it does.
 */
export async function consume(
  db: Database, key: string, now: number,
): Promise<ThrottleDecision> {
  const rows = await db.select().from(mailThrottle).where(eq(mailThrottle.key, key)).limit(1);
  const row = rows[0];

  if (row === undefined) {
    await db.insert(mailThrottle)
      .values({ key, lastSentAt: now, windowStart: now, count: 1 });
    return { allowed: true, retryAfter: 0 };
  }

  const sinceLast = now - row.lastSentAt;
  if (sinceLast < MIN_INTERVAL_SECONDS) {
    return { allowed: false, retryAfter: MIN_INTERVAL_SECONDS - sinceLast };
  }

  // A window that has run out is replaced rather than extended, so the cap is a
  // rolling day from first send and not a permanent ban after the fifth.
  const windowExpired = now - row.windowStart >= WINDOW_SECONDS;
  const count = windowExpired ? 0 : row.count;
  const windowStart = windowExpired ? now : row.windowStart;

  if (count >= MAX_PER_WINDOW) {
    return { allowed: false, retryAfter: windowStart + WINDOW_SECONDS - now };
  }

  await db.update(mailThrottle)
    .set({ lastSentAt: now, windowStart, count: count + 1 })
    .where(eq(mailThrottle.key, key));
  return { allowed: true, retryAfter: 0 };
}
