import { defineConfig } from "drizzle-kit";

/**
 * Migrations are generated as plain SQL and applied with `wrangler d1 migrations
 * apply`, rather than pushed straight at a live database. A generated file can be
 * read and reviewed before it touches anyone's garden; a push cannot.
 */
export default defineConfig({
  schema: "./src/server/db/schema.ts",
  out: "./drizzle",
  dialect: "sqlite",
  driver: "d1-http",
  verbose: true,
  strict: true,
});
