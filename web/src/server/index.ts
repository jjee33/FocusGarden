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
import { accountRoutes } from "./routes/account.js";
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
   * Health runs BEFORE the config check, and reports what is wrong by name.
   *
   * It was originally behind the assertion, which meant the one endpoint you
   * would reach for to diagnose a misconfigured deployment was the one
   * guaranteed to fail from the misconfiguration.
   *
   * It then checked only that each value was PRESENT, and reported a green
   * deployment whose Resend key was actually a copy of the auth secret pasted
   * into the wrong line. A health check that says ok when it is not is worse
   * than no health check, so each credential is now checked against the shape
   * its issuer gives it. Shapes and names only: knowing that RESEND_API_KEY does
   * not start with `re_` is diagnosis, printing the value would be a leak.
   */
  app.get("/api/health", (c) => {
    const env = c.env as unknown as Record<string, string | undefined>;
    const checks: { key: string; ok: (v: string) => boolean; want: string }[] = [
      { key: "APP_URL", ok: (v) => v.startsWith("http"), want: "an http(s) origin" },
      { key: "BETTER_AUTH_SECRET", ok: (v) => v.length >= 24, want: "24+ random characters" },
      {
        key: "GOOGLE_CLIENT_ID",
        ok: (v) => v.endsWith(".apps.googleusercontent.com"),
        want: "to end with .apps.googleusercontent.com",
      },
      {
        key: "GOOGLE_CLIENT_SECRET",
        ok: (v) => v.startsWith("GOCSPX-"),
        want: "to start with GOCSPX-",
      },
      { key: "RESEND_API_KEY", ok: (v) => v.startsWith("re_"), want: "to start with re_" },
      { key: "MAIL_FROM", ok: (v) => v.includes("@"), want: "an email address" },
    ];

    const missing: string[] = [];
    const malformed: { key: string; want: string }[] = [];
    for (const check of checks) {
      const value = env[check.key];
      if (value === undefined || value === "") missing.push(check.key);
      else if (!check.ok(value)) malformed.push({ key: check.key, want: check.want });
    }

    const hasDatabase = c.env.DB !== undefined;
    const ok = missing.length === 0 && malformed.length === 0 && hasDatabase;
    return c.json({
      ok,
      database: hasDatabase ? "bound" : "missing",
      missing,
      malformed,
    }, ok ? 200 : 503);
  });

  app.use("/api/*", async (c, next) => {
    assertEnv(c.env);
    c.set("db", createDatabase(c.env));
    await next();
  });

  /** better-auth owns everything under here: sign-in, callbacks, verification. */
  app.on(["GET", "POST"], "/api/auth/*", (c) => createAuth(c.env).handler(c.req.raw));

  /**
   * Unauthenticated, and it has to be: the whole point is a way back in for
   * somebody who cannot sign in yet because their verification email never
   * arrived. Rate limiting is what stands in for a session here.
   */
  app.route("/api/account", accountRoutes());

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
