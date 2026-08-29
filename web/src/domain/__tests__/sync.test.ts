/**
 * Merging two copies of a garden.
 *
 * Sync is the part of this project most likely to lose someone's data quietly,
 * so these are the cases where a plausible implementation is wrong: a delete
 * that comes back, an edit that vanishes, a sync that rewrites everything when
 * nothing changed, and two devices resolving the same tie in opposite directions
 * and diverging forever.
 */

import { describe, expect, it } from "vitest";

import {
  NEVER_SYNCED, acknowledge, isDeleted, liveValues, makeRecord,
  mergeAppendOnly, mergeCollection, tombstone, touch,
} from "../sync.js";
import type { SyncRecord } from "../sync.js";

const T0 = 1_700_000_000;

/** A record the server has acknowledged at `revision`, with no local edits. */
function clean(id: string, value: string, revision: number, updatedAt = T0): SyncRecord<string> {
  return { id, revision, dirty: false, updatedAt, deletedAt: null, value };
}

/** A record with a local edit the server has not seen. */
function dirty(id: string, value: string, revision: number, updatedAt = T0): SyncRecord<string> {
  return { id, revision, dirty: true, updatedAt, deletedAt: null, value };
}

describe("mergeCollection", () => {
  it("takes what only one side has, in both directions", () => {
    const out = mergeCollection([dirty("a", "local", NEVER_SYNCED)], [clean("b", "remote", 1)]);
    expect(out.merged.map((r) => r.id).sort()).toEqual(["a", "b"]);
    expect(out.toPush.map((r) => r.id)).toEqual(["a"]);
    expect(out.toApply.map((r) => r.id)).toEqual(["b"]);
  });

  it("does no work at all when nothing has changed", () => {
    // The case that decides whether an idle sync is free or rewrites the whole
    // history back over itself every time.
    const same = [clean("a", "one", 4), clean("b", "two", 7)];
    const out = mergeCollection(same, same);
    expect(out.merged).toHaveLength(2);
    expect(out.toPush).toHaveLength(0);
    expect(out.toApply).toHaveLength(0);
    expect(out.conflicted).toEqual([]);
  });

  it("fast-forwards a clean local record to the server's newer one", () => {
    const out = mergeCollection([clean("a", "old", 3)], [clean("a", "new", 4)]);
    expect(out.merged[0]!.value).toBe("new");
    expect(out.toApply).toHaveLength(1);
    expect(out.conflicted).toEqual([]);
  });

  it("pushes a local edit when the server has not moved, and calls it no conflict", () => {
    const out = mergeCollection([dirty("a", "my edit", 3)], [clean("a", "server copy", 3)]);
    expect(out.merged[0]!.value).toBe("my edit");
    expect(out.toPush).toHaveLength(1);
    // Not a conflict: the server is still where we left it.
    expect(out.conflicted).toEqual([]);
  });

  it("reports a genuine conflict and resolves it by edit time", () => {
    // We have unpushed changes AND the server has moved on. That is the only
    // situation that deserves the word conflict.
    const out = mergeCollection(
      [dirty("a", "mine", 3, T0 + 100)],
      [clean("a", "theirs", 5, T0)],
    );
    expect(out.conflicted).toEqual(["a"]);
    expect(out.merged[0]!.value).toBe("mine");
    expect(out.toPush).toHaveLength(1);
  });

  it("lets the server win a conflict when its edit is later", () => {
    const out = mergeCollection(
      [dirty("a", "mine", 3, T0)],
      [clean("a", "theirs", 5, T0 + 100)],
    );
    expect(out.conflicted).toEqual(["a"]);
    expect(out.merged[0]!.value).toBe("theirs");
    expect(out.toApply).toHaveLength(1);
  });

  it("breaks an exact tie deterministically, so two devices cannot diverge", () => {
    // Not because the server is more correct - because the rule must be the same
    // everywhere. Two devices resolving this differently would drift apart
    // permanently and neither would ever notice.
    const out = mergeCollection(
      [dirty("a", "mine", 3, T0)],
      [clean("a", "theirs", 5, T0)],
    );
    expect(out.merged[0]!.value).toBe("theirs");
  });

  it("PUSHES a local tombstone, so the delete is not undone on the next pull", () => {
    const deleted = tombstone(clean("a", "gone", 4), T0 + 5);
    const out = mergeCollection([deleted], []);
    expect(out.toPush).toHaveLength(1);
    expect(isDeleted(out.toPush[0]!)).toBe(true);
  });

  it("adopts a server tombstone over a clean local copy", () => {
    const remoteDeleted = { ...clean("a", "gone", 5), deletedAt: T0 + 5 };
    const out = mergeCollection([clean("a", "still here", 4)], [remoteDeleted]);
    expect(isDeleted(out.merged[0]!)).toBe(true);
  });

  it("lets a later local edit beat an older server tombstone", () => {
    // Resurrection is right here: deleted on one device, then genuinely edited
    // on another afterwards. The later intent wins.
    const remoteDeleted = { ...clean("a", "gone", 5), deletedAt: T0, updatedAt: T0 };
    const revived = touch(clean("a", "old", 4), "brought back", T0 + 60);
    const out = mergeCollection([revived], [remoteDeleted]);
    expect(isDeleted(out.merged[0]!)).toBe(false);
    expect(out.merged[0]!.value).toBe("brought back");
  });

  it("converges no matter how many times it runs", () => {
    const local = [dirty("a", "a1", 2, T0 + 1), clean("b", "b1", 3)];
    const remote = [clean("a", "a2", 4, T0), clean("c", "c1", 1)];

    const first = mergeCollection(local, remote);
    // After a round trip the pushed records are acknowledged and the applied
    // ones are already clean, so a second merge against the same server state
    // must settle rather than oscillate.
    const settled = first.merged.map((r) => (r.dirty ? acknowledge(r, 9) : r));
    const second = mergeCollection(settled, settled);
    expect(second.toPush).toHaveLength(0);
    expect(second.toApply).toHaveLength(0);
    expect(second.merged.map((r) => r.id).sort()).toEqual(["a", "b", "c"]);
  });
});

