// @vitest-environment jsdom
/**
 * A session outlives the screen it was started on.
 *
 * Every screen in the shell unmounts when another tab is chosen. The timer used
 * to live inside FocusScreen, so opening the garden mid-session destroyed the
 * clock: the session stopped counting, never finished, and was never credited.
 * These render the real shell, because the defect lived in the wiring between
 * the shell and a screen - not in either half on its own.
 */

import "fake-indexeddb/auto";
import { IDBFactory } from "fake-indexeddb";
import { act, cleanup, fireEvent, render, screen, waitFor, within } from "@testing-library/react";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// Signed out, and settled: the shell renders the local-only app straight away.
vi.mock("../auth-client.js", () => ({
  useSession: () => ({ data: null, isPending: false }),
  signIn: {}, signUp: {}, signOut: async () => {},
  readableAuthError: (m: string | undefined) => m ?? "",
  resendVerification: async () => ({ ok: true }),
}));

import { App } from "../App.js";

const EPOCH_MS = 1_700_000_000_000;
let millis = EPOCH_MS;

function advance(seconds: number): void {
  millis += seconds * 1000;
  act(() => { vi.advanceTimersByTime(seconds * 1000); });
}

beforeEach(() => {
  globalThis.indexedDB = new IDBFactory();
  millis = EPOCH_MS;
  // Both clocks from one source, so they cannot drift into a false anomaly.
  vi.spyOn(Date, "now").mockImplementation(() => millis);
  vi.spyOn(performance, "now").mockImplementation(() => millis - EPOCH_MS);
  // Only the tick is faked. IndexedDB and waitFor keep their real timers.
  vi.useFakeTimers({ toFake: ["setInterval", "clearInterval"] });
  vi.stubGlobal("matchMedia", (query: string) => ({
    matches: false, media: query,
    addEventListener: () => {}, removeEventListener: () => {},
  }));
  localStorage.setItem("fg.localOnly", "1");
  // The demo garden is already onboarded, so the shell goes straight to Focus.
  window.history.replaceState(null, "", "/?demo=1");
});

afterEach(() => {
  cleanup();
  vi.useRealTimers();
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
  localStorage.clear();
  window.history.replaceState(null, "", "/");
});

async function openApp() {
  render(<App />);
  await waitFor(() => expect(screen.getByRole("button", { name: "Start focusing" })).toBeTruthy());
}

function nav(name: RegExp) {
  const rail = screen.getAllByRole("navigation", { name: "Sections" })[0]!;
  return within(rail).getByRole("button", { name });
}

function lifetimeFocus(): string {
  const tile = screen.getByText("Lifetime focus").closest(".tile")!;
  return tile.querySelector("b")!.textContent ?? "";
}

describe("the shell's timer", () => {
  it("keeps counting while another screen is open", async () => {
    await openApp();
    fireEvent.click(screen.getByRole("button", { name: "25m" }));
    fireEvent.click(screen.getByRole("button", { name: "Start focusing" }));
    advance(60);

    fireEvent.click(nav(/^Garden/));
    expect(screen.queryByRole("button", { name: "Pause" })).toBeNull();
    advance(120);

    fireEvent.click(nav(/^Focus/));
    // Three minutes in, not a fresh idle timer.
    expect(screen.getByRole("button", { name: "Pause" })).toBeTruthy();
    expect(screen.getByText("22:00")).toBeTruthy();
  });

  it("finishes and credits a session that ended while elsewhere", async () => {
    await openApp();
    const before = lifetimeFocus();
    fireEvent.click(screen.getByRole("button", { name: "15m" }));
    fireEvent.click(screen.getByRole("button", { name: "Start focusing" }));

    fireEvent.click(nav(/^Statistics/));
    advance(15 * 60 + 1);

    fireEvent.click(nav(/^Focus/));
    expect(screen.getByRole("button", { name: "Start focusing" })).toBeTruthy();
    expect(lifetimeFocus()).not.toBe(before);
  });

  it("marks the Focus entry while a session runs elsewhere", async () => {
    await openApp();
    expect(nav(/^Focus/).hasAttribute("data-running")).toBe(false);
    fireEvent.click(screen.getByRole("button", { name: "Start focusing" }));
    fireEvent.click(nav(/^Garden/));
    expect(nav(/^Focus/).hasAttribute("data-running")).toBe(true);
    expect(nav(/^Focus/).textContent).toContain("session in progress");
  });
});

describe("the focus screen reads the player's settings", () => {
  function setSlider(label: string, value: number): void {
    fireEvent.click(nav(/^Settings/));
    fireEvent.change(screen.getByLabelText(label), { target: { value: String(value) } });
    fireEvent.click(nav(/^Focus/));
  }

  it("counts the cycle against the configured length, not a fixed four", async () => {
    await openApp();
    setSlider("Sessions before a long break", 6);
    fireEvent.click(screen.getByRole("button", { name: "Start focusing" }));
    expect(screen.getByText(/^Session \d of 6 ·/)).toBeTruthy();
  });

  it("starts at the configured focus length and offers it as a choice", async () => {
    await openApp();
    setSlider("Focus session", 30);
    expect(screen.getByRole("button", { name: "30m" }).getAttribute("aria-pressed")).toBe("true");
    expect(screen.getByText("30:00")).toBeTruthy();
  });

  it("remembers a picked preset as the new default", async () => {
    await openApp();
    fireEvent.click(screen.getByRole("button", { name: "45m" }));
    fireEvent.click(nav(/^Settings/));
    expect((screen.getByLabelText("Focus session") as HTMLInputElement).value).toBe("45");
  });
});
