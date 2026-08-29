/**
 * Versioned save migration chain. Port of systems/save/save_migrations.gd.
 *
 * The framework exists BEFORE it is needed, and that is deliberate: the first
 * time a save shape changes is exactly when it is too late to design this,
 * because people already have files. The desktop built its chain at version 1
 * "before there was anything to migrate - which is the only time it could have
 * been designed calmly", and the web inherits that discipline rather than
 * rediscovering the reason for it.
 *
 * HOW TO ADD A MIGRATION
 *   1. Bump CURRENT_VERSION in save-data.ts - AND in models/save_data.gd, which
 *      must move in lockstep because SaveBundle is shared between the clients.
 *   2. Append one step to `getChain()` with the new from/to pair.
 *   3. Add a test asserting an old fixture upgrades correctly.
 *
 * Steps are pure Json -> Json transforms so they test without any IO, and are
 * applied strictly in order. A step must NEVER delete data it does not
 * understand: an unknown key from a newer build that a downgrade left behind is
 * harmless, and deleting it is not.
 */

import type { Json } from "./dict-util.js";
import { getDict, getInt, getString } from "./dict-util.js";
import { CURRENT_VERSION } from "./save-data.js";
import { posmod } from "./gd.js";
import { ROTATIONS } from "./garden-layout.js";

export const MigrationStatus = {
  /** Already current, or migrated successfully. */
  OK: "ok",
  /** Save is newer than this build. Refuse, never erase. */
  FUTURE_VERSION: "future_version",
  /** Version gap with no migration step covering it. */
  NO_PATH: "no_path",
} as const;
export type MigrationStatus = (typeof MigrationStatus)[keyof typeof MigrationStatus];

export interface MigrationStep {
  from: number;
  to: number;
  apply: (data: Json) => Json;
}

export interface MigrationResult {
  status: MigrationStatus;
  data: Json;
  fromVersion: number;
  toVersion: number;
  appliedSteps: string[];
}

export function isOk(result: MigrationResult): boolean {
  return result.status === MigrationStatus.OK;
}

/**
 * The ordered chain.
 *
 * 1 -> 2: ornaments and planted specimens gained a facing, and the appearance
 * mode became a setting. Format 1 stored a garden cell as a bare decoration id
 * string; format 2 stores {id, rotation} so an ornament can be turned. Rotation
 * defaults to 0, which is exactly how every existing garden already looks, so
 * this step cannot change what a player sees - it only makes the shape writable.
 */
export function getChain(): MigrationStep[] {
  return [
    {
      from: 1,
      to: 2,
      apply: (data) => {
        const garden = getDict(data, "garden");
        const decorations = getDict(garden, "decorations");
        const upgraded: Json = {};
        for (const [key, entry] of Object.entries(decorations)) {
          if (typeof entry === "object" && entry !== null && !Array.isArray(entry)) {
            upgraded[key] = entry;
          } else if (typeof entry === "string" && entry !== "") {
            upgraded[key] = { id: entry, rotation: 0 };
          }
        }
        garden["decorations"] = upgraded;
        data["garden"] = garden;

        const settings = getDict(data, "settings");
        if (!("theme_mode" in settings)) settings["theme_mode"] = "light";
        data["settings"] = settings;
        return data;
      },
    },
  ];
}

function findStep(chain: MigrationStep[], fromVersion: number): MigrationStep | null {
  return chain.find((step) => step.from === fromVersion) ?? null;
}

/**
 * Upgrades `data` to `targetVersion`, applying each step in order.
 *
 * `chain` is injectable so tests can exercise multi-step upgrades, gaps and
 * future-version refusal without waiting for the app to have real migrations.
 */
export function migrate(
  data: Json,
  targetVersion: number = CURRENT_VERSION,
  chain: MigrationStep[] = getChain(),
): MigrationResult {
  const result: MigrationResult = {
    status: MigrationStatus.OK,
    data: structuredClone(data),
    fromVersion: getInt(data, "save_version", 1),
    toVersion: 0,
    appliedSteps: [],
  };
  result.toVersion = result.fromVersion;

  if (result.fromVersion > targetVersion) {
    // A save written by a NEWER build. We cannot know what its fields mean, and
    // guessing risks destroying real progress. Refuse and preserve.
    result.status = MigrationStatus.FUTURE_VERSION;
    return result;
  }

  let version = result.fromVersion;
  while (version < targetVersion) {
    const step = findStep(chain, version);
    if (step === null) {
      // A gap in the chain. Stop where we are and report it, rather than handing
      // back data that is silently half-migrated.
      result.status = MigrationStatus.NO_PATH;
      result.toVersion = version;
      return result;
    }
    result.data = step.apply(result.data);
    const previous = version;
    version = step.to;
    result.data["save_version"] = version;
    result.appliedSteps.push(`${previous}->${version}`);
  }

  result.toVersion = version;
  result.data["save_version"] = version;
  result.status = MigrationStatus.OK;
  return result;
}

/**
 * Normalises one decoration entry, accepting both shapes. Exported because the
 * bundle reader needs it for a file that skipped the migration.
 */
export function readDecorationEntry(entry: unknown): { id: string; rotation: number } | null {
  if (typeof entry === "string") return entry === "" ? null : { id: entry, rotation: 0 };
  if (typeof entry === "object" && entry !== null && !Array.isArray(entry)) {
    const record = entry as Json;
    const id = getString(record, "id");
    if (id === "") return null;
    return { id, rotation: posmod(getInt(record, "rotation"), ROTATIONS) };
  }
  return null;
}
