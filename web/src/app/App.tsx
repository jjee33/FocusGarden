/**
 * The shell: the launch screens, the nav that carries them, and first run.
 *
 * Catalogue, Journal and Achievements are deliberately absent. Their domain
 * logic is ported and tested; only the screens are deferred, so shipping them
 * later is UI work and nothing else.
 */

import { useEffect, useState } from "react";

import "./theme.css";
import "./app.css";
import { FocusScreen } from "./screens/FocusScreen.js";
import { GardenScreen } from "./screens/GardenScreen.js";
import { ShelfScreen } from "./screens/ShelfScreen.js";
import { StatisticsScreen } from "./screens/StatisticsScreen.js";
import { SettingsScreen } from "./screens/SettingsScreen.js";
import { OnboardingScreen } from "./screens/OnboardingScreen.js";
import { AuthScreen } from "./screens/AuthScreen.js";
import { ResetLinkExpiredScreen, ResetPasswordScreen } from "./screens/ResetPasswordScreen.js";
import { useSession } from "./auth-client.js";
import { useSync } from "./useSync.js";
import { useGarden } from "./useGarden.js";
import { useTheme } from "./usePlatform.js";

type ScreenId = "focus" | "garden" | "shelf" | "stats" | "settings";

/** The four that fit a tab bar. Settings lives behind the last one on mobile. */
const SCREENS: { id: ScreenId; label: string; short: string }[] = [
  { id: "focus", label: "Focus", short: "Focus" },
  { id: "garden", label: "Garden", short: "Garden" },
  { id: "shelf", label: "Shelf", short: "Shelf" },
  { id: "stats", label: "Statistics", short: "Stats" },
  { id: "settings", label: "Settings", short: "More" },
];

/**
 * Remembers that someone chose to carry on without an account, so the offer is
 * made once rather than every time they open the app.
 */
const LOCAL_ONLY_KEY = "fg.localOnly";

function readLocalOnly(): boolean {
  try {
    return localStorage.getItem(LOCAL_ONLY_KEY) === "1";
  } catch {
    // Storage blocked. Offering the account again is the harmless failure here.
    return false;
  }
}

/**
 * The one URL this app reads.
 *
 * There is no router, and adding one to serve a single screen would be a
 * dependency and a refactor in exchange for nothing. better-auth sends people to
 * /reset?token=... once it has checked the link, so that is the only path worth
 * recognising; everything else is the app.
 */
interface ResetArrival {
  token: string;
  /** Set when better-auth rejected the link before we ever saw a token. */
  failed: boolean;
}

function resetFromUrl(): ResetArrival {
  try {
    const url = new URL(window.location.href);
    if (url.pathname !== "/reset") return { token: "", failed: false };
    // A spent or expired link comes back as ?error=INVALID_TOKEN with no token.
    // Reading only the token would drop those people into the app with no idea
    // why the thing they clicked did nothing.
    return {
      token: url.searchParams.get("token") ?? "",
      failed: url.searchParams.get("error") !== null,
    };
  } catch {
    return { token: "", failed: false };
  }
}

