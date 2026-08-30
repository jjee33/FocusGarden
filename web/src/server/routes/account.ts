/**
 * The account endpoints that do not belong to better-auth.
 *
 * Just one so far, and it exists because of a specific failure. better-auth
 * writes the user row and then sends the verification email, so a mail outage
 * leaves an account that exists, cannot be verified, cannot be signed into, and
 * reports "already taken" on a second attempt. `auth.ts` now keeps the account
 * alive through such a failure; this is the way back out of it.
 *
 * IT ANSWERS THE SAME WAY WHETHER OR NOT THE ADDRESS EXISTS. An unauthenticated
 * endpoint that says "no account with that email" is a lookup service for
 * whoever asks, and it would undo the care taken over exactly this in
 * `readableAuthError`. The only thing that changes the response is the rate
 * limit, which is a property of the caller rather than of the address.
 */

import { Hono } from "hono";

import type { AppBindings } from "../context.js";
import { createAuth, type MailReport } from "../auth.js";
import { consume, throttleKey } from "../throttle.js";

export function accountRoutes() {
  const routes = new Hono<AppBindings>();

  routes.post("/resend-verification", async (c) => {
    const body = await c.req.json<{ email?: unknown }>().catch(() => ({ email: undefined }));
    const email = typeof body.email === "string" ? body.email.trim() : "";

    // Shape only. Whether it is a real account is deliberately not checked here,
    // and deliberately not visible in the answer.
    if (email === "" || !email.includes("@") || email.length > 320) {
      return c.json({ error: "That does not look like an email address." }, 400);
    }

    const now = Math.floor(Date.now() / 1000);
    const key = await throttleKey("verify", email);
    const decision = await consume(c.get("db"), key, now);
    if (!decision.allowed) {
      return c.json(
        { error: "Give it a minute before asking for another.", retryAfter: decision.retryAfter },
        429,
        { "Retry-After": String(decision.retryAfter) },
      );
    }

    const report: MailReport = { failed: false, detail: "" };
    const auth = createAuth(c.env, report);

    try {
      await auth.api.sendVerificationEmail({ body: { email, callbackURL: "/" } });
    } catch (caught) {
      // An unknown address, or an already-verified one, lands here. Both are
      // ordinary and neither is the caller's business, so both look like success.
      console.warn("Resend verification skipped:", caught instanceof Error ? caught.message : caught);
      return c.json({ sent: true });
    }

    // The one failure worth admitting: the address was fine and the mail still
    // did not go. Saying "sent" here is the cheerful lie this endpoint exists to
    // avoid, and it would leave someone refreshing an inbox forever.
    if (report.failed) {
      console.error("Resend verification failed to send:", report.detail);
      return c.json({ error: "We could not send that email just now. Try again shortly." }, 502);
    }

    return c.json({ sent: true });
  });

  return routes;
}
