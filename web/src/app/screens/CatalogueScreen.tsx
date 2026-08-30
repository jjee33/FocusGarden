/**
 * The catalogue: every species, and what you have done with it.
 *
 * Collection is the part of this genre that makes tomorrow's session feel like
 * progress rather than repetition, and all of it was already built - discovery,
 * times grown, fastest maturity, favourites - and recorded on every session
 * since launch. It simply had nowhere to be seen.
 *
 * UNDISCOVERED SPECIES ARE SHOWN, NOT HIDDEN, except the handful the content
 * marks `hiddenUntilDiscovered`. A locked row with a name and a rarity is what
 * makes a collection feel finite and finishable; an empty grid that fills up
 * from nothing gives you no idea whether you are a quarter of the way in or
 * nearly done. The ones that stay hidden are the deliberate surprises.
 */

import { useMemo, useState } from "react";

import { PlantView } from "../components/PlantView.js";
import { Icon } from "../components/Icon.js";
import type { useGarden } from "../useGarden.js";
import { ALL_SPECIES } from "../../content/content.js";
import { RARITY_NAMES } from "../../domain/species.js";
import { formatDuration } from "../../domain/time-util.js";
import type { CatalogueEntry } from "../../domain/catalogue-entry.js";
import { useIsCompact, useReducedMotion, useTheme } from "../usePlatform.js";

interface Props {
  garden: ReturnType<typeof useGarden>;
}

type Filter = "all" | "discovered" | "missing" | "favourites";

const FILTERS: { id: Filter; label: string }[] = [
  { id: "all", label: "All" },
  { id: "discovered", label: "Found" },
  { id: "missing", label: "Not yet" },
  { id: "favourites", label: "Favourites" },
];

export function CatalogueScreen({ garden }: Props) {
  const { save, toggleFavouriteSpecies } = garden;
  const { foliageAmbient } = useTheme();
  const reducedMotion = useReducedMotion();
  const compact = useIsCompact(700);
  const [filter, setFilter] = useState<Filter>("all");

  const byId = useMemo(() => {
    const map = new Map<string, CatalogueEntry>();
    for (const e of save.catalogue) map.set(e.speciesId, e);
    return map;
  }, [save.catalogue]);

  const rows = useMemo(() => ALL_SPECIES
    .map((species) => ({ species, entry: byId.get(species.id) ?? null }))
    // A species flagged hidden stays out of the list entirely until it is found,
    // which is the only kind of secret this screen keeps.
    .filter(({ species, entry }) => !species.hiddenUntilDiscovered || entry?.discovered === true),
    [byId]);

  const shown = rows.filter(({ entry }) => {
    if (filter === "discovered") return entry?.discovered === true;
    if (filter === "missing") return entry?.discovered !== true;
    if (filter === "favourites") return entry?.favorite === true;
    return true;
  });

  const found = rows.filter((r) => r.entry?.discovered === true).length;

  return (
    <>
      <header className="greet">
        <h1>Catalogue</h1>
        <p>
          {found} of {rows.length} found
          {found === rows.length && rows.length > 0 ? " — the whole shop" : ""}
        </p>
      </header>

      <div className="seg-group" role="group" aria-label="Filter the catalogue">
        {FILTERS.map((f) => (
          <button
            key={f.id}
            type="button"
            className="chip"
            aria-pressed={filter === f.id}
            onClick={() => setFilter(f.id)}
          >
            {f.label}
          </button>
        ))}
      </div>

      {shown.length === 0 && (
        <p className="empty">Nothing here yet. Grow something and it will appear.</p>
      )}

      <div className="catalogue-grid">
        {shown.map(({ species, entry }) => {
          const found = entry?.discovered === true;
          return (
            <article
              className={`spec-card${found ? "" : " spec-card--locked"}`}
              key={species.id}
            >
              <div className="spec-card__art">
                {found && species.morphology != null ? (
                  <PlantView
                    morphology={species.morphology}
                    growth={1}
                    width={compact ? 96 : 118}
                    height={compact ? 110 : 132}
                    seed={species.id}
                    lod={0.55}
                    animate={!reducedMotion}
                    foliageAmbient={foliageAmbient}
                  />
                ) : (
                  <span className="spec-card__locked" aria-hidden="true">
                    <Icon name="lock" size={1.6} />
                  </span>
                )}
              </div>

              <div className="spec-card__body">
                <h2>{species.displayName}</h2>
                <p className="spec-card__latin">{species.scientificName}</p>
                <p className="rarity" style={{
                    background: `var(--rarity-${species.rarity})`,
                    color: `var(--rarity-ink-${species.rarity})`,
                  }}>
                  {RARITY_NAMES[species.rarity]}
                </p>

                {found && entry !== null ? (
                  <dl className="spec-card__facts">
                    <div><dt>Grown</dt><dd>{entry.timesGrown}×</dd></div>
                    <div><dt>Time in it</dt><dd>{formatDuration(entry.totalFocusMinutes)}</dd></div>
                    {entry.fastestGrowthMinutes >= 0 && (
                      <div><dt>Best</dt><dd>{formatDuration(entry.fastestGrowthMinutes)}</dd></div>
                    )}
                  </dl>
                ) : (
                  <p className="spec-card__hint">Not grown yet.</p>
                )}
              </div>

              {found && (
                <button
                  type="button"
                  className="spec-card__fav"
                  aria-pressed={entry?.favorite === true}
                  aria-label={
                    entry?.favorite === true
                      ? `Remove ${species.displayName} from favourites`
                      : `Add ${species.displayName} to favourites`
                  }
                  onClick={() => toggleFavouriteSpecies(species.id)}
                >
                  <Icon name="star" />
                </button>
              )}
            </article>
          );
        })}
      </div>
    </>
  );
}
