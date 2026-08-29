/**
 * A whole garden in one file: the profile AND the session history.
 * Port of systems/save/save_bundle.gd.
 *
 * THE FAILURE THIS FIXES, on the desktop and now here. The save is two things -
 * the profile and the session history - because the history is the authoritative
 * analytics dataset and grows forever, so a routine save must not rewrite it.
 * Export only ever knew about the first half. The result did not look like a
 * missing file, it looked like selective data loss: everything CACHED on the
 * profile came across, and everything DERIVED from sessions did not. Statistics
 * read zero, and every still-growing plant redrew itself as a seed while its
 * label still said "Young", because a plant's progress is evaluated from its own
 * session rows rather than stored as a ratio.
 *
 * THE ENVELOPE is the save dictionary exactly as `saveDataToDict` writes it, plus
 * a `sessions` array and an `export` block. A SUPERSET, not a wrapper, and the
 * difference matters:
 *
 *   - Migrations apply to it unchanged, because `save_version` and every key a
 *     step touches are still exactly where they were.
 *   - A build OLDER than this one still imports the profile, ignoring the key it
 *     does not recognise rather than failing on a shape it cannot parse.
 *   - It stays one readable, diffable, inert JSON object.
 *
 * This is also the sync payload. Nothing here touches storage or the network, so
 * it stays testable in isolation.
 */

import type { Json } from "./dict-util.js";
import { getArray, getDict, getString } from "./dict-util.js";
import type { SaveData } from "./save-data.js";
import { CURRENT_VERSION, saveDataFromDict, saveDataToDict } from "./save-data.js";
import type { FocusSession } from "./focus-session.js";
import { focusSessionFromDict, focusSessionToDict } from "./focus-session.js";
import { formatDateKey } from "./time-util.js";
import { ingestSessions, makeRequirementContext } from "./requirement-context.js";

/** Deliberately the same word the shard files use, so both are obviously the same records. */
export const SESSIONS_KEY = "sessions";
/** Provenance. Never read back into gameplay - it exists so a file can be identified. */
export const META_KEY = "export";

export interface BundleSummary {
  plantCount: number;
  sessionCount: number;
  breakCount: number;
  focusMinutes: number;
  daysFocused: number;
  firstDateKey: string;
  lastDateKey: string;
  appVersion: string;
  /**
   * False for a bare profile, and for anything written before sessions travelled
   * with a save. The difference matters to the player: an empty history and a
   * missing one look identical afterwards, and only one of them is something
   * they did.
   */
  hasSessions: boolean;
  /**
   * Rows that could not be read, and rows dropped as duplicates. Both reported
   * rather than swallowed - a silently smaller history is exactly the fault this
   * format exists to prevent.
   */
  skippedCount: number;
  duplicateCount: number;
}

export interface ImportedBundle {
  save: SaveData;
  sessions: FocusSession[];
  summary: BundleSummary;
}

/** A readable date range, or "" when the bundle carries no history. */
export function describeRange(summary: BundleSummary): string {
  if (summary.firstDateKey === "" || summary.lastDateKey === "") return "";
  if (summary.firstDateKey === summary.lastDateKey) return formatDateKey(summary.firstDateKey);
  return formatDateKey(summary.firstDateKey) + " - " + formatDateKey(summary.lastDateKey);
}

/**
 * Wraps a save and its sessions into one exportable object.
 *
 * Works from a serialised copy, so nothing here can mutate live state - someone
 * pressing "Export a copy" is not asking to change anything.
 */
