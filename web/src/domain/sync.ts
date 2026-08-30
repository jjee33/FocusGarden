/**
 * Merging two copies of a garden.
 *
 * SYNC METADATA IS NOT PART OF THE SAVE FORMAT, and that is deliberate. Adding
 * `revision` to PlantInstance and friends would change the on-disk shape, which
 * means bumping SaveData.CURRENT_VERSION - and because SaveBundle is shared with
 * the desktop, every shipped desktop build would then refuse the file as
 * FUTURE_VERSION. The desktop has no interest in sync and should not be made to
 * learn about it. So revisions live BESIDE the data: in a local metadata store
 * on the client, in columns on the server. The save format stays version 2.
 *
 * THE REVISION IS ASSIGNED BY THE SERVER, and that is the load-bearing decision
 * here. An earlier draft had each client increment its own counter, which meant
 * two devices could independently reach "revision 3" holding DIFFERENT content -
 * so equal revisions did not imply equal records, and any shortcut that assumed
 * they did would silently keep one device's version and discard the other's. A
 * server-assigned revision is globally meaningful: same revision genuinely means
 * same version of that record.
 *
 * A local edit therefore does not invent a revision. It sets `dirty` and keeps
 * the last revision the server acknowledged, which also makes the definition of
 * a conflict exact: we have unpushed changes AND the server has moved on.
 *
 * THE MODEL, in two rules:
 *
 *   1. Focus sessions are IMMUTABLE and append-only with unique ids, so merging
 *      them is a set union. There is no such thing as a conflicting session
 *      because nothing ever edits one. That is a property the data model already
 *      guaranteed; this exploits it rather than inventing machinery.
 *
 *   2. Everything else is last-write-wins, with deletes as TOMBSTONES rather
 *      than absences. An absence is ambiguous - "deleted here" and "not seen
 *      here" look identical - and guessing wrong either resurrects something
 *      thrown away or discards something made on another device.
 */

export interface SyncRecord<T> {
  id: string;
  /**
   * Server-assigned. Zero means the server has never seen this record.
   * Never incremented locally: see the header.
   */
  revision: number;
  /** A local edit the server has not acknowledged yet. */
  dirty: boolean;
  /** Unix seconds of the local edit. Used to resolve and describe conflicts. */
  updatedAt: number;
  /** Set when deleted. The row survives so the delete can travel. */
  deletedAt: number | null;
  value: T;
}

export const NEVER_SYNCED = 0;

export interface MergeOutcome<T> {
  /** The reconciled set, tombstones included. */
  merged: SyncRecord<T>[];
  /** Records the local side must adopt. */
  toApply: SyncRecord<T>[];
  /** Records the server has not got, or has an older copy of. */
  toPush: SyncRecord<T>[];
  /**
   * Ids that were edited in both places since the last agreement. Resolved, but
   * reported - a conflict that is silently resolved is a conflict nobody can
   * ever investigate.
   */
  conflicted: string[];
}

/**
 * Reconciles one collection against the server's copy.
 *
 * Four cases, and the interesting one is the last:
 *   - remote only            -> apply
 *   - local only             -> push (including tombstones)
 *   - both, local clean      -> fast-forward to remote
 *   - both, local dirty      -> push if the server has not moved; otherwise a
 *                               genuine conflict, resolved by edit time
 */
export function mergeCollection<T>(
  local: readonly SyncRecord<T>[],
  remote: readonly SyncRecord<T>[],
): MergeOutcome<T> {
  const outcome: MergeOutcome<T> = { merged: [], toApply: [], toPush: [], conflicted: [] };
  const localById = new Map(local.map((r) => [r.id, r]));
  const remoteById = new Map(remote.map((r) => [r.id, r]));

  for (const [id, mine] of localById) {
    const theirs = remoteById.get(id);

    if (theirs === undefined) {
      // Only here. A local TOMBSTONE is pushed too: the server has to learn
      // about the delete, or the next pull brings the record back.
      outcome.merged.push(mine);
      outcome.toPush.push(mine);
      continue;
    }

    if (!mine.dirty) {
      if (theirs.revision === mine.revision) {
        // Agreed. No work in either direction - the case that keeps a sync where
        // nothing changed from rewriting the entire garden back over itself.
        outcome.merged.push(mine);
      } else {
        outcome.merged.push(theirs);
        outcome.toApply.push(theirs);
      }
      continue;
    }

    if (theirs.revision === mine.revision) {
      // We have changes and the server has not moved since we last agreed. A
      // plain push, not a conflict.
      outcome.merged.push(mine);
      outcome.toPush.push(mine);
      continue;
    }

    // Both sides moved. Later edit wins; the server breaks an exact tie, purely
    // so every device resolves it the same way. Two devices choosing differently
    // would diverge permanently and neither would notice.
    outcome.conflicted.push(id);
    if (theirs.updatedAt > mine.updatedAt) {
      outcome.merged.push(theirs);
      outcome.toApply.push(theirs);
    } else if (mine.updatedAt > theirs.updatedAt) {
      outcome.merged.push(mine);
      outcome.toPush.push(mine);
    } else {
      outcome.merged.push(theirs);
      outcome.toApply.push(theirs);
    }
  }

  for (const [id, theirs] of remoteById) {
    if (localById.has(id)) continue;
    outcome.merged.push(theirs);
    outcome.toApply.push(theirs);
  }

  return outcome;
}

