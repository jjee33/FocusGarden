/**
 * Authoritative elapsed-time measurement for focus sessions.
 * Port of systems/time/game_clock.gd.
 *
 * THE RULE: elapsed time is derived from timestamps, never accumulated frame
 * deltas. That is why the timer survives a minimised window or a stalled frame -
 * none of those touch a timestamp. In a browser it matters more than it did on
 * the desktop: background tabs have their timer callbacks throttled to once a
 * second or worse, and any implementation that counted ticks would quietly lose
 * most of a session the moment someone switched tabs. This one recomputes from
 * timestamps on every read, so throttling changes only how often the display
 * refreshes, never what it says.
 *
 * THE DUAL CLOCK: two clocks run at once.
 *   * monotonic (`performance.now`) - cannot be changed by the user or the OS,
 *     but does not advance while the machine is asleep.
 *   * wall (`Date.now`) - survives sleep and restarts, but moves when the clock
 *     is set, when NTP corrects, and at DST boundaries.
 *
 * Credited time is ALWAYS the monotonic elapsed time. The wall clock is used
 * only to DETECT anomalies and to survive restarts - never to decide how much
 * credit a session earns. Working through the cases:
 *   * machine slept 3 hours mid-session -> wall advances, monotonic does not, so
 *     credit is the few minutes actually spent awake. The player was asleep.
 *   * user winds the clock forward to farm plants -> wall inflates, monotonic is
 *     untouched, credit stays honest.
 *   * clock corrected backwards mid-session -> wall goes backwards, monotonic
 *     keeps counting, credit is unaffected.
 *
 * An earlier draft of the original credited min(monotonic, wall). That is wrong
 * for the third case: a backwards correction would silently delete real focus
 * time the player had earned.
 *
 * Divergence is never punished. The session is kept and flagged.
 *
 * BROWSER CAVEAT the desktop did not have: `performance.now` is deliberately
 * coarsened by browsers (to ~100us, or as much as 1-2ms with cross-origin
 * isolation disabled) as a Spectre mitigation. That is far below the 5-second
 * anomaly threshold, so it cannot produce a false anomaly, but it does mean the
 * monotonic reading is not exact to the microsecond the way Time.get_ticks_usec
 * is. Nothing here depends on that precision.
 */

import { maxf } from "./gd.js";
import type { Json } from "./dict-util.js";
import { getFloat, getInt } from "./dict-util.js";
import type { Anomaly } from "./focus-session.js";
import { Anomaly as A } from "./focus-session.js";

/**
 * Divergence beyond this is treated as an anomaly rather than clock jitter.
 * Generous enough that ordinary NTP drift never trips it.
 */
export const ANOMALY_THRESHOLD_SECONDS = 5.0;

export const ClockState = { IDLE: 0, RUNNING: 1, PAUSED: 2 } as const;
export type ClockState = (typeof ClockState)[keyof typeof ClockState];

/** Result of a measurement. Typed fields, so a typo is a compile error. */
export interface Sample {
  creditedSeconds: number;
  pausedSeconds: number;
  anomaly: Anomaly;
  wallElapsedSeconds: number;
  monotonicElapsedSeconds: number;
}

export interface TimeProviders {
  /** Seconds, monotonic. Defaults to performance.now() / 1000. */
  monotonic: () => number;
  /** Unix seconds. Defaults to Date.now() / 1000. */
  wall: () => number;
}

const defaultProviders: TimeProviders = {
  monotonic: () => performance.now() / 1000,
  wall: () => Date.now() / 1000,
};

export class GameClock {
  state: ClockState = ClockState.IDLE;

  private wallStart = 0;
  private monoStart = 0;
  /** Paused time across all previous pauses, measured monotonically. */
  private pausedAccumulated = 0;
  private pauseBeganMono = 0;
  /** Set when rebuilt from a persisted session; monotonic history is then gone. */
  private recoveredFromSave = false;
  private providers: TimeProviders;

  /**
   * `providers` is injectable so tests can simulate sleep, clock jumps and long
   * sessions without waiting or touching the system clock.
   */
  constructor(providers: Partial<TimeProviders> = {}) {
    this.providers = { ...defaultProviders, ...providers };
  }

