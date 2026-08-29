/**
 * The clock is tested with injected time sources, because the cases that matter
 * are a laptop lid closing, a clock being wound forward to farm plants, and NTP
 * stepping backwards mid-session. None of those are reachable by waiting.
 */

import { describe, expect, it } from "vitest";

import { ANOMALY_THRESHOLD_SECONDS, ClockState, GameClock } from "../game-clock.js";
import { Anomaly } from "../focus-session.js";

/** A pair of clocks that can be moved independently, the way reality moves them. */
function fakeClocks(startWall = 1_700_000_000) {
  const state = { mono: 1000, wall: startWall };
  const providers = { monotonic: () => state.mono, wall: () => state.wall };
  return {
    providers,
    /** Ordinary time passing: both clocks advance together. */
    advance(seconds: number) {
      state.mono += seconds;
      state.wall += seconds;
    },
    /** The lid closes: wall time passes, monotonic does not. */
    sleep(seconds: number) {
      state.wall += seconds;
    },
    /** Someone sets the clock. Monotonic is untouched. */
    setWallClock(delta: number) {
      state.wall += delta;
    },
  };
}

describe("GameClock", () => {
  it("credits monotonic elapsed time for an ordinary session", () => {
    const c = fakeClocks();
    const clock = new GameClock(c.providers);
    clock.start();
    c.advance(25 * 60);
    const sample = clock.sample();
    expect(sample.creditedSeconds).toBe(1500);
    expect(sample.anomaly).toBe(Anomaly.NONE);
  });

  it("excludes paused time from credit", () => {
    const c = fakeClocks();
    const clock = new GameClock(c.providers);
    clock.start();
    c.advance(600);
    clock.pause();
    c.advance(300);
    clock.resume();
    c.advance(600);
    const sample = clock.sample();
    expect(sample.creditedSeconds).toBe(1200);
    expect(sample.pausedSeconds).toBe(300);
  });

  it("counts an in-progress pause without ending it", () => {
    const c = fakeClocks();
    const clock = new GameClock(c.providers);
    clock.start();
    c.advance(60);
    clock.pause();
    c.advance(45);
    const sample = clock.sample();
    expect(sample.pausedSeconds).toBe(45);
    expect(sample.creditedSeconds).toBe(60);
    expect(clock.state).toBe(ClockState.PAUSED);
  });

  it("credits only waking time when the machine sleeps, and flags it", () => {
    const c = fakeClocks();
    const clock = new GameClock(c.providers);
    clock.start();
    c.advance(120);
    c.sleep(3 * 60 * 60);
    const sample = clock.sample();
    // The player was asleep, not focusing.
    expect(sample.creditedSeconds).toBe(120);
    expect(sample.wallElapsedSeconds).toBe(120 + 10800);
    expect(sample.anomaly).toBe(Anomaly.SUSPEND);
  });

  it("ignores a clock wound forward to farm plants", () => {
    const c = fakeClocks();
    const clock = new GameClock(c.providers);
    clock.start();
    c.advance(60);
    c.setWallClock(10 * 60 * 60);
    const sample = clock.sample();
    expect(sample.creditedSeconds).toBe(60);
    expect(sample.anomaly).toBe(Anomaly.SUSPEND);
  });

  it("does not delete earned time when the clock steps backwards", () => {
    const c = fakeClocks();
    const clock = new GameClock(c.providers);
    clock.start();
    c.advance(900);
    // NTP correction, a manual fix, or a DST roll.
    c.setWallClock(-3600);
    const sample = clock.sample();
    // The original once credited min(monotonic, wall), which silently destroyed
    // fifteen minutes of real focus in exactly this case.
    expect(sample.creditedSeconds).toBe(900);
    expect(sample.anomaly).toBe(Anomaly.CLOCK_JUMP);
  });

  it("treats drift below the threshold as jitter, not an anomaly", () => {
    const c = fakeClocks();
    const clock = new GameClock(c.providers);
    clock.start();
    c.advance(600);
    c.setWallClock(ANOMALY_THRESHOLD_SECONDS - 0.5);
    expect(clock.sample().anomaly).toBe(Anomaly.NONE);
  });

  it("is unaffected by how often it is sampled", () => {
    // The property that makes this survive background-tab throttling: reading it
    // once after 25 minutes and reading it 1,500 times must agree exactly.
    const rare = fakeClocks();
    const rareClock = new GameClock(rare.providers);
    rareClock.start();
    rare.advance(1500);

    const often = fakeClocks();
    const oftenClock = new GameClock(often.providers);
    oftenClock.start();
    for (let i = 0; i < 1500; i++) {
      often.advance(1);
      oftenClock.sample();
    }
    expect(oftenClock.sample().creditedSeconds).toBe(rareClock.sample().creditedSeconds);
  });

  it("reports nothing at all before it is started", () => {
    const clock = new GameClock(fakeClocks().providers);
    const sample = clock.sample();
    expect(sample.creditedSeconds).toBe(0);
    expect(sample.anomaly).toBe(Anomaly.NONE);
  });

  it("survives a reload by falling back to wall time", () => {
    const START = 1_700_000_000;
    const c = fakeClocks(START);
    const clock = new GameClock(c.providers);
    clock.start();
    c.advance(300);
    const persisted = clock.toDict();

    // The tab is closed for an hour. Wall time keeps running in the real world;
    // monotonic history is gone and restarts from an unrelated origin.
    const after = fakeClocks(START + 300 + 3600);
    const restored = GameClock.fromDict(persisted, after.providers);
    after.advance(120);

    // Wall time is all there is, so the WHOLE span counts - including the hour
    // the tab was shut, because nothing here can know whether the machine was
    // awake for it. That is deliberate and it is why the recovered path is not
    // trusted on its own: SessionCredit.settleRecovered caps the result at the
    // intended duration, and the player is asked before any of it is applied.
    expect(restored.sample().creditedSeconds).toBeCloseTo(4020, 6);
  });

  it("credits nothing rather than negative time if the books disagree", () => {
    const c = fakeClocks();
    const clock = new GameClock(c.providers);
    clock.start();
    clock.pause();
    // Monotonic runs backwards only if a provider lies; the guard exists so a
    // bookkeeping impossibility preserves the session instead of poisoning totals.
    c.advance(-100);
    const sample = clock.sample();
    expect(sample.creditedSeconds).toBe(0);
    expect(sample.anomaly).toBe(Anomaly.NEGATIVE_DURATION);
  });

  it("ignores pause and resume called out of order", () => {
    const c = fakeClocks();
    const clock = new GameClock(c.providers);
    clock.start();
    clock.resume();
    expect(clock.state).toBe(ClockState.RUNNING);
    clock.pause();
    clock.pause();
    expect(clock.state).toBe(ClockState.PAUSED);
    c.advance(10);
    clock.resume();
    expect(clock.sample().pausedSeconds).toBe(10);
  });
});
