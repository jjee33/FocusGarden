/**
 * One recorded focus or break session. Port of models/focus_session.gd.
 *
 * This is the authoritative analytics record. Statistics are always derived from
 * these rows, never stored only as aggregates, so any total can be recomputed
 * from scratch if a cached rollup is ever wrong.
 *
 * Enums stay NUMERIC here, unlike the authored content in content.generated.json.
 * These values are written into save files and synced between clients, so their
 * ordinals are part of the wire format and cannot be renamed into strings without
 * a migration.
 */

import { clampi, maxf, maxi, toInt } from "./gd.js";
import type { Json } from "./dict-util.js";
import { getBool, getFloat, getInt, getString } from "./dict-util.js";
import { isValidDateKey, localDateKey, localHour } from "./time-util.js";

export const Kind = { FOCUS: 0, SHORT_BREAK: 1, LONG_BREAK: 2 } as const;
export type Kind = (typeof Kind)[keyof typeof Kind];

export const Completion = {
  /** Ran to the intended duration. Full credit. */
  COMPLETED: 0,
  /** Player finished manually. Credit for actual focus time. */
  ENDED_EARLY: 1,
  /** Player discarded it. No growth credit. */
  CANCELLED: 2,
  /** App closed or crashed mid-session; recovered on next launch. */
  ABANDONED: 3,
} as const;
export type Completion = (typeof Completion)[keyof typeof Completion];

/**
 * Divergence between the monotonic and wall clocks means the machine slept or the
 * clock moved. We keep the session and flag it rather than punishing the player
 * or corrupting statistics.
 */
export const Anomaly = { NONE: 0, SUSPEND: 1, CLOCK_JUMP: 2, NEGATIVE_DURATION: 3 } as const;
export type Anomaly = (typeof Anomaly)[keyof typeof Anomaly];

export interface FocusSession {
  id: string;
  kind: Kind;
  startedAtUtc: number;
  endedAtUtc: number;
  /** Local date the session STARTED, captured at record time and never recomputed. */
  dateKey: string;
  /** Local hour 0-23 at start, so time-of-day rules never re-derive an offset. */
  startHour: number;
  intendedDurationMinutes: number;
  /** Credited focus time. Excludes paused time and is capped when an anomaly is seen. */
  actualFocusMinutes: number;
  pausedMinutes: number;
  completion: Completion;
  anomaly: Anomaly;
  interruptionReason: string;
  projectId: string;
  plantUid: string;
  xpEarned: number;
  /**
   * Idempotency guard for the session pipeline. Once the completion steps have run
   * for this session they can never run again - this is what makes "XP cannot
   * double-award" a structural property rather than a hope.
   */
  awardsApplied: boolean;
}

export function makeFocusSession(overrides: Partial<FocusSession> = {}): FocusSession {
  return {
    id: "", kind: Kind.FOCUS, startedAtUtc: 0, endedAtUtc: 0, dateKey: "", startHour: 0,
    intendedDurationMinutes: 0, actualFocusMinutes: 0, pausedMinutes: 0,
    completion: Completion.COMPLETED, anomaly: Anomaly.NONE, interruptionReason: "",
    projectId: "", plantUid: "", xpEarned: 0, awardsApplied: false,
    ...overrides,
  };
}

export function createFocusSession(
  kind: Kind, intendedMinutes: number, projectId: string, plantUid: string,
  id: string, nowUnixUtc: number, offsetSeconds?: number,
): FocusSession {
  return makeFocusSession({
    id, kind, intendedDurationMinutes: intendedMinutes, projectId, plantUid,
    startedAtUtc: nowUnixUtc,
    dateKey: localDateKey(nowUnixUtc, offsetSeconds),
    startHour: localHour(nowUnixUtc, offsetSeconds),
  });
}

export function isFocus(session: FocusSession): boolean {
  return session.kind === Kind.FOCUS;
}

