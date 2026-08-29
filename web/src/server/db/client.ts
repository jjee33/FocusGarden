/**
 * The Drizzle instance.
 *
 * The one file that knows the database is D1. Everything else takes a `Database`
 * and never asks what is underneath it.
 */

import { drizzle } from "drizzle-orm/d1";
import type { DrizzleD1Database } from "drizzle-orm/d1";

import type { Env } from "../env.js";
import { schema } from "./schema.js";

export type Database = DrizzleD1Database<typeof schema>;

export function createDatabase(env: Env): Database {
  // The cast is contained here on purpose: `D1Like` exists so that shared code
  // never has to name a Cloudflare type, and this is the single place the real
  // shape is reintroduced.
  return drizzle(env.DB as never, { schema });
}