describe("mergeAppendOnly", () => {
  it("unions sessions by id and never conflicts", () => {
    const out = mergeAppendOnly([{ id: "s1" }, { id: "s2" }], [{ id: "s2" }, { id: "s3" }]);
    expect(out.merged.map((r) => r.id).sort()).toEqual(["s1", "s2", "s3"]);
    expect(out.toApply.map((r) => r.id)).toEqual(["s3"]);
    expect(out.toPush.map((r) => r.id)).toEqual(["s1"]);
  });

  it("never duplicates a session held by both sides", () => {
    // A duplicated session id would permanently double lifetime focus, session
    // counts, day totals and the streak, all at once.
    const both = [{ id: "s1" }, { id: "s2" }];
    const out = mergeAppendOnly(both, both);
    expect(out.merged).toHaveLength(2);
    expect(out.toApply).toHaveLength(0);
    expect(out.toPush).toHaveLength(0);
  });

  it("is idempotent", () => {
    const first = mergeAppendOnly([{ id: "s1" }], [{ id: "s2" }]);
    const second = mergeAppendOnly(first.merged, first.merged);
    expect(second.merged).toHaveLength(2);
    expect(second.toApply).toHaveLength(0);
  });
});

describe("record helpers", () => {
  it("starts unsynced and dirty", () => {
    const created = makeRecord("a", "one", T0);
    expect(created.revision).toBe(NEVER_SYNCED);
    expect(created.dirty).toBe(true);
  });

  it("never invents a revision locally", () => {
    // The whole reason equal revisions can be trusted to mean equal records.
    const edited = touch(clean("a", "one", 7), "two", T0 + 10);
    expect(edited.revision).toBe(7);
    expect(edited.dirty).toBe(true);
  });

  it("clears dirty only when the server acknowledges", () => {
    const acked = acknowledge(touch(clean("a", "one", 7), "two", T0 + 10), 8);
    expect(acked.revision).toBe(8);
    expect(acked.dirty).toBe(false);
  });

  it("keeps the row when deleting, so the delete can travel", () => {
    const deleted = tombstone(clean("a", "one", 3), T0 + 10);
    expect(isDeleted(deleted)).toBe(true);
    expect(deleted.dirty).toBe(true);
    expect(liveValues([deleted])).toEqual([]);
  });

  it("un-deletes on a later edit", () => {
    const revived = touch(tombstone(clean("a", "one", 3), T0 + 10), "again", T0 + 20);
    expect(isDeleted(revived)).toBe(false);
    expect(liveValues([revived])).toEqual(["again"]);
  });
});
