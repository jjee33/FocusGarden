/**
 * The page a stranger lands on.
 *
 * Until now `/` was the sign-in card and nothing else, which asked people to
 * make an account for a product they had not been shown. This is the argument
 * for the product; the card is now the last thing on the page rather than the
 * first.
 *
 * THE HERO GROWS WHILE YOU WATCH, and that is the whole idea. Every competitor
 * can write "turn focus into progress" over a stock illustration. This app has a
 * procedural renderer that draws a plant at any point between seed and maturity,
 * so instead of describing the pitch the page performs it: three plants fill out
 * in front of you while a counter climbs through the hours of focus that would
 * have grown them. It is the one thing here nobody else's landing page can copy,
 * so it is the only place the design spends any boldness.
 *
 * Growth advances in twelve discrete steps rather than per frame. The SVG is
 * rebuilt whenever `growth` changes, and rebuilding three plants sixty times a
 * second to animate something that reads perfectly well at five would be paying
 * a lot of main thread for nothing anyone can see.
 */

import { useEffect, useMemo, useState } from "react";

import { PlantView } from "../components/PlantView.js";
import { Icon } from "../components/Icon.js";
import { AuthPanel } from "../components/AuthPanel.js";
import { ALL_SPECIES } from "../../content/content.js";
import { RARITY_NAMES } from "../../domain/species.js";
import { useIsCompact, useReducedMotion, useTheme } from "../usePlatform.js";

interface Props {
  /** Continue without an account. The garden stays on this device. */
  onSkip: () => void;
}

/** Enough to read as growth, few enough that the renderer is never the bottleneck. */
const GROWTH_STEPS = 12;
const GROWTH_MS = 5200;

/**
 * Three plants at three speeds, so the bed fills unevenly the way a real one
 * does. Chosen for silhouette contrast - a spike, a broad-leaf and a frond -
 * rather than for rarity, because the point is to show the range of the
 * renderer in one glance.
 */
const HERO = [
  { id: "snake_plant", lag: 0.0, seed: "hero-a", scale: 0.86 },
  { id: "monstera", lag: 0.18, seed: "hero-b", scale: 1.0 },
  { id: "boston_fern", lag: 0.34, seed: "hero-c", scale: 0.8 },
] as const;

/** The hours the hero garden is pretending to represent, for the counter. */
const HERO_HOURS = 14;

function useGrowth(): number {
  const reduced = useReducedMotion();
  const [step, setStep] = useState(reduced ? GROWTH_STEPS : 0);

  useEffect(() => {
    if (reduced) { setStep(GROWTH_STEPS); return; }

    // No "already started" ref guard here: StrictMode mounts effects twice in
    // dev, and a guard that survives the first cleanup leaves the second mount
    // with no interval at all - a hero frozen at bare soil. The step state
    // survives the remount, so re-running the effect resumes rather than
    // restarts, and the interval clears itself once growth is complete.
    const every = GROWTH_MS / GROWTH_STEPS;
    const id = window.setInterval(() => {
      setStep((s) => {
        if (s >= GROWTH_STEPS) { window.clearInterval(id); return s; }
        return s + 1;
      });
    }, every);
    return () => { window.clearInterval(id); };
  }, [reduced]);

  return step / GROWTH_STEPS;
}

