/**
 * The focus timer, on top of GameClock.
 *
 * Owns the session lifecycle and nothing else - it never awards XP, grows a
 * plant, or evaluates an achievement. When a session ends it hands the record to
 * the caller and stops caring, exactly as TimerManager does.
 *
 * THE TICK IS A DISPLAY CONCERN ONLY. It exists to repaint the countdown; the
 * value it paints is recomputed from timestamps every time. That is why a
 * background tab - where browsers clamp intervals to once a second or worse -
 * cannot cost the player a single credited second. Nothing here accumulates.
 *
 * The timer OWNS the session record from the moment it starts, rather than
 * building one at the end. That is what makes an interrupted session
 * recoverable: there is something to write down before the tab goes away.
 */

import { useCallback, useEffect, useRef, useState } from "react";

import { ClockState, GameClock } from "../domain/game-clock.js";
import type { Anomaly, Completion, FocusSession, Kind } from "../domain/focus-session.js";
import { Anomaly as A, Completion as C, Kind as K, createFocusSession } from "../domain/focus-session.js";
import { generate } from "../domain/uid.js";
import { settle } from "../domain/session-credit.js";
import { SECONDS_PER_MINUTE } from "../domain/time-util.js";

/** How often the countdown is republished. The displayed value is still exact. */
const TICK_MS = 250;

export type TimerState = "idle" | "running" | "paused";

export interface TimerSnapshot {
  state: TimerState;
  kind: Kind;
  intendedMinutes: number;
  /** Seconds left, floored at zero. */
  remainingSeconds: number;
  elapsedMinutes: number;
  pausedMinutes: number;
  /** 0..1 through the intended duration, for the dial. */
  ratio: number;
  anomaly: Anomaly;
  /** True once the intended duration has elapsed. */
  finished: boolean;
}

const IDLE: TimerSnapshot = {
  state: "idle", kind: K.FOCUS, intendedMinutes: 0, remainingSeconds: 0,
  elapsedMinutes: 0, pausedMinutes: 0, ratio: 0, anomaly: A.NONE, finished: false,
};

export interface TimerHooks {
  /** A finished session, already settled. The caller applies it. */
  onFinished: (session: FocusSession) => void;
  /** Called on every STATE CHANGE so the running session survives a closed tab. */
  onPersist?: (session: FocusSession, clock: GameClock) => void;
  /** Called once the session is no longer in flight. */
  onCleared?: () => void;
}

export function useFocusTimer(hooks: TimerHooks) {
  const clock = useRef<GameClock>(null as unknown as GameClock);
  if (clock.current === null) clock.current = new GameClock();

  const current = useRef<FocusSession | null>(null);
  const [snapshot, setSnapshot] = useState<TimerSnapshot>(IDLE);
  const finishedRef = useRef(false);
  const hooksRef = useRef(hooks);
  hooksRef.current = hooks;

  const read = useCallback((): TimerSnapshot => {
    const c = clock.current;
    const session = current.current;
    if (c.state === ClockState.IDLE || session === null) return IDLE;
    const sample = c.sample();
    const totalSeconds = session.intendedDurationMinutes * 60;
    return {
      state: c.state === ClockState.PAUSED ? "paused" : "running",
      kind: session.kind,
      intendedMinutes: session.intendedDurationMinutes,
      remainingSeconds: Math.max(0, totalSeconds - sample.creditedSeconds),
      elapsedMinutes: sample.creditedSeconds / SECONDS_PER_MINUTE,
      pausedMinutes: sample.pausedSeconds / SECONDS_PER_MINUTE,
      ratio: totalSeconds <= 0 ? 0 : Math.min(1, sample.creditedSeconds / totalSeconds),
      anomaly: sample.anomaly,
      finished: totalSeconds > 0 && sample.creditedSeconds >= totalSeconds,
    };
  }, []);

  const persist = useCallback(() => {
    const session = current.current;
    if (session === null) return;
    hooksRef.current.onPersist?.(session, clock.current);
  }, []);

  useEffect(() => {
    if (snapshot.state === "idle") return;
    const id = setInterval(() => setSnapshot(read()), TICK_MS);

    // Repainting on return from a background tab matters: the interval may not
    // have run for minutes, and the first thing the player sees must be right.
    const onVisible = (): void => setSnapshot(read());
    // pagehide, not beforeunload: mobile browsers do not fire beforeunload when
    // the OS reclaims a backgrounded page, which is exactly when a session is
    // most likely to be lost.
    const onHide = (): void => persist();
    document.addEventListener("visibilitychange", onVisible);
    window.addEventListener("pagehide", onHide);
    return () => {
      clearInterval(id);
      document.removeEventListener("visibilitychange", onVisible);
      window.removeEventListener("pagehide", onHide);
    };
  }, [snapshot.state, read, persist]);

  const finish = useCallback((completion: Completion) => {
    const c = clock.current;
    const session = current.current;
    if (c.state === ClockState.IDLE || session === null) return;

    const sample = c.sample();
    c.stop();
    current.current = null;
    finishedRef.current = false;
    setSnapshot(IDLE);

    // Settled here, in the one place that decides how much of a measured session
    // counts, before anything downstream sees a number.
    session.actualFocusMinutes = settle(
      completion,
      sample.creditedSeconds / SECONDS_PER_MINUTE,
      session.intendedDurationMinutes,
    );
    session.pausedMinutes = sample.pausedSeconds / SECONDS_PER_MINUTE;
    session.completion = completion;
    session.anomaly = sample.anomaly;
    session.endedAtUtc = Date.now() / 1000;

    hooksRef.current.onCleared?.();
    hooksRef.current.onFinished(session);
  }, []);

  // Auto-complete at the intended duration. Guarded so a burst of ticks past the
  // finish line cannot fire it twice.
  useEffect(() => {
    if (snapshot.finished && !finishedRef.current) {
      finishedRef.current = true;
      finish(C.COMPLETED);
    }
  }, [snapshot.finished, finish]);

  const start = useCallback((
    kind: Kind, intendedMinutes: number, projectId = "", plantUid = "",
  ) => {
    const now = Date.now() / 1000;
    current.current = createFocusSession(
      kind, intendedMinutes, projectId, plantUid, generate("s", now), now,
    );
    finishedRef.current = false;
    clock.current.start();
    setSnapshot(read());
    persist();
  }, [read, persist]);

  const pause = useCallback(() => {
    clock.current.pause();
    setSnapshot(read());
    persist();
  }, [read, persist]);

  const resume = useCallback(() => {
    clock.current.resume();
    setSnapshot(read());
    persist();
  }, [read, persist]);

  return {
    snapshot,
    start,
    pause,
    resume,
    /** Player finished manually. Credit for the time actually focused. */
    endEarly: () => finish(C.ENDED_EARLY),
    /** Player discarded it. No growth credit, but the record is still kept. */
    cancel: () => finish(C.CANCELLED),
  };
}
