/**
 * Only something shaped like a session is treated as one.
 */

import { describe, expect, it, vi } from "vitest";

vi.mock("../auth-client.js", () => ({ useSession: () => ({ data: null, isPending: false }) }));

import { isAccountSession } from "../account-session.js";

describe("isAccountSession", () => {
  it("accepts a session with a user id", () => {
    expect(isAccountSession({ user: { id: "u_1", email: "a@b.c" }, session: {} })).toBe(true);
  });

  it("rejects everything a broken network path can hand back", () => {
    expect(isAccountSession(null)).toBe(false);
    expect(isAccountSession(undefined)).toBe(false);
    expect(isAccountSession("<!doctype html>")).toBe(false);
    expect(isAccountSession({})).toBe(false);
    expect(isAccountSession({ user: null })).toBe(false);
    expect(isAccountSession({ user: "u_1" })).toBe(false);
    expect(isAccountSession({ user: {} })).toBe(false);
  });
});
