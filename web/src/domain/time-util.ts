/**
 * Calendar helpers for streaks, heatmaps and daily goals.
 * Port of systems/util/time_util.gd.
 *
 * DAYLIGHT SAVING POLICY: a session's local date key is captured at the moment
 * the session is recorded and then stored permanently on the record. Aggregation
 * reads the stored key and never recomputes it from the UTC stamp. Recomputing
 * later would apply today's UTC offset to a historical timestamp and silently
 * shift sessions across midnight whenever DST flipped in between.
 *
 * MIDNIGHT POLICY: a session spanning midnight is credited entirely to the local
 * date it STARTED on. Sessions are not split, so one session is one row of
 * history and a 23:50 start belongs to the day the player sat down.
 *
 * DATE VALIDATION IS STRICTER HERE THAN IN JAVASCRIPT'S Date.
 * `Date.parse("2026-02-30T00:00:00Z")` silently rolls over to 2 March. Godot's
 * parser rejects it. Rolling over would put a session on a day that does not
 * exist and quietly break the streak either side of it, so the parts are range
 * checked by hand before any Date is constructed.
 */

import { clampi, gdRound, intdiv, maxi, pad2, toInt } from "./gd.js";

export const SECONDS_PER_DAY = 86400;
export const SECONDS_PER_MINUTE = 60;

/** Short forms, so a date never pushes a card wider than its neighbours. */
export const MONTH_ABBREVIATIONS = [
  "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
] as const;

/**
 * Current UTC offset in seconds, as reported by the runtime right now.
 *
 * `getTimezoneOffset` counts minutes WEST of UTC, the opposite sign to Godot's
 * `bias`, hence the negation.
 */
export function localOffsetSeconds(atUnixUtc?: number): number {
  const at = atUnixUtc === undefined ? new Date() : new Date(atUnixUtc * 1000);
  return -at.getTimezoneOffset() * SECONDS_PER_MINUTE;
}

/**
 * "YYYY-MM-DD" in local time for a UTC unix timestamp.
 * Capture this once, at record time, then store it.
 *
 * `offsetSeconds` is injectable so tests can pin a zone instead of depending on
 * where the suite happens to run.
 */
export function localDateKey(unixUtc: number, offsetSeconds?: number): string {
  const offset = offsetSeconds ?? localOffsetSeconds(unixUtc);
  const shifted = toInt(unixUtc) + offset;
  const d = new Date(shifted * 1000);
  return `${String(d.getUTCFullYear()).padStart(4, "0")}-${pad2(d.getUTCMonth() + 1)}-${pad2(d.getUTCDate())}`;
}

export function todayKey(nowUnixUtc?: number, offsetSeconds?: number): string {
  return localDateKey(nowUnixUtc ?? Date.now() / 1000, offsetSeconds);
}

/** Local hour 0-23, for time-of-day requirements and the Night Owl achievement. */
export function localHour(unixUtc: number, offsetSeconds?: number): number {
  const offset = offsetSeconds ?? localOffsetSeconds(unixUtc);
  return new Date((toInt(unixUtc) + offset) * 1000).getUTCHours();
}

/**
 * Whole days from `fromKey` to `toKey`. Negative when `toKey` is earlier.
 * Returns 0 for unparseable input rather than throwing, so one bad record cannot
 * break a whole streak calculation.
 */
export function daysBetween(fromKey: string, toKey: string): number {
  const from = dateKeyToUnix(fromKey);
  const to = dateKeyToUnix(toKey);
  if (from < 0 || to < 0) return 0;
  return gdRound((to - from) / SECONDS_PER_DAY);
}

/** Date key `offset` days away from `key`. Unparseable keys are returned as-is. */
export function shiftDateKey(key: string, offset: number): string {
  const base = dateKeyToUnix(key);
  if (base < 0) return key;
  const d = new Date((base + offset * SECONDS_PER_DAY) * 1000);
  return `${String(d.getUTCFullYear()).padStart(4, "0")}-${pad2(d.getUTCMonth() + 1)}-${pad2(d.getUTCDate())}`;
}

export function isValidDateKey(key: string): boolean {
  return dateKeyToUnix(key) >= 0;
}

/**
 * "14 Aug 2026" - one day, written the way a person reads one.
 *
 * Takes a stored date key rather than a timestamp: a key already IS a local day,
 * captured at record time, and re-deriving it from a timestamp would apply
 * today's UTC offset to a historical date.
 */
