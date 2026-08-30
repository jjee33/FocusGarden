/**
 * Reading a whole garden out of the database, and putting one back.
 *
 * The row shapes are the sync protocol's, not the domain's, so this is the one
 * place that converts between them in bulk. Everything here works in the SAME
 * dictionary format the clients serialise to, which is what lets the desktop,
 * the browser and the database all agree about what a plant is without three
 * definitions of it.
 */

import { eq } from "drizzle-orm";

import type { Database } from "../db/client.js";
import {
  achievementState, catalogueEntry, focusSession, journalEntry,
  plant, profile, project, revisionCounter,
} from "../db/schema.js";
import {
  makeSaveData, saveDataFromDict, saveDataToDict, type SaveData,
} from "../../domain/save-data.js";
import {
  focusSessionFromDict, focusSessionToDict, type FocusSession,
} from "../../domain/focus-session.js";
import { plantInstanceToDict } from "../../domain/plant-instance.js";
import { projectCategoryToDict } from "../../domain/project-category.js";
import { catalogueEntryToDict } from "../../domain/catalogue-entry.js";
import { achievementStateToDict } from "../../domain/achievement-state.js";
import { journalEntryToDict } from "../../domain/journal-entry.js";
import type { Json } from "../../domain/dict-util.js";

/**
 * Rebuilds a SaveData from the rows.
 *
 * The profile row holds everything that is not a collection, in exactly the
 * shape saveDataToDict emits, so the collections are dropped back in beside it
 * and the whole thing is parsed by the same function the clients use. Assembling
 * a SaveData field by field here would be a fourth place that has to know what a
 * save contains.
 */
export async function readGarden(
  db: Database, userId: string,
): Promise<{ save: SaveData; sessions: FocusSession[] }> {
  const profileRow = await db.select().from(profile).where(eq(profile.userId, userId)).get();

  const live = <T extends { data: unknown; deletedAt: number | null }>(rows: T[]): unknown[] =>
    rows.filter((r) => r.deletedAt === null).map((r) => r.data);

  const [plants, projects, catalogue, achievements, journal, sessions] = await Promise.all([
    db.select().from(plant).where(eq(plant.userId, userId)).all(),
    db.select().from(project).where(eq(project.userId, userId)).all(),
    db.select().from(catalogueEntry).where(eq(catalogueEntry.userId, userId)).all(),
    db.select().from(achievementState).where(eq(achievementState.userId, userId)).all(),
    db.select().from(journalEntry).where(eq(journalEntry.userId, userId)).all(),
    db.select().from(focusSession).where(eq(focusSession.userId, userId)).all(),
  ]);

  if (profileRow === undefined) {
    // No profile means nothing has ever synced. An empty save is the honest
    // answer; inventing one from the loose collections would be worse.
    return { save: makeSaveData(), sessions: [] };
  }

  const dict = {
    ...(profileRow.data as Record<string, Json>),
    plants: live(plants),
    projects: live(projects),
    catalogue: live(catalogue),
    achievements: live(achievements),
    journal: journal.map((r) => r.data),
  } as Json;

  return {
    save: saveDataFromDict(dict),
    sessions: sessions.map((r) => focusSessionFromDict(r.data as Json)),
  };
}

export interface ReplaceResult {
  plants: number;
  sessions: number;
  revision: number;
}

/**
 * Replaces this account's entire garden.
 *
 * EVERY WRITE IS SCOPED TO THE ONE USER. The deletes carry a userId predicate
 * rather than clearing a table, which is the difference between replacing one
 * garden and emptying the database.
 *
 * The revision counter is bumped once and every row written at that number, so a
 * browser that syncs afterwards sees exactly one change and pulls the whole
 * thing - rather than concluding, record by record, that half of it is stale.
 */
