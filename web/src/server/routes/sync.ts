/**
 * Push and pull.
 *
 * The server does not merge. It stores what it is given, hands back what it
 * holds, and assigns revisions - the reconciliation happens on the client, in
 * `domain/sync.ts`, where it can be tested without a database and where the 10 ms
 * Worker CPU budget is not a consideration.
 *
 * REVISIONS ARE ASSIGNED HERE, from one counter per account. That is what makes
 * "same revision" mean "same version" on every device: a client never invents
 * one, it marks a record dirty and takes the number this hands back. One counter
 * per user rather than one per record also makes "everything since N" a single
 * comparison instead of a scan.
 *
 * PUSHES ARE IDEMPOTENT, keyed on a client-generated request id. A push that
 * times out on a flaky connection gets retried, and without the guard the retry
 * would apply the same batch twice - which for append-only sessions means
 * duplicate rows, and duplicate rows permanently double every figure derived
 * from them.
 */

import { Hono } from "hono";
import { and, eq, gt, inArray } from "drizzle-orm";

import type { Database } from "../db/client.js";
import {
  achievementState, catalogueEntry, dailyRollup, focusSession, journalEntry,
  plant, profile, project, pushLog, revisionCounter,
} from "../db/schema.js";
import type { AppBindings } from "../context.js";

/** The syncable collections, so push and pull do not each list them separately. */
const COLLECTIONS = {
  plants: plant,
  projects: project,
  catalogue: catalogueEntry,
  achievements: achievementState,
} as const;

type CollectionName = keyof typeof COLLECTIONS;

interface WireRecord {
  id: string;
  revision: number;
  updatedAt: number;
  deletedAt: number | null;
  value: unknown;
}

interface PushBody {
  /** Client-generated, stable across retries of the same batch. */
  requestId: string;
  profile?: { data: unknown; saveVersion: number; revision: number; updatedAt: number };
  plants?: WireRecord[];
  projects?: WireRecord[];
  catalogue?: WireRecord[];
  achievements?: WireRecord[];
  /** Append-only; no revisions, deduplicated by id. */
  journal?: { id: string; data: unknown; createdAt: number }[];
  sessions?: { id: string; dateKey: string; data: unknown; createdAt: number }[];
}

/** Next revision for this account. Read and written inside the caller's batch. */
async function nextRevision(db: Database, userId: string): Promise<number> {
  const existing = await db.select().from(revisionCounter)
    .where(eq(revisionCounter.userId, userId)).get();
  const next = (existing?.value ?? 0) + 1;
  await db.insert(revisionCounter).values({ userId, value: next })
    .onConflictDoUpdate({ target: revisionCounter.userId, set: { value: next } });
  return next;
}

