/**
 * Surviving an interrupted session.
 *
 * On the desktop the interruption is a crash. In a browser it is a closed tab, a
 * reload, or a phone reclaiming memory from a backgrounded page - which makes
 * this more important here, not less. Without it, closing the tab twenty minutes
 * in silently throws that time away.
 */

import { describe, expect, it } from "vitest";

import { buildInFlight, hasInFlight, recoverInFlight, INTERRUPTION_REASON } from "../in-flight.js";
import { GameClock } from "../game-clock.js";
import { Anomaly, Completion, Kind, makeFocusSession } from "../focus-session.js";
import type { Json } from "../dict-util.js";

const START = 1_700_000_000;

/** Both clocks from one fake, so they cannot drift into a false anomaly. */
function clocks(startWall = START) {
  const state = { mono: 1000, wall: startWall };
  return {
    providers: { monotonic: () => state.mono, wall: () => state.wall },
    advance(seconds: number) {
      state.mono += seconds;
      state.wall += seconds;
    },
  };
}

function runningSession(intendedMinutes = 25) {
  return makeFocusSession({
    id: "s_running",
    kind: Kind.FOCUS,
    intendedDurationMinutes: intendedMinutes,
    startedAtUtc: START,
    dateKey: "2026-08-29",
    plantUid: "pl_1",
    projectId: "p_1",
  });
}

describe("buildInFlight", () => {
  it("stores the session and the clock's wall anchor", () => {
    const c = clocks();
    const clock = new GameClock(c.providers);
    clock.start();
    const stored = buildInFlight(runningSession(), clock);

    expect(hasInFlight(stored)).toBe(true);
    expect((stored["session"] as Json)["id"]).toBe("s_running");
    // Only wall time is stored: a monotonic value is meaningless across a reload.
    expect((stored["clock"] as Json)["wall_start"]).toBe(START);
  });
});

describe("recoverInFlight", () => {
  it("returns null when there is nothing stored", () => {
    expect(recoverInFlight({})).toBeNull();
    expect(hasInFlight({})).toBe(false);
  });

  it("returns null for a record with no id", () => {
    expect(recoverInFlight({ session: { id: "" }, clock: {} })).toBeNull();
  });

  it("never offers back a session whose awards already landed", () => {
    // Otherwise a reload after a completed session would credit it a second time.
    const stored = { session: { id: "s_1", awards_applied: true }, clock: { wall_start: START } };
    expect(recoverInFlight(stored)).toBeNull();
  });

  it("credits the wall time the tab was away, capped at the intended duration", () => {
    const c = clocks();
    const clock = new GameClock(c.providers);
    clock.start();
    c.advance(600);
    const stored = buildInFlight(runningSession(25), clock);

    // The tab is gone for an hour and comes back.
    const after = clocks(START + 600 + 3600);
    const recovered = recoverInFlight(stored, START + 4200, after.providers)!;

    expect(recovered).not.toBeNull();
    expect(recovered.completion).toBe(Completion.ABANDONED);
    expect(recovered.interruptionReason).toBe(INTERRUPTION_REASON);
    // Wall time says 70 minutes elapsed. The cap says 25, because the tab may
    // have been shut for days and a three-day "focus session" is not three days
    // of focus.
    expect(recovered.actualFocusMinutes).toBe(25);
    expect(recovered.endedAtUtc).toBe(START + 4200);
  });

  it("credits the real figure when it is under the cap", () => {
    const c = clocks();
    const clock = new GameClock(c.providers);
    clock.start();
    c.advance(300);
    const stored = buildInFlight(runningSession(25), clock);

    const after = clocks(START + 300);
    const recovered = recoverInFlight(stored, START + 300, after.providers)!;
    expect(recovered.actualFocusMinutes).toBeCloseTo(5, 6);
  });

  it("carries the paused time across the interruption", () => {
    const c = clocks();
    const clock = new GameClock(c.providers);
    clock.start();
    c.advance(120);
    clock.pause();
    c.advance(180);
    clock.resume();
    c.advance(60);
    const stored = buildInFlight(runningSession(25), clock);

    const after = clocks(START + 360);
    const recovered = recoverInFlight(stored, START + 360, after.providers)!;
    expect(recovered.pausedMinutes).toBeCloseTo(3, 6);
  });

  it("keeps the record and flags it rather than discarding an anomalous one", () => {
    // A recovered session is measured from wall time alone, which is exactly the
    // clock that can jump. It is kept and flagged, never dropped.
    const c = clocks();
    const clock = new GameClock(c.providers);
    clock.start();
    const stored = buildInFlight(runningSession(25), clock);

    const after = clocks(START);
    const recovered = recoverInFlight(stored, START, after.providers)!;
    expect(recovered).not.toBeNull();
    expect(Object.values(Anomaly)).toContain(recovered.anomaly);
  });

  it("preserves everything the session was about", () => {
    const c = clocks();
    const clock = new GameClock(c.providers);
    clock.start();
    c.advance(60);
    const stored = buildInFlight(runningSession(25), clock);

    const after = clocks(START + 60);
    const recovered = recoverInFlight(stored, START + 60, after.providers)!;
    expect(recovered.id).toBe("s_running");
    expect(recovered.plantUid).toBe("pl_1");
    expect(recovered.projectId).toBe("p_1");
    expect(recovered.dateKey).toBe("2026-08-29");
    expect(recovered.intendedDurationMinutes).toBe(25);
    // Crucially NOT applied: only the player knows whether they were focusing
    // while the tab was shut, so the UI asks before any of this is credited.
    expect(recovered.awardsApplied).toBe(false);
  });
});