export async function replaceGarden(
  db: Database, userId: string, save: SaveData, sessions: FocusSession[],
): Promise<ReplaceResult> {
  const now = Math.floor(Date.now() / 1000);

  const counter = await db.select().from(revisionCounter)
    .where(eq(revisionCounter.userId, userId)).get();
  const revision = (counter?.value ?? 0) + 1;
  if (counter === undefined) {
    await db.insert(revisionCounter).values({ userId, value: revision });
  } else {
    await db.update(revisionCounter).set({ value: revision })
      .where(eq(revisionCounter.userId, userId));
  }

  const full = saveDataToDict(save) as Record<string, Json>;
  const profileData: Json = {
    save_version: full["save_version"],
    player: full["player"],
    settings: full["settings"],
    shelf: full["shelf"],
    garden: full["garden"],
    expeditions: full["expeditions"],
  };

  await db.delete(plant).where(eq(plant.userId, userId));
  await db.delete(project).where(eq(project.userId, userId));
  await db.delete(catalogueEntry).where(eq(catalogueEntry.userId, userId));
  await db.delete(achievementState).where(eq(achievementState.userId, userId));
  await db.delete(journalEntry).where(eq(journalEntry.userId, userId));
  await db.delete(focusSession).where(eq(focusSession.userId, userId));

  await db.insert(profile).values({
    userId,
    data: profileData,
    saveVersion: save.saveVersion,
    revision,
    updatedAt: now,
  }).onConflictDoUpdate({
    target: profile.userId,
    set: { data: profileData, saveVersion: save.saveVersion, revision, updatedAt: now },
  });

  const rows = <T>(items: T[], id: (v: T) => string, write: (v: T) => Json) =>
    items.map((v) => ({
      id: id(v), userId, data: write(v), revision, updatedAt: now, deletedAt: null,
    }));

  /*
   * CHUNKED BY BOUND PARAMETERS, NOT BY ROWS. D1 refuses any statement with more
   * than 100 of them, and a multi-row insert binds one per column per row - so
   * the safe batch size depends on how wide the table is, not on a number that
   * looks reasonable.
   *
   * The first version chunked at 40 rows. Every test bundle had one row per
   * table and sailed through; the first real garden pushed 24 achievement rows
   * at six columns each, 144 parameters, and the whole sync failed with nothing
   * but "Failed query". Small synthetic fixtures cannot find a limit that scales
   * with the data.
   *
   * The caller supplies the insert rather than the table, so each call keeps its
   * own row type. Passing the table into a generic helper needed an `as never`
   * at every site, and a cast that silences the compiler on an INSERT will one
   * day silence a real column mismatch.
   */
  const PARAMETER_BUDGET = 90;
  const inChunks = async <T>(
    values: T[], columns: number, insert: (batch: T[]) => Promise<unknown>,
  ) => {
    const perBatch = Math.max(1, Math.floor(PARAMETER_BUDGET / columns));
    for (let i = 0; i < values.length; i += perBatch) {
      const batch = values.slice(i, i + perBatch);
      if (batch.length > 0) await insert(batch);
    }
  };

  await inChunks(
    rows(save.plants, (p) => p.uid, plantInstanceToDict), 6,
    (b) => db.insert(plant).values(b).run(),
  );
  await inChunks(
    rows(save.projects, (p) => p.id, projectCategoryToDict), 6,
    (b) => db.insert(project).values(b).run(),
  );
  await inChunks(
    rows(save.catalogue, (c) => c.speciesId, catalogueEntryToDict), 6,
    (b) => db.insert(catalogueEntry).values(b).run(),
  );
  await inChunks(
    rows(save.achievements, (a) => a.achievementId, achievementStateToDict), 6,
    (b) => db.insert(achievementState).values(b).run(),
  );
  await inChunks(
    save.journal.map((j) => ({
      id: j.id, userId, data: journalEntryToDict(j), createdAt: Math.floor(j.createdAtUtc),
    })), 4,
    (b) => db.insert(journalEntry).values(b).run(),
  );
  await inChunks(
    sessions.map((s) => ({
      id: s.id, userId, dateKey: s.dateKey, data: focusSessionToDict(s),
      createdAt: Math.floor(s.startedAtUtc),
    })), 5,
    (b) => db.insert(focusSession).values(b).run(),
  );

  return { plants: save.plants.length, sessions: sessions.length, revision };
}
