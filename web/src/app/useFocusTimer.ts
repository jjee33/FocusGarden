/**
 * The focus timer, on top of GameClock.
 *
 * Owns the session lifecycle and nothing else - it never awards XP, grows a
 * plant, or evaluates an achievement. When a session ends it hands the numbers
 * to the caller and stops caring, exactly as TimerManager does.
 *
 * THE TICK IS A DISPLAY CONCERN ONLY. It exists to repaint the countdown; the
 * value it paints is recomputed from timestamps every time. That is why a
 * background tab - where browsers clamp intervals to once a second or worse -
 * cannot cost the player a single credited second. Nothing here accumulates.
 */

import { useCallback, useEffect, useRef, useState } from "react";

import { ClockState, GameClock } from "../domain/game-clock.js";
import type { Anomaly, Completion, Kind } from "../domain/focus-session.js";
import { Anomaly as A, Completion as C, Kind as K } from "../domain/focus-session.js";

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

export interface FinishedSession {
  kind: Kind;
  intendedMinutes: number;
  rawMinutes: number;
  completion: Completion;
}

export function useFocusTimer(onFinished: (session: FinishedSession) => void) {
  const clock = useRef<GameClock>(null as unknown as GameClock);
  if (clock.current === null) clock.current = new GameClock();

  const config = useRef<{ kind: Kind; intendedMinutes: number }>({
    kind: K.FOCUS, intendedMinutes: 0,
  });
  const [snapshot, setSnapshot] = useState<TimerSnapshot>(IDLE);
  const finishedRef = useRef(false);
  const onFinishedRef = useRef(onFinished);
  onFinishedRef.current = onFinished;

  const read = useCallback((): TimerSnapshot => {
    const c = clock.current;
    if (c.state === ClockState.IDLE) return IDLE;
    const sample = c.sample();
    const { kind, intendedMinutes } = config.current;
    const totalSeconds = intendedMinutes * 60;
    const remaining = Math.max(0, totalSeconds - sample.creditedSeconds);
    return {
      state: c.state === ClockState.PAUSED ? "paused" : "running",
      kind,
      intendedMinutes,
      remainingSeconds: remaining,
      elapsedMinutes: sample.creditedSeconds / 60,
      pausedMinutes: sample.pausedSeconds / 60,
      ratio: totalSeconds <= 0 ? 0 : Math.min(1, sample.creditedSeconds / totalSeconds),
      anomaly: sample.anomaly,
      finished: totalSeconds > 0 && sample.creditedSeconds >= totalSeconds,
    };
  }, []);

  useEffect(() => {
    if (snapshot.state === "idle") return;
    const id = setInterval(() => setSnapshot(read()), TICK_MS);
    // Repainting on return from a background tab matters: the interval may not
    // have run for minutes, and the first thing the player sees must be right.
    const onVisible = (): void => setSnapshot(read());
    document.addEventListener("visibilitychange", onVisible);
    return () => {
      clearInterval(id);
      document.removeEventListener("visibilitychange", onVisible);
    };
  }, [snapshot.state, read]);

  const finish = useCallback((completion: Completion) => {
    const c = clock.current;
    if (c.state === ClockState.IDLE) return;
    const sample = c.sample();
    c.stop();
    finishedRef.current = false;
    setSnapshot(IDLE);
    onFinishedRef.current({
      kind: config.current.kind,
      intendedMinutes: config.current.intendedMinutes,
      rawMinutes: sample.creditedSeconds / 60,
      completion,
    });
  }, []);

  // Auto-complete when the intended duration is reached. Guarded so a burst of
  // ticks past the finish line cannot fire it twice.
  useEffect(() => {
    if (snapshot.finished && !finishedRef.current) {
      finishedRef.current = true;
      finish(C.COMPLETED);
    }
  }, [snapshot.finished, finish]);

  const start = useCallback((kind: Kind, intendedMinutes: number) => {
    config.current = { kind, intendedMinutes };
    finishedRef.current = false;
    clock.current.start();
    setSnapshot(read());
  }, [read]);

  const pause = useCallback(() => {
    clock.current.pause();
    setSnapshot(read());
  }, [read]);

  const resume = useCallback(() => {
    clock.current.resume();
    setSnapshot(read());
  }, [read]);

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
