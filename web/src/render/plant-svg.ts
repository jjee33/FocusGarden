/**
 * Draws plants and pots procedurally as SVG. Port of ui/plants/plant_painter.gd.
 *
 * WHY PROCEDURAL: sixteen species across three growth stages is eighty pieces of
 * artwork, and every later species multiplies it again. Drawing from a compact
 * morphology description instead gives every plant the same hand, scales cleanly
 * to any DPI, and lets growth stages interpolate smoothly rather than popping
 * between frames - which is the thing the player is actually watching.
 *
 * WHAT THIS ADDS OVER THE GODOT PAINTER. The geometry below is a faithful port;
 * the materials are not, because they could not be. `draw_colored_polygon` offers
 * a flat fill and one darkened outline, so every plant on the desktop reads as
 * flat vector art. SVG has gradients, so leaves shade along their own midrib,
 * pots get a body gradient and a glaze highlight, foliage darkens with depth, and
 * every plant sits on a contact shadow instead of floating. Same shapes, real
 * light. Each layer can be switched off through `materials`, which is how the
 * before/after comparison is produced.
 *
 * LEAVES ARE INSTANCED, and this is load-bearing rather than tidiness. Emitting
 * full path data per leaf measured ~57 KB for one specimen, so a thirty-plant
 * garden would have been ~1.7 MB of DOM. One unit-length leaf in <defs>, placed
 * with <use> and a translate/rotate/scale transform, is ~5 KB for the same plant.
 * The unit leaf is legitimate because a leaf's outline depends only on the
 * morphology and on `growth`, both constant across one plant - `length` scales it
 * uniformly and `angle` is a rigid rotation.
 *
 * GRAIN IS NOT DRAWN HERE. It belongs to the scene, as one static overlay behind
 * everything, not one filter per plant - see the `.fg-grain` rule in app/theme.css,
 * which is its single definition. Measured at 8.3 ms median frame time with the
 * overlay on and off, identical, so it is free where it sits.
 */

import { TAU, bezier, clampf, lerpf } from "./math.js";
import type { Rgb } from "./color.js";
import {
  applyAmbient, darkened, hashSeed, hueShift, lerpColor, lightened, parseColor, seededRandom, toHex,
} from "./color.js";
import type { PlantMorphology } from "../domain/species.js";
import type { PotStyle } from "../domain/pot.js";

// --- Constants, from the painter ---------------------------------------------

/** Outline darkness applied to any fill: a drawn edge, not a cartoon stroke. */
const OUTLINE_DARKEN = 0.3;
const OUTLINE_WIDTH = 1.6;
/** Samples along a leaf midrib. 14 is indistinguishable from 30 at these sizes. */
const LEAF_SEGMENTS = 14;
/** Pot height as a fraction of the plant's total drawn height. */
const POT_HEIGHT_RATIO = 0.34;
/** Rim height as a fraction of pot height. */
const RIM_HEIGHT_RATIO = 0.16;
/** How far the rim oversails the body each side. Small: too far reads as a saucer. */
const RIM_OVERHANG = 0.515;

export interface Materials {
  /** Per-leaf gradient along the true midrib axis. */
  gradients: boolean;
  /** Foliage darkening with depth, so leaves layer instead of stacking. */
  occlusion: boolean;
  /** The ellipse that makes a pot sit on a surface rather than float above it. */
  contactShadow: boolean;
  /** Glaze highlight down the pot body. */
  specular: boolean;
  /** Seeded per-instance jitter, so two of a species are not identical. */
  variation: boolean;
}

export const FULL_MATERIALS: Materials = {
  gradients: true, occlusion: true, contactShadow: true, specular: true, variation: true,
};

/** Exactly what the Godot painter can express, for the before/after comparison. */
export const FLAT_MATERIALS: Materials = {
  gradients: false, occlusion: false, contactShadow: false, specular: false, variation: false,
};

export interface PlantRenderOptions {
  morphology: PlantMorphology;
  pot?: PotStyle | null;
  /** 0..1. Drives both size and how much foliage has appeared. */
  growth: number;
  /** Idle sway phase in radians. Static here; animation is a CSS concern. */
  sway?: number;
  /** Flowers are the reward for finishing. False suppresses them entirely. */
  bloom?: boolean;
  width: number;
  height: number;
  /** A PlantInstance uid. Seeds the per-instance variation. */
  seed?: string;
  /**
   * 0..1 detail. Scales the NUMBER of drawn elements - leaves, strands, fronds,
   * leaflets - not just path precision.
   *
   * An earlier version only dropped the leaf outline from 14 segments to 8, which
   * measured as an 11% saving and no change at all in node count: leaves are
   * instanced, so the segment count lives in one <defs> path while the fifty
   * placements referencing it are what actually cost. At 56px a pothos was still
   * drawing 56 leaves nobody could resolve.
   */
  lod?: number;
  materials?: Partial<Materials>;
  /** Palette.foliage_ambient: content colours sit down into a dark scene. */
  foliageAmbient?: number;
  /** Palette.moss(), for the seed-stage shoot. */
  seedShootColor?: string;
  /** Adds a class to the foliage group so CSS can sway it. */
  animate?: boolean;
}

/** Trimmed numbers: SVG path data is most of the payload. */
function n(value: number): string {
  const rounded = Math.round(value * 100) / 100;
  return Object.is(rounded, -0) ? "0" : String(rounded);
}

/**
 * `translate(tx ty) rotate(deg) scale(sx sy)` collapsed into one matrix.
 *
 * Shorter to serialise and cheaper to apply - the browser composes exactly this
 * anyway. On a Boston fern's 198 placements the saving is several kilobytes.
 * SVG maps (x,y) to (a*x + c*y + e, b*x + d*y + f).
 */
function placement(tx: number, ty: number, radians: number, sx: number, sy: number): string {
  const cos = Math.cos(radians);
  const sin = Math.sin(radians);
  const t = (v: number): string => {
    const r = Math.round(v * 1000) / 1000;
    return Object.is(r, -0) ? "0" : String(r);
  };
  return `matrix(${t(sx * cos)} ${t(sx * sin)} ${t(-sy * sin)} ${t(sy * cos)} ${n(tx)} ${n(ty)})`;
}

