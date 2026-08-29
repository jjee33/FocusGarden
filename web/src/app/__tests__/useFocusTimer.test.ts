// @vitest-environment jsdom
/**
 * The timer hook's lifecycle.
 *
 * Written after an audit found that every defect in the first cut of this app
 * lived in src/app/ - the one layer with no tests. The domain had 62. This layer
 * had none, and that is not a coincidence.
 *
 * The clock itself is already covered against injected time sources in
 * domain/__tests__/game-clock.test.ts. What is tested here is only what the hook
 * adds on top: the lifecycle, and whether a finish can fire twice.
 */

import { act, renderHook } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { useFocusTimer } from "../useFocusTimer.js";
import { Completion, Kind } from "../../domain/focus-session.js";

/**
 * Both clocks driven from one fake, because the hook reads `performance.now`
 * and `Date.now` and the two must not drift apart in a test - a divergence over
 * five seconds would be reported as a SUSPEND anomaly.
 */
function useFakeClocks() {
  let millis = 1_700_000_000_000;
  vi.spyOn(Date, "now").mockImplementation(() => millis);
  vi.spyOn(performance, "now").mockImplementation(() => millis - 1_700_000_000_000);
  return {
    advance(seconds: number) {
      millis += seconds * 1000;
      vi.advanceTimersByTime(seconds * 1000);
    },
  };
}

beforeEach(() => {
  vi.useFakeTimers();
});

afterEach(() => {
  vi.useRealTimers();
  vi.restoreAllMocks();
});

describe("useFocusTimer", () => {
  it("starts idle and reports nothing", () => {
    const { result } = renderHook(() => useFocusTimer({ onFinished: () => {} }));
    expect(result.current.snapshot.state).toBe("idle");
    expect(result.current.snapshot.remainingSeconds).toBe(0);
  });

  it("counts down from the intended duration", () => {
    const clocks = useFakeClocks();
    const { result } = renderHook(() => useFocusTimer({ onFinished: () => {} }));

    act(() => result.current.start(Kind.FOCUS, 25));
    expect(result.current.snapshot.state).toBe("running");
    expect(result.current.snapshot.remainingSeconds).toBe(1500);

    act(() => clocks.advance(60));
    expect(result.current.snapshot.remainingSeconds).toBe(1440);
    expect(result.current.snapshot.elapsedMinutes).toBeCloseTo(1, 6);
    expect(result.current.snapshot.ratio).toBeCloseTo(60 / 1500, 6);
  });

  it("holds while paused and resumes without crediting the gap", () => {
    const clocks = useFakeClocks();
    const { result } = renderHook(() => useFocusTimer({ onFinished: () => {} }));

    act(() => result.current.start(Kind.FOCUS, 25));
    act(() => clocks.advance(120));
    act(() => result.current.pause());
    act(() => clocks.advance(300));

    expect(result.current.snapshot.state).toBe("paused");
    expect(result.current.snapshot.remainingSeconds).toBe(1380);
    expect(result.current.snapshot.pausedMinutes).toBeCloseTo(5, 6);

    act(() => result.current.resume());
    act(() => clocks.advance(60));
    expect(result.current.snapshot.remainingSeconds).toBe(1320);
  });

  it("completes itself at the intended duration and reports COMPLETED", () => {
    const clocks = useFakeClocks();
    const finished = vi.fn();
    const { result } = renderHook(() => useFocusTimer({ onFinished: finished }));

    act(() => result.current.start(Kind.FOCUS, 1));
    act(() => clocks.advance(61));

    expect(finished).toHaveBeenCalledTimes(1);
    expect(finished.mock.calls[0]![0]).toMatchObject({
      kind: Kind.FOCUS, intendedDurationMinutes: 1, completion: Completion.COMPLETED,
    });
    // Already settled by the time it leaves the timer: a completed session is
    // worth its intended duration exactly, never the tick it overshot by.
    expect(finished.mock.calls[0]![0].actualFocusMinutes).toBe(1);
    expect(result.current.snapshot.state).toBe("idle");
  });

  it("fires the finish exactly once even as ticks keep arriving past the line", () => {
    // The guard that actually protects against a double award. A burst of ticks
    // past the finish line, or a visibilitychange repaint landing on an already
    // finished session, must not settle it twice.
    const clocks = useFakeClocks();
    const finished = vi.fn();
    const { result } = renderHook(() => useFocusTimer({ onFinished: finished }));

    act(() => result.current.start(Kind.FOCUS, 1));
    act(() => clocks.advance(90));
    act(() => clocks.advance(90));
    act(() => clocks.advance(90));

    expect(finished).toHaveBeenCalledTimes(1);
  });

  it("credits the time actually focused when ended early", () => {
    const clocks = useFakeClocks();
    const finished = vi.fn();
    const { result } = renderHook(() => useFocusTimer({ onFinished: finished }));

    act(() => result.current.start(Kind.FOCUS, 25));
    act(() => clocks.advance(600));
    act(() => result.current.endEarly());

    expect(finished).toHaveBeenCalledTimes(1);
    const call = finished.mock.calls[0]![0];
    expect(call.completion).toBe(Completion.ENDED_EARLY);
    expect(call.actualFocusMinutes).toBeCloseTo(10, 6);
  });

  it("settles a discarded session to nothing, via SessionCredit", () => {
    const clocks = useFakeClocks();
    const finished = vi.fn();
    const { result } = renderHook(() => useFocusTimer({ onFinished: finished }));

    act(() => result.current.start(Kind.FOCUS, 25));
    act(() => clocks.advance(300));
    act(() => result.current.cancel());

    const call = finished.mock.calls[0]![0];
    expect(call.completion).toBe(Completion.CANCELLED);
    // Settled to zero: SessionCredit is the one place that decides a discarded
    // session earns nothing, and the timer defers to it rather than duplicating it.
    expect(call.actualFocusMinutes).toBe(0);
  });

  it("ignores a second finish after the clock has stopped", () => {
    const clocks = useFakeClocks();
    const finished = vi.fn();
    const { result } = renderHook(() => useFocusTimer({ onFinished: finished }));

    act(() => result.current.start(Kind.FOCUS, 25));
    act(() => clocks.advance(60));
    act(() => result.current.endEarly());
    act(() => result.current.endEarly());
    act(() => result.current.cancel());

    expect(finished).toHaveBeenCalledTimes(1);
  });

  it("is unaffected by how often the tick fires", () => {
    // The property that survives background-tab throttling. A tab that got one
    // tick in ten minutes and one that got 2,400 must agree on the remainder.
    const rare = (() => {
      const clocks = useFakeClocks();
      const { result } = renderHook(() => useFocusTimer({ onFinished: () => {} }));
      act(() => result.current.start(Kind.FOCUS, 25));
      act(() => clocks.advance(600));
      return result.current.snapshot.remainingSeconds;
    })();
    vi.restoreAllMocks();

    const often = (() => {
      const clocks = useFakeClocks();
      const { result } = renderHook(() => useFocusTimer({ onFinished: () => {} }));
      act(() => result.current.start(Kind.FOCUS, 25));
      for (let i = 0; i < 600; i++) act(() => clocks.advance(1));
      return result.current.snapshot.remainingSeconds;
    })();

    expect(often).toBe(rare);
  });
});
