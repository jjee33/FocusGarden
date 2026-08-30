/**
 * The Worker: one entry serving the app and its API.
 *
 * Hono because it runs unchanged on Workers AND on Node - the portability hinge
 * the whole server design turns on. Nothing in here imports a Cloudflare type;
 * the platform arrives as `Env`, and `adapters/` is the only place that knows
 * which platform it is.
 *
 * Static assets are handled by the platform's own asset binding rather than by
 * this code. On Cloudflare that means they never reach the Worker at all, which
 * is why they are free and unmetered.
 */

import { Hono } from "hono";
import { cors } from "hono/cors";
import { secureHeaders } from "hono/secure-headers";

import type { AppBindings } from "./context.js";
import { assertEnv } from "./env.js";
import { createDatabase } from "./db/client.js";
import { createAuth } from "./auth.js";
import { syncRoutes } from "./routes/sync.js";

export function createApp() {
  const app = new Hono<AppBindings>();

  app.use("*", secureHeaders());

  // The app and the API are one origin, so cross-origin requests are not part of
  // any legitimate flow. The allowance exists only for local development, where
  // Vite serves on a different port.
  app.use("/api/*", async (c, next) => {
    const handler = cors({
      origin: c.env.APP_URL,
      credentials: true,
      allowMethods: ["GET", "POST", "OPTIONS"],
    });
    return handler(c, next);
  });

  /**
   * Health runs BEFORE the config check, and reports what is missing by name.
   *
   * It was behind the assertion, which meant the one endpoint you would reach
   * for to diagnose a misconfigured deployment was the one guaranteed to fail
   * from the misconfiguration - a 500 with no clue in it. Names only: knowing
   * that RESEND_API_KEY is unset is diagnosis, printing its value is a leak.
   */
  app.get("/api/health", (c) => {
    const required = [
      "APP_URL", "BETTER_AUTH_SECRET", "GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET",
      "RESEND_API_KEY", "MAIL_FROM",
    ] as const;
    const env = c.env as unknown as Record<string, unknown>;
    const missing = required.filter((key) => {
      const value = env[key];
      return value === undefined || value === "";
    });
    const hasDatabase = c.env.DB !== undefined;
    return c.json({
      ok: missing.length === 0 && hasDatabase,
      database: hasDatabase ? "bound" : "missing",
      missing,
    }, missing.length === 0 && hasDatabase ? 200 : 503);
  });

  app.use("/api/*", async (c, next) => {
    assertEnv(c.env);
    c.set("db", createDatabase(c.env));
    await next();
  });

  /** better-auth owns everything under here: sign-in, callbacks, verification. */
  app.on(["GET", "POST"], "/api/auth/*", (c) => createAuth(c.env).handler(c.req.raw));

  /**
   * Everything past this point needs an account.
   *
   * 401 with no body: a sync endpoint is called by code, not read by a person,
   * and an error page shaped like a login prompt is what makes a client retry
   * forever against HTML it cannot parse.
   */
  app.use("/api/sync/*", async (c, next) => {
    const auth = createAuth(c.env);
    const result = await auth.api.getSession({ headers: c.req.raw.headers });
    if (result === null) return c.json({ error: "Not signed in." }, 401);
    c.set("user", {
      id: result.user.id,
      email: result.user.email,
      name: result.user.name,
    });
    await next();
  });

  app.route("/api/sync", syncRoutes());

  app.notFound((c) => c.json({ error: "No such endpoint." }, 404));

  app.onError((error, c) => {
    // The message is logged, never returned. A stack trace in a response body is
    // a map of the server handed to whoever asked for it.
    console.error("Unhandled:", error);
    return c.json({ error: "Something went wrong. Nothing was changed." }, 500);
  });

  return app;
}

export default createApp();