/**
 * Merges immutable, append-only records by id.
 *
 * No revisions, no tombstones, no conflicts. Where both sides hold the same id
 * the local copy is kept: they are meant to be identical, and choosing one side
 * consistently avoids a pointless write.
 */
export function mergeAppendOnly<T extends { id: string }>(
  local: readonly T[], remote: readonly T[],
): { merged: T[]; toApply: T[]; toPush: T[] } {
  const localById = new Map(local.map((r) => [r.id, r]));
  const remoteById = new Map(remote.map((r) => [r.id, r]));
  const toApply = remote.filter((r) => !localById.has(r.id));
  const toPush = local.filter((r) => !remoteById.has(r.id));
  return { merged: [...local, ...toApply], toApply, toPush };
}

/** A record the server has never seen. */
export function makeRecord<T>(id: string, value: T, nowUnixUtc: number): SyncRecord<T> {
  return {
    id, revision: NEVER_SYNCED, dirty: true, updatedAt: nowUnixUtc, deletedAt: null, value,
  };
}

/** A local edit. Marks dirty; the revision stays whatever the server last said. */
export function touch<T>(record: SyncRecord<T>, value: T, nowUnixUtc: number): SyncRecord<T> {
  return { ...record, dirty: true, updatedAt: nowUnixUtc, deletedAt: null, value };
}

/**
 * Marks a record deleted without removing it, so the delete can travel. Dropping
 * the row instead would make the record look merely unseen to the other device,
 * which would push its copy back and undo the delete.
 */
export function tombstone<T>(record: SyncRecord<T>, nowUnixUtc: number): SyncRecord<T> {
  return { ...record, dirty: true, updatedAt: nowUnixUtc, deletedAt: nowUnixUtc };
}

/** Applies the server's acknowledgement of a push. */
export function acknowledge<T>(record: SyncRecord<T>, revision: number): SyncRecord<T> {
  return { ...record, revision, dirty: false };
}

export function isDeleted<T>(record: SyncRecord<T>): boolean {
  return record.deletedAt !== null;
}

/** The live records, for anything that wants to render rather than reconcile. */
export function liveValues<T>(records: readonly SyncRecord<T>[]): T[] {
  return records.filter((r) => !isDeleted(r)).map((r) => r.value);
}

/**
 * How far the next pull may start from.
 *
 * THE CURSOR IS WHAT YOU READ, NEVER WHAT YOU WROTE, and the difference is
 * other people's data. A sync cycle pulls and then pushes, so the push lands at
 * a higher revision than the pull reported - and anything a second device
 * committed in that gap sits between the two numbers. Taking the push revision
 * as the cursor asks the server for "everything after my own write" and steps
 * straight over it:
 *
 *   A pulls, sees revision 3
 *   B pushes a new plant       -> revision 4
 *   A pushes an unrelated edit -> revision 5
 *   A stores 5, asks for what follows 5, and never sees revision 4 again.
 *
 * That is not a rare interleaving; two devices syncing within a few seconds is
 * the ordinary case for the feature an account exists to provide.
 *
 * Erring the other way is cheap. A cursor left at the pull revision re-fetches
 * this device's own writes next time, and the merge hashes them, finds them
 * identical to what it already holds, and does nothing.
 */
export function nextPullCursor(pullRevision: number, pushRevision: number): number {
  void pushRevision;
  return pullRevision;
}
