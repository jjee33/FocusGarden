/**
 * A plant, rendered.
 *
 * Thin on purpose: the renderer is a pure string function so it can be tested in
 * node without a DOM, and this is the only place that hands its output to React.
 *
 * `dangerouslySetInnerHTML` is the right tool here despite the name. Every byte
 * comes from renderPlantSvg, which emits numbers and colours it computed itself
 * from typed content - no user text reaches it, so there is nothing to inject.
 * The alternative, building the same few hundred elements through JSX, would cost
 * a React fibre per leaf and is the thing the instancing work exists to avoid.
 */

import { memo, useMemo } from "react";

import { posmod } from "../../domain/gd.js";
import { GARDEN_ROTATIONS } from "../../domain/plant-instance.js";
import type { PlantMorphology } from "../../domain/species.js";
import type { PotStyle } from "../../domain/pot.js";
import type { Materials } from "../../render/plant-svg.js";
import { renderPlantSvg } from "../../render/plant-svg.js";

export interface PlantViewProps {
  morphology: PlantMorphology;
  pot?: PotStyle | null;
  growth: number;
  width: number;
  height: number;
  /** A PlantInstance uid, so a specimen looks the same every render. */
  seed?: string;
  lod?: number;
  bloom?: boolean;
  materials?: Partial<Materials>;
  foliageAmbient?: number;
  /** Idle sway. Suppressed by the reduced-motion policy at the call site. */
  animate?: boolean;
  /**
   * 0-3, a quarter turn each. A side-on plant cannot be tipped onto its side and
   * still look like a plant, so a facing MIRRORS it and leans it instead. The
   * point is that a row of one species stops looking like the same plant stamped
   * four times. Only decorations - benches, paths, seen from above - rotate.
   */
  facing?: number;
  /** Describes the plant to a screen reader; the SVG itself is decorative. */
  label?: string;
  className?: string;
}

function PlantViewImpl({
  morphology, pot = null, growth, width, height,
  seed = "", lod = 1, bloom = true, materials, foliageAmbient = 1,
  animate = false, facing = 0, label, className,
}: PlantViewProps) {
  const svg = useMemo(
    () => renderPlantSvg({
      morphology, pot, growth, width, height, seed, lod, bloom,
      foliageAmbient, animate,
      ...(materials === undefined ? {} : { materials }),
    }),
    [morphology, pot, growth, width, height, seed, lod, bloom, materials, foliageAmbient, animate],
  );

  // The odd facings mirror; the upper pair also nudge sideways, so four turns
  // give four distinguishable silhouettes rather than two. FACING_LEAN = 0.045.
  const turn = posmod(facing, GARDEN_ROTATIONS);
  const offset = turn < 2 ? 0 : width * 0.045;
  const transform = turn % 2 === 1
    ? `translateX(${offset}px) scaleX(-1)`
    : `translateX(${offset}px)`;

  return (
    <div
      className={className}
      style={{ lineHeight: 0, transform, transformOrigin: "50% 100%" }}
      role={label === undefined ? "presentation" : "img"}
      {...(label === undefined ? { "aria-hidden": true } : { "aria-label": label })}
      dangerouslySetInnerHTML={{ __html: svg }}
    />
  );
}

/**
 * Memoised because the focus screen re-renders four times a second while a
 * session runs, and the plant only changes when its growth ratio crosses a
 * visible threshold. Without this, every tick would rebuild a few hundred SVG
 * nodes for a plant that has not moved.
 */
export const PlantView = memo(PlantViewImpl);
