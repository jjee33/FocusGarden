/**
 * What this device last agreed with the server about.
 *
 * Kept in its own IndexedDB store, deliberately outside the save. Putting
 * revisions on PlantInstance would change the on-disk shape, bump
 * SaveData.CURRENT_VERSION, and make every shipped desktop build refuse the file
 * as FUTURE_VERSION. The desktop has no interest in sync; this is the web
 * client's bookkeeping and it stays the web client's problem.
 *
 * DIRTY IS DERIVED, NOT TRACKED, and that is the important choice here. The
 * obvious design threads a `dirty` flag through every mutation - place a plant,
 * rename a project, finish a session - and the bug it invites is a mutation that
 * forgets to set it, which does not fail loudly, it just silently stops syncing
 * one record forever. Instead each synced record's content is hashed, and
 * anything whose hash no longer matches is dirty by definition. A mutation
 * cannot forget to be noticed.
 */

import type { Json } from "../domain/dict-util.js";
import { META_STORE, get, put, transact } from "./db.js";

/** Where the whole bookkeeping blob lives, as one record. */
const SYNC_META_KEY = "sync";

export interface RecordMeta {
  /** Server-assigned. 0 means the server has never seen this record. */
  revision: number;
  /** Content hash at the moment the server acknowledged it. */
  hash: string;
}

export interface SyncMeta {
  /** Highest revision this device has pulled. */
  lastRevision: number;
  /** Newest `createdAt` seen for append-only rows, so pulls stay bounded. */
  lastAppendAt: number;
  /** Unix seconds of the last successful exchange, for the UI. */
  lastSyncedAt: number;
  /** Which account this bookkeeping belongs to. */
  userId: string;
  records: Record<string, Record<string, RecordMeta>>;
  /** Ids deleted locally, kept until the server confirms it knows. */
  tombstones: Record<string, Record<string, number>>;
}

export function emptySyncMeta(): SyncMeta {
  return {
    lastRevision: 0, lastAppendAt: 0, lastSyncedAt: 0, userId: "",
    records: {}, tombstones: {},
  };
}

export async function loadSyncMeta(db: IDBDatabase): Promise<SyncMeta> {
  const stored = await transact(db, [META_STORE], "readonly",
    (tx) => get<SyncMeta>(tx, META_STORE, SYNC_META_KEY));
  return stored ?? emptySyncMeta();
}

export async function saveSyncMeta(db: IDBDatabase, meta: SyncMeta): Promise<void> {
  await transact(db, [META_STORE], "readwrite", async (tx) => {
    await put(tx, META_STORE, meta, SYNC_META_KEY);
  });
}

/**
 * A different account on the same device starts from nothing.
 *
 * Otherwise this device would claim to have already synced records belonging to
 * somebody else, and push one person's garden into another person's account.
 */
export function metaForUser(meta: SyncMeta, userId: string): SyncMeta {
  if (meta.userId === userId) return meta;
  return { ...emptySyncMeta(), userId };
}

/**
 * FNV-1a over a stably-keyed serialisation.
 *
 * `JSON.stringify` orders keys by insertion, so two objects with identical
 * content but different construction order would hash differently and look
 * permanently dirty - a record that re-uploads on every single sync forever.
 * Sorting the keys is what makes the hash a function of the content.
 */
export function contentHash(value: unknown): string {
  const text = stableStringify(value);
  let hash = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) {
    hash ^= text.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193);
  }
  return (hash >>> 0).toString(36);
}

function stableStringify(value: unknown): string {
  if (value === null || typeof value !== "object") return JSON.stringify(value) ?? "null";
  if (Array.isArray(value)) return `[${value.map(stableStringify).join(",")}]`;
  const entries = Object.entries(value as Json).sort(([a], [b]) => (a < b ? -1 : a > b ? 1 : 0));
  return `{${entries.map(([k, v]) => `${JSON.stringify(k)}:${stableStringify(v)}`).join(",")}}`;
}

/** True when this record differs from whatever the server last acknowledged. */
export function isDirty(
  meta: SyncMeta, collection: string, id: string, value: unknown,
): boolean {
  const known = meta.records[collection]?.[id];
  if (known === undefined) return true;
  return known.hash !== contentHash(value);
}

export function revisionOf(meta: SyncMeta, collection: string, id: string): number {
  return meta.records[collection]?.[id]?.revision ?? 0;
}

/** Records what the server accepted, so the same content is not pushed again. */
export function acknowledgeRecord(
  meta: SyncMeta, collection: string, id: string, revision: number, value: unknown,
): void {
  meta.records[collection] ??= {};
  meta.records[collection]![id] = { revision, hash: contentHash(value) };
}
