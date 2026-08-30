/**
 * These are credentials, so the properties worth asserting are the security
 * ones: that tokens are unpredictable, that the stored form is not the token,
 * and that malformed input is rejected before it reaches the database.
 */

import { describe, expect, it } from "vitest";

import { bearerFrom, hashToken, isWellFormed, mintToken } from "../device-token.js";

describe("mintToken", () => {
  it("announces what it is, so a leaked one can be recognised and scanned for", () => {
    expect(mintToken().startsWith("fgt_")).toBe(true);
  });

  it("never repeats", () => {
    const seen = new Set(Array.from({ length: 500 }, () => mintToken()));
    expect(seen.size).toBe(500);
  });

  it("carries enough entropy to be worth calling a secret", () => {
    const body = mintToken().slice(4);
    expect(body.length).toBeGreaterThanOrEqual(40);
    // base64url only: a token that needs escaping somewhere will eventually be
    // mangled by the one client that forgets.
    expect(/^[A-Za-z0-9_-]+$/.test(body)).toBe(true);
  });
});

describe("isWellFormed", () => {
  it("accepts what mintToken produces", () => {
    expect(isWellFormed(mintToken())).toBe(true);
  });

  it("rejects the shapes that would otherwise reach a database lookup", () => {
    for (const bad of ["", "fgt_", "fgt_short", "hello", "Bearer fgt_xxx", " ".repeat(60)]) {
      expect(isWellFormed(bad)).toBe(false);
    }
  });
});

describe("hashToken", () => {
  it("does not contain the token it came from", async () => {
    const token = mintToken();
    const hash = await hashToken(token);
    expect(hash).not.toContain(token);
    expect(hash).not.toContain(token.slice(4));
    expect(hash).toMatch(/^[0-9a-f]{64}$/);
  });

  it("is stable, or every stored token would stop working", async () => {
    const token = mintToken();
    expect(await hashToken(token)).toBe(await hashToken(token));
  });

  it("separates two tokens that differ by one character", async () => {
    const a = "fgt_" + "A".repeat(43);
    const b = "fgt_" + "A".repeat(42) + "B";
    expect(await hashToken(a)).not.toBe(await hashToken(b));
  });
});

describe("bearerFrom", () => {
  it("reads a bearer token", () => {
    expect(bearerFrom(new Headers({ authorization: "Bearer fgt_abc" }))).toBe("fgt_abc");
  });

  it("is case-insensitive on the header name, as HTTP requires", () => {
    expect(bearerFrom(new Headers({ Authorization: "Bearer fgt_abc" }))).toBe("fgt_abc");
  });

  it("returns nothing for other schemes rather than passing them along", () => {
    expect(bearerFrom(new Headers({ authorization: "Basic dXNlcjpwYXNz" }))).toBe("");
    expect(bearerFrom(new Headers())).toBe("");
  });
});
