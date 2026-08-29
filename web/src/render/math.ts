/** Small geometry helpers shared by the renderer, matching the GDScript painter. */

export const TAU = Math.PI * 2;

export type Vec2 = readonly [number, number];

export function clampf(value: number, min: number, max: number): number {
  return value < min ? min : value > max ? max : value;
}

export function lerpf(from: number, to: number, weight: number): number {
  return from + (to - from) * weight;
}

/** Quadratic bezier, written the way the painter writes it: nested lerps. */
export function bezier(from: Vec2, control: Vec2, to: Vec2, t: number): Vec2 {
  const ax = lerpf(from[0], control[0], t);
  const ay = lerpf(from[1], control[1], t);
  const bx = lerpf(control[0], to[0], t);
  const by = lerpf(control[1], to[1], t);
  return [lerpf(ax, bx, t), lerpf(ay, by, t)];
}
