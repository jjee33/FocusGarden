/**
 * The database, in Drizzle's SQLite dialect.
 *
 * SQLite because the first deployment is Cloudflare D1. The dialect is the only
 * Cloudflare-shaped thing in here; swapping to Postgres later is a change of
 * import and column helper, not a redesign, which is the point of writing it
 * through Drizzle rather than raw SQL.
 *
 * WHY MOST OF IT IS JSON. The server never computes anything. Every rule - XP,
 * growth, streaks, achievements - runs in the browser over a local copy, because
 * a Worker gets 10 ms of CPU on the free plan and evaluating a requirement over
 * a long history would blow it. So the server is a store, and the only columns
 * that need to be real columns are the ones it actually filters or orders by:
 * the owner, the sync metadata, and a session's date. Normalising twenty fields
 * per entity would buy nothing and would mean every model change had to be made
 * in two places and kept in step.
 *
 * NAME COLLISION, deliberately respected: better-auth owns a table called
 * `session`. Ours is `focus_session`. Getting this wrong would have auth
 * silently sharing a table with somebody's pomodoros.
 */

import { index, integer, primaryKey, sqliteTable, text, uniqueIndex } from "drizzle-orm/sqlite-core";

// ---------------------------------------------------------------- better-auth

/**
 * These four are better-auth's, and their shape is its contract, not ours. They
 * are declared here so Drizzle can see them and so migrations are generated from
 * one place; nothing in this project should write to them directly.
 */
export const user = sqliteTable("user", {
  id: text("id").primaryKey(),
  name: text("name").notNull(),
  email: text("email").notNull().unique(),
  emailVerified: integer("email_verified", { mode: "boolean" }).notNull().default(false),
  image: text("image"),
  createdAt: integer("created_at", { mode: "timestamp" }).notNull(),
  updatedAt: integer("updated_at", { mode: "timestamp" }).notNull(),
});

export const session = sqliteTable("session", {
  id: text("id").primaryKey(),
  expiresAt: integer("expires_at", { mode: "timestamp" }).notNull(),
  token: text("token").notNull().unique(),
  createdAt: integer("created_at", { mode: "timestamp" }).notNull(),
  updatedAt: integer("updated_at", { mode: "timestamp" }).notNull(),
  ipAddress: text("ip_address"),
  userAgent: text("user_agent"),
  userId: text("user_id").notNull().references(() => user.id, { onDelete: "cascade" }),
});

/**
 * `issuer` is not optional, and leaving it out does not fail at startup.
 *
 * better-auth 1.7 scopes account identity by issuer, so the unique key is
 * (issuer, accountId) rather than accountId alone. Omitting the column let the
 * server boot, let sign-up create the USER row, and only then threw - which
 * meant the credential row holding the password hash was never written. The
 * result was an account that existed, could never sign in even once verified,
 * and reported "already taken" on a second attempt.
 *
 * These four tables are better-auth's contract, not ours, and this is what it
 * costs to transcribe a contract by hand: the drift is invisible until the exact
 * request that needs the missing piece. Worth re-checking against
 * `@better-auth/core/dist/db/get-tables.mjs` on every upgrade - `user`,
 * `session` and `verification` were verified against it and match.
 */
export const account = sqliteTable("account", {
  id: text("id").primaryKey(),
  /** "credential" for email+password; the provider id for social sign-in. */
  issuer: text("issuer").notNull(),
  accountId: text("account_id").notNull(),
  providerId: text("provider_id").notNull(),
  userId: text("user_id").notNull().references(() => user.id, { onDelete: "cascade" }),
  accessToken: text("access_token"),
  refreshToken: text("refresh_token"),
  idToken: text("id_token"),
  accessTokenExpiresAt: integer("access_token_expires_at", { mode: "timestamp" }),
  refreshTokenExpiresAt: integer("refresh_token_expires_at", { mode: "timestamp" }),
  scope: text("scope"),
  password: text("password"),
  createdAt: integer("created_at", { mode: "timestamp" }).notNull(),
  updatedAt: integer("updated_at", { mode: "timestamp" }).notNull(),
}, (table) => [
  uniqueIndex("account_issuer_account_id").on(table.issuer, table.accountId),
  index("account_user_id").on(table.userId),
]);

export const verification = sqliteTable("verification", {
  id: text("id").primaryKey(),
  identifier: text("identifier").notNull(),
  value: text("value").notNull(),
  expiresAt: integer("expires_at", { mode: "timestamp" }).notNull(),
  createdAt: integer("created_at", { mode: "timestamp" }),
  updatedAt: integer("updated_at", { mode: "timestamp" }),
});

// ------------------------------------------------------------------- the game

/**
 * One row per user: the profile scalars and the layouts, as the save writes them.
 *
 * `revision` is SERVER-ASSIGNED and is what makes "same revision" mean "same
 * version" everywhere. A client never invents one; it marks a record dirty and
 * the server hands back the next number on push.
 */
export const profile = sqliteTable("profile", {
  userId: text("user_id").primaryKey().references(() => user.id, { onDelete: "cascade" }),
  /** `SaveData.to_dict()` minus the collections. Version 2 of the shared format. */
  data: text("data", { mode: "json" }).notNull(),
  saveVersion: integer("save_version").notNull(),
  revision: integer("revision").notNull().default(1),
  updatedAt: integer("updated_at").notNull(),
});

