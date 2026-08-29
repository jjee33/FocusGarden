/**
 * Comparing release versions. Port of systems/util/version_util.gd.
 *
 * Versions are MAJOR.MINOR.PATCH and are compared component by component as
 * integers, never as strings - "0.10.0" sorts before "0.9.0" lexically, which
 * would strand every player on 0.9 the moment the tenth minor release shipped.
 *
 * Nothing here trusts its argument: anything unparseable reads as 0.0.0 and
 * therefore never looks newer than what is already installed.
 */

import { mini } from "./gd.js";

export const PARTS = 3;

/** Digits and nothing else, so a leading sign cannot smuggle a negative in. */
function isDigits(text: string): boolean {
  if (text === "") return false;
  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i);
    if (code < 48 || code > 57) return false;
  }
  return true;
}

/**
 * Numeric components, or null when the string is not a version at all.
 * `strict` demands exactly three, which is what a manifest has to carry; the
 * lenient form pads a short version so ordering is defined for anything parseable.
 */
function components(version: string, strict: boolean): [number, number, number] | null {
  let cleaned = version.trim();
  // Git tags carry a leading v, and a manifest generated from one may keep it.
  if (cleaned.startsWith("v") || cleaned.startsWith("V")) cleaned = cleaned.slice(1);

  // Drop a pre-release or build suffix: "1.2.3-beta.1" compares as 1.2.3. The
  // truncation happens first and the numeric check second, so "1.-2.0" is
  // rejected as garbage rather than read as a bare "1" carrying a suffix.
  let cut = cleaned.length;
  for (const marker of ["-", "+"]) {
    const found = cleaned.indexOf(marker);
    if (found !== -1) cut = mini(cut, found);
  }
  cleaned = cleaned.slice(0, cut);

  const pieces = cleaned.split(".");
  if (pieces.length > PARTS) return null;
  if (strict && pieces.length !== PARTS) return null;

  const parsed: [number, number, number] = [0, 0, 0];
  for (let i = 0; i < pieces.length; i++) {
    const piece = pieces[i]!;
    if (!isDigits(piece)) return null;
    parsed[i as 0 | 1 | 2] = Number(piece);
  }
  return parsed;
}

/** Three integers, reading anything unparseable as 0.0.0. */
export function parse(version: string): [number, number, number] {
  return components(version, false) ?? [0, 0, 0];
}

/** -1 if a is older than b, 0 if they match, 1 if a is newer. */
export function compare(a: string, b: string): number {
  const left = parse(a);
  const right = parse(b);
  for (let i = 0; i < PARTS; i++) {
    if (left[i as 0 | 1 | 2] < right[i as 0 | 1 | 2]) return -1;
    if (left[i as 0 | 1 | 2] > right[i as 0 | 1 | 2]) return 1;
  }
  return 0;
}

/** True when `candidate` is a release the player does not have yet. */
export function isNewer(candidate: string, current: string): boolean {
  return compare(candidate, current) > 0;
}

/** True when the string is a well-formed MAJOR.MINOR.PATCH version. */
export function isValid(version: string): boolean {
  return components(version, true) !== null;
}
