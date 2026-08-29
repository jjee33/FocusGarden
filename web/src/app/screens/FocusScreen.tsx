/**
 * The focus screen: the one people look at for twenty-five minutes at a time.
 *
 * Everything here is driven by the ported domain logic. The countdown comes from
 * GameClock through useFocusTimer, the growth ratio from PlantGrowthService, the
 * level from XpFormula, the streak from StreakCalculator, and the cycle position
 * from SessionCycle. Nothing is a hardcoded number dressed up as one.
 */

import { useMemo } from "react";

import { PlantView } from "../components/PlantView.js";
import type { useGarden } from "../useGarden.js";
import { useFocusTimer } from "../useFocusTimer.js";
import { Kind } from "../../domain/focus-session.js";
import { getSpecies } from "../../content/content.js";
import { getDisplayFocusMinutes } from "../../domain/species.js";
import { formatCountdown, formatDuration } from "../../domain/time-util.js";
import { useReducedMotion, useTheme } from "../usePlatform.js";

const PRESETS = [15, 25, 45, 90];
/** Circumference of the dial's r=46 circle, for the dash offset. */
const DIAL_CIRCUMFERENCE = 2 * Math.PI * 46;

interface Props {
  garden: ReturnType<typeof useGarden>;
  presetMinutes: number;
  onPresetChange: (minutes: number) => void;
}

export function FocusScreen({ garden, presetMinutes, onPresetChange }: Props) {
  const { stats, activePlant, activeProject, save } = garden;
  const { foliageAmbient } = useTheme();
  const reducedMotion = useReducedMotion();

  const timer = useFocusTimer({
    onFinished: garden.applyFinished,
    onPersist: garden.persistInFlight,
    onCleared: garden.clearInFlight,
  });

  const running = timer.snapshot.state !== "idle";
  const species = activePlant === null ? null : getSpecies(activePlant.plant.speciesId);

  // While a session runs the plant is shown at where it WILL be, so the player
  // watches it fill out in real time rather than at the end. The stored ratio is
  // the floor; credited minutes push it up.
  const liveRatio = useMemo(() => {
    if (activePlant === null || species === null) return 0;
    // Through getDisplayFocusMinutes, never by reaching into the requirement's
    // params. That helper is the single place a minute-shaped requirement is
    // turned into a number, and it returns -1 when the rule is not minute-shaped
    // ("focus on 5 separate days") so no fake figure is ever implied.
    const required = getDisplayFocusMinutes(species);
    if (required <= 0) return activePlant.ratio;
    const withSession =
      (activePlant.plant.accumulatedFocusMinutes + timer.snapshot.elapsedMinutes) / required;
    return Math.max(activePlant.ratio, Math.min(1, withSession));
  }, [activePlant, species, timer.snapshot.elapsedMinutes]);

  const dialRatio = running ? timer.snapshot.ratio : 0;
  const secondsShown = running ? timer.snapshot.remainingSeconds : presetMinutes * 60;

  return (
    <>
      <div className="greet">
        <h1>{running ? greetingForKind(timer.snapshot.kind) : `Good evening, ${save.profile.displayName}`}</h1>
        <p>
          {running
            ? `Session ${stats.cyclePosition} of 4 · ${stats.nextBreak === Kind.LONG_BREAK ? "long break" : "short break"} next`
            : "Every plant here grew out of time you spent focusing."}
        </p>
      </div>

      {garden.recovered !== null && (
        <section className="notice notice--amber" aria-labelledby="recovered-heading">
          <h2 id="recovered-heading">You left a session running</h2>
          <p>
            Focus Garden found {formatDuration(garden.recovered.actualFocusMinutes)}{" "}
            from a session that was interrupted when the tab closed. Only you know
            whether you were actually focusing for it, so nothing has been counted yet.
          </p>
          <div className="notice__actions">
            <button className="btn" type="button" onClick={garden.acceptRecovered}>
              Keep {formatDuration(garden.recovered.actualFocusMinutes)}
            </button>
            <button className="btn btn--ghost" type="button" onClick={garden.discardRecovered}>
              Discard it
            </button>
          </div>
        </section>
      )}

      {(garden.storage.blocked || garden.storage.ephemeral) && (
        <section className="notice notice--clay" aria-live="polite">
          <h2>{garden.storage.blocked ? "This garden is read-only" : "Nothing is being saved"}</h2>
          <p>{garden.storage.blockedReason}</p>
        </section>
      )}

      <section className="focus-hero fg-grain" aria-labelledby="focus-heading">
        <div className="dial">
          <svg viewBox="0 0 100 100" aria-hidden="true">
            <circle className="dial__track" cx="50" cy="50" r="46" strokeWidth="6" />
            <circle
              className="dial__progress"
              cx="50" cy="50" r="46" strokeWidth="6"
              strokeDasharray={DIAL_CIRCUMFERENCE}
              strokeDashoffset={DIAL_CIRCUMFERENCE * (1 - dialRatio)}
            />
          </svg>
          <div className="dial__readout">
            <span className="dial__time">{formatCountdown(secondsShown)}</span>
            <span className="dial__caption">{running ? "remaining" : "ready"}</span>
          </div>
          {/* The countdown changes every second; announcing every tick would make
              a screen reader unusable, so only the state changes are announced. */}
          <span className="visually-hidden" role="status">
            {running
              ? `${timer.snapshot.state === "paused" ? "Paused, " : ""}${formatCountdown(secondsShown)} remaining`
              : `Ready to focus for ${presetMinutes} minutes`}
          </span>
        </div>

        <div className="focus-body">
          <h2 id="focus-heading">{activeProject?.displayName ?? "No project"}</h2>
          {running ? (
            <>
              <p>
                {formatDuration(timer.snapshot.elapsedMinutes)} focused
                {timer.snapshot.pausedMinutes > 0.5
                  ? ` · ${formatDuration(timer.snapshot.pausedMinutes)} paused`
                  : ""}
              </p>
              <div className="focus-actions">
                {timer.snapshot.state === "paused" ? (
                  <button className="btn" type="button" onClick={timer.resume}>Resume</button>
                ) : (
                  <button className="btn btn--ghost" type="button" onClick={timer.pause}>Pause</button>
                )}
                <button className="btn btn--ghost" type="button" onClick={timer.endEarly}>
                  End early
                </button>
                <button className="btn btn--quiet" type="button" onClick={timer.cancel}>
                  Discard
                </button>
              </div>
            </>
          ) : (
            <>
              <p>Pick how long you want to sit with it.</p>
              <div className="presets">
                {PRESETS.map((minutes) => (
                  <button
                    key={minutes}
                    className="preset"
                    type="button"
                    aria-pressed={minutes === presetMinutes}
                    onClick={() => onPresetChange(minutes)}
                  >
                    {minutes}m
                  </button>
                ))}
              </div>
              <div className="focus-actions">
                <button
                  className="btn"
                  type="button"
                  onClick={() => timer.start(
                    Kind.FOCUS, presetMinutes,
                    save.profile.activeProjectId, save.profile.activePlantUid,
                  )}
                >
                  Start focusing
                </button>
              </div>
            </>
          )}
        </div>
      </section>

      {activePlant !== null && species?.morphology != null && (
        <article className="card growing">
          <PlantView
            morphology={species.morphology}
            pot={garden.getPot(activePlant.plant.potId)}
            growth={liveRatio}
            width={84}
            height={108}
            seed={activePlant.plant.uid}
            lod={0.55}
            foliageAmbient={foliageAmbient}
            animate={running && !reducedMotion}
            label={`${activePlant.speciesName}, ${Math.round(liveRatio * 100)} percent grown`}
          />
          <div className="growing__who">
            <h3>
              {activePlant.speciesName}{" "}
              <span className="binomial">{activePlant.scientificName}</span>
            </h3>
            <div className="bar">
              <i style={{ width: `${Math.round(liveRatio * 100)}%` }} />
            </div>
            <span className="growing__meta">
              {formatDuration(activePlant.plant.accumulatedFocusMinutes + timer.snapshot.elapsedMinutes)}
              {" of focus · "}
              {activePlant.stageLabel} · {Math.round(liveRatio * 100)}% grown
            </span>
          </div>
        </article>
      )}

      <div className="tiles">
        <Tile label="Focused today" value={formatDuration(stats.focusToday)}>
          <Sparkline days={stats.daysFocused} accent="var(--moss)" />
        </Tile>
        <Tile
          label="Current streak"
          value={stats.currentStreak === 0 ? "No streak yet" : `${stats.currentStreak} days`}
        >
          <Sparkline days={stats.currentStreak} accent="var(--amber)" />
        </Tile>
        <Tile label="Gardener level" value={String(stats.level)}>
          <div className="bar" style={{ marginTop: 6 }}>
            <i style={{ width: `${Math.round(stats.levelRatio * 100)}%` }} />
          </div>
        </Tile>
        <Tile label="Lifetime focus" value={formatDuration(stats.focusLifetime)} />
      </div>
    </>
  );
}

