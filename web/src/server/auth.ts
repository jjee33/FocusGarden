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
/**
 * Somewhere for a failed send to be noticed by the caller that asked for it.
 *
 * better-auth calls `sendVerificationEmail` deep inside its own handler and
 * nothing it returns reaches the response. Without this, a caller has no way to
 * tell "the mail went" from "the mail was refused", and the resend button would
 * report success against a broken mail key - which is exactly the class of
 * cheerful lie that cost an afternoon here already.
 */
export interface MailReport {
  failed: boolean;
  detail: string;
}

export function createAuth(env: Env, report?: MailReport) {
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
      /**
       * A refused send must not take the account down with it.
       *
       * better-auth writes the user row and THEN calls this, so letting the
       * throw escape produced an account that exists, cannot be verified,
       * cannot be signed into, and answers "already taken" when you try again -
       * a permanent dead end reached by one transient mail outage, and Resend
       * will have one eventually.
       *
       * So the account survives and the failure is reported instead. The person
       * lands on "check your email" with a resend button, and that button - which
       * DOES pass a report - is where a still-broken mail path finally says so.
       */
      sendVerificationEmail: async ({ user, url }) => {
        try {
          await sendMail(env, {
            to: user.email,
            subject: "Confirm your email for Focus Garden",
            ...verificationEmail(url),
          });
        } catch (caught) {
          const detail = caught instanceof Error ? caught.message : String(caught);
          console.error("Verification email failed:", detail);
          if (report === undefined) return;
          report.failed = true;
          report.detail = detail;
        }
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
