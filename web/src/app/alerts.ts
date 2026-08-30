/**
 * Telling the person their session ended.
 *
 * `notifyFocusComplete` and `notifyBreakComplete` have been in the settings model
 * since the port, promising something nothing delivered: the web app ended a
 * session in complete silence. For a timer whose entire premise is "go and do
 * your work", that means watching the countdown - which is the one thing it
 * exists to stop you doing.
 *
 * THREE LAYERS, WEAKEST DEPENDENCY FIRST. The title always works and needs no
 * permission. The chime needs a prior user gesture, which starting a session
 * supplies. The notification needs permission that may never be granted. Each
 * layer is useful on its own, and none of them assumes the one above it worked.
 */

/** Restored when nothing is running, so the tab does not keep a stale countdown. */
const IDLE_TITLE = "Focus Garden";

/**
 * The countdown in the tab title.
 *
 * This is the part that matters most and costs least. A backgrounded tab showing
 * "18:42 · Focus Garden" is the whole feature for anyone who never grants a
 * permission, and there is no browser where it fails.
 */
export function setTitleCountdown(remainingSeconds: number, focusing: boolean): void {
  const total = Math.max(0, Math.ceil(remainingSeconds));
  const mm = Math.floor(total / 60);
  const ss = total % 60;
  const clock = `${mm}:${String(ss).padStart(2, "0")}`;
  document.title = `${clock} · ${focusing ? "Focusing" : "Break"} · ${IDLE_TITLE}`;
}

export function clearTitle(): void {
  document.title = IDLE_TITLE;
}

/**
 * Ask only when the answer is about to be useful.
 *
 * Called as a session starts, never on page load. Someone who has just committed
 * to twenty-five minutes away from the screen has a reason to be asked whether
 * they want telling when it is over; someone who has just opened the page does
 * not, and a prompt at that moment gets dismissed forever out of reflex.
 *
 * Returns quietly if the API is missing, if permission was already decided, or
 * if the browser refuses - none of which is a failure worth surfacing.
 */
export async function requestNotifyPermission(): Promise<void> {
  try {
    if (typeof Notification === "undefined") return;
    if (Notification.permission !== "default") return;
    await Notification.requestPermission();
  } catch {
    // Some browsers throw on the promise form in insecure or embedded contexts.
  }
}

export interface AlertSettings {
  notifyFocusComplete: boolean;
  notifyBreakComplete: boolean;
  /** 0..1. The existing timer volume setting; 0 means the chime is off. */
  volumeTimer: number;
}

/**
 * A short two-note chime, synthesised rather than shipped.
 *
 * An audio file would be another asset to load, cache, and get wrong on the one
 * browser that wants a different container. Two sine tones through an envelope
 * is a few lines, weighs nothing, and cannot 404. It is deliberately soft and
 * short: this is a plant shop, not an alarm clock.
 */
function chime(volume: number): void {
  if (volume <= 0) return;
  try {
    const Ctor = window.AudioContext
      ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (Ctor === undefined) return;
    const ctx = new Ctor();
    const now = ctx.currentTime;

    // A fifth, low and warm. Rising, because the session finishing is good news.
    for (const [freq, at] of [[587.33, 0], [880.0, 0.16]] as const) {
      const osc = ctx.createOscillator();
      const gain = ctx.createGain();
      osc.type = "sine";
      osc.frequency.value = freq;
      // Ramped, never switched: a gain that jumps to full is a click, and a
      // click is the least calm sound a computer can make.
      gain.gain.setValueAtTime(0.0001, now + at);
      gain.gain.exponentialRampToValueAtTime(0.22 * volume, now + at + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.0001, now + at + 0.55);
      osc.connect(gain).connect(ctx.destination);
      osc.start(now + at);
      osc.stop(now + at + 0.6);
    }
    // Released once the sound is done; an AudioContext per session would
    // otherwise accumulate until the browser refuses to make another.
    window.setTimeout(() => void ctx.close().catch(() => {}), 1200);
  } catch {
    // Audio is the least important layer here. Never let it break a completion.
  }
}

/**
 * Announce a finished session: chime, then notification.
 *
 * Both are best-effort and independently guarded, because this runs at the exact
 * moment a session is being credited and nothing here is worth losing a session
 * over.
 */
export function announceComplete(
  focusing: boolean, minutes: number, settings: AlertSettings,
): void {
  const wanted = focusing ? settings.notifyFocusComplete : settings.notifyBreakComplete;
  if (!wanted) return;

  chime(settings.volumeTimer);

  try {
    if (typeof Notification === "undefined" || Notification.permission !== "granted") return;
    const whole = Math.max(0, Math.round(minutes));
    new Notification(focusing ? "Session complete" : "Break over", {
      body: focusing
        ? `${whole} ${whole === 1 ? "minute" : "minutes"} of focus, grown into your garden.`
        : "Ready when you are.",
      icon: "/icon.svg",
      badge: "/icon.svg",
      // Replaces rather than stacks: nobody wants six of these after a long day.
      tag: "focus-garden-session",
    });
  } catch {
    // Notification constructors throw on some mobile browsers that expose the
    // API but only support it through a service worker registration.
  }
}
