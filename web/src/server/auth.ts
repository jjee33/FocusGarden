/**
 * Authentication, via better-auth.
 *
 * Self-hosted rather than bought: it runs inside the same Worker, stores its
 * sessions in the same database, and costs nothing. The whole surface is four
 * tables it owns and a handful of routes it mounts under /api/auth.
 *
 * TWO THINGS THAT BITE, both configuration rather than code:
 *
 *   1. better-auth uses `AsyncLocalStorage`, so the Worker needs the
 *      `nodejs_compat` flag. Without it the very first request throws with an
 *      error that says nothing about the cause.
 *   2. `baseURL` must be the real origin. better-auth builds the OAuth callback
 *      from it, so if it disagrees with what Google has registered the sign-in
 *      fails with a redirect mismatch and no useful detail.
 *
 * The callback Google must know about is, exactly:
 *     {APP_URL}/api/auth/callback/google
 */

import { betterAuth } from "better-auth";
import { drizzleAdapter } from "better-auth/adapters/drizzle";

import type { Env } from "./env.js";
import { createDatabase } from "./db/client.js";
import { schema } from "./db/schema.js";
import { sendMail, verificationEmail, resetPasswordEmail } from "./mail.js";

/**
 * Built per request rather than once at module scope.
 *
 * A Worker isolate is reused across requests from different eyeballs, and the
 * bindings arrive with the request, not with the module. Caching an instance
 * built from one request's env is how a config value leaks between users.
 *
 * The return type is inferred deliberately: better-auth derives a precise type
 * from the options object, and annotating the loose `Auth<BetterAuthOptions>`
 * throws away everything it worked out.
 */
export function createAuth(env: Env) {
  return betterAuth({
    baseURL: env.APP_URL,
    secret: env.BETTER_AUTH_SECRET,
    database: drizzleAdapter(createDatabase(env), { provider: "sqlite", schema }),

    emailAndPassword: {
      enabled: true,
      // Nobody signs in until they have proved they own the address. Turning
      // this off is the difference between an account system and a spam vector.
      requireEmailVerification: true,
      minPasswordLength: 10,
      sendResetPassword: async ({ user, url }) => {
        await sendMail(env, {
          to: user.email,
          subject: "Reset your Focus Garden password",
          ...resetPasswordEmail(url),
        });
      },
    },

    emailVerification: {
      sendOnSignUp: true,
      autoSignInAfterVerification: true,
      sendVerificationEmail: async ({ user, url }) => {
        await sendMail(env, {
          to: user.email,
          subject: "Confirm your email for Focus Garden",
          ...verificationEmail(url),
        });
      },
    },

    socialProviders: {
      google: {
        clientId: env.GOOGLE_CLIENT_ID,
        clientSecret: env.GOOGLE_CLIENT_SECRET,
      },
    },

    session: {
      // Long, because this is a daily-use habit app and being signed out every
      // week is the sort of friction that ends a habit.
      expiresIn: 60 * 60 * 24 * 60,
      updateAge: 60 * 60 * 24,
    },

    advanced: {
      // The API and the app are the same origin, so the cookie never needs to
      // cross sites - and SameSite=Lax is what stops it being sent on one.
      defaultCookieAttributes: {
        sameSite: "lax",
        secure: true,
        httpOnly: true,
      },
    },
  });
}
