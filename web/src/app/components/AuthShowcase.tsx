/**
 * What the empty half of a desktop screen is for.
 *
 * The sign-in panel is sized for a phone, and phone-first was the right call —
 * but on a 1920-wide monitor it left a small card floating in an acre of beige,
 * which is the first thing anyone arriving on a laptop sees. The page did not
 * look broken; it looked unfinished, and this is the acquisition surface.
 *
 * So the space shows the product instead of describing it. Focus Garden's whole
 * pitch is that time turns into something worth looking at, and the renderer for
 * that already exists — a paragraph claiming plants grow is weaker than three
 * plants at three different stages of growth.
 *
 * NOTHING HERE IS ON THE CRITICAL PATH. Below 900px the component returns null
 * rather than being hidden with CSS - `display: none` still builds three
 * procedural SVGs and puts them in the DOM, which is a cost a phone pays for
 * something it will never see. Every plant is also drawn at reduced detail,
 * because this is scene-setting rather than somebody's actual garden.
 */

import { useMemo } from "react";

import { PlantView } from "./PlantView.js";
import { ALL_SPECIES } from "../../content/content.js";
import { useIsCompact, useReducedMotion } from "../usePlatform.js";

/**
 * Three stages of the same idea: just planted, halfway, and grown.
 *
 * Chosen rather than random so the progression reads left to right, and so the
 * page looks the same to everyone who is shown it.
 */
const CAST = [
  { id: "jade_plant", growth: 0.18, seed: "showcase-a" },
  { id: "monstera", growth: 1, seed: "showcase-b" },
  { id: "boston_fern", growth: 0.55, seed: "showcase-c" },
] as const;

export function AuthShowcase() {
  const reduced = useReducedMotion();
  // 900 matches the breakpoint the two-column layout starts at. If these ever
  // disagree the showcase either renders into a column that does not exist or
  // leaves a hole where one does.
  const compact = useIsCompact(900);

  const cast = useMemo(
    () => CAST
      .map((c) => ({ ...c, species: ALL_SPECIES.find((s) => s.id === c.id) ?? null }))
      .filter((c) => c.species?.morphology != null),
    [],
  );

  // Content is data-driven, so a renamed species should quietly drop a plant
  // rather than take the sign-in screen down with it.
  if (compact || cast.length === 0) return null;

  return (
    <aside className="showcase" aria-hidden="true">
      <div className="showcase__bed">
        {cast.map((c, i) => (
          <div className={`showcase__slot showcase__slot--${i}`} key={c.id}>
            <PlantView
              morphology={c.species!.morphology!}
              growth={c.growth}
              width={190}
              height={230}
              seed={c.seed}
              lod={0.6}
              animate={!reduced}
              bloom={c.growth >= 1}
            />
          </div>
        ))}
      </div>
      <p className="showcase__caption">
        Three plants, and the hours that grew them.
      </p>
    </aside>
  );
}
