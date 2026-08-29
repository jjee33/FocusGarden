/**
 * The shell: the launch screens, the nav that carries them, and first run.
 *
 * Catalogue, Journal and Achievements are deliberately absent. Their domain
 * logic is ported and tested; only the screens are deferred, so shipping them
 * later is UI work and nothing else.
 */

import { useState } from "react";

import "./theme.css";
import "./app.css";
import { FocusScreen } from "./screens/FocusScreen.js";
import { GardenScreen } from "./screens/GardenScreen.js";
import { ShelfScreen } from "./screens/ShelfScreen.js";
import { StatisticsScreen } from "./screens/StatisticsScreen.js";
import { SettingsScreen } from "./screens/SettingsScreen.js";
import { OnboardingScreen } from "./screens/OnboardingScreen.js";
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

export function App() {
  const [screen, setScreen] = useState<ScreenId>("focus");
  const [presetMinutes, setPresetMinutes] = useState(25);
  const garden = useGarden();
  const theme = useTheme();

  // Nothing is rendered until the first load settles. Flashing an empty garden
  // and then filling it in reads as data loss for the half-second it lasts.
  if (!garden.storage.ready) {
    return (
      <div className="boot" role="status" aria-live="polite">
        <span className="visually-hidden">Opening your garden</span>
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
          {screen === "settings" && <SettingsScreen garden={garden} />}
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
