/**
 * Unique identifier generation for player-owned records.
 * Port of systems/util/uid.gd.
 *
 * Ids are time-prefixed so they sort chronologically when listed, with random
 * suffix bits for collision resistance - duplicated ids are called out as a case
 * to handle, not to hope against.
 */

const RANDOM_BITS = 8;
const HEX = "0123456789abcdef";

/**
 * Returns an id like "s_1m9k3xq2-4f7a1c9e". The prefix names the record kind so
 * a stray id in a log or save file is self-describing.
 */
export function generate(prefix: string, nowUnixUtc = Date.now() / 1000): string {
  const stamp = Math.trunc(nowUnixUtc * 1000).toString(36);
  let random = "";
  for (let i = 0; i < RANDOM_BITS; i++) {
    random += HEX[Math.floor(Math.random() * 16)];
  }
  return `${prefix}_${stamp}-${random}`;
}

/**
 * True when `id` looks like something we generated. Used on load to reject
 * malformed ids rather than letting them poison lookups.
 */
export function isValid(id: string): boolean {
  return id !== "" && id.includes("_") && id.includes("-");
}
