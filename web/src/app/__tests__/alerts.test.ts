/**
 * @vitest-environment jsdom
 *
 * These exist because every layer here fails quietly by design - a missing API,
 * a refused permission, a browser that throws on the Notification constructor.
 * Quiet failure is right at runtime and useless in a test suite, so this pins
 * both halves: that it does the thing when it can, and that it does not throw
 * when it cannot.
 */

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import {
  announceComplete, clearTitle, requestNotifyPermission, setTitleCountdown,
} from "../alerts.js";

const ON = { notifyFocusComplete: true, notifyBreakComplete: true, volumeTimer: 0 };

describe("setTitleCountdown", () => {
  afterEach(() => { clearTitle(); });

  it("puts a readable clock in front of the name", () => {
    setTitleCountdown(1122, true);
    expect(document.title).toBe("18:42 · Focusing · Focus Garden");
  });

  it("pads the seconds, because 18:4 is not a time", () => {
    setTitleCountdown(1084, true);
    expect(document.title).toBe("18:04 · Focusing · Focus Garden");
  });

  it("rounds up, so the last second is shown as 0:01 and not 0:00", () => {
    setTitleCountdown(0.4, true);
    expect(document.title).toBe("0:01 · Focusing · Focus Garden");
  });

  it("never shows a negative clock if the timer overshoots", () => {
    setTitleCountdown(-30, true);
    expect(document.title).toBe("0:00 · Focusing · Focus Garden");
  });

  it("says which kind of block is running", () => {
    setTitleCountdown(300, false);
    expect(document.title).toBe("5:00 · Break · Focus Garden");
  });

  it("restores the plain name when nothing is running", () => {
    setTitleCountdown(300, true);
    clearTitle();
    expect(document.title).toBe("Focus Garden");
  });
});

describe("requestNotifyPermission", () => {
  afterEach(() => {
    Reflect.deleteProperty(globalThis, "Notification");
    vi.restoreAllMocks();
  });

  it("does nothing at all where the API does not exist", async () => {
    Reflect.deleteProperty(globalThis, "Notification");
    await expect(requestNotifyPermission()).resolves.toBeUndefined();
  });

  it("asks once, when the answer has not been given yet", async () => {
    const ask = vi.fn().mockResolvedValue("granted");
    vi.stubGlobal("Notification", { permission: "default", requestPermission: ask });
    await requestNotifyPermission();
    expect(ask).toHaveBeenCalledTimes(1);
  });

  it("does not re-ask someone who already said no", async () => {
    const ask = vi.fn();
    vi.stubGlobal("Notification", { permission: "denied", requestPermission: ask });
    await requestNotifyPermission();
    expect(ask).not.toHaveBeenCalled();
  });

  it("swallows a browser that throws instead of returning a promise", async () => {
    vi.stubGlobal("Notification", {
      permission: "default",
      requestPermission: () => { throw new Error("not allowed here"); },
    });
    await expect(requestNotifyPermission()).resolves.toBeUndefined();
  });
});

describe("announceComplete", () => {
  let made: { title: string; body: string }[] = [];

  beforeEach(() => {
    made = [];
    class FakeNotification {
      static permission = "granted";
      constructor(title: string, opts: { body?: string }) {
        made.push({ title, body: opts.body ?? "" });
      }
    }
    vi.stubGlobal("Notification", FakeNotification);
  });
  afterEach(() => { vi.unstubAllGlobals(); vi.restoreAllMocks(); });

  it("announces a finished focus session", () => {
    announceComplete(true, 25, ON);
    expect(made).toHaveLength(1);
    expect(made[0]!.title).toBe("Session complete");
    expect(made[0]!.body).toContain("25 minutes");
  });

  it("gets the singular right, because '1 minutes' looks broken", () => {
    announceComplete(true, 1, ON);
    expect(made[0]!.body).toContain("1 minute of focus");
  });

  it("says something different when a break ends", () => {
    announceComplete(false, 5, ON);
    expect(made[0]!.title).toBe("Break over");
  });

  it("respects the setting that turns focus alerts off", () => {
    announceComplete(true, 25, { ...ON, notifyFocusComplete: false });
    expect(made).toHaveLength(0);
  });

  it("respects the break setting independently of the focus one", () => {
    announceComplete(false, 5, { ...ON, notifyBreakComplete: false });
    expect(made).toHaveLength(0);
    announceComplete(true, 25, { ...ON, notifyBreakComplete: false });
    expect(made).toHaveLength(1);
  });

  it("stays silent when permission was never granted", () => {
    vi.stubGlobal("Notification", { permission: "default" });
    expect(() => announceComplete(true, 25, ON)).not.toThrow();
  });

  it("does not throw where the constructor itself is hostile", () => {
    vi.stubGlobal("Notification", class {
      static permission = "granted";
      constructor() { throw new Error("service worker registration required"); }
    });
    expect(() => announceComplete(true, 25, ON)).not.toThrow();
  });

  it("does not throw with no audio support, which is the common mobile case", () => {
    vi.stubGlobal("AudioContext", undefined);
    expect(() => announceComplete(true, 25, { ...ON, volumeTimer: 0.8 })).not.toThrow();
  });
});
