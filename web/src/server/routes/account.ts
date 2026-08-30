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
import type { Context } from "hono";
import { and, eq } from "drizzle-orm";

import type { AppBindings } from "../context.js";
import { createAuth, type MailReport } from "../auth.js";
import { consume, throttleKey } from "../throttle.js";
import { hashToken, mintToken } from "../device-token.js";
import { deviceToken, user } from "../db/schema.js";

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

  /*
   * The way back in for someone who has forgotten their password.
   *
   * better-auth exposes /api/auth/forget-password directly, and this wraps it for
   * the same reason resend-verification exists: it sends mail to an address an
   * anonymous caller chose, so it needs the same throttle, and it must answer
   * identically whether or not the address is registered.
   *
   * Its own budget, separate from verification. Being unable to reset your
   * password because you asked for a verification link earlier is a lockout
   * wearing a rate limit's clothes.
   */
  routes.post("/forgot-password", async (c) => {
    const body = await c.req.json<{ email?: unknown }>().catch(() => ({ email: undefined }));
    const email = typeof body.email === "string" ? body.email.trim() : "";
    if (email === "" || !email.includes("@") || email.length > 320) {
      return c.json({ error: "That does not look like an email address." }, 400);
    }

    const now = Math.floor(Date.now() / 1000);
    const key = await throttleKey("reset", email);
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
      // redirectTo is where better-auth sends the person AFTER it has checked the
      // token, with the token appended. It must be same-origin; better-auth
      // enforces that itself.
      await auth.api.requestPasswordReset({ body: { email, redirectTo: "/reset" } });
    } catch (caught) {
      // An unknown address lands here and is nobody's business.
      console.warn("Password reset skipped:", caught instanceof Error ? caught.message : caught);
      return c.json({ sent: true });
    }

    if (report.failed) {
      console.error("Password reset failed to send:", report.detail);
      return c.json({ error: "We could not send that email just now. Try again shortly." }, 502);
    }
    return c.json({ sent: true });
  });

  /*
   * Delete the account, and everything attached to it.
   *
   * THE ONLY AUTHENTICATED ROUTE ON THIS ROUTER, which is otherwise deliberately
   * open because its whole job is helping people who cannot sign in. So the
   * session is checked here rather than by middleware - putting a guard on the
   * whole group would break resend-verification and forgot-password, which is
   * the opposite of what this file is for.
   *
   * CONFIRMED BY TYPING THE ADDRESS, not by a second button. This is permanent
   * and cascades to twelve tables; the friction is the feature. It is checked
   * against the SESSION's email, so a typo cannot delete anything and a stale
   * page cannot delete the wrong account.
   *
   * One DELETE does all of it. Every table that references user.id does so with
   * ON DELETE CASCADE - verified against the live database's CREATE TABLE
   * statements, all twelve of them - so hand-rolling twelve deletes would be a
   * second definition of "everything attached to this account" that could fall
   * out of step with the schema the moment a table was added.
   */
  routes.post("/delete", async (c) => {
    const auth = createAuth(c.env);
    const result = await auth.api.getSession({ headers: c.req.raw.headers });
    if (result === null) return c.json({ error: "Not signed in." }, 401);

    const body = await c.req.json<{ email?: unknown }>().catch(() => ({ email: undefined }));
    const typed = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
    if (typed !== result.user.email.trim().toLowerCase()) {
      return c.json({ error: "That does not match the address on this account." }, 400);
    }

    await c.get("db").delete(user).where(eq(user.id, result.user.id));

    console.info("Account deleted at the owner's request.");
    return c.json({ deleted: true });
  });

  /*
   * Device tokens: create, list, revoke.
   *
   * All three require a real signed-in session, never a token. A token that can
   * mint more tokens is a token that cannot meaningfully be revoked - one leaked
   * credential would quietly become a permanent foothold. Making the browser the
   * only place tokens are issued keeps revocation actually final.
   */
  const requireSession = async (c: Context<AppBindings>) => {
    const auth = createAuth(c.env);
    return auth.api.getSession({ headers: c.req.raw.headers });
  };

  routes.post("/tokens", async (c) => {
    const session = await requireSession(c);
    if (session === null) return c.json({ error: "Not signed in." }, 401);

    const body = await c.req.json<{ label?: unknown }>().catch(() => ({ label: undefined }));
    const label = typeof body.label === "string" ? body.label.trim().slice(0, 60) : "";
    if (label === "") return c.json({ error: "Give the device a name." }, 400);

    const db = c.get("db");
    const existing = await db.select().from(deviceToken)
      .where(eq(deviceToken.userId, session.user.id)).all();
    // A cap, because there is no legitimate reason to hold dozens and an
    // unbounded list is somewhere for a forgotten credential to hide.
    if (existing.length >= 10) {
      return c.json({ error: "That is ten devices already. Revoke one first." }, 400);
    }

    const token = mintToken();
    await db.insert(deviceToken).values({
      id: crypto.randomUUID(),
      userId: session.user.id,
      tokenHash: await hashToken(token),
      label,
      createdAt: Math.floor(Date.now() / 1000),
      lastUsedAt: 0,
    });

    // The only time the raw token exists outside the person's own clipboard.
    return c.json({ token, label });
  });

  routes.get("/tokens", async (c) => {
    const session = await requireSession(c);
    if (session === null) return c.json({ error: "Not signed in." }, 401);

    const rows = await c.get("db").select().from(deviceToken)
      .where(eq(deviceToken.userId, session.user.id)).all();

    // Never the hash. It is not the token, but it is the thing the token is
    // checked against, and there is no reason for it to leave the server.
    return c.json({
      tokens: rows.map((r) => ({
        id: r.id, label: r.label, createdAt: r.createdAt, lastUsedAt: r.lastUsedAt,
      })),
    });
  });

  routes.post("/tokens/revoke", async (c) => {
    const session = await requireSession(c);
    if (session === null) return c.json({ error: "Not signed in." }, 401);

    const body = await c.req.json<{ id?: unknown }>().catch(() => ({ id: undefined }));
    const id = typeof body.id === "string" ? body.id : "";
    if (id === "") return c.json({ error: "Which device?" }, 400);

    // Scoped to the caller's own rows, so an id belonging to somebody else
    // matches nothing rather than revoking their device.
    await c.get("db").delete(deviceToken)
      .where(and(eq(deviceToken.id, id), eq(deviceToken.userId, session.user.id)));

    /*
     * Always "revoked", even when nothing matched, and that is deliberate.
     *
     * Answering 404 for an id that exists but belongs to someone else - while
     * answering 200 for one that does not exist at all - turns this into an
     * oracle for probing which token ids are real. From the caller's own point
     * of view the statement is true either way: after this call they have no
     * device with that id.
     */
    return c.json({ revoked: true });
  });

  return routes;
}