export function LandingScreen({ onSkip }: Props) {
  const growth = useGrowth();
  const reduced = useReducedMotion();
  const compact = useIsCompact(760);
  const { foliageAmbient } = useTheme();

  const hero = useMemo(
    () => HERO
      .map((h) => ({ ...h, species: ALL_SPECIES.find((s) => s.id === h.id) ?? null }))
      .filter((h) => h.species?.morphology != null),
    [],
  );

  // Six, not sixteen. A wall of every species is an inventory; a handful is an
  // invitation, and the number is stated in words beside it.
  const shelf = useMemo(
    () => ["pothos", "lavender", "echeveria", "bonsai", "orchid", "aloe_vera"]
      .map((id) => ALL_SPECIES.find((s) => s.id === id) ?? null)
      .filter((s): s is NonNullable<typeof s> => s?.morphology != null),
    [],
  );

  const hours = Math.round(growth * HERO_HOURS);

  return (
    <main className="land">
      <header className="land__bar">
        <span className="land__mark">
          <b>Focus Garden</b>
          <span>grow what you give time to</span>
        </span>
        <a className="land__jump" href="#start">Start</a>
      </header>

      {/* --- hero ------------------------------------------------------- */}
      <section className="land__hero">
        <div className="land__words">
          <h1>
            Every plant here grew out of time you spent focusing.
          </h1>
          <p>
            A focus timer that remembers every minute you give it. Sit down for
            twenty-five minutes and something in your garden will be a little
            further along than it was. Nothing here can be bought, hurried, or
            watered — only grown.
          </p>
          <div className="land__cta">
            <a className="btn" href="#start">Start growing</a>
            <a className="btn btn--ghost" href="#how">See how it works</a>
          </div>
        </div>

        <div className="land__bed" aria-hidden="true">
          <div className="land__plants">
            {hero.map((h) => {
              // Each plant lags the one before it, so the bed fills unevenly.
              const own = Math.max(0, Math.min(1, (growth - h.lag) / (1 - h.lag)));
              return (
                <div className="land__plant" key={h.id}>
                  <PlantView
                    morphology={h.species!.morphology!}
                    growth={own}
                    width={Math.round((compact ? 120 : 190) * h.scale)}
                    height={Math.round((compact ? 150 : 240) * h.scale)}
                    seed={h.seed}
                    lod={compact ? 0.65 : 0.85}
                    bloom={own >= 1}
                    animate={!reduced}
                    foliageAmbient={foliageAmbient}
                  />
                </div>
              );
            })}
          </div>
          <p className="land__ticker">
            <b>{hours}</b> {hours === 1 ? "hour" : "hours"} of focus
          </p>
        </div>
      </section>

      {/* --- how ---------------------------------------------------------
          Numbered because it genuinely is a sequence: you cannot grow the
          thing before you have chosen it, and the growth is the consequence
          of the sitting. Order carries meaning here. */}
      <section className="land__how" id="how">
        <h2>Three things, in order</h2>
        <ol className="land__steps">
          <li>
            <span className="land__num">One</span>
            <h3>Choose something to grow</h3>
            <p>
              Sixteen species, from a jade plant to a juniper bonsai. Each needs a
              different number of hours to reach maturity — three for a
              houseplant, ten for the bonsai.
            </p>
          </li>
          <li>
            <span className="land__num">Two</span>
            <h3>Sit with your work</h3>
            <p>
              Set a length and begin. Take a break, make a cup of tea, step away
              when you need to — the timer counts real time, so the credit is
              exactly the time you gave it, and a session cut short is offered
              back rather than lost.
            </p>
          </li>
          <li>
            <span className="land__num">Three</span>
            <h3>Watch it come in</h3>
            <p>
              Minutes become growth. A plant reaching maturity goes into the
              ground, joins the catalogue, and stays there — a keepsake of hours
              that would otherwise slip by with nothing to show for them.
            </p>
          </li>
        </ol>
      </section>

      {/* --- the collection --------------------------------------------- */}
      <section className="land__shelf">
        <div className="land__shelfwords">
          <h2>Sixteen to find</h2>
          <p>
            Every plant here truly grows — it fills out leaf by leaf, from first
            sprout to full bloom, and no two grow quite the same way. Six of
            them are below, fully grown.
          </p>
        </div>
        <ul className="land__specimens">
          {shelf.map((s) => (
            <li key={s.id}>
              <PlantView
                morphology={s.morphology!}
                growth={1}
                width={compact ? 84 : 104}
                height={compact ? 104 : 130}
                seed={`shelf-${s.id}`}
                lod={0.6}
                animate={false}
                foliageAmbient={foliageAmbient}
              />
              <b>{s.displayName}</b>
              <span
                className="rarity"
                style={{
                  background: `var(--rarity-${s.rarity})`,
                  color: `var(--rarity-ink-${s.rarity})`,
                }}
              >
                {RARITY_NAMES[s.rarity]}
              </span>
            </li>
          ))}
        </ul>
      </section>

      {/* --- the promises ------------------------------------------------
          Stated as facts about the product rather than as marketing, because
          every one of them is checkable and several are unusual. */}
      <section className="land__plain">
        <h2>A quiet corner of the internet</h2>
        <ul className="land__facts">
          <li><Icon name="check" /><span><b>No ads, no payment, no upsell.</b> There is no paid tier and nothing to buy.</span></li>
          <li><Icon name="check" /><span><b>No tracking.</b> Nothing here watches you or follows you around the internet.</span></li>
          <li><Icon name="check" /><span><b>Works offline.</b> Your garden lives with you, not somewhere far away — it keeps growing on a plane, on a train, or anywhere without signal.</span></li>
          <li><Icon name="check" /><span><b>An account is optional.</b> It buys one thing: the same garden on your other devices.</span></li>
          <li><Icon name="check" /><span><b>Your garden is yours to keep.</b> Take a copy with you whenever you like — nothing is locked away.</span></li>
        </ul>
      </section>

      {/* --- the ask ------------------------------------------------------ */}
      <section className="land__start" id="start">
        <AuthPanel onSkip={onSkip} />
      </section>

      <footer className="land__foot">
        <span>Focus Garden</span>
        <a href="/privacy">Privacy</a>
        <a href="/terms">Terms</a>
      </footer>
    </main>
  );
}