function pointsToPath(points: readonly (readonly [number, number])[]): string {
  if (points.length === 0) return "";
  let d = `M${n(points[0]![0])} ${n(points[0]![1])}`;
  for (let i = 1; i < points.length; i++) d += `L${n(points[i]![0])} ${n(points[i]![1])}`;
  return `${d}Z`;
}

// --- Geometry, ported ---------------------------------------------------------

/** Foliage count for a growth value. At least two, so a young plant reads as one. */
function leafCount(m: PlantMorphology, growth: number): number {
  return Math.max(2, Math.min(m.leafCountMax, 2 + Math.trunc(growth * (m.leafCountMax - 2))));
}

/**
 * Size easing. Early growth is visible quickly - the first session should show an
 * obvious change - and later growth tapers, so maturity still feels earned.
 */
function sizeCurve(growth: number): number {
  return lerpf(0.34, 1.0, Math.sqrt(clampf(growth, 0, 1)));
}

/** Half-width factor at `t`, defining the silhouette of each leaf shape. */
function widthProfile(m: PlantMorphology, t: number, growth: number): number {
  let base = 0;
  switch (m.leafShape) {
    case "oval": base = Math.sin(Math.PI * t); break;
    case "lance": base = Math.pow(Math.sin(Math.PI * t), 0.75) * (1 - t * 0.35); break;
    // Widest low down, with a notched base.
    case "heart": base = Math.sin(Math.PI * Math.pow(t, 0.68)); break;
    case "round": base = Math.sin(Math.PI * t) * 1.25; break;
    case "strap": base = clampf(Math.sin(Math.PI * t) * 2.6, 0, 1) * (1 - t * 0.2); break;
    case "needle": base = Math.sin(Math.PI * t) * 0.35; break;
    case "split": {
      // Fenestration: the edge is pulled toward the midrib at intervals, which
      // reads as a monstera's splits without a concave multi-part polygon.
      const notch = Math.abs(Math.sin(t * Math.PI * 3.5));
      base = Math.sin(Math.PI * t) * lerpf(0.42, 1.0, notch);
      break;
    }
    default: base = Math.sin(Math.PI * t);
  }
  // A young leaf is proportionally narrower, the way new growth actually looks.
  return base * lerpf(0.72, 1.0, clampf(growth, 0, 1));
}

/**
 * Midrib position at `t`, for a unit-length leaf pointing straight up.
 *
 * The painter takes an angle here and bakes the rotation into the polygon. This
 * version always builds at angle 0 and lets the <use> transform rotate it, which
 * is identical - rotation is linear - and is what makes instancing possible.
 */
function unitMidrib(m: PlantMorphology, t: number): readonly [number, number] {
  const tip: readonly [number, number] = [0, -1];
  const control: readonly [number, number] = [m.leafArc, -0.55];
  return bezier([0, 0], control, tip, t);
}

/** Unit leaf outline as a closed path, tip pointing up, ready to be instanced. */
function unitLeafPath(m: PlantMorphology, growth: number, segments: number): string {
  const maxWidth = m.leafWidthRatio;
  const left: [number, number][] = [];
  const right: [number, number][] = [];

  for (let i = 0; i <= segments; i++) {
    const t = i / segments;
    const point = unitMidrib(m, t);
    const ahead = unitMidrib(m, Math.min(1, t + 0.02));
    const behind = unitMidrib(m, Math.max(0, t - 0.02));
    let alongX = ahead[0] - behind[0];
    let alongY = ahead[1] - behind[1];
    if (alongX * alongX + alongY * alongY < 0.0001) {
      alongX = 0;
      alongY = -1;
    }
    const length = Math.hypot(alongX, alongY) || 1;
    const normalX = -alongY / length;
    const normalY = alongX / length;
    const half = widthProfile(m, t, growth) * maxWidth * 0.5;
    left.push([point[0] + normalX * half, point[1] + normalY * half]);
    right.push([point[0] - normalX * half, point[1] - normalY * half]);
  }
  return pointsToPath([...left, ...right.reverse()]);
}

// --- The renderer -------------------------------------------------------------