export function formatDateKey(key: string): string {
  if (!isValidDateKey(key)) return key;
  const parts = key.split("-");
  const day = toInt(Number(parts[2]));
  const month = MONTH_ABBREVIATIONS[clampi(toInt(Number(parts[1])) - 1, 0, 11)];
  const year = toInt(Number(parts[0]));
  return `${day} ${month} ${year}`;
}

/**
 * "1h 25m" / "45m" / "30s". Used everywhere focus time is displayed, so the app
 * never shows two different formats for the same quantity.
 */
export function formatDuration(totalMinutes: number): string {
  // Exactly zero reads as "0m", not "0s". A stat tile showing "0s" for a day with
  // no focus implies a stopwatch is running; "0m" reads as "none yet".
  if (totalMinutes <= 0) return "0m";
  if (totalMinutes < 1) return `${toInt(gdRound(totalMinutes * SECONDS_PER_MINUTE))}s`;
  const whole = toInt(gdRound(totalMinutes));
  const hours = intdiv(whole, 60);
  const minutes = whole % 60;
  if (hours <= 0) return `${minutes}m`;
  // A whole number of hours says so. The zero-padded minutes keep "1h 05m"
  // aligned with "1h 25m" in a column; "3h 00m" is just noise.
  if (minutes === 0) return `${hours}h`;
  return `${hours}h ${pad2(minutes)}m`;
}

/** Countdown clock: "25:00", or "1:05:00" once past an hour. */
export function formatCountdown(totalSeconds: number): string {
  const remaining = maxi(0, Math.ceil(totalSeconds));
  const hours = intdiv(remaining, 3600);
  const minutes = intdiv(remaining % 3600, 60);
  const seconds = remaining % 60;
  if (hours > 0) return `${hours}:${pad2(minutes)}:${pad2(seconds)}`;
  return `${minutes}:${pad2(seconds)}`;
}

/**
 * "14 Aug 2026, 09:42" - a moment, written the way a person reads one.
 *
 * KNOWN DIVERGENCE FROM THE DESKTOP BUILD, deliberate. `TimeUtil.format_datetime`
 * in GDScript calls `Time.get_datetime_dict_from_unix_time`, which returns UTC
 * components, and never adds `local_offset_seconds` — so despite its own comment
 * saying "Local time, deliberately", the desktop app renders these timestamps in
 * UTC. Every other function in that file applies the offset correctly. This port
 * does what the comment says rather than what the code does; the desktop bug is
 * worth fixing separately, and until it is, "planted at" times differ between the
 * two clients by the viewer's UTC offset.
 */
export function formatDatetime(unixSeconds: number, offsetSeconds?: number): string {
  if (unixSeconds <= 0) return "";
  const offset = offsetSeconds ?? localOffsetSeconds(unixSeconds);
  const d = new Date((toInt(unixSeconds) + offset) * 1000);
  const month = MONTH_ABBREVIATIONS[clampi(d.getUTCMonth(), 0, 11)];
  return `${d.getUTCDate()} ${month} ${d.getUTCFullYear()}, ${pad2(d.getUTCHours())}:${pad2(d.getUTCMinutes())}`;
}

/**
 * Date keys are interpreted at UTC midnight purely as a stable day index. The key
 * already encodes local time, so no further offset may be applied here - doing so
 * would double-shift and break daysBetween across timezone changes.
 *
 * Returns -1 for anything unparseable. Godot returns 0 both for the epoch itself
 * and for junk, and resolves the ambiguity by special-casing the one date a save
 * can never legitimately contain; that behaviour is reproduced exactly.
 */
export function dateKeyToUnix(key: string): number {
  if (key.length !== 10) return -1;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(key)) return -1;

  const year = Number(key.slice(0, 4));
  const month = Number(key.slice(5, 7));
  const day = Number(key.slice(8, 10));
  if (month < 1 || month > 12) return -1;
  if (day < 1 || day > daysInMonth(year, month)) return -1;

  // NOT Date.UTC: it remaps years 0-99 onto 1900-1999, so "0042-01-01" would
  // silently become 1942. setUTCFullYear on an epoch Date has no such legacy.
  const d = new Date(0);
  d.setUTCFullYear(year, month - 1, day);
  d.setUTCHours(0, 0, 0, 0);

  const parsed = d.getTime() / 1000;
  if (parsed === 0 && key !== "1970-01-01") return -1;
  return parsed;
}

function daysInMonth(year: number, month: number): number {
  if (month === 2) return isLeapYear(year) ? 29 : 28;
  return month === 4 || month === 6 || month === 9 || month === 11 ? 30 : 31;
}

function isLeapYear(year: number): boolean {
  return (year % 4 === 0 && year % 100 !== 0) || year % 400 === 0;
}
