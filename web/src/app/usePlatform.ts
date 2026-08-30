/**
 * Theme and motion policy, read once and shared.
 *
 * Both mirror ui/theme/palette.gd and ui/theme/motion.gd rather than inventing
 * new behaviour. The renderer needs the resolved theme as a NUMBER
 * (`foliage_ambient`), not a class name, because it multiplies authored plant
 * colours so they sit down into a dark scene instead of glowing out of it.
 */

import { useCallback, useEffect, useState } from "react";

export type ThemeChoice = "system" | "light" | "dark";
export type ResolvedTheme = "light" | "dark";

const STORAGE_KEY = "fg.theme";

function readStoredChoice(): ThemeChoice {
  // A private window, cleared site data, or a browser set to block storage all
  // throw here rather than returning null, so this cannot be a bare read.
  try {
    const stored = localStorage.getItem(STORAGE_KEY);
    if (stored === "light" || stored === "dark" || stored === "system") return stored;
  } catch {
    /* storage unavailable; the system default is a fine answer */
  }
  return "system";
}

export function useTheme(): {
  choice: ThemeChoice;
  resolved: ResolvedTheme;
  foliageAmbient: number;
  setChoice: (next: ThemeChoice) => void;
  cycle: () => void;
} {
  const [choice, setChoiceState] = useState<ThemeChoice>(readStoredChoice);
  const [systemDark, setSystemDark] = useState(
    () => typeof matchMedia === "function" && matchMedia("(prefers-color-scheme: dark)").matches,
  );

  useEffect(() => {
    const query = matchMedia("(prefers-color-scheme: dark)");
    const onChange = (event: MediaQueryListEvent): void => setSystemDark(event.matches);
    query.addEventListener("change", onChange);
    return () => query.removeEventListener("change", onChange);
  }, []);

  const resolved: ResolvedTheme = choice === "system" ? (systemDark ? "dark" : "light") : choice;

  useEffect(() => {
    const root = document.documentElement;
    // "system" removes the stamp entirely, so prefers-color-scheme decides. Any
    // other value stamps, which is what lets the toggle beat the OS both ways.
    if (choice === "system") root.removeAttribute("data-theme");
    else root.setAttribute("data-theme", choice);
  }, [choice]);

  const setChoice = useCallback((next: ThemeChoice) => {
    setChoiceState(next);
    try {
      localStorage.setItem(STORAGE_KEY, next);
    } catch {
      /* the choice still applies for this session */
    }
  }, []);

  const cycle = useCallback(() => {
    setChoice(resolved === "dark" ? "light" : "dark");
  }, [resolved, setChoice]);

  return {
    choice,
    resolved,
    foliageAmbient: resolved === "dark" ? 0.82 : 1,
    setChoice,
    cycle,
  };
}

/**
 * True when animation should be skipped ENTIRELY rather than shortened.
 *
 * Port of Motion.is_reduced. The distinction matters: a fade can be run at zero
 * duration and still land on its end state, but a looping idle sway has no end
 * state to land on and has to be switched off.
 */
export function useReducedMotion(): boolean {
  const [reduced, setReduced] = useState(
    () => typeof matchMedia === "function" && matchMedia("(prefers-reduced-motion: reduce)").matches,
  );
  useEffect(() => {
    const query = matchMedia("(prefers-reduced-motion: reduce)");
    const onChange = (event: MediaQueryListEvent): void => setReduced(event.matches);
    query.addEventListener("change", onChange);
    return () => query.removeEventListener("change", onChange);
  }, []);
  return reduced;
}

/** Coarse breakpoint. The nav rail becomes a tab bar below this. */
export function useIsCompact(breakpoint = 768): boolean {
  const [compact, setCompact] = useState(
    () => typeof matchMedia === "function" && matchMedia(`(max-width: ${breakpoint - 1}px)`).matches,
  );
  useEffect(() => {
    const query = matchMedia(`(max-width: ${breakpoint - 1}px)`);
    // Re-read on mount as well as subscribing. The initialiser runs during the
    // first render, and a viewport that changes between then and here - a phone
    // rotated while the bundle loads, a window resized mid-load - would leave a
    // value that is wrong until the next change event, which may never come.
    setCompact(query.matches);
    const onChange = (event: MediaQueryListEvent): void => setCompact(event.matches);
    query.addEventListener("change", onChange);
    return () => query.removeEventListener("change", onChange);
  }, [breakpoint]);
  return compact;
}
