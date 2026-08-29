/**
 * GDScript numeric semantics, in one place.
 *
 * WHY THIS FILE EXISTS: the domain logic below is a port from GDScript, and the
 * differences between the two languages' arithmetic are all silent. None of them
 * throws; each one just produces a slightly wrong number in a save file.
 *
 *   posmod(-1, 4)     is 3 in GDScript.  -1 % 4 is -1 in JavaScript.
 *   int(-2.7)         is -2 in GDScript.  Math.floor(-2.7) is -3.
 *   7 / 2             is 3 in GDScript when both sides are int. It is 3.5 here.
 *   round(-0.5)       is -1 in GDScript.  Math.round(-0.5) is -0.
 *
 * Every port module goes through these helpers rather than using the operators
 * directly, so the rule is applied once and can be tested once. The fixtures in
 * __fixtures__/ pin each of these against the real engine.
 */

/**
 * Collapses -0 to 0.
 *
 * GDScript's `int` type has no negative zero, so `int(-0.7)` is 0 while
 * `Math.trunc(-0.7)` is -0. The two compare equal under `===`, which is why this
 * hid until the primitives were pinned directly against the engine. It is worth
 * fixing rather than tolerating: `Object.is` separates them, `JSON.stringify`
 * can emit "-0", and `1 / -0` is -Infinity. Every integer-returning helper below
 * normalises through this.
 */
function z(value: number): number {
  return value === 0 ? 0 : value;
}

/** GDScript `posmod`: the result always carries the sign of `b`. */
export function posmod(a: number, b: number): number {
  return z(((a % b) + b) % b);
}

/** GDScript `int(x)` cast, and integer division: both truncate toward zero. */
export function toInt(value: number): number {
  return z(Math.trunc(value));
}

/** GDScript `a / b` where both operands are ints. */
export function intdiv(a: number, b: number): number {
  return z(Math.trunc(a / b));
}

/**
 * GDScript `round()`: halves go away from zero, so round(-0.5) is -1.
 * JavaScript's Math.round breaks ties toward +Infinity, giving -0.
 */
export function gdRound(value: number): number {
  return z(value < 0 ? -Math.round(-value) : Math.round(value));
}

/** GDScript `int(floor(x))`. Separate from toInt because they differ below zero. */
export function floorToInt(value: number): number {
  return z(Math.floor(value));
}

/** GDScript `int(ceil(x))`. */
export function ceilToInt(value: number): number {
  return z(Math.ceil(value));
}

export function clampi(value: number, min: number, max: number): number {
  return value < min ? min : value > max ? max : value;
}

export function clampf(value: number, min: number, max: number): number {
  return value < min ? min : value > max ? max : value;
}

export function maxi(a: number, b: number): number {
  return a > b ? a : b;
}

export function mini(a: number, b: number): number {
  return a < b ? a : b;
}

export function maxf(a: number, b: number): number {
  return a > b ? a : b;
}

export function minf(a: number, b: number): number {
  return a < b ? a : b;
}

export function lerpf(from: number, to: number, weight: number): number {
  return from + (to - from) * weight;
}

/** Zero-padded integer, for the `%02d` forms the GDScript formatters use. */
export function pad2(value: number): string {
  return String(value).padStart(2, "0");
}
