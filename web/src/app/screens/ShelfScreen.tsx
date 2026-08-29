/**
 * The shelf: a curated row, as opposed to the garden's plot.
 *
 * Plants here are IN POTS, unlike the garden where they are in the ground. That
 * is the whole distinction between the two screens and the reason both exist.
 *
 * `ShelfLayout` holds styling and decorations only - placement lives on
 * `PlantInstance.shelfSlot`, so the shelf and the plant can never disagree about
 * where something is. Same tap-to-select then tap-to-place interaction as the
 * garden, for the same reasons: it works with a mouse, a finger and the Tab key
 * through one code path.
 */

import { useState } from "react";

import { PlantView } from "../components/PlantView.js";
import type { PlantSummary, useGarden } from "../useGarden.js";
import { getSpecies } from "../../content/content.js";
import { Location, canBeDisplayed } from "../../domain/plant-instance.js";
import { formatDuration } from "../../domain/time-util.js";
import { useReducedMotion, useTheme } from "../usePlatform.js";

interface Props {
  garden: ReturnType<typeof useGarden>;
}

/** How many plants fit on one board before it wraps to the next. */
const PER_ROW = 4;

export function ShelfScreen({ garden }: Props) {
  const { summaries, save, placeOnShelf, returnToInventory } = garden;
  const { foliageAmbient } = useTheme();
  const reducedMotion = useReducedMotion();
  const [selectedUid, setSelectedUid] = useState<string | null>(null);

  const slotCount = save.shelf.slotCount;
  const shelved = summaries.filter((s) => s.plant.location === Location.SHELF);
  const available = summaries.filter(
    (s) => s.plant.location === Location.INVENTORY && canBeDisplayed(s.plant),
  );

  const occupant = (slot: number): PlantSummary | undefined =>
    shelved.find((s) => s.plant.shelfSlot === slot);

  const onSlotClick = (slot: number): void => {
    const here = occupant(slot);
    if (selectedUid !== null) {
      if (here === undefined) {
        placeOnShelf(selectedUid, slot);
        setSelectedUid(null);
      } else {
        setSelectedUid(here.plant.uid);
      }
      return;
    }
    if (here !== undefined) setSelectedUid(here.plant.uid);
  };

  const selected = summaries.find((s) => s.plant.uid === selectedUid) ?? null;
  const rows = Math.ceil(slotCount / PER_ROW);

  return (
    <>
      <div className="greet">
        <h1>{save.shelf.displayName}</h1>
        <p>
          {shelved.length} of {slotCount} spaces filled ·{" "}
          {formatDuration(shelved.reduce((sum, s) => sum + s.plant.accumulatedFocusMinutes, 0))}
          {" "}on display
        </p>
      </div>

      <p className="hint" aria-live="polite">
        {selected === null
          ? "Pick a plant below, then tap a space to put it out."
          : `${selected.speciesName} selected. Tap a space to place it.`}
      </p>

      <section className="shelf-scene fg-grain" aria-label="Display shelf">
        {Array.from({ length: rows }, (_, row) => (
          <div
            key={row}
            className="shelf-row"
            style={{ gridTemplateColumns: `repeat(${PER_ROW}, minmax(0, 1fr))` }}
          >
            {Array.from({ length: PER_ROW }, (_, column) => {
              const slot = row * PER_ROW + column;
              if (slot >= slotCount) return <span key={slot} />;
              const here = occupant(slot);
              const species = here === undefined ? null : getSpecies(here.plant.speciesId);
              const isTarget = selectedUid !== null && here === undefined;
              return (
                <button
                  key={slot}
                  type="button"
                  className={
                    "slot"
                    + (isTarget ? " slot--target" : "")
                    + (here?.plant.uid === selectedUid ? " slot--selected" : "")
                  }
                  onClick={() => onSlotClick(slot)}
                  aria-label={here === undefined
                    ? `Empty space ${slot + 1}`
                    : `${here.speciesName}, ${here.stageLabel}, space ${slot + 1}`}
                >
                  {species?.morphology != null && here !== undefined && (
                    <PlantView
                      morphology={species.morphology}
                      // In pots here, unlike the garden. That is the difference
                      // between a shelf and a plot.
                      pot={garden.getPot(here.plant.potId)}
                      growth={here.ratio}
                      width={118}
                      height={150}
                      seed={here.plant.uid}
                      lod={0.45}
                      foliageAmbient={foliageAmbient}
                      animate={!reducedMotion && here.plant.uid === selectedUid}
                    />
                  )}
                </button>
              );
            })}
          </div>
        ))}
      </section>

      {selected !== null && selected.plant.location === Location.SHELF && (
        <div className="focus-actions">
          <button
            className="btn btn--ghost"
            type="button"
            onClick={() => {
              returnToInventory(selected.plant.uid);
              setSelectedUid(null);
            }}
          >
            Take {selected.speciesName} down
          </button>
          <button className="btn btn--quiet" type="button" onClick={() => setSelectedUid(null)}>
            Done
          </button>
        </div>
      )}

      <section aria-labelledby="available-heading">
        <div className="section-head">
          <h2 id="available-heading">Ready to display</h2>
          <span className="eyebrow">{available.length} available</span>
        </div>
        {available.length === 0 ? (
          <p className="hint">
            Nothing waiting. A plant can go on the shelf once it is a third of the way grown.
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
                  onClick={() => setSelectedUid(s.plant.uid === selectedUid ? null : s.plant.uid)}
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
                  <span className="growing__meta">{Math.round(s.ratio * 100)}%</span>
                </button>
              );
            })}
          </div>
        )}
      </section>
    </>
  );
}