export function buildBundle(
  save: SaveData,
  sessions: FocusSession[],
  appVersion: string,
  nowUnixUtc = Date.now() / 1000,
): Json {
  const bundle = saveDataToDict(save);

  // Stamped explicitly rather than trusting whatever the in-memory object was
  // carrying, exactly as a real write does.
  bundle["save_version"] = CURRENT_VERSION;

  // An interrupted session does NOT travel between machines. Offering to resume
  // a pomodoro interrupted on a different computer three weeks ago is nonsense.
  // The key is EMPTIED rather than removed, so the shape stays identical.
  bundle["in_flight_session"] = {};

  bundle[SESSIONS_KEY] = sessions.map(focusSessionToDict);
  bundle[META_KEY] = {
    app_version: appVersion,
    exported_at_utc: nowUnixUtc,
    // Informational only. Import counts the array; a header is never trusted to
    // describe the body it travelled with.
    session_count: sessions.length,
  };
  return bundle;
}

/**
 * Whether this file carries session history at all.
 *
 * Checks for an ARRAY at the key, not a non-empty one: a real bundle from someone
 * who has never finished a session is a legitimate export of an empty history and
 * must not be reported as the truncated kind of file.
 */
export function hasSessions(bundle: Json): boolean {
  return Array.isArray(bundle[SESSIONS_KEY]);
}

/**
 * Reads an ALREADY-MIGRATED bundle into its parts. Migration stays the caller's
 * job so this holds no version knowledge and remains a pure shape transform.
 */
export function readBundle(bundle: Json): ImportedBundle {
  // The bundle IS the save dictionary with extra keys, which is exactly why the
  // envelope is a superset rather than a wrapper.
  const save = saveDataFromDict(bundle);
  const summary: BundleSummary = {
    plantCount: save.plants.length,
    sessionCount: 0,
    breakCount: 0,
    focusMinutes: 0,
    daysFocused: 0,
    firstDateKey: "",
    lastDateKey: "",
    appVersion: getString(getDict(bundle, META_KEY), "app_version"),
    hasSessions: hasSessions(bundle),
    skippedCount: 0,
    duplicateCount: 0,
  };
  const sessions = readSessions(bundle, summary);
  summarise(sessions, summary);
  return { save, sessions, summary };
}

/**
 * DEDUPLICATION IS MANDATORY, not defensive tidiness. A bundle carrying one
 * repeated id would be written as two identical rows and would permanently
 * double every figure derived from them - lifetime focus, session counts, day
 * totals and the streak, all at once, in the one dataset this project says has
 * to stay exactly true.
 */
function readSessions(bundle: Json, summary: BundleSummary): FocusSession[] {
  const out: FocusSession[] = [];
  const seen = new Set<string>();
  for (const entry of getArray(bundle, SESSIONS_KEY)) {
    if (typeof entry !== "object" || entry === null || Array.isArray(entry)) {
      summary.skippedCount += 1;
      continue;
    }
    const session = focusSessionFromDict(entry as Json);
    // An id-less row cannot be de-duplicated, credited to a plant, or replaced by
    // a later write. Losing one malformed record is recoverable; letting it
    // through is what corrupts the totals.
    if (session.id === "") {
      summary.skippedCount += 1;
      continue;
    }
    if (seen.has(session.id)) {
      summary.duplicateCount += 1;
      continue;
    }
    seen.add(session.id);
    out.push(session);
  }
  return out;
}

/**
 * The aggregates come from the requirement context, which is this app's one
 * implementation of "which sessions count, and for how much". The figure quoted
 * before an import has to be the figure the statistics screen shows afterwards,
 * or the confirmation was a lie - and it would drift the first time either rule
 * was tuned if this counted them itself.
 */
function summarise(sessions: FocusSession[], summary: BundleSummary): void {
  const context = makeRequirementContext();
  ingestSessions(context, sessions);
  summary.sessionCount = context.completedFocusSessions;
  summary.breakCount = context.completedBreakSessions;
  summary.focusMinutes = context.totalFocusMinutes;

  const days = context.uniqueFocusDays;
  summary.daysFocused = days.length;
  if (days.length > 0) {
    summary.firstDateKey = days[0]!;
    summary.lastDateKey = days[days.length - 1]!;
  }
}
