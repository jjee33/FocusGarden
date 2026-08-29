/**
 * Defensive readers for deserializing player data. Port of systems/util/dict_util.gd.
 *
 * Save files are JSON that may have been written by an older version, hand-edited,
 * or truncated. Every read goes through here so a missing or wrong-typed key
 * produces a sane default instead of a crash or a silently corrupt value.
 *
 * The GDScript original absorbs the fact that JSON has one number type, so ints
 * arrive as floats. TypeScript has the same problem for the same reason, and the
 * same answer: `getInt` truncates whatever number it finds.
 *
 * NOTE ON BOOLEANS AND NaN: the GDScript checks are `value is float or value is int`.
 * In JavaScript `typeof true === "boolean"`, so a bool cannot slip through as a
 * number the way it would with a loose truthiness check. NaN is a number in JS but
 * not in GDScript's JSON output, so it is rejected explicitly.
 */

export type Json = Record<string, unknown>;

function isNumber(value: unknown): value is number {
  return typeof value === "number" && Number.isFinite(value);
}

export function getString(data: Json, key: string, fallback = ""): string {
  const value = data[key];
  return typeof value === "string" ? value : fallback;
}

export function getInt(data: Json, key: string, fallback = 0): number {
  const value = data[key];
  return isNumber(value) ? Math.trunc(value) : fallback;
}

export function getFloat(data: Json, key: string, fallback = 0): number {
  const value = data[key];
  return isNumber(value) ? value : fallback;
}

export function getBool(data: Json, key: string, fallback = false): boolean {
  const value = data[key];
  return typeof value === "boolean" ? value : fallback;
}

export function getDict(data: Json, key: string): Json {
  const value = data[key];
  return isPlainObject(value) ? value : {};
}

export function getArray(data: Json, key: string): unknown[] {
  const value = data[key];
  return Array.isArray(value) ? value : [];
}

/**
 * String array with non-string entries dropped rather than coerced, so a
 * corrupted entry cannot masquerade as a valid id.
 */
export function getStringArray(data: Json, key: string): string[] {
  return getArray(data, key).filter((entry): entry is string => typeof entry === "string");
}

/** Arrays are objects in JavaScript; a JSON object never is one here. */
function isPlainObject(value: unknown): value is Json {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