  start(): void {
    this.wallStart = this.providers.wall();
    this.monoStart = this.providers.monotonic();
    this.pausedAccumulated = 0;
    this.pauseBeganMono = 0;
    this.recoveredFromSave = false;
    this.state = ClockState.RUNNING;
  }

  pause(): void {
    if (this.state !== ClockState.RUNNING) return;
    this.pauseBeganMono = this.providers.monotonic();
    this.state = ClockState.PAUSED;
  }

  resume(): void {
    if (this.state !== ClockState.PAUSED) return;
    // Pause length is measured monotonically. Using wall time here would let a
    // clock change while paused silently add or remove focus credit.
    this.pausedAccumulated += maxf(0, this.providers.monotonic() - this.pauseBeganMono);
    this.pauseBeganMono = 0;
    this.state = ClockState.RUNNING;
  }

  stop(): void {
    this.state = ClockState.IDLE;
  }

  /** Current measurement. Pure arithmetic over four numbers; safe to call often. */
  sample(): Sample {
    const result: Sample = {
      creditedSeconds: 0, pausedSeconds: 0, anomaly: A.NONE,
      wallElapsedSeconds: 0, monotonicElapsedSeconds: 0,
    };
    if (this.state === ClockState.IDLE && this.wallStart === 0) return result;

    const nowMono = this.providers.monotonic();
    const nowWall = this.providers.wall();

    // A pause still in progress is not yet in the accumulator.
    let paused = this.pausedAccumulated;
    if (this.state === ClockState.PAUSED) {
      paused += maxf(0, nowMono - this.pauseBeganMono);
    }

    const monoElapsed = nowMono - this.monoStart - paused;
    const wallElapsed = nowWall - this.wallStart - paused;
    result.monotonicElapsedSeconds = monoElapsed;
    result.wallElapsedSeconds = wallElapsed;
    result.pausedSeconds = paused;

    if (this.recoveredFromSave) {
      // Monotonic history did not survive the restart, so it would read as
      // near-zero and wrongly zero out a legitimate session. Wall time is all we
      // have; the session is already flagged as recovered by the caller.
      result.creditedSeconds = maxf(0, wallElapsed);
      return result;
    }

    const divergence = wallElapsed - monoElapsed;
    if (divergence > ANOMALY_THRESHOLD_SECONDS) {
      // Wall ran ahead of monotonic. Overwhelmingly the common cause is system
      // suspend; a forward clock change looks identical from here. Either way the
      // credited figure is the same conservative one.
      result.anomaly = A.SUSPEND;
    } else if (divergence < -ANOMALY_THRESHOLD_SECONDS) {
      // Wall went backwards relative to monotonic: the clock was set back, NTP
      // corrected, or DST rolled. Monotonic cannot do this.
      result.anomaly = A.CLOCK_JUMP;
    }

    let credited = monoElapsed;
    if (credited < 0) {
      // Monotonic time cannot decrease, so this means the accumulated pause
      // exceeds the elapsed time - a bookkeeping impossibility. Preserve the
      // session, credit nothing, flag it.
      result.anomaly = A.NEGATIVE_DURATION;
      credited = 0;
    }
    result.creditedSeconds = credited;
    return result;
  }

  /**
   * Serialises the in-flight clock so a session survives the tab closing.
   * Only wall time is stored: monotonic values are meaningless across a reload.
   */
  toDict(): Json {
    return {
      wall_start: this.wallStart,
      paused_accumulated: this.pausedAccumulated,
      state: this.state,
    };
  }

  /**
   * Rebuilds a clock from a persisted in-flight session. The result measures with
   * wall time only, and callers must flag the session as recovered, because we
   * cannot know whether the machine was asleep while the tab was closed.
   */
  static fromDict(data: Json, providers: Partial<TimeProviders> = {}): GameClock {
    const clock = new GameClock(providers);
    clock.wallStart = getFloat(data, "wall_start");
    clock.pausedAccumulated = maxf(0, getFloat(data, "paused_accumulated"));
    const rawState = getInt(data, "state", ClockState.IDLE);
    clock.state = rawState >= 0 && rawState <= ClockState.PAUSED
      ? (rawState as ClockState)
      : ClockState.IDLE;
    clock.monoStart = clock.providers.monotonic();
    clock.recoveredFromSave = true;
    return clock;
  }
}
