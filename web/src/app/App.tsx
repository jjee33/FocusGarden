/**
 * The shell for the Phase 3 spike: two screens, the nav that carries them, and
 * the theme control.
 *
 * Only Focus and Garden are built. The other nine screens are Phase 4, and the
 * point of stopping here is that the look gets judged on two finished screens
 * rather than eleven half-finished ones.
 */

import { useState } from "react";

import "./theme.css";
import "./app.css";
import { FocusScreen } from "./screens/FocusScreen.js";
import { GardenScreen } from "./screens/GardenScreen.js";
import { useGarden } from "./useGarden.js";
import { useTheme } from "./usePlatform.js";

type ScreenId = "focus" | "garden" | "shelf" | "catalogue";

const SCREENS: { id: ScreenId; label: string; built: boolean }[] = [
  { id: "focus", label: "Focus", built: true },
  { id: "garden", label: "Garden", built: true },
  { id: "shelf", label: "Shelf", built: false },
  { id: "catalogue", label: "Catalogue", built: false },
];

export function App() {
  const [screen, setScreen] = useState<ScreenId>("focus");
  const [presetMinutes, setPresetMinutes] = useState(25);
  const garden = useGarden();
  const theme = useTheme();

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
              {!s.built && <span style={{ marginLeft: "auto", opacity: 0.5, fontSize: 10 }}>soon</span>}
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
          {screen === "focus" && (
            <FocusScreen
              garden={garden}
              presetMinutes={presetMinutes}
              onPresetChange={setPresetMinutes}
            />
          )}
          {screen === "garden" && <GardenScreen garden={garden} />}
          {(screen === "shelf" || screen === "catalogue") && (
            <div className="greet">
              <h1>Not built yet</h1>
              <p>
                This spike covers Focus and Garden only. The remaining screens come
                after the look is agreed.
              </p>
            </div>
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
            {s.label}
          </button>
        ))}
      </nav>
    </div>
  );
}