export function isBreak(session: FocusSession): boolean {
  return session.kind === Kind.SHORT_BREAK || session.kind === Kind.LONG_BREAK;
}

/**
 * Whether this session should contribute growth, XP and streak credit.
 * Cancelled sessions and anything with no credited time never count.
 */
export function countsTowardProgress(session: FocusSession): boolean {
  return session.completion !== Completion.CANCELLED && session.actualFocusMinutes > 0;
}

export function focusSessionToDict(s: FocusSession): Json {
  return {
    id: s.id,
    kind: s.kind,
    started_at_utc: s.startedAtUtc,
    ended_at_utc: s.endedAtUtc,
    date_key: s.dateKey,
    start_hour: s.startHour,
    intended_duration_minutes: s.intendedDurationMinutes,
    actual_focus_minutes: s.actualFocusMinutes,
    paused_minutes: s.pausedMinutes,
    completion: s.completion,
    anomaly: s.anomaly,
    interruption_reason: s.interruptionReason,
    project_id: s.projectId,
    plant_uid: s.plantUid,
    xp_earned: s.xpEarned,
    awards_applied: s.awardsApplied,
  };
}

export function focusSessionFromDict(data: Json, offsetSeconds?: number): FocusSession {
  const session = makeFocusSession({
    id: getString(data, "id"),
    kind: safeKind(getInt(data, "kind", Kind.FOCUS)),
    startedAtUtc: getFloat(data, "started_at_utc"),
    endedAtUtc: getFloat(data, "ended_at_utc"),
    dateKey: getString(data, "date_key"),
    startHour: clampi(getInt(data, "start_hour"), 0, 23),
    intendedDurationMinutes: maxf(0, getFloat(data, "intended_duration_minutes")),
    // Negative durations are impossible and would poison every total that sums
    // them, so they are clamped here at the boundary.
    actualFocusMinutes: maxf(0, getFloat(data, "actual_focus_minutes")),
    pausedMinutes: maxf(0, getFloat(data, "paused_minutes")),
    completion: safeCompletion(getInt(data, "completion", Completion.COMPLETED)),
    anomaly: safeAnomaly(getInt(data, "anomaly", Anomaly.NONE)),
    interruptionReason: getString(data, "interruption_reason"),
    projectId: getString(data, "project_id"),
    plantUid: getString(data, "plant_uid"),
    xpEarned: maxi(0, getInt(data, "xp_earned")),
    awardsApplied: getBool(data, "awards_applied"),
  });

  // A record with no usable date key cannot be placed on the calendar. Rebuild it
  // from the timestamp rather than dropping the session entirely.
  if (!isValidDateKey(session.dateKey) && session.startedAtUtc > 0) {
    session.dateKey = localDateKey(session.startedAtUtc, offsetSeconds);
  }
  return session;
}

// Enum values arriving from JSON are untrusted; an out-of-range int would make
// later switches fall through in surprising ways.
function safeKind(value: number): Kind {
  return value >= 0 && value <= Kind.LONG_BREAK ? (toInt(value) as Kind) : Kind.FOCUS;
}

function safeCompletion(value: number): Completion {
  return value >= 0 && value <= Completion.ABANDONED
    ? (toInt(value) as Completion)
    : Completion.COMPLETED;
}

function safeAnomaly(value: number): Anomaly {
  return value >= 0 && value <= Anomaly.NEGATIVE_DURATION
    ? (toInt(value) as Anomaly)
    : Anomaly.NONE;
}

/** Ids are time-prefixed so they sort chronologically. Port of systems/util/uid.gd. */
export function generateUid(prefix: string, nowUnixUtc = Date.now() / 1000): string {
  const stamp = Math.trunc(nowUnixUtc * 1000).toString(36);
  let random = "";
  for (let i = 0; i < 8; i++) random += "0123456789abcdef"[Math.floor(Math.random() * 16)];
  return `${prefix}_${stamp}-${random}`;
}
