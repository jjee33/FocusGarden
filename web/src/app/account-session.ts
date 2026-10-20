/**
 * The signed-in account, or null - never anything in between.
 *
 * better-auth hands back whatever the session endpoint answered with. Behind a
 * captive portal, a misconfigured proxy, or a static host with no API (vite
 * preview, an offline PWA shell falling back to index.html) that is an HTML page
 * wearing a 200: truthy, and not a session. The shell guarded against it; the
 * Settings screen read `useSession()` directly and crashed on
 * `authSession.user.email`, which put the error boundary in front of the one
 * screen holding Export.
 *
 * Every reader goes through this, so the check exists in one place.
 */

import { useSession } from "./auth-client.js";

type RawSession = ReturnType<typeof useSession>["data"];
export type AccountSession = NonNullable<RawSession>;

export function isAccountSession(value: unknown): value is AccountSession {
  if (value === null || typeof value !== "object" || !("user" in value)) return false;
  const user = (value as { user: unknown }).user;
  return user !== null && typeof user === "object"
    && typeof (user as { id?: unknown }).id === "string";
}

export function useAccountSession(): { session: AccountSession | null; isPending: boolean } {
  const { data, isPending } = useSession();
  return { session: isAccountSession(data) ? data : null, isPending };
}
