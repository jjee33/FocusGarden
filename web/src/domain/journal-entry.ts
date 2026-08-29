/**
 * One dated event in the player's history. Port of models/journal_entry.gd.
 *
 * The journal is append-only and never rewritten: it is the narrative record of
 * the player's productivity, and "progress must feel permanent" depends on
 * entries surviving every later change.
 *
 * Entries store a `body` string composed WHEN THE EVENT HAPPENED rather than a
 * template resolved at read time, so wording changes in a future version cannot
 * retroactively alter what the player's history says.
 */

import { toInt } from "./gd.js";
import type { Json } from "./dict-util.js";
import { getFloat, getInt, getString } from "./dict-util.js";
import { generate } from "./uid.js";
import { localDateKey } from "./time-util.js";

export const JournalKind = {
  SEED_PLANTED: 0,
  STAGE_REACHED: 1,
  PLANT_MATURED: 2,
  MUTATION_DISCOVERED: 3,
  ACHIEVEMENT_UNLOCKED: 4,
  GARDEN_EXPANSION: 5,
  MILESTONE_REACHED: 6,
  LEVEL_UP: 7,
  EXPEDITION_COMPLETED: 8,
} as const;
export type JournalKind = (typeof JournalKind)[keyof typeof JournalKind];

export interface JournalEntry {
  id: string;
  kind: JournalKind;
  createdAtUtc: number;
  dateKey: string;
  title: string;
  body: string;
  /** Optional back-reference (plant uid, achievement id, species id). */
  subjectId: string;
}

export function makeJournalEntry(overrides: Partial<JournalEntry> = {}): JournalEntry {
  return {
    id: "", kind: JournalKind.MILESTONE_REACHED, createdAtUtc: 0,
    dateKey: "", title: "", body: "", subjectId: "",
    ...overrides,
  };
}

export function createJournalEntry(
  kind: JournalKind, title: string, body: string, subjectId = "",
  nowUnixUtc = Date.now() / 1000, offsetSeconds?: number,
): JournalEntry {
  return makeJournalEntry({
    id: generate("j", nowUnixUtc),
    kind, title, body, subjectId,
    createdAtUtc: nowUnixUtc,
    dateKey: localDateKey(nowUnixUtc, offsetSeconds),
  });
}

export function journalEntryToDict(e: JournalEntry): Json {
  return {
    id: e.id,
    kind: e.kind,
    created_at_utc: e.createdAtUtc,
    date_key: e.dateKey,
    title: e.title,
    body: e.body,
    subject_id: e.subjectId,
  };
}

export function journalEntryFromDict(data: Json): JournalEntry {
  const raw = getInt(data, "kind", JournalKind.MILESTONE_REACHED);
  return makeJournalEntry({
    id: getString(data, "id"),
    kind: raw >= 0 && raw <= JournalKind.EXPEDITION_COMPLETED
      ? (toInt(raw) as JournalKind)
      : JournalKind.MILESTONE_REACHED,
    createdAtUtc: getFloat(data, "created_at_utc"),
    dateKey: getString(data, "date_key"),
    title: getString(data, "title"),
    body: getString(data, "body"),
    subjectId: getString(data, "subject_id"),
  });
}