/**
 * A syncable collection member. Deletes are TOMBSTONES: `deletedAt` is set and
 * the row stays, because an absent row is ambiguous between "deleted" and "not
 * seen yet", and guessing wrong either resurrects something someone threw away
 * or discards something they made elsewhere.
 */
function syncable(name: string) {
  return sqliteTable(name, {
    id: text("id").primaryKey(),
    userId: text("user_id").notNull().references(() => user.id, { onDelete: "cascade" }),
    data: text("data", { mode: "json" }).notNull(),
    revision: integer("revision").notNull().default(1),
    updatedAt: integer("updated_at").notNull(),
    deletedAt: integer("deleted_at"),
  }, (table) => [index(`${name}_user_idx`).on(table.userId, table.revision)]);
}

export const plant = syncable("plant");
export const project = syncable("project");
export const catalogueEntry = syncable("catalogue_entry");
export const achievementState = syncable("achievement_state");

/**
 * The journal is append-only and never rewritten, so it needs no revision and no
 * tombstone - which is also why it is not `syncable`.
 */
export const journalEntry = sqliteTable("journal_entry", {
  id: text("id").primaryKey(),
  userId: text("user_id").notNull().references(() => user.id, { onDelete: "cascade" }),
  data: text("data", { mode: "json" }).notNull(),
  createdAt: integer("created_at").notNull(),
}, (table) => [index("journal_user_idx").on(table.userId, table.createdAt)]);

/**
 * Focus sessions: immutable, append-only, unique ids. Syncing them is a set
 * union, so there is no revision here either - nothing ever edits one.
 *
 * `dateKey` is a real column because it is the one thing the server orders and
 * filters by: it is how a rollup is rebuilt and how a partial pull is bounded.
 */
export const focusSession = sqliteTable("focus_session", {
  id: text("id").primaryKey(),
  userId: text("user_id").notNull().references(() => user.id, { onDelete: "cascade" }),
  /** Local "YYYY-MM-DD", captured at record time and never recomputed. */
  dateKey: text("date_key").notNull(),
  data: text("data", { mode: "json" }).notNull(),
  createdAt: integer("created_at").notNull(),
}, (table) => [
  index("focus_session_user_date_idx").on(table.userId, table.dateKey),
  index("focus_session_user_created_idx").on(table.userId, table.createdAt),
]);

/**
 * A write-time cache, and the one concession to D1's 5M row-reads per day.
 *
 * `focus_session` stays authoritative and every figure remains recomputable from
 * it - the project's rule that no statistic is stored as a bare total is intact.
 * This exists so the heatmap and a returning client's first paint do not scan a
 * year of rows, and it can be rebuilt from scratch at any time.
 */
export const dailyRollup = sqliteTable("daily_rollup", {
  userId: text("user_id").notNull().references(() => user.id, { onDelete: "cascade" }),
  dateKey: text("date_key").notNull(),
  focusMinutes: integer("focus_minutes").notNull().default(0),
  sessionCount: integer("session_count").notNull().default(0),
}, (table) => [
  primaryKey({ columns: [table.userId, table.dateKey] }),
]);

/**
 * The last revision handed out per user, so revisions are monotonic per account
 * rather than per record. One counter is simpler to reason about than many and
 * makes "everything changed since revision N" a single comparison.
 */
export const revisionCounter = sqliteTable("revision_counter", {
  userId: text("user_id").primaryKey().references(() => user.id, { onDelete: "cascade" }),
  value: integer("value").notNull().default(0),
});

/** Guards against the same device pushing the same batch twice on a retry. */
export const pushLog = sqliteTable("push_log", {
  userId: text("user_id").notNull().references(() => user.id, { onDelete: "cascade" }),
  requestId: text("request_id").notNull(),
  appliedAt: integer("applied_at").notNull(),
}, (table) => [
  uniqueIndex("push_log_unique").on(table.userId, table.requestId),
]);

/**
 * Rate limiting for the emails anyone can ask for without signing in.
 *
 * `/api/account/resend-verification` takes an address from an anonymous caller
 * and sends mail to it. Unthrottled that is a spam amplifier pointed at a
 * stranger's inbox with our sending domain on it, which costs us the domain's
 * reputation and them their afternoon.
 *
 * THE KEY IS A HASH, NOT THE ADDRESS. Anyone can POST any email here, so an
 * unhashed column would fill with addresses belonging to people who never had an
 * account and never asked us to store anything about them. A hash still throttles
 * exactly as well - the same input lands on the same row - while holding nothing
 * readable about the people who are only here because somebody typed their
 * address into a form.
 */
export const mailThrottle = sqliteTable("mail_throttle", {
  /** sha256(purpose + ":" + lowercased address). */
  key: text("key").primaryKey(),
  /** Unix seconds of the last send, for the minimum interval. */
  lastSentAt: integer("last_sent_at").notNull(),
  /** Start of the current 24h window, for the daily cap. */
  windowStart: integer("window_start").notNull(),
  /** Sends inside the current window. */
  count: integer("count").notNull(),
});

export const schema = {
  user, session, account, verification,
  profile, plant, project, catalogueEntry, achievementState,
  journalEntry, focusSession, dailyRollup, revisionCounter, pushLog,
  mailThrottle,
};
