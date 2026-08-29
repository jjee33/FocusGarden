/**
 * The persistence layer, pinned against the engine.
 *
 * This is where "probably right" is least acceptable. SaveBundle is the wire
 * format BETWEEN the two clients, so a divergence here does not show up as a
 * wrong pixel - it shows up as a garden that imports smaller than it was
 * exported, which is the one failure the format exists to prevent.
 */

import { describe, expect, it } from "vitest";

import fixture from "../__fixtures__/persistence.json";

import { CURRENT_VERSION, saveDataFromDict, saveDataToDict } from "../save-data.js";
import { gameSettingsFromDict, gameSettingsToDict } from "../game-settings.js";
import { catalogueEntryFromDict, catalogueEntryToDict } from "../catalogue-entry.js";
import { achievementStateFromDict, achievementStateToDict } from "../achievement-state.js";
import { journalEntryFromDict, journalEntryToDict } from "../journal-entry.js";
import { projectCategoryFromDict, projectCategoryToDict } from "../project-category.js";
import { shelfLayoutFromDict, shelfLayoutToDict } from "../shelf-layout.js";
import { gardenLayoutFromDict, gardenLayoutToDict } from "../garden-layout.js";
import { MigrationStatus, migrate } from "../migrations.js";
import { describeRange, readBundle } from "../save-bundle.js";
import * as Version from "../version-util.js";
import type { Json } from "../dict-util.js";

/** The GDScript enum's declaration order, which is what the fixture records. */
const STATUS_BY_ORDINAL: MigrationStatus[] = [
  MigrationStatus.OK,
  MigrationStatus.FUTURE_VERSION,
  MigrationStatus.NO_PATH,
];

/** Every from_dict is asserted the same way: read it, write it, compare. */
function roundTrip<T>(
  cases: { in: unknown; out: unknown }[],
  read: (data: Json) => T,
  write: (value: T) => Json,
  label: string,
): void {
  for (const c of cases) {
    const actual = write(read(c.in as Json));
    expect(actual, `${label}(${JSON.stringify(c.in)})`).toEqual(c.out);
  }
}

describe("Save format version", () => {
  it("matches the desktop build exactly", () => {
    // Not a preference. SaveBundle is shared, so a web build writing a higher
    // version makes every shipped desktop build refuse the file as FUTURE_VERSION.
    expect(CURRENT_VERSION).toBe(fixture.constants.SAVE_CURRENT_VERSION);
  });
});

describe("Defensive load", () => {
  it(`GameSettings clamps every numeric across ${fixture.game_settings_from_dict.length} hostile inputs`, () => {
    roundTrip(
      fixture.game_settings_from_dict, gameSettingsFromDict, gameSettingsToDict, "gameSettings",
    );
  });

  it("CatalogueEntry", () => {
    roundTrip(
      fixture.catalogue_entry_from_dict, catalogueEntryFromDict, catalogueEntryToDict, "catalogue",
    );
  });

  it("AchievementState repairs an unlocked entry claiming partial progress", () => {
    roundTrip(
      fixture.achievement_state_from_dict, achievementStateFromDict, achievementStateToDict,
      "achievementState",
    );
  });

  it("JournalEntry", () => {
    roundTrip(fixture.journal_entry_from_dict, journalEntryFromDict, journalEntryToDict, "journal");
  });

  it("ProjectCategory", () => {
    roundTrip(
      fixture.project_category_from_dict, projectCategoryFromDict, projectCategoryToDict, "project",
    );
  });

  it("ShelfLayout", () => {
    roundTrip(fixture.shelf_layout_from_dict, shelfLayoutFromDict, shelfLayoutToDict, "shelf");
  });

  it("GardenLayout reads the format-1 bare string as well as the format-2 shape", () => {
    roundTrip(fixture.garden_layout_from_dict, gardenLayoutFromDict, gardenLayoutToDict, "garden");
  });

  it("SaveData drops duplicate ids and skips malformed entries", () => {
    roundTrip(fixture.save_data_from_dict, saveDataFromDict, saveDataToDict, "saveData");
  });
});

describe("Migrations", () => {
  it("reproduces every outcome, including the two refusals", () => {
    // The gap case is recorded against an INJECTED chain, not the shipped one, so
    // replaying it here with the real chain would apply the real 1->2 step first
    // and diverge. It has its own test below, which is where it belongs.
    for (const c of fixture.migrate.filter((m) => m.label !== "gap in the chain")) {
      const result = migrate(c.in as Json, c.target);
      const label = `migrate[${c.label}]`;
      expect(result.status, `${label}.status`).toBe(STATUS_BY_ORDINAL[c.status]);
      expect(result.fromVersion, `${label}.fromVersion`).toBe(c.from_version);
      expect(result.toVersion, `${label}.toVersion`).toBe(c.to_version);
      expect(result.appliedSteps, `${label}.appliedSteps`).toEqual(c.applied_steps);
      expect(result.data, `${label}.data`).toEqual(c.data);
    }
  });

  it("refuses a future version without touching the data", () => {
    // The refusal path matters more than the happy one: guessing what a newer
    // build's fields mean risks destroying real progress, so the file is left
    // exactly as found.
    const input = { save_version: 99, player: { total_xp: 500 } };
    const result = migrate(input, 2);
    expect(result.status).toBe(MigrationStatus.FUTURE_VERSION);
    expect(result.data).toEqual(input);
  });

  it("stops at a gap rather than handing back half-migrated data", () => {
    const chain = [{ from: 1, to: 2, apply: (d: Json) => d }];
    const result = migrate({ save_version: 1 }, 4, chain);
    expect(result.status).toBe(MigrationStatus.NO_PATH);
    expect(result.toVersion).toBe(2);
  });

  it("does not mutate its input", () => {
    const input: Json = { save_version: 1, garden: { decorations: { "0,0": "pond" } } };
    const snapshot = structuredClone(input);
    migrate(input, 2);
    expect(input).toEqual(snapshot);
  });
});