export function syncRoutes() {
  const app = new Hono<AppBindings>();

  /**
   * Everything the client has not seen.
   *
   * `since` is the last revision it holds. Sessions are filtered by `createdAt`
   * instead, because they carry no revision - being immutable, they only ever
   * appear, never change.
   */
  app.get("/pull", async (c) => {
    const user = c.get("user");
    const db = c.get("db");
    const since = Number(c.req.query("since") ?? "0");
    const sessionsSince = Number(c.req.query("sessionsSince") ?? "0");

    const counter = await db.select().from(revisionCounter)
      .where(eq(revisionCounter.userId, user.id)).get();

    const profileRow = await db.select().from(profile)
      .where(and(eq(profile.userId, user.id), gt(profile.revision, since))).get();

    const collections: Record<string, WireRecord[]> = {};
    for (const [name, table] of Object.entries(COLLECTIONS)) {
      const rows = await db.select().from(table)
        .where(and(eq(table.userId, user.id), gt(table.revision, since))).all();
      collections[name] = rows.map((row) => ({
        id: row.id,
        revision: row.revision,
        updatedAt: row.updatedAt,
        deletedAt: row.deletedAt,
        value: row.data,
      }));
    }

    const journal = await db.select().from(journalEntry)
      .where(and(eq(journalEntry.userId, user.id), gt(journalEntry.createdAt, sessionsSince)))
      .all();

    const sessions = await db.select().from(focusSession)
      .where(and(eq(focusSession.userId, user.id), gt(focusSession.createdAt, sessionsSince)))
      .all();

    return c.json({
      revision: counter?.value ?? 0,
      profile: profileRow === undefined ? null : {
        data: profileRow.data,
        saveVersion: profileRow.saveVersion,
        revision: profileRow.revision,
        updatedAt: profileRow.updatedAt,
      },
      ...collections,
      journal: journal.map((row) => ({ id: row.id, data: row.data, createdAt: row.createdAt })),
      sessions: sessions.map((row) => ({
        id: row.id, dateKey: row.dateKey, data: row.data, createdAt: row.createdAt,
      })),
    });
  });

  /**
   * Applies a batch and reports the revision each record was given.
   *
   * Everything lands under one revision: a batch is one logical change, and
   * numbering its members separately would let a partially-pulled client believe
   * it had a consistent view when it had half of one.
   */
  app.post("/push", async (c) => {
    const user = c.get("user");
    const db = c.get("db");
    const body = await c.req.json<PushBody>();

    if (typeof body.requestId !== "string" || body.requestId === "") {
      return c.json({ error: "requestId is required so a retry cannot apply twice." }, 400);
    }

    // The retry guard. Inserted first: if this conflicts, the batch already
    // landed and re-applying it would duplicate append-only rows.
    const alreadyApplied = await db.select().from(pushLog)
      .where(and(eq(pushLog.userId, user.id), eq(pushLog.requestId, body.requestId))).get();
    if (alreadyApplied !== undefined) {
      const counter = await db.select().from(revisionCounter)
        .where(eq(revisionCounter.userId, user.id)).get();
      return c.json({ revision: counter?.value ?? 0, duplicate: true, acknowledged: {} });
    }

    const revision = await nextRevision(db, user.id);
    const now = Math.floor(Date.now() / 1000);
    const acknowledged: Record<string, string[]> = {};

    if (body.profile !== undefined) {
      await db.insert(profile).values({
        userId: user.id,
        data: body.profile.data,
        saveVersion: body.profile.saveVersion,
        revision,
        updatedAt: body.profile.updatedAt,
      }).onConflictDoUpdate({
        target: profile.userId,
        set: { data: body.profile.data, saveVersion: body.profile.saveVersion, revision,
          updatedAt: body.profile.updatedAt },
      });
    }

    for (const name of Object.keys(COLLECTIONS) as CollectionName[]) {
      const table = COLLECTIONS[name];
      const records = body[name] ?? [];
      acknowledged[name] = [];
      for (const record of records) {
        if (typeof record.id !== "string" || record.id === "") continue;
        await db.insert(table).values({
          id: record.id,
          userId: user.id,
          data: record.value,
          revision,
          updatedAt: record.updatedAt,
          deletedAt: record.deletedAt,
        }).onConflictDoUpdate({
          // MUST match the table's primary key, which is (user_id, id). Naming
          // only `id` here is what let one account's push overwrite another
          // account's row - the conflict it resolved was the wrong conflict.
          target: [table.userId, table.id],
          set: { data: record.value, revision, updatedAt: record.updatedAt,
            deletedAt: record.deletedAt },
        });
        acknowledged[name]!.push(record.id);
      }
    }

    // Append-only, so a repeat is ignored rather than overwritten. `doNothing`
    // is the whole deduplication: the row that exists is the one that counts.
    for (const entry of body.journal ?? []) {
      if (typeof entry.id !== "string" || entry.id === "") continue;
      await db.insert(journalEntry)
        .values({ id: entry.id, userId: user.id, data: entry.data, createdAt: entry.createdAt })
        .onConflictDoNothing();
    }

    const touchedDays = new Set<string>();
    for (const entry of body.sessions ?? []) {
      if (typeof entry.id !== "string" || entry.id === "") continue;
      await db.insert(focusSession).values({
        id: entry.id, userId: user.id, dateKey: entry.dateKey,
        data: entry.data, createdAt: entry.createdAt,
      }).onConflictDoNothing();
      touchedDays.add(entry.dateKey);
    }

    if (touchedDays.size > 0) await rebuildRollups(db, user.id, [...touchedDays]);

    await db.insert(pushLog)
      .values({ userId: user.id, requestId: body.requestId, appliedAt: now })
      .onConflictDoNothing();

    return c.json({ revision, duplicate: false, acknowledged });
  });

  return app;
}

/**
 * Recomputes the rollup for the days a push touched.
 *
 * Recomputed from the rows rather than incremented, because an increment is
 * wrong the moment a push is retried or a session arrives out of order, and a
 * silently wrong total is exactly what keeping the full history is meant to
 * prevent. Only the affected days are touched, so the cost is bounded by the
 * push and not by the size of the account.
 */
async function rebuildRollups(db: Database, userId: string, dateKeys: string[]): Promise<void> {
  const rows = await db.select().from(focusSession)
    .where(and(eq(focusSession.userId, userId), inArray(focusSession.dateKey, dateKeys)))
    .all();

  const totals = new Map<string, { minutes: number; count: number }>();
  for (const key of dateKeys) totals.set(key, { minutes: 0, count: 0 });

  for (const row of rows) {
    const data = row.data as { actual_focus_minutes?: number; kind?: number; completion?: number };
    // The same rule the client uses: cancelled sessions and zero-length ones do
    // not count, and breaks are not focus.
    const minutes = typeof data.actual_focus_minutes === "number" ? data.actual_focus_minutes : 0;
    if (data.completion === 2 || minutes <= 0 || data.kind !== 0) continue;
    const bucket = totals.get(row.dateKey);
    if (bucket === undefined) continue;
    bucket.minutes += minutes;
    bucket.count += 1;
  }

  for (const [dateKey, bucket] of totals) {
    await db.insert(dailyRollup).values({
      userId, dateKey,
      focusMinutes: Math.round(bucket.minutes),
      sessionCount: bucket.count,
    }).onConflictDoUpdate({
      target: [dailyRollup.userId, dailyRollup.dateKey],
      set: { focusMinutes: Math.round(bucket.minutes), sessionCount: bucket.count },
    });
  }
}
