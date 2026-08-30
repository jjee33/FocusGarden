/**
 * The journal: what happened, in the order it happened.
 *
 * Entries are written by the session pipeline - a seed planted, a stage reached,
 * a plant matured, an achievement earned - and have been accumulating since the
 * first session. This is the quietest of the three screens and the one that
 * suits the product best: the garden shows where you got to, and this shows how.
 *
 * GROUPED BY DAY, NEWEST FIRST. A flat list of two hundred entries is a log
 * file. Days are the unit people actually remember things in, and the date key
 * is already stored on every entry precisely so it never has to be recomputed
 * from a timestamp - see the DST policy in time-util.
 */

import { useMemo } from "react";

import { Icon, type IconName } from "../components/Icon.js";
import type { useGarden } from "../useGarden.js";
import { JournalKind } from "../../domain/journal-entry.js";
import type { JournalEntry } from "../../domain/journal-entry.js";
import { formatDateKey } from "../../domain/time-util.js";

interface Props {
  garden: ReturnType<typeof useGarden>;
}

/**
 * A glyph per kind of event.
 *
 * Every entry already carries its kind, so this needs no guessing from the text.
 * The icon is what lets someone skim a long day and find the one thing they were
 * looking for.
 */
const MARK: Record<number, IconName> = {
  [JournalKind.SEED_PLANTED]: "sprout",
  [JournalKind.STAGE_REACHED]: "leaf",
  [JournalKind.PLANT_MATURED]: "flower",
  [JournalKind.MUTATION_DISCOVERED]: "sparkle",
  [JournalKind.ACHIEVEMENT_UNLOCKED]: "achievements",
  [JournalKind.GARDEN_EXPANSION]: "expand",
  [JournalKind.MILESTONE_REACHED]: "star",
  [JournalKind.LEVEL_UP]: "level",
  [JournalKind.EXPEDITION_COMPLETED]: "clock",
};

export function JournalScreen({ garden }: Props) {
  const { save } = garden;

  const days = useMemo(() => {
    const map = new Map<string, JournalEntry[]>();
    for (const entry of save.journal) {
      map.set(entry.dateKey, [...(map.get(entry.dateKey) ?? []), entry]);
    }
    return [...map.entries()]
      .sort((a, b) => (a[0] < b[0] ? 1 : a[0] > b[0] ? -1 : 0))
      .map(([key, entries]) => ({
        key,
        entries: [...entries].sort((a, b) => b.createdAtUtc - a.createdAtUtc),
      }));
  }, [save.journal]);

  if (days.length === 0) {
    return (
      <>
        <header className="greet">
          <h1>Journal</h1>
        </header>
        <p className="empty">
          Nothing written yet. Finish a session and the first entry appears here —
          this fills itself in as your garden grows.
        </p>
      </>
    );
  }

  return (
    <>
      <header className="greet">
        <h1>Journal</h1>
        <p>
          {save.journal.length} {save.journal.length === 1 ? "entry" : "entries"}
          {" over "}{days.length} {days.length === 1 ? "day" : "days"}
        </p>
      </header>

      {days.map((day) => (
        <section className="card journal-day" key={day.key}>
          <h2>{formatDateKey(day.key)}</h2>
          <ol className="journal-list">
            {day.entries.map((entry) => (
              <li className="journal-entry" key={entry.id}>
                <span className="journal-entry__mark" aria-hidden="true">
                  <Icon name={MARK[entry.kind] ?? "leaf"} size={1.15} />
                </span>
                <div>
                  <h3>{entry.title}</h3>
                  {entry.body !== "" && <p>{entry.body}</p>}
                </div>
              </li>
            ))}
          </ol>
        </section>
      ))}
    </>
  );
}
