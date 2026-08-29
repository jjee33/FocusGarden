/**
 * What the server needs from its environment.
 *
 * HAND-WRITTEN, and that is the portability rule in one file. Nothing in the
 * app imports `@cloudflare/workers-types` or reaches for a Workers global; it
 * asks for this interface, and an adapter supplies it. Moving to a container
 * later means writing a second adapter, not auditing every module for platform
 * assumptions.
 *
 * `D1Like` is the narrow slice of D1 that Drizzle actually calls. Typing the
 * real thing would drag the Workers types into shared code and quietly make the
 * rule unenforceable.
 */

export interface D1Like {
  prepare: (query: string) => unknown;
  batch: <T = unknown>(statements: unknown[]) => Promise<T[]>;
  exec: (query: string) => Promise<unknown>;
}

export interface Env {
  /** The database. D1 today; a Postgres pool behind the same calls tomorrow. */
  DB: D1Like;

  /** Absolute origin, e.g. https://thefocusgarden.com. better-auth builds its
   *  OAuth callback from this, so a wrong value fails with a redirect mismatch
   *  and no useful detail. */
  APP_URL: string;

  /** Long random string. Rotating it signs everyone out; that is the point. */
  BETTER_AUTH_SECRET: string;

  GOOGLE_CLIENT_ID: string;
  GOOGLE_CLIENT_SECRET: string;

  /** Resend, for verification and password-reset mail. */
  RESEND_API_KEY: string;
  /** The verified sending identity, e.g. Focus Garden <hello@account.thefocusgarden.com>. */
  MAIL_FROM: string;
}

/**
 * Fails loudly at boot rather than at the first sign-in.
 *
 * A missing secret otherwise surfaces as an opaque OAuth error much later, to a
 * user, in production - which is the worst possible place to discover it.
 */
export function assertEnv(env: Partial<Env>): asserts env is Env {
  const required: (keyof Env)[] = [
    "DB", "APP_URL", "BETTER_AUTH_SECRET",
    "GOOGLE_CLIENT_ID", "GOOGLE_CLIENT_SECRET",
    "RESEND_API_KEY", "MAIL_FROM",
  ];
  const missing = required.filter((key) => env[key] === undefined || env[key] === "");
  if (missing.length > 0) {
    throw new Error(
      `Focus Garden is missing configuration: ${missing.join(", ")}. `
      + `Set them with \`wrangler secret put <NAME>\` (or in .dev.vars locally).`,
    );
  }
}