export function App() {
  // Read once, at mount. Re-deriving it on render would resurrect the screen
  // after it has been dismissed and the URL tidied up.
  const [reset, setReset] = useState(resetFromUrl);
  const [screen, setScreen] = useState<ScreenId>("focus");
  const [presetMinutes, setPresetMinutes] = useState(25);
  const [localOnly, setLocalOnly] = useState(readLocalOnly);
  const garden = useGarden();
  const theme = useTheme();
  const { data: authSession, isPending: authPending } = useSession();

  // Latched, not derived: once the first session check has resolved we stay
  // settled, however many times better-auth refetches afterwards.
  const [settledOnce, setSettledOnce] = useState(false);
  useEffect(() => {
    if (!authPending) setSettledOnce(true);
  }, [authPending]);

  // Sync is only ever attempted for a signed-in account with somewhere to store
  // the result. Signed out, the app is complete on its own - that is the whole
  // point of local-first, and it is why nothing below this line can break it.
  const sync = useSync({
    save: garden.save,
    sessions: garden.sessions,
    onMerged: garden.applyMerged,
    db: garden.db,
    userId: authSession?.user.id ?? null,
    enabled: garden.storage.ready && !garden.storage.blocked && !garden.storage.ephemeral,
  });

  // Signing in supersedes the earlier "not now": the offer should not reappear
  // on a device where an account is already in use.
  useEffect(() => {
    if (authSession !== null && localOnly) setLocalOnly(false);
  }, [authSession, localOnly]);

  /*
   * The reset screen comes before every other gate.
   *
   * Someone arriving on this link may be signed out, half onboarded, or signed
   * in as somebody else on a shared machine. None of that belongs between them
   * and the password they came to change - the token authorises this, not the
   * session.
   */
  if (reset.token !== "" || reset.failed) {
    const clear = (): void => {
      setReset({ token: "", failed: false });
      // The token is single-use and now spent; leaving it in the address bar
      // means a refresh reopens a screen that can only fail.
      window.history.replaceState(null, "", "/");
    };
    return reset.failed
      ? <ResetLinkExpiredScreen onDone={clear} />
      : <ResetPasswordScreen token={reset.token} onDone={clear} />;
  }

  // ONCE, on first load - never again, and the difference is a lost account.
  //
  // The intent below is right: flashing an empty garden and then filling it in
  // reads as data loss for the half-second it lasts, and flashing the sign-in
  // screen at someone already signed in is worse. The mistake was gating on
  // `authPending` forever.
  //
  // Signing up makes better-auth refetch the session. That flipped authPending
  // back to true, which swapped AuthScreen for this boot screen, which UNMOUNTED
  // it - destroying the "Check your email" state it had just set. What the person
  // saw was the form vanish and the start screen come back: identical to a silent
  // failure. So they try again, are told the address is already taken, and give
  // up on an account that exists and works. Reproduced on production, and there
  // is a real signup sitting unverified because of it.
  //
  // After the first settle the app has enough to render, and a background
  // session refresh must never take the UI away from someone mid-task.
  if (!settledOnce || !garden.storage.ready) {
    return (
      <div className="boot" role="status" aria-live="polite">
        <span className="visually-hidden">Opening your garden</span>
      </div>
    );
  }

  // The account is offered before anything else, and can be declined. This app
  // is local-first, so an account buys one thing - the same garden on another
  // device - and demanding it up front would be asking for an email in exchange
  // for nothing anyone can see yet.
  if (authSession === null && !localOnly) {
    return (
      <AuthScreen
        onSkip={() => {
          setLocalOnly(true);
          try {
            localStorage.setItem(LOCAL_ONLY_KEY, "1");
          } catch {
            // The choice still holds for this session.
          }
        }}
      />
    );
  }

  /*
   * A signed-in account gets its first pull before we conclude it needs
   * onboarding.
   *
   * On a second device the local save is empty for the moment before sync lands,
   * and rendering onboarding into that gap invites someone to fill in a name they
   * already chose - creating a second garden over the top of the one they came
   * back for. Only the very first exchange is waited on, and only while it is
   * actually in flight: if it fails or the device is offline, onboarding proceeds,
   * because local-first has to keep working when the server does not.
   */
  const awaitingFirstSync = authSession !== null
    && sync.status.lastSyncedAt === 0
    && sync.status.state === "syncing";

  if (awaitingFirstSync) {
    return (
      <div className="boot" role="status" aria-live="polite">
        <span className="visually-hidden">Fetching your garden</span>
      </div>
    );
  }

  if (!garden.save.profile.onboardingCompleted) {
    return (
      <main className="shell__main">
        <div className="shell__content">
          <OnboardingScreen onComplete={garden.completeOnboarding} />
        </div>
      </main>
    );
  }

  return (
    <div className="shell">
      <aside className="rail">
        <div className="rail__brand">
          <b>Focus Garden</b>
          <span>grow what you give time to</span>
        </div>
        <nav className="rail__nav" aria-label="Sections">
          {SCREENS.map((s) => (
            <button
              key={s.id}
              type="button"
              className="rail__item"
              {...(screen === s.id ? { "aria-current": "page" as const } : {})}
              onClick={() => setScreen(s.id)}
            >
              <span className="rail__dot" />
              {s.label}
            </button>
          ))}
        </nav>
        <div className="rail__footer">
          <button className="rail__item" type="button" onClick={theme.cycle}>
            <span className="rail__dot" />
            {theme.resolved === "dark" ? "Light mode" : "Dark mode"}
          </button>
        </div>
      </aside>

      <main className="shell__main">
        <div className="shell__content">
          {garden.transferMessage !== "" && (
            <section className="notice" aria-live="polite">
              <h2>Data</h2>
              <p>{garden.transferMessage}</p>
              <div className="notice__actions">
                <button
                  className="btn btn--quiet"
                  type="button"
                  onClick={() => garden.setTransferMessage("")}
                >
                  Dismiss
                </button>
              </div>
            </section>
          )}

          {screen === "focus" && (
            <FocusScreen
              garden={garden}
              presetMinutes={presetMinutes}
              onPresetChange={setPresetMinutes}
            />
          )}
          {screen === "garden" && <GardenScreen garden={garden} />}
          {screen === "shelf" && <ShelfScreen garden={garden} />}
          {screen === "stats" && <StatisticsScreen garden={garden} />}
          {screen === "settings" && (
            <SettingsScreen
              garden={garden}
              sync={sync}
              onSignedOut={() => setLocalOnly(false)}
            />
          )}
        </div>
      </main>

      <nav className="tabbar" aria-label="Sections">
        {SCREENS.map((s) => (
          <button
            key={s.id}
            type="button"
            className="tabbar__item"
            {...(screen === s.id ? { "aria-current": "page" as const } : {})}
            onClick={() => setScreen(s.id)}
          >
            <span className="tabbar__dot" />
            {s.short}
          </button>
        ))}
      </nav>
    </div>
  );
}
