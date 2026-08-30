/**
 * The whole garden as one SaveBundle, for a client that cannot do a real merge.
 *
 * The browser syncs record by record through /api/sync and reconciles in
 * domain/sync.ts. The desktop app cannot: reimplementing that merge in GDScript
 * would be a second copy of the hardest logic in this project, kept in step by
 * hope. It already reads and writes SaveBundle files, so it exchanges whole
 * bundles instead.
 *
 * THIS REPLACES, IT DOES NOT MERGE, and that is why neither direction is wired
 * to a timer. Whole-garden last-write-wins is a fine primitive when a person is
 * choosing explicitly - "send mine up", "bring theirs down" - and a catastrophe
 * on a schedule. The desktop is required to say which it is doing and what it
 * will cost before either call.
 *
 * Authentication comes from the /api/sync/* guard, so this accepts a browser
 * session or a device token without knowing which it got.
 */

import { Hono } from "hono";

import type { AppBindings } from "../context.js";
import { buildBundle, readBundle } from "../../domain/save-bundle.js";
import { MigrationStatus, migrate } from "../../domain/migrations.js";
import type { Json } from "../../domain/dict-util.js";
import { readGarden, replaceGarden } from "./bundle-store.js";

export function bundleRoutes() {
  const routes = new Hono<AppBindings>();

  /** Everything this account has, in the format the desktop already reads. */
  routes.get("/bundle", async (c) => {
    const { save, sessions } = await readGarden(c.get("db"), c.get("user").id);
    return c.json(buildBundle(save, sessions, "web"));
  });

  /**
   * Replaces everything this account has with the supplied bundle.
   *
   * Validated completely before a single row is touched. A bundle from a newer
   * version, or one that cannot be migrated, is refused here rather than
   * half-applied - the same contract the desktop and the web importer already
   * hold, for the same reason.
   */
  routes.post("/bundle", async (c) => {
    const body = await c.req.json<Json>().catch(() => null);
    if (body === null) return c.json({ error: "That was not JSON." }, 400);

    const migration = migrate(body);
    if (migration.status !== MigrationStatus.OK) {
      return c.json({
        error: migration.status === MigrationStatus.FUTURE_VERSION
          ? "That bundle was written by a newer version of Focus Garden."
          : "That bundle's save format cannot be read by this version.",
      }, 400);
    }

    const imported = readBundle(migration.data);
    const result = await replaceGarden(c.get("db"), c.get("user").id, imported.save, imported.sessions);

    return c.json({
      replaced: true,
      plants: result.plants,
      sessions: result.sessions,
      revision: result.revision,
    });
  });

  return routes;
}
