/**
 * The garden: the payoff screen, where hours of focus are standing in a bed.
 *
 * TOUCH FIRST. Placement is tap-to-select then tap-to-place, with the tray as
 * the source and the bed as the target. Drag is a poor primary interaction on a
 * phone - it competes with scrolling, has no hover state to telegraph a valid
 * drop, and is unusable with a screen reader or a keyboard. Tap-place is all
 * three at once: it works with a mouse, a finger and the Tab key without a
 * separate code path, which is why the desktop's drag-and-drop is not what got
 * ported here.
 */

import { useState } from "react";

import { PlantView } from "../components/PlantView.js";
import type { PlantSummary, useGarden } from "../useGarden.js";
import { getSpecies } from "../../content/content.js";
import { ALL_EXPANSIONS } from "../../content/content.js";
import { Location, canBeDisplayed } from "../../domain/plant-instance.js";
import { formatDuration } from "../../domain/time-util.js";
import { RARITY_NAMES } from "../../domain/species.js";
import { useReducedMotion, useTheme } from "../usePlatform.js";

interface Props {
  garden: ReturnType<typeof useGarden>;
}

export function GardenScreen({ garden }: Props) {
  const { summaries, placeInGarden, rotatePlant } = garden;
  const { foliageAmbient } = useTheme();
  const reducedMotion = useReducedMotion();
  const [selectedUid, setSelectedUid] = useState<string | null>(null);

  // The smallest shipped plot. Expansions are earned through the requirement
  // engine; wiring that ladder up is Phase 4.
  const expansion = ALL_EXPANSIONS[0];
  const cols = expansion?.gridWidth ?? 4;
  const rows = expansion?.gridHeight ?? 3;

  const planted = summaries.filter((s) => s.plant.location === Location.GARDEN);
  // Only plants far enough along to be worth looking at can be placed. A seed in
  // a pot is not a thing to display, and the point of the gate is that reaching
  // it means something.
  const available = summaries.filter(
    (s) => s.plant.location !== Location.GARDEN && canBeDisplayed(s.plant),
  );
  const notReady = summaries.filter(
    (s) => s.plant.location !== Location.GARDEN && !canBeDisplayed(s.plant),
  );

  const occupant = (x: number, y: number): PlantSummary | undefined =>
    planted.find((s) => s.plant.gardenCellX === x && s.plant.gardenCellY === y);

  const onCellClick = (x: number, y: number): void => {
    const here = occupant(x, y);
    if (selectedUid !== null) {
      // An occupied cell is not a valid target; tapping it selects instead, which
      // is what someone reaching for "move that one" actually means.
      if (here === undefined) {
        placeInGarden(selectedUid, x, y);
        setSelectedUid(null);
      } else {
        setSelectedUid(here.plant.uid);
      }
      return;
    }
    if (here !== undefined) setSelectedUid(here.plant.uid);
  };

  const selected = summaries.find((s) => s.plant.uid === selectedUid) ?? null;

  return (
    <>
      <div className="greet">
        <h1>Your garden</h1>
        <p>
          {planted.length} planted ·{" "}
          {formatDuration(planted.reduce((sum, s) => sum + s.plant.accumulatedFocusMinutes, 0))}{" "}
          of focus standing in the bed
        </p>
      </div>

      <p className="hint" aria-live="polite">
        {selected === null
          ? "Pick a plant below, then tap an empty bed to plant it out."
          : `${selected.speciesName} selected. Tap a bed to plant it, or use Turn.`}
      </p>

      <section className="garden-scene fg-grain" aria-label="Garden beds">
        <div className="garden-plot">
        <div
          className="garden-grid"
          data-placing={selectedUid !== null}
          style={{ gridTemplateColumns: `repeat(${cols}, minmax(0, 1fr))` }}
        >
          {Array.from({ length: rows * cols }, (_, index) => {
            const x = index % cols;
            const y = Math.floor(index / cols);
            const here = occupant(x, y);
            const isTarget = selectedUid !== null && here === undefined;
            const isSelected = here !== undefined && here.plant.uid === selectedUid;
            const species = here === undefined ? null : getSpecies(here.plant.speciesId);
            return (
              <button
                key={`${x}-${y}`}
                type="button"
                className={
                  "cell"
                  + (isTarget ? " cell--target" : "")
                  + (isSelected ? " cell--selected" : "")
                }
                onClick={() => onCellClick(x, y)}
                aria-label={
                  here === undefined
                    ? `Empty bed, row ${y + 1} column ${x + 1}`
                    : `${here.speciesName}, ${here.stageLabel}, row ${y + 1} column ${x + 1}`
                }
              >
                <span className="cell__bed" />
                {species?.morphology != null && here !== undefined && (
                  <span className="cell__plant">
                    <PlantView
                      morphology={species.morphology}
                      // Garden plants are in the GROUND, not in pots.
                      pot={null}
                      growth={here.ratio}
                      width={132}
                      height={190}
                      seed={here.plant.uid}
                      lod={0.4}
                      facing={here.plant.gardenRotation}
                      foliageAmbient={foliageAmbient}
                      // Sway is switched on only for the plant the screen is
                      // featuring. A bed of twelve all moving at once is visual
                      // noise on a screen meant to feel calm - and it is twelve
                      // compositor layers instead of one.
                      animate={!reducedMotion && here.plant.uid === selectedUid}
                    />
                  </span>
                )}
              </button>
            );
          })}
        </div>
        </div>
      </section>

      {selected !== null && selected.plant.location === Location.GARDEN && (
        <div className="focus-actions">
          <button className="btn btn--ghost" type="button" onClick={() => rotatePlant(selected.plant.uid)}>
            Turn {selected.speciesName}
          </button>
          <button className="btn btn--quiet" type="button" onClick={() => setSelectedUid(null)}>
            Done
          </button>
        </div>
      )}

      <section aria-labelledby="tray-heading">
        <div className="section-head">
          <h2 id="tray-heading">Ready to plant</h2>
          <span className="eyebrow">{available.length} available</span>
        </div>
        {available.length === 0 ? (
          <p className="hint">
            Nothing ready yet. A plant can go out once it is a third of the way grown.
          </p>
        ) : (
          <div className="tray">
            {available.map((s) => {
              const species = getSpecies(s.plant.speciesId);
              if (species?.morphology == null) return null;
              return (
                <button
                  key={s.plant.uid}
                  type="button"
                  className="tray__item"
                  aria-pressed={s.plant.uid === selectedUid}
                  onClick={() =>
                    setSelectedUid(s.plant.uid === selectedUid ? null : s.plant.uid)}
                >
                  <PlantView
                    morphology={species.morphology}
                    pot={garden.getPot(s.plant.potId)}
                    growth={s.ratio}
                    width={72}
                    height={92}
                    seed={s.plant.uid}
                    lod={0.35}
                    foliageAmbient={foliageAmbient}
                  />
                  <span className="tray__name">{s.speciesName}</span>
                  <span
                    className="rarity"
                    style={{
                    background: `var(--rarity-${species.rarity})`,
                    color: `var(--rarity-ink-${species.rarity})`,
                  }}
                  >
                    {RARITY_NAMES[species.rarity]}
                  </span>
                </button>
              );
            })}
          </div>
        )}
      </section>

      {notReady.length > 0 && (
        <section aria-labelledby="growing-heading">
          <div className="section-head">
            <h2 id="growing-heading">Still growing</h2>
          </div>
          <div className="tray">
            {notReady.map((s) => {
              const species = getSpecies(s.plant.speciesId);
              if (species?.morphology == null) return null;
              return (
                <div key={s.plant.uid} className="tray__item" style={{ cursor: "default" }}>
                  <PlantView
                    morphology={species.morphology}
                    pot={garden.getPot(s.plant.potId)}
                    growth={s.ratio}
                    width={72}
                    height={92}
                    seed={s.plant.uid}
                    lod={0.35}
                    foliageAmbient={foliageAmbient}
                  />
                  <span className="tray__name">{s.speciesName}</span>
                  <span className="growing__meta">{Math.round(s.ratio * 100)}%</span>
                </div>
              );
            })}
          </div>
        </section>
      )}
    </>
  );
}
