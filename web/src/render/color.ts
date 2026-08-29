/**
 * Godot `Color` arithmetic, reproduced exactly.
 *
 * The painter's whole look comes from three operations - `darkened` for the ink
 * edge, `lerp` for base-to-tip shading, and `lightened` for highlights - applied
 * to 0..1 float channels. CSS wants 0-255 hex, so every value crosses that
 * boundary twice per draw. Doing the maths in float space and converting once at
 * the end keeps the results identical to the desktop build; converting first and
 * blending 8-bit integers does not, because the rounding compounds.
 *
 * These are deliberately NOT gamma-correct. Godot's Color.darkened multiplies the
 * raw channel values, so matching it means doing the same naive thing.
 */

export interface Rgb {
  r: number;
  g: number;
  b: number;
}

const HEX = /^#?([0-9a-f]{6})$/i;

export function parseColor(hex: string): Rgb {
  const match = HEX.exec(hex.trim());
  if (match === null) return { r: 0, g: 0, b: 0 };
  const n = parseInt(match[1]!, 16);
  return {
    r: ((n >> 16) & 255) / 255,
    g: ((n >> 8) & 255) / 255,
    b: (n & 255) / 255,
  };
}

export function toHex(c: Rgb): string {
  const channel = (v: number): string => {
    const byte = Math.round(Math.max(0, Math.min(1, v)) * 255);
    return byte.toString(16).padStart(2, "0");
  };
  return `#${channel(c.r)}${channel(c.g)}${channel(c.b)}`;
}

/** Godot `Color.darkened(amount)`: a plain per-channel multiply. */
export function darkened(c: Rgb, amount: number): Rgb {
  const k = 1 - amount;
  return { r: c.r * k, g: c.g * k, b: c.b * k };
}

/** Godot `Color.lightened(amount)`: moves each channel toward 1. */
export function lightened(c: Rgb, amount: number): Rgb {
  return {
    r: c.r + (1 - c.r) * amount,
    g: c.g + (1 - c.g) * amount,
    b: c.b + (1 - c.b) * amount,
  };
}

/** Godot `Color.lerp(to, weight)`. */
export function lerpColor(from: Rgb, to: Rgb, weight: number): Rgb {
  return {
    r: from.r + (to.r - from.r) * weight,
    g: from.g + (to.g - from.g) * weight,
    b: from.b + (to.b - from.b) * weight,
  };
}

/**
 * Multiplies a content colour by the scene's ambient tint.
 *
 * Authored plant and pot colours are the same in both themes - a monstera is
 * green at night too - but they have to sit down into a dark scene rather than
 * glowing out of it. This is `Palette.foliage_ambient`, applied the same way.
 */
export function applyAmbient(c: Rgb, ambient: number): Rgb {
  if (ambient === 1) return c;
  return { r: c.r * ambient, g: c.g * ambient, b: c.b * ambient };
}

/**
 * Rotates hue by `degrees`, for seeded per-instance variation.
 *
 * Not part of the GDScript painter - this exists only so two specimens of the
 * same species are not byte-identical. Kept small at the call site; a large shift
 * would make a species unrecognisable, which the catalogue depends on.
 */
export function hueShift(c: Rgb, degrees: number): Rgb {
  if (degrees === 0) return c;
  const max = Math.max(c.r, c.g, c.b);
  const min = Math.min(c.r, c.g, c.b);
  const delta = max - min;
  const lightness = (max + min) / 2;
  if (delta === 0) return c;

  const saturation = delta / (1 - Math.abs(2 * lightness - 1));
  let hue: number;
  if (max === c.r) hue = ((c.g - c.b) / delta) % 6;
  else if (max === c.g) hue = (c.b - c.r) / delta + 2;
  else hue = (c.r - c.g) / delta + 4;
  hue = (hue * 60 + degrees + 360) % 360;

  const chroma = (1 - Math.abs(2 * lightness - 1)) * saturation;
  const x = chroma * (1 - Math.abs(((hue / 60) % 2) - 1));
  const m = lightness - chroma / 2;
  let rgb: [number, number, number];
  if (hue < 60) rgb = [chroma, x, 0];
  else if (hue < 120) rgb = [x, chroma, 0];
  else if (hue < 180) rgb = [0, chroma, x];
  else if (hue < 240) rgb = [0, x, chroma];
  else if (hue < 300) rgb = [x, 0, chroma];
  else rgb = [chroma, 0, x];
  return { r: rgb[0] + m, g: rgb[1] + m, b: rgb[2] + m };
}

/**
 * Deterministic 32-bit hash of a string, for seeding per-instance variation from
 * a PlantInstance uid. FNV-1a: short, stable across runtimes, and good enough for
 * jitter that nobody is betting money on.
 */
export function hashSeed(text: string): number {
  let hash = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) {
    hash ^= text.charCodeAt(i);
    hash = Math.imul(hash, 0x01000193);
  }
  return hash >>> 0;
}

/** mulberry32, so a specimen looks the same on every redraw and every device. */
export function seededRandom(seed: number): () => number {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