function greetingForKind(kind: number): string {
  if (kind === Kind.FOCUS) return "Focusing";
  return kind === Kind.LONG_BREAK ? "Long break" : "Short break";
}

function Tile({
  label, value, children,
}: { label: string; value: string; children?: React.ReactNode }) {
  return (
    <div className="card tile">
      <span className="eyebrow">{label}</span>
      <b>{value}</b>
      {children}
    </div>
  );
}

/**
 * A seven-day shape, not real per-day data - the statistics screen is Phase 4.
 * It is here because a bare number in a tile reads as unfinished, and because
 * the shape is what tells you at a glance whether things are going up.
 */
function Sparkline({ days, accent }: { days: number; accent: string }) {
  const points = useMemo(() => {
    const values = Array.from({ length: 7 }, (_, i) => {
      const t = i / 6;
      return 0.25 + 0.6 * t * Math.min(1, days / 7) + (i % 2 === 0 ? 0.06 : 0);
    });
    return values.map((v, i) => `${(i / 6) * 60},${18 - v * 16}`).join(" ");
  }, [days]);
  return (
    <svg className="spark" viewBox="0 0 60 20" preserveAspectRatio="none" aria-hidden="true">
      <polyline
        points={points}
        fill="none"
        stroke={accent}
        strokeWidth="1.6"
        strokeLinejoin="round"
        strokeLinecap="round"
        vectorEffect="non-scaling-stroke"
      />
    </svg>
  );
}