export function renderPlantSvg(options: PlantRenderOptions): string {
  const {
    morphology: m, pot = null, width, height,
    sway = 0, bloom = true, seed = "", lod = 1,
    foliageAmbient = 1, seedShootColor = "#4F8340", animate = false,
  } = options;
  const mat: Materials = { ...FULL_MATERIALS, ...(options.materials ?? {}) };
  const growth = clampf(options.growth, 0, 1);

  const rand = seededRandom(hashSeed(seed === "" ? "unseeded" : seed));
  const jitterHue = mat.variation ? (rand() - 0.5) * 12 : 0;
  const jitterScale = mat.variation ? 1 + (rand() - 0.5) * 0.1 : 1;
  const jitterLean = mat.variation ? (rand() - 0.5) * 0.14 : 0;

  const tint = (hex: string): Rgb =>
    applyAmbient(hueShift(parseColor(hex), jitterHue), foliageAmbient);

  const leafBase = tint(m.leafColorBase);
  const leafTip = tint(m.leafColorTip);
  const stem = tint(m.stemColor);
  const flowerColor = tint(m.flowerColor);
  const flowerCentre = tint(m.flowerCentreColor);
  const variegationColor = tint(m.variegationColor);

  // The pot base sits on the floor of the box; the plant grows up from there.
  const originX = width / 2;
  const originY = height * 0.955;
  // With a pot, roughly a third of the box is container and the foliage sits on
  // top of it. Planted straight into the ground there is no container to leave
  // room for, so the foliage gets the whole box - otherwise a garden bed shows a
  // plant a third the size it should be.
  const scalePx = height * (pot === null ? 0.98 : 0.74) * jitterScale;
  const potHeight = scalePx * POT_HEIGHT_RATIO;

  const uid = `p${(hashSeed(`${seed}|${m.form}|${width}x${height}`) % 0xffffff).toString(36)}`;
  const defs: string[] = [];
  const body: string[] = [];

  // --- leaf gradients, created lazily and shared ---
  // The painter gives each leaf one flat colour from its position in the plant.
  // Here that colour becomes the midpoint of a gradient running base-to-tip along
  // the leaf's own axis, and depth darkening folds into the same lookup rather
  // than needing an overlay pass. Quantising means a plant defines about a dozen
  // gradients instead of one per leaf.
  const gradientIds = new Map<string, string>();
  function leafFill(shadeT: number, depth: number): string {
    const tone = Math.round(clampf(shadeT, 0, 1) * 7) / 7;
    const shade = mat.occlusion ? Math.round(clampf(depth, 0, 1) * 3) / 3 : 1;
    const key = `${tone}|${shade}`;
    const existing = gradientIds.get(key);
    if (existing !== undefined) return `url(#${existing})`;

    let colour = lerpColor(leafBase, leafTip, tone);
    if (mat.occlusion && shade < 1) colour = darkened(colour, (1 - shade) * 0.26);
    if (!mat.gradients) {
      const id = `${uid}f${gradientIds.size}`;
      gradientIds.set(key, id);
      // No gradient wanted: a solid paint server keeps one code path for <use>.
      defs.push(`<linearGradient id="${id}"><stop offset="0" stop-color="${toHex(colour)}"/></linearGradient>`);
      return `url(#${id})`;
    }
    const id = `${uid}g${gradientIds.size}`;
    gradientIds.set(key, id);
    const root = darkened(colour, 0.14);
    const edge = lerpColor(colour, leafTip, 0.45);
    // y1=1 is the leaf base (bottom of its own bounding box), y2=0 the tip.
    defs.push(
      `<linearGradient id="${id}" x1="0" y1="1" x2="0" y2="0">`
      + `<stop offset="0" stop-color="${toHex(root)}"/>`
      + `<stop offset="0.5" stop-color="${toHex(colour)}"/>`
      + `<stop offset="1" stop-color="${toHex(edge)}"/></linearGradient>`,
    );
    return `url(#${id})`;
  }

  /**
   * Element counts at this detail level. Never below `min`, so a plant at any
   * size still reads as that plant rather than collapsing to a stick.
   */
  const detail = (count: number, min = 2): number =>
    Math.max(min, Math.round(count * clampf(lod, 0.15, 1)));

  // --- the instanced unit leaf ---
  const segments = lod < 0.6 ? 8 : LEAF_SEGMENTS;
  const leafId = `${uid}L`;
  defs.push(
    `<path id="${leafId}" d="${unitLeafPath(m, growth, segments)}"`
    + ` vector-effect="non-scaling-stroke"/>`,
  );
  const outlineStroke = toHex(darkened(leafBase, OUTLINE_DARKEN));

  /** One leaf, grown from `attach` at `angle` (0 = straight up, + = right). */
  function leaf(
    attach: readonly [number, number], length: number, angle: number,
    shadeT: number, depth = 1,
  ): void {
    if (length <= 1) return;
    // stroke, stroke-width, vector-effect and stroke-linejoin are set once on the
    // foliage group and inherited. Repeating them per leaf cost ~90 bytes each,
    // which on a trailing plant's 56 leaves was a third of the whole payload.
    body.push(
      `<use href="#${leafId}"`
      + ` transform="${placement(attach[0], attach[1], angle, length, length)}"`
      + ` fill="${leafFill(shadeT, depth)}"/>`,
    );
    // Variegation: a lighter stripe following the midrib. Cosmetic only.
    if (m.variegation > 0.01) {
      const stripe: [number, number][] = [];
      for (let i = 0; i < 7; i++) {
        const p = unitMidrib(m, i / 6);
        stripe.push([p[0], p[1]]);
      }
      const colour = lerpColor(lerpColor(leafBase, leafTip, shadeT), variegationColor, m.variegation);
      body.push(
        `<polyline points="${stripe.map(([x, y]) => `${n(x)},${n(y)}`).join(" ")}"`
        + ` transform="${placement(attach[0], attach[1], angle, length, length)}"`
        + ` fill="none" stroke="${toHex(colour)}" stroke-width="${n(Math.max(1, length * 0.05 * m.variegation))}"`
        + ` vector-effect="non-scaling-stroke" stroke-linecap="round"/>`,
      );
    }
  }

  /** A filled shape with the painter's darkened ink edge, in one element. */
  function shape(path: string, colour: Rgb, strokeFrom?: Rgb): void {
    body.push(
      `<path d="${path}" fill="${toHex(colour)}"`
      + ` stroke="${toHex(darkened(strokeFrom ?? colour, OUTLINE_DARKEN))}"`
      + ` stroke-width="${OUTLINE_WIDTH}" stroke-linejoin="round"/>`,
    );
  }

  function polyline(points: readonly (readonly [number, number])[], colour: Rgb, w: number): void {
    body.push(
      `<polyline points="${points.map(([x, y]) => `${n(x)},${n(y)}`).join(" ")}"`
      + ` fill="none" stroke="${toHex(colour)}" stroke-width="${n(w)}"`
      + ` stroke-linecap="round" stroke-linejoin="round"/>`,
    );
  }

  function ellipse(cx: number, cy: number, rx: number, ry: number, colour: Rgb): void {
    body.push(
      `<ellipse cx="${n(cx)}" cy="${n(cy)}" rx="${n(rx)}" ry="${n(ry)}"`
      + ` fill="${toHex(colour)}" stroke="none"/>`,
    );
  }

  // --- contact shadow, first so everything sits on it ---
  if (mat.contactShadow) {
    const shadowId = `${uid}s`;
    defs.push(
      `<radialGradient id="${shadowId}">`
      + `<stop offset="0" stop-color="#000" stop-opacity="0.32"/>`
      + `<stop offset="0.62" stop-color="#000" stop-opacity="0.11"/>`
      + `<stop offset="1" stop-color="#000" stop-opacity="0"/></radialGradient>`,
    );
    const spread = pot === null ? scalePx * 0.22 : potHeight * pot.bottomWidthRatio * 0.85;
    body.push(
      `<ellipse cx="${n(originX)}" cy="${n(originY + potHeight * 0.03)}"`
      + ` rx="${n(spread)}" ry="${n(potHeight * 0.13)}" fill="url(#${shadowId})"/>`,
    );
  }

  // --- pot ---
  if (pot !== null) {
    drawPot(pot);
  }

  // Foliage rises from the SOIL SURFACE, at the top of the pot - not from inside
  // its body. Getting this wrong makes every plant look like it was pushed
  // halfway through its container.
  const soil: readonly [number, number] = pot === null
    ? [originX, originY]
    : [originX, originY - (potHeight + potHeight * RIM_HEIGHT_RATIO * 0.4)];

  const foliage: string[] = [];
  const foliageStart = body.length;

  if (growth <= 0.02) {
    // A seed has no foliage at all - just disturbed soil and a hint of a shoot.
    const s = scalePx;
    shape(
      pointsToPath([
        [soil[0] - s * 0.012, soil[1]],
        [soil[0] - s * 0.006, soil[1] - s * 0.05],
        [soil[0] + s * 0.006, soil[1] - s * 0.05],
        [soil[0] + s * 0.012, soil[1]],
      ]),
      applyAmbient(parseColor(seedShootColor), foliageAmbient),
    );
  } else {
    switch (m.form) {
      case "rosette": drawRosette(); break;
      case "upright": drawUpright(); break;
      case "trailing": drawTrailing(); break;
      case "frond": drawFrond(); break;
      case "spike": drawSpike(); break;
      case "succulent": drawSucculent(); break;
      case "cactus": drawCactus(); break;
      case "flowering": drawFlowering(); break;
      default: drawRosette();
    }
  }
  foliage.push(...body.splice(foliageStart));

  const swayClass = animate && m.swayAmount > 0.001 ? ' class="fg-sway"' : "";
  // width/height as well as viewBox: an SVG with only a viewBox has no intrinsic
  // size, so inside a grid `auto` track or a flex item it collapses to nothing.
  return `<svg width="${n(width)}" height="${n(height)}" viewBox="0 0 ${n(width)} ${n(height)}"`
    + ` xmlns="http://www.w3.org/2000/svg" role="img">`
    + `<defs>${defs.join("")}</defs>`
    + body.join("")
    + `<g${swayClass} style="transform-origin:${n(soil[0])}px ${n(soil[1])}px"`
    // stroke and stroke-width inherit into every <use>; vector-effect does NOT
    // (SVG 2 defines it as non-inherited), so it lives on the referenced paths in
    // <defs>. Setting it here instead let each leaf scale its own 1.6px outline by
    // its transform - about 91x - and every plant rendered as a solid blob.
    + ` stroke="${outlineStroke}" stroke-width="${OUTLINE_WIDTH}" stroke-linejoin="round">`
    + foliage.join("")
    + `</g></svg>`;

  // --- Growth forms -----------------------------------------------------------

  /** Leaves radiating from a single crown: aloe, echeveria, spider plant. */
  function drawRosette(): void {
    const count = detail(leafCount(m, growth));
    const length = scalePx * m.leafLengthRatio * sizeCurve(growth);
    // Back-to-front: outer lower leaves first, so the newest central growth sits
    // on top the way a real rosette does.
    for (let i = 0; i < count; i++) {
      const t = i / Math.max(1, count - 1);
      // Alternating outward so the rosette fills evenly rather than sweeping.
      const side = i % 2 === 0 ? 1 : -1;
      const rank = Math.floor(i * 0.5) / Math.max(1, count * 0.5);
      let angle = side * lerpf(0.15, m.spreadRadians, rank);
      const phase = sway + i * 0.7;
      angle += Math.sin(phase) * m.swayAmount * (0.4 + rank) + jitterLean * 0.3;
      leaf(soil, length * lerpf(1.0, 0.68, rank), angle, t, 1 - rank * 0.5);
    }
  }

  /** A central stem with leaves stepping up it: rubber plant, jade, monstera. */
  function drawUpright(): void {
    const count = detail(leafCount(m, growth));
    const stemHeight = scalePx * 0.62 * sizeCurve(growth);
    const lean = Math.sin(sway) * m.swayAmount * 0.5 + jitterLean * 0.5;

    const spine: [number, number][] = [];
    for (let i = 0; i < 9; i++) {
      const t = i / 8;
      spine.push([soil[0] + lean * t * stemHeight * 0.25, soil[1] - stemHeight * t]);
    }
    polyline(spine, stem, Math.max(2, scalePx * 0.018));

    for (let i = 0; i < count; i++) {
      const t = (i + 1) / (count + 1);
      const attach: [number, number] = [
        soil[0] + lean * t * stemHeight * 0.25, soil[1] - stemHeight * t,
      ];
      const side = i % 2 === 0 ? 1 : -1;
      let angle = side * lerpf(m.spreadRadians, m.spreadRadians * 0.45, t);
      angle += Math.sin(sway + i * 0.8) * m.swayAmount;
      const length = scalePx * m.leafLengthRatio * sizeCurve(growth) * lerpf(1.0, 0.6, t);
      leaf(attach, length, angle, t, lerpf(0.62, 1.0, t));
    }
    // Crown leaf, so an upright plant does not end in a bare stem tip.
    leaf(
      [soil[0] + lean * stemHeight * 0.25, soil[1] - stemHeight],
      scalePx * m.leafLengthRatio * sizeCurve(growth) * 0.55,
      Math.sin(sway) * m.swayAmount, 1.0, 1,
    );
  }

  /** Stems arcing outward and down: pothos, string-of-hearts, ivy. */
  function drawTrailing(): void {
    const strands = detail(Math.max(3, Math.min(7, 3 + Math.trunc(growth * 4))), 2);
    const reach = scalePx * 0.42 * sizeCurve(growth);

    for (let s = 0; s < strands; s++) {
      const side = s % 2 === 0 ? 1 : -1;
      const spread = (Math.trunc(s / 2) + 1) / strands;
      const phase = sway + s * 0.9;
      // Strands rise a little, then fall away past the pot rim - that downward
      // turn is what makes a trailing plant read as trailing rather than as a
      // shrub with wide arms.
      const tip: readonly [number, number] = [
        soil[0] + side * reach * (0.7 + spread) + Math.sin(phase) * scalePx * m.swayAmount * 0.5,
        soil[1] + scalePx * 0.16 * spread + Math.cos(phase) * scalePx * 0.012,
      ];
      const control: readonly [number, number] = [
        soil[0] + side * reach * 0.5, soil[1] - scalePx * 0.3,
      ];

      const strand: [number, number][] = [];
      for (let i = 0; i < 13; i++) {
        const p = bezier(soil, control, tip, i / 12);
        strand.push([p[0], p[1]]);
      }
      polyline(strand, stem, Math.max(1.5, scalePx * 0.011));

      const leaves = detail(Math.max(3, Math.min(8, Math.trunc(4 + growth * 4))), 2);
      for (let i = 0; i < leaves; i++) {
        const t = lerpf(0.22, 0.98, i / Math.max(1, leaves - 1));
        const point = bezier(soil, control, tip, t);
        const next = bezier(soil, control, tip, Math.min(1, t + 0.06));
        const dx = next[0] - point[0];
        const dy = next[1] - point[1];
        const len = Math.hypot(dx, dy) || 1;
        // Perpendicular to the strand, flipped each leaf so they alternate.
        let angle = Math.atan2(dx / len, -(dy / len)) + (Math.PI * 0.5 * (i % 2 === 0 ? 1 : -1));
        angle += Math.sin(phase + i) * m.swayAmount * 1.2;
        leaf(point, scalePx * m.leafLengthRatio * 0.34 * sizeCurve(growth), angle, t,
          1 - spread * 0.3);
      }
    }
  }

  /** Arching compound fronds: ferns, palms. */
  function drawFrond(): void {
    const count = detail(Math.max(2, Math.min(m.leafCountMax, 2 + Math.trunc(growth * (m.leafCountMax - 2)))));
    const length = scalePx * m.leafLengthRatio * 1.05 * sizeCurve(growth);
    const bladeId = `${uid}B`;
    defs.push(
      `<path id="${bladeId}" d="M-0.16 0L0.3 0.3L0.62 0.86L0.52 0Z"`
      + ` vector-effect="non-scaling-stroke"/>`,
    );
    // Leaflets are collected and appended after every rachis, so the ribs sit
    // behind the foliage rather than being over-drawn frond by frond.
    const leaflets_out: string[] = [];

    for (let i = 0; i < count; i++) {
      const side = i % 2 === 0 ? 1 : -1;
      const rank = Math.floor(i * 0.5) / Math.max(1, count * 0.5);
      let angle = side * lerpf(0.12, m.spreadRadians, rank);
      angle += Math.sin(sway + i * 0.6) * m.swayAmount + jitterLean * 0.25;

      const tip: readonly [number, number] = [
        soil[0] + Math.sin(angle) * length, soil[1] - Math.cos(angle) * length,
      ];
      // Fronds arch: the control point sits high and inside, pulling the tip over.
      const control: readonly [number, number] = [
        soil[0] + Math.sin(angle) * length * 0.3, soil[1] - Math.cos(angle) * length * 0.85,
      ];

      const rib: [number, number][] = [];
      for (let j = 0; j < 10; j++) {
        const p = bezier(soil, control, tip, j / 9);
        rib.push([p[0], p[1]]);
      }
      polyline(rib, stem, Math.max(1.4, scalePx * 0.01));

      // Leaflets in opposed pairs along the rib. Densely packed and overlapping,
      // because a fern frond reads as one soft mass - spaced-out triangles look
      // like a fish skeleton instead.
      const leaflets = detail(12, 4);
      const depth = 1 - rank * 0.45;
      for (let j = 1; j < leaflets; j++) {
        const t = j / leaflets;
        const point = bezier(soil, control, tip, t);
        const next = bezier(soil, control, tip, Math.min(1, t + 0.06));
        const dx = next[0] - point[0];
        const dy = next[1] - point[1];
        const len = Math.hypot(dx, dy) || 1;
        const ax = dx / len;
        const ay = dy / len;
        // The blade's normal is implicit now: the unit path is authored in the
        // (along, normal) frame, so the placement matrix supplies both axes.
        // Widest in the middle of the frond, tapering at both ends.
        const size = length * 0.3 * Math.sin(Math.PI * clampf(t * 0.85 + 0.15, 0, 1));
        let shade = lerpColor(leafBase, leafTip, t);
        if (mat.occlusion) shade = darkened(shade, (1 - depth) * 0.24);
        // Instanced for the same reason leaves are: a fern is up to 13 fronds of
        // 11 opposed leaflet pairs, which as explicit quads was 286 full paths and
        // made Boston fern twice the size of any other specimen. The blade is a
        // fixed shape in the (along, normal) frame, so one unit path serves all of
        // them; scale(size, -size) mirrors it to the far side of the rachis.
        const radians = Math.atan2(ay, ax);
        const fill = toHex(shade);
        const stroke = toHex(darkened(shade, OUTLINE_DARKEN));
        for (const dir of [1, -1]) {
          leaflets_out.push(
            `<use href="#${bladeId}"`
            + ` transform="${placement(point[0], point[1], radians, size, dir * size)}"`
            + ` fill="${fill}" stroke="${stroke}"/>`,
          );
        }
      }
    }
    body.push(...leaflets_out);
  }

  /** Tall stiff blades: snake plant. */
  function drawSpike(): void {
    const count = detail(leafCount(m, growth));
    // No extra multiplier: spike species already carry a long leaf ratio, and
    // stacking a second one made them overflow whatever box they were drawn in.
    const length = scalePx * m.leafLengthRatio * sizeCurve(growth);
    for (let i = 0; i < count; i++) {
      const spread = i / Math.max(1, count - 1) - 0.5;
      let angle = spread * m.spreadRadians * 0.9;
      angle += Math.sin(sway + i * 0.5) * m.swayAmount * 0.35;
      const length2 = length * (0.75 + 0.25 * Math.cos(spread * Math.PI));
      leaf(soil, length2, angle, i / Math.max(1, count), 1 - Math.abs(spread) * 0.7);
    }
  }

  /** Tight fleshy rosette: echeveria, jade offsets. */
  function drawSucculent(): void {
    const rings = 3;
    const length = scalePx * m.leafLengthRatio * sizeCurve(growth);
    const breathe = 1 + Math.sin(sway) * m.swayAmount * 0.15;

    for (let ring = 0; ring < rings; ring++) {
      const ringT = ring / (rings - 1);
      const perRing = detail(8 - ring * 2, 3);
      const ringLength = length * lerpf(1.0, 0.45, ringT) * breathe;
      if (growth < ringT * 0.8) continue;
      for (let i = 0; i < perRing; i++) {
        const angle = (TAU * i) / perRing + ringT * 0.4;
        // Projected to an ellipse so the rosette reads as seen from above and
        // slightly in front, matching the reference's three-quarter view.
        const dx = Math.sin(angle);
        const dy = -Math.cos(angle) * 0.55;
        const dl = Math.hypot(dx, dy) || 1;
        const nx = -dy / dl;
        const ny = dx / dl;
        const w = ringLength * 0.42;
        let colour = lerpColor(leafBase, leafTip, ringT);
        // Blades on the far side of the ellipse sit behind the near ones.
        if (mat.occlusion) colour = darkened(colour, dy < 0 ? 0.16 : 0);
        shape(
          pointsToPath([
            [soil[0], soil[1]],
            [soil[0] + nx * w * 0.5 + dx * ringLength * 0.45,
              soil[1] + ny * w * 0.5 + dy * ringLength * 0.45],
            [soil[0] + dx * ringLength, soil[1] + dy * ringLength],
            [soil[0] - nx * w * 0.5 + dx * ringLength * 0.45,
              soil[1] - ny * w * 0.5 + dy * ringLength * 0.45],
          ]),
          colour, leafBase,
        );
      }
    }
  }

  /** Columnar body with areoles: moon cactus and friends. */
  function drawCactus(): void {
    const h = scalePx * 0.5 * sizeCurve(growth);
    const w = h * 0.52;
    const lean = Math.sin(sway) * m.swayAmount * 0.25 + jitterLean * 0.2;

    const outline: [number, number][] = [];
    for (let i = 0; i <= 20; i++) {
      const t = i / 20;
      const half = w * 0.5 * Math.sin(Math.PI * clampf(t * 0.92 + 0.08, 0, 1));
      outline.push([soil[0] - half + lean * t * h * 0.1, soil[1] - h * t]);
    }
    for (let i = 20; i >= 0; i--) {
      const t = i / 20;
      const half = w * 0.5 * Math.sin(Math.PI * clampf(t * 0.92 + 0.08, 0, 1));
      outline.push([soil[0] + half + lean * t * h * 0.1, soil[1] - h * t]);
    }

    if (mat.gradients) {
      const id = `${uid}c`;
      defs.push(
        `<linearGradient id="${id}" x1="0" y1="0" x2="1" y2="0">`
        + `<stop offset="0" stop-color="${toHex(lightened(leafBase, 0.16))}"/>`
        + `<stop offset="0.4" stop-color="${toHex(leafBase)}"/>`
        + `<stop offset="1" stop-color="${toHex(darkened(leafBase, 0.22))}"/></linearGradient>`,
      );
      body.push(
        `<path d="${pointsToPath(outline)}" fill="url(#${id})"`
        + ` stroke="${toHex(darkened(leafBase, OUTLINE_DARKEN))}" stroke-width="${OUTLINE_WIDTH}"/>`,
      );
    } else {
      shape(pointsToPath(outline), leafBase);
    }

    for (let rib = 0; rib < 3; rib++) {
      const offset = (rib - 1) * w * 0.22;
      const line: [number, number][] = [];
      for (let i = 0; i < 9; i++) {
        const t = lerpf(0.12, 0.92, i / 8);
        line.push([soil[0] + offset * Math.sin(Math.PI * t) + lean * t * h * 0.1, soil[1] - h * t]);
      }
      polyline(line, leafTip, Math.max(1, scalePx * 0.008));
    }

    // Flowers are the reward for finishing, not for getting close.
    if (m.hasFlowers && bloom && growth > 0.75) {
      drawBloom([soil[0] + lean * h * 0.1, soil[1] - h], scalePx * 0.1, sway);
    }
  }

  /** Stems carrying blooms: peace lily, lavender, sunflower, orchid. */
  function drawFlowering(): void {
    // The foliage clump first, so blooms sit in front of their own leaves.
    const count = detail(Math.max(2, leafCount(m, growth) - 2));
    const length = scalePx * m.leafLengthRatio * 0.8 * sizeCurve(growth);
    for (let i = 0; i < count; i++) {
      const side = i % 2 === 0 ? 1 : -1;
      const rank = Math.floor(i * 0.5) / Math.max(1, count * 0.5);
      let angle = side * lerpf(0.2, m.spreadRadians, rank);
      angle += Math.sin(sway + i * 0.7) * m.swayAmount * 0.7;
      leaf(soil, length * lerpf(1.0, 0.7, rank), angle, rank, 1 - rank * 0.4);
    }

    // Blooms only once the plant is established, and only once it has actually
    // finished - a seedling with flowers on it would undercut the whole point of
    // watching something grow, and so would a plant that peaked before maturity.
    if (growth < 0.55 || !bloom) return;
    const progress = clampf((growth - 0.55) / (1.0 - 0.55), 0, 1);
    const stalks = Math.max(1, Math.min(m.flowerCount, 1 + Math.trunc(progress * m.flowerCount)));
    // Stalks clear the foliage by a little, not by a lot. Taller stalks left the
    // blooms floating in space, visually detached from the plant carrying them.
    const stalkHeight = Math.max(scalePx * 0.34, scalePx * m.leafLengthRatio * 1.15)
      * sizeCurve(growth);

    for (let i = 0; i < stalks; i++) {
      const side = i % 2 === 0 ? 1 : -1;
      const offset = side * scalePx * 0.06 * (Math.trunc(i / 2) + 1);
      const phase = sway + i * 1.1;
      const tip: readonly [number, number] = [
        soil[0] + offset + Math.sin(phase) * scalePx * m.swayAmount * 0.6,
        soil[1] - stalkHeight,
      ];
      const control: readonly [number, number] = [
        soil[0] + offset * 0.4, soil[1] - stalkHeight * 0.6,
      ];
      const stalk: [number, number][] = [];
      for (let j = 0; j < 9; j++) {
        const p = bezier(soil, control, tip, j / 8);
        stalk.push([p[0], p[1]]);
      }
      polyline(stalk, stem, Math.max(1.4, scalePx * 0.011));
      drawBloom(tip, scalePx * 0.085 * progress, phase);
    }
  }

  function drawBloom(centre: readonly [number, number], radius: number, phase: number): void {
    if (radius <= 0.5) return;
    const [cx, cy] = centre;
    switch (m.flowerShape) {
      case "daisy": {
        for (let i = 0; i < 8; i++) {
          const angle = (TAU * i) / 8 + phase * 0.15;
          ellipse(cx + Math.cos(angle) * radius * 0.72, cy + Math.sin(angle) * radius * 0.72,
            radius * 0.52, radius * 0.36, flowerColor);
        }
        ellipse(cx, cy, radius * 0.45, radius * 0.45, flowerCentre);
        break;
      }
      case "spire": {
        // A lavender-style raceme: small florets stacked up the stem.
        for (let i = 0; i < 7; i++) {
          const t = i / 6;
          ellipse(cx + Math.sin(phase + t * 3) * radius * 0.2, cy + radius * 1.6 * t,
            radius * 0.34 * (1 - t * 0.45), radius * 0.5 * (1 - t * 0.4), flowerColor);
        }
        break;
      }
      case "spathe": {
        // Peace lily: a broad bract curling behind a narrow upright spadix, built
        // as a pointed oval so it reads as a cupped petal rather than a sliver.
        const bract: [number, number][] = [];
        for (let i = 0; i < 15; i++) {
          const t = i / 14;
          bract.push([cx + Math.sin(Math.PI * Math.pow(t, 0.75)) * radius * 1.15,
            cy - radius * 2 * t + radius * 0.4]);
        }
        for (let i = 14; i >= 0; i--) {
          const t = i / 14;
          bract.push([cx - Math.sin(Math.PI * Math.pow(t, 0.75)) * radius * 0.5,
            cy - radius * 2 * t + radius * 0.4]);
        }
        shape(pointsToPath(bract), flowerColor);
        ellipse(cx + radius * 0.15, cy - radius * 0.55, radius * 0.2, radius * 0.75, flowerCentre);
        break;
      }
      case "cluster": {
        // Five petals radiating outward, each an ellipse oriented along its own
        // spoke. Plain circles read as scattered dots rather than a bloom.
        for (let i = 0; i < 5; i++) {
          const angle = (TAU * i) / 5 - Math.PI * 0.5;
          const px = cx + Math.cos(angle) * radius * 0.62;
          const py = cy + Math.sin(angle) * radius * 0.62;
          body.push(
            `<ellipse cx="${n(px)}" cy="${n(py)}" rx="${n(radius * 0.66)}" ry="${n(radius * 0.4)}"`
            + ` transform="rotate(${n((angle * 180) / Math.PI)} ${n(px)} ${n(py)})"`
            + ` fill="${toHex(flowerColor)}" stroke="${toHex(darkened(flowerColor, OUTLINE_DARKEN))}"`
            + ` stroke-width="${OUTLINE_WIDTH}"/>`,
          );
        }
        ellipse(cx, cy, radius * 0.34, radius * 0.34, flowerCentre);
        break;
      }
      default: break;
    }
  }

  // --- Pot ---------------------------------------------------------------------

  function drawPot(p: PotStyle): void {
    const h = potHeight;
    const topW = h * p.topWidthRatio;
    const bottomW = h * p.bottomWidthRatio;
    const rimH = h * RIM_HEIGHT_RATIO;
    const potBody = applyAmbient(parseColor(p.bodyColor), foliageAmbient);
    const potRim = applyAmbient(parseColor(p.rimColor), foliageAmbient);
    const potAccent = applyAmbient(parseColor(p.accentColor), foliageAmbient);
    const potSoil = applyAmbient(parseColor(p.soilColor), foliageAmbient);

    let outline: [number, number][];
    switch (p.shape) {
      case "rounded":
      case "bowl":
        outline = roundedPotOutline(topW, bottomW, h, p.shape === "bowl");
        break;
      case "cylinder":
        outline = [
          [originX - topW * 0.5, originY], [originX - topW * 0.5, originY - h],
          [originX + topW * 0.5, originY - h], [originX + topW * 0.5, originY],
        ];
        break;
      case "tapered":
      case "basket":
      default:
        outline = [
          [originX - bottomW * 0.5, originY], [originX - topW * 0.5, originY - h],
          [originX + topW * 0.5, originY - h], [originX + bottomW * 0.5, originY],
        ];
    }
    const bodyPath = pointsToPath(outline);

    if (mat.gradients) {
      const id = `${uid}b`;
      defs.push(
        `<linearGradient id="${id}" x1="0" y1="0" x2="1" y2="0">`
        + `<stop offset="0" stop-color="${toHex(lightened(potBody, 0.18))}"/>`
        + `<stop offset="0.38" stop-color="${toHex(potBody)}"/>`
        + `<stop offset="1" stop-color="${toHex(darkened(potBody, 0.24))}"/></linearGradient>`,
      );
      body.push(`<path d="${bodyPath}" fill="url(#${id})"/>`);
    } else {
      body.push(`<path d="${bodyPath}" fill="${toHex(potBody)}"/>`);
    }

    drawPattern(p, topW, bottomW, h, potAccent);

    // The glaze highlight. Terracotta gets a fainter one than a glazed pot would,
    // but every fired surface catches some light down one side.
    if (mat.specular) {
      body.push(
        `<path d="M${n(originX - topW * 0.32)} ${n(originY - h * 0.84)}`
        + `q${n(topW * 0.06)} ${n(h * 0.34)} ${n(bottomW * 0.04)} ${n(h * 0.7)}"`
        + ` fill="none" stroke="#fff" stroke-opacity="0.22"`
        + ` stroke-width="${n(h * 0.08)}" stroke-linecap="round"/>`,
      );
    }

    // Rim: a band across the top, slightly wider than the body, which is what
    // makes a flat shape read as a container with an opening.
    const rimPath = pointsToPath([
      [originX - topW * RIM_OVERHANG, originY - h],
      [originX - topW * RIM_OVERHANG, originY - h - rimH],
      [originX + topW * RIM_OVERHANG, originY - h - rimH],
      [originX + topW * RIM_OVERHANG, originY - h],
    ]);
    if (mat.gradients) {
      const id = `${uid}r`;
      defs.push(
        `<linearGradient id="${id}" x1="0" y1="0" x2="1" y2="0">`
        + `<stop offset="0" stop-color="${toHex(lightened(potRim, 0.14))}"/>`
        + `<stop offset="1" stop-color="${toHex(darkened(potRim, 0.18))}"/></linearGradient>`,
      );
      body.push(
        `<path d="${rimPath}" fill="url(#${id})"`
        + ` stroke="${toHex(darkened(potRim, OUTLINE_DARKEN))}" stroke-width="${OUTLINE_WIDTH}"/>`,
      );
    } else {
      shape(rimPath, potRim);
    }
    body.push(
      `<path d="${bodyPath}" fill="none"`
      + ` stroke="${toHex(darkened(potBody, OUTLINE_DARKEN))}" stroke-width="${OUTLINE_WIDTH}"/>`,
    );

    // Soil last, so it sits in the opening rather than behind the rim outline.
    ellipse(originX, originY - h - rimH * 0.55, topW * 0.47, rimH * 0.5, potSoil);
    if (mat.occlusion) {
      const id = `${uid}o`;
      defs.push(
        `<radialGradient id="${id}">`
        + `<stop offset="0" stop-color="#000" stop-opacity="0.26"/>`
        + `<stop offset="1" stop-color="#000" stop-opacity="0"/></radialGradient>`,
      );
      body.push(
        `<ellipse cx="${n(originX)}" cy="${n(originY - h - rimH * 0.55)}"`
        + ` rx="${n(topW * 0.34)}" ry="${n(rimH * 0.62)}" fill="url(#${id})"/>`,
      );
    }
  }

  function roundedPotOutline(
    topW: number, bottomW: number, h: number, isBowl: boolean,
  ): [number, number][] {
    const belly = isBowl ? 1.0 : 0.72;
    const points: [number, number][] = [];
    for (let i = 0; i < 15; i++) {
      const t = i / 14;
      const w = lerpf(bottomW, topW, t) * 0.5 + Math.sin(Math.PI * t) * h * 0.09 * belly;
      points.push([originX - w, originY - h * t]);
    }
    for (let i = 14; i >= 0; i--) {
      const t = i / 14;
      const w = lerpf(bottomW, topW, t) * 0.5 + Math.sin(Math.PI * t) * h * 0.09 * belly;
      points.push([originX + w, originY - h * t]);
    }
    return points;
  }

  /** Surface decoration, mirroring the painted and woven pots in the reference. */
  function drawPattern(
    p: PotStyle, topW: number, bottomW: number, h: number, accent: Rgb,
  ): void {
    switch (p.pattern) {
      case "bands":
        for (let i = 0; i < 3; i++) {
          const t = 0.3 + i * 0.18;
          const w = lerpf(bottomW, topW, t) * 0.5;
          polyline([[originX - w, originY - h * t], [originX + w, originY - h * t]],
            accent, Math.max(1.5, h * 0.05));
        }
        break;
      case "chevron":
        for (let i = 0; i < 4; i++) {
          const t = 0.24 + i * 0.17;
          const w = lerpf(bottomW, topW, t) * 0.42;
          const y = originY - h * t;
          polyline([[originX - w, y], [originX, y - h * 0.07], [originX + w, y]],
            accent, Math.max(1.2, h * 0.028));
        }
        break;
      case "dots":
        for (let row = 0; row < 3; row++) {
          for (let col = 0; col < 3; col++) {
            const t = 0.28 + row * 0.2;
            const w = lerpf(bottomW, topW, t) * 0.5;
            ellipse(originX + lerpf(-w * 0.62, w * 0.62, col / 2), originY - h * t,
              h * 0.035, h * 0.035, accent);
          }
        }
        break;
      case "weave": {
        // Basketwork: close horizontals with a broken vertical rhythm.
        for (let i = 0; i < 7; i++) {
          const t = 0.08 + i * 0.13;
          const w = lerpf(bottomW, topW, t) * 0.5;
          polyline([[originX - w, originY - h * t], [originX + w, originY - h * t]],
            accent, Math.max(1, h * 0.022));
        }
        for (let i = 0; i < 5; i++) {
          const x = lerpf(-topW * 0.36, topW * 0.36, i / 4);
          polyline([[originX + x, originY - h * 0.1], [originX + x, originY - h * 0.92]],
            darkened(accent, 0.12), Math.max(1, h * 0.016));
        }
        break;
      }
      case "none":
      default:
        break;
    }
  }
}