describe("VersionUtil", () => {
  it(`parses and orders ${fixture.version_util.length} version strings`, () => {
    for (const c of fixture.version_util) {
      expect(Version.parse(c.version), `parse(${c.version})`).toEqual(c.parse);
      expect(Version.isValid(c.version), `isValid(${c.version})`).toBe(c.is_valid);
      expect(Version.compare(c.version, "1.0.0"), `compare(${c.version})`)
        .toBe(c.compare_to_1_0_0);
      expect(Version.isNewer(c.version, "1.0.0"), `isNewer(${c.version})`)
        .toBe(c.is_newer_than_1_0_0);
    }
  });

  it("orders 0.10.0 after 0.9.0, which a string compare gets backwards", () => {
    expect(Version.isNewer("0.10.0", "0.9.0")).toBe(true);
    expect("0.10.0" > "0.9.0").toBe(false);
  });
});

describe("SaveBundle", () => {
  it("reads the engine's own bundle identically", () => {
    for (const c of fixture.save_bundle.read) {
      const source = c.label === "clean"
        ? fixture.save_bundle.built
        : rebuild(c.label as "damaged" | "no_sessions_key");
      const imported = readBundle(source as Json);
      const label = `readBundle[${c.label}]`;

      expect(imported.summary.sessionCount, `${label}.sessionCount`).toBe(c.summary.session_count);
      expect(imported.summary.breakCount, `${label}.breakCount`).toBe(c.summary.break_count);
      expect(imported.summary.focusMinutes, `${label}.focusMinutes`)
        .toBeCloseTo(c.summary.focus_minutes, 9);
      expect(imported.summary.daysFocused, `${label}.daysFocused`).toBe(c.summary.days_focused);
      expect(imported.summary.hasSessions, `${label}.hasSessions`).toBe(c.summary.has_sessions);
      expect(imported.summary.skippedCount, `${label}.skippedCount`).toBe(c.summary.skipped_count);
      expect(imported.summary.duplicateCount, `${label}.duplicateCount`)
        .toBe(c.summary.duplicate_count);
      expect(imported.summary.plantCount, `${label}.plantCount`).toBe(c.summary.plant_count);
      expect(imported.summary.appVersion, `${label}.appVersion`).toBe(c.summary.app_version);
      expect(imported.sessions.map((s) => s.id), `${label}.sessionIds`).toEqual(c.session_ids);
      expect(describeRange(imported.summary), `${label}.describeRange`)
        .toBe(c.describe_range.replace("–", "-"));
    }
  });

  it("empties the in-flight session so an interrupted pomodoro does not travel", () => {
    expect(fixture.save_bundle.built.in_flight_session).toEqual({});
    // Emptied, NOT removed: the bundle's shape must stay identical to a save's.
    expect("in_flight_session" in fixture.save_bundle.built).toBe(true);
  });

  it("counts the body, never the header", () => {
    // The meta block says four sessions; three of those count toward progress and
    // one is a break. A header is never trusted to describe the body it arrived with.
    expect(fixture.save_bundle.built.export.session_count).toBe(4);
    const imported = readBundle(fixture.save_bundle.built as Json);
    expect(imported.sessions).toHaveLength(4);
    expect(imported.summary.sessionCount).toBe(3);
    expect(imported.summary.breakCount).toBe(1);
  });

  it("survives a migration applied to the whole envelope", () => {
    // The envelope is a SUPERSET of the save dictionary, which is the only reason
    // a migration step can run over a bundle untouched. The extra keys must ride
    // through unchanged.
    const bundle = structuredClone(fixture.save_bundle.built) as Json;
    bundle["save_version"] = 1;
    const result = migrate(bundle, 2);
    expect(result.status).toBe(MigrationStatus.OK);
    expect(Array.isArray(result.data["sessions"])).toBe(true);
    expect((result.data["sessions"] as unknown[]).length).toBe(4);
    expect(result.data["export"]).toEqual(fixture.save_bundle.built.export);
  });
});

/** Mirrors the damage the exporter inflicts, so both sides read the same bytes. */
function rebuild(kind: "damaged" | "no_sessions_key"): Json {
  const bundle = structuredClone(fixture.save_bundle.built) as Json;
  if (kind === "no_sessions_key") {
    delete bundle["sessions"];
    return bundle;
  }
  const rows = [...(bundle["sessions"] as unknown[])];
  rows.push(structuredClone(rows[0]));
  rows.push({ date_key: "2026-08-29", actual_focus_minutes: 10.0 });
  rows.push("not a row");
  bundle["sessions"] = rows;
  return bundle;
}
