/**
 * Retention decides what gets DELETED, so it is the one part of the backup tool
 * that can quietly destroy history. A bug here is invisible until the day you
 * reach for a backup that a previous run rotated away.
 *
 * The tool itself is plain JS in tools/ because it runs under Node with wrangler
 * rather than in the bundle; only this pure function is imported.
 */

import { describe, expect, it } from "vitest";

// @ts-expect-error - a Node-side tool, deliberately outside the typed app source.
import { planRetention } from "../../../tools/backup-d1.mjs";

const NOW = new Date("2026-08-30T02:00:00Z");

function names(...dates: string[]): string[] {
  return dates.map((d) => `focus-garden-${d}T0200Z.sql`);
}

describe("planRetention", () => {
  it("keeps everything when there is little", () => {
    const files = names("2026-08-30", "2026-08-29", "2026-08-28");
    const { keep, drop } = planRetention(files, NOW);
    expect(drop).toEqual([]);
    expect(keep).toHaveLength(3);
  });

  it("keeps the last seven days outright", () => {
    const files = names(
      "2026-08-30","2026-08-29","2026-08-28","2026-08-27",
      "2026-08-26","2026-08-25","2026-08-24","2026-08-23",
    );
    const { keep } = planRetention(files, NOW);
    for (const d of ["2026-08-30","2026-08-29","2026-08-28","2026-08-27","2026-08-26","2026-08-25","2026-08-24"]) {
      expect(keep.some((k: string) => k.includes(d))).toBe(true);
    }
  });

  it("never drops the newest backup, whatever else happens", () => {
    const many = Array.from({ length: 400 }, (_, i) => {
      const d = new Date(NOW.getTime() - i * 86400000);
      return `focus-garden-${d.toISOString().slice(0, 10)}T0200Z.sql`;
    });
    const { keep, drop } = planRetention(many, NOW);
    expect(keep).toContain(many[0]);
    expect(drop).not.toContain(many[0]);
  });

  it("thins old history instead of keeping all of it", () => {
    const many = Array.from({ length: 400 }, (_, i) => {
      const d = new Date(NOW.getTime() - i * 86400000);
      return `focus-garden-${d.toISOString().slice(0, 10)}T0200Z.sql`;
    });
    const { keep, drop } = planRetention(many, NOW);
    expect(drop.length).toBeGreaterThan(300);
    // Enough to reach back a year, not so many that the disk fills.
    expect(keep.length).toBeGreaterThanOrEqual(7);
    expect(keep.length).toBeLessThan(30);
  });

  it("keeps something from each of the last several months", () => {
    const monthly = Array.from({ length: 12 }, (_, i) => {
      const d = new Date(Date.UTC(2026, 7 - i, 15));
      return `focus-garden-${d.toISOString().slice(0, 10)}T0200Z.sql`;
    });
    const { keep } = planRetention(monthly, NOW);
    expect(keep.length).toBeGreaterThanOrEqual(8);
  });

  it("ignores files that are not backups rather than deleting them", () => {
    const files = [...names("2026-08-30"), "notes.txt", "focus-garden-latest.sql", "README"];
    const { keep, drop } = planRetention(files, NOW);
    expect(drop).not.toContain("notes.txt");
    expect(drop).not.toContain("README");
    expect(drop).not.toContain("focus-garden-latest.sql");
    expect(keep).toHaveLength(1);
  });

  it("copes with an empty directory", () => {
    const { keep, drop } = planRetention([], NOW);
    expect(keep).toEqual([]);
    expect(drop).toEqual([]);
  });
});
