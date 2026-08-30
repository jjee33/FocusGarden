/**
 * Long-lived tokens for clients that are not browsers.
 *
 * The desktop app has no cookie jar and nowhere sensible to land an OAuth
 * redirect, so it authenticates with a token the person creates in the web app
 * and pastes into its settings. Explicit, revocable, and it never asks anyone to
 * type their password into a native window.
 *
 * THE RAW TOKEN IS NEVER STORED. It is shown once and only its sha256 is kept,
 * so a stolen database yields no working credentials - the whole difference
 * between this and a password column. It also makes "show me my token again"
 * impossible rather than merely discouraged, which is the correct answer.
 *
 * Lookup is BY HASH, so there is no comparison to get wrong: the database either
 * has that row or it does not. No timing-safe compare is needed because no
 * secret is ever compared.
 */

import { eq } from "drizzle-orm";

import type { Database } from "./db/client.js";
import { deviceToken } from "./db/schema.js";

/**
 * Identifies the string as ours at a glance, and lets secret scanners match it.
 * A credential that looks like random noise gets committed; one that announces
 * itself gets caught.
 */
const PREFIX = "fgt_";

/** 256 bits. There is no reason to be frugal here. */
const ENTROPY_BYTES = 32;

export function isWellFormed(token: string): boolean {
  return token.startsWith(PREFIX) && token.length >= PREFIX.length + 40;
}

export async function hashToken(token: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** base64url of 32 random bytes. Returned once, to the caller, and never again. */
export function mintToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(ENTROPY_BYTES));
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  const b64 = btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  return `${PREFIX}${b64}`;
}

export interface TokenOwner {
  userId: string;
  tokenId: string;
}

/**
 * Resolves a bearer token to its owner, or null.
 *
 * `lastUsedAt` is updated on every successful call. That is a write on a read
 * path, which is worth it: without it there is no way for someone to look at a
 * list of tokens and tell which one is the laptop they sold.
 */
export async function ownerOf(db: Database, token: string): Promise<TokenOwner | null> {
  if (!isWellFormed(token)) return null;

  const hash = await hashToken(token);
  const row = await db.select().from(deviceToken).where(eq(deviceToken.tokenHash, hash)).get();
  if (row === undefined) return null;

  const now = Math.floor(Date.now() / 1000);
  // Only when it has actually moved. A sync every few minutes would otherwise
  // write this row every few minutes for no added information.
  if (now - row.lastUsedAt > 60) {
    await db.update(deviceToken).set({ lastUsedAt: now }).where(eq(deviceToken.id, row.id));
  }

  return { userId: row.userId, tokenId: row.id };
}

/** Reads the token out of an Authorization header, if there is one. */
export function bearerFrom(headers: Headers): string {
  const raw = headers.get("authorization") ?? "";
  return raw.startsWith("Bearer ") ? raw.slice("Bearer ".length).trim() : "";
}
