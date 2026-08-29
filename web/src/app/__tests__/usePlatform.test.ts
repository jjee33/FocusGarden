// @vitest-environment jsdom
/**
 * Theme resolution across all THREE states.
 *
 * Two is the usual mistake. The third - "system", where nothing is stamped on the
 * root and only prefers-color-scheme decides - is the one most viewers are in,
 * and it is the state where a colour defined solely inside a media block or a
 * [data-theme] block silently fails to apply.
 */

import { act, renderHook } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { useIsCompact, useReducedMotion, useTheme } from "../usePlatform.js";

/** jsdom ships no matchMedia, so the queries the hooks rely on are stubbed. */
function stubMatchMedia(matches: Record<string, boolean>) {
  const listeners = new Map<string, Set<(e: MediaQueryListEvent) => void>>();
  vi.stubGlobal("matchMedia", (query: string) => ({
    matches: matches[query] ?? false,
    media: query,
    addEventListener: (_: string, fn: (e: MediaQueryListEvent) => void) => {
      if (!listeners.has(query)) listeners.set(query, new Set());
      listeners.get(query)!.add(fn);
    },
    removeEventListener: (_: string, fn: (e: MediaQueryListEvent) => void) => {
      listeners.get(query)?.delete(fn);
    },
  }));
  return {
    /** Simulate the OS flipping, the way a viewer changing their setting would. */
    change(query: string, value: boolean) {
      matches[query] = value;
      for (const fn of listeners.get(query) ?? []) {
        fn({ matches: value } as MediaQueryListEvent);
      }
    },
  };
}

const DARK = "(prefers-color-scheme: dark)";
const REDUCED = "(prefers-reduced-motion: reduce)";

beforeEach(() => {
  localStorage.clear();
  document.documentElement.removeAttribute("data-theme");
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("useTheme", () => {
  it("stamps nothing in the system state and follows the OS", () => {
    stubMatchMedia({ [DARK]: true });
    const { result } = renderHook(() => useTheme());

    expect(result.current.choice).toBe("system");
    expect(result.current.resolved).toBe("dark");
    // The absence of the stamp IS the system state. Writing data-theme="dark"
    // here would freeze the page against a viewer who later changes their OS.
    expect(document.documentElement.hasAttribute("data-theme")).toBe(false);
  });

  it("follows the OS live when it changes underneath", () => {
    const media = stubMatchMedia({ [DARK]: false });
    const { result } = renderHook(() => useTheme());
    expect(result.current.resolved).toBe("light");

    act(() => media.change(DARK, true));
    expect(result.current.resolved).toBe("dark");
  });

  it("lets an explicit choice beat the OS in BOTH directions", () => {
    stubMatchMedia({ [DARK]: true });
    const { result } = renderHook(() => useTheme());

    act(() => result.current.setChoice("light"));
    expect(result.current.resolved).toBe("light");
    expect(document.documentElement.getAttribute("data-theme")).toBe("light");

    act(() => result.current.setChoice("dark"));
    expect(document.documentElement.getAttribute("data-theme")).toBe("dark");
  });

  it("returns to the system state and removes the stamp", () => {
    stubMatchMedia({ [DARK]: false });
    const { result } = renderHook(() => useTheme());

    act(() => result.current.setChoice("dark"));
    expect(document.documentElement.getAttribute("data-theme")).toBe("dark");

    act(() => result.current.setChoice("system"));
    expect(document.documentElement.hasAttribute("data-theme")).toBe(false);
    expect(result.current.resolved).toBe("light");
  });

  it("hands the renderer a number, not a class name", () => {
    // The plant renderer multiplies authored colours by this so a monstera sits
    // down into a dark scene rather than glowing out of it.
    stubMatchMedia({ [DARK]: true });
    const { result } = renderHook(() => useTheme());
    expect(result.current.foliageAmbient).toBe(0.82);

    act(() => result.current.setChoice("light"));
    expect(result.current.foliageAmbient).toBe(1);
  });

  it("remembers the choice, and survives storage being unavailable", () => {
    stubMatchMedia({ [DARK]: false });
    const first = renderHook(() => useTheme());
    act(() => first.result.current.setChoice("dark"));

    const second = renderHook(() => useTheme());
    expect(second.result.current.choice).toBe("dark");

    // A private window, cleared site data, or a browser set to block storage
    // throws here rather than returning null.
    const setItem = vi.spyOn(Storage.prototype, "setItem")
      .mockImplementation(() => { throw new Error("blocked"); });
    const third = renderHook(() => useTheme());
    expect(() => act(() => third.result.current.setChoice("light"))).not.toThrow();
    // The choice still applies for this session even though it could not persist.
    expect(third.result.current.resolved).toBe("light");
    setItem.mockRestore();
  });

  it("cycles from whatever is currently resolved", () => {
    stubMatchMedia({ [DARK]: true });
    const { result } = renderHook(() => useTheme());
    act(() => result.current.cycle());
    expect(result.current.resolved).toBe("light");
    act(() => result.current.cycle());
    expect(result.current.resolved).toBe("dark");
  });
});

describe("useReducedMotion", () => {
  it("reports the OS preference and tracks changes", () => {
    const media = stubMatchMedia({ [REDUCED]: false });
    const { result } = renderHook(() => useReducedMotion());
    expect(result.current).toBe(false);

    act(() => media.change(REDUCED, true));
    expect(result.current).toBe(true);
  });
});

describe("useIsCompact", () => {
  it("switches the nav rail for a tab bar below the breakpoint", () => {
    const media = stubMatchMedia({ "(max-width: 767px)": true });
    const { result } = renderHook(() => useIsCompact());
    expect(result.current).toBe(true);

    act(() => media.change("(max-width: 767px)", false));
    expect(result.current).toBe(false);
  });
});
