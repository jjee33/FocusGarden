/**
 * The browser half of authentication.
 *
 * `baseURL` is left unset on purpose: the app and the API are the same origin,
 * so better-auth resolves against the page it is running on. Pinning it here
 * would mean a build for localhost could not run in production, and the value
 * that actually matters - the one the OAuth callback is built from - is the
 * server's APP_URL, not this.
 */

import { createAuthClient } from "better-auth/react";

export const authClient = createAuthClient();

export const { useSession, signIn, signUp, signOut } = authClient;

/**
 * The one message a person should ever see from a failed sign-in.
 *
 * Auth errors are the classic place to leak: "no account with that email" tells
 * anyone who asks which addresses are registered. Everything that could
 * distinguish a wrong password from an unknown account collapses into one
 * sentence, and the specific ones that are safe to say are named explicitly.
 */
export function readableAuthError(message: string | undefined): string {
  const raw = (message ?? "").toLowerCase();
  if (raw.includes("verif")) {
    return "Check your email and confirm your address first - we sent a link when you signed up.";
  }
  if (raw.includes("already") || raw.includes("exists")) {
    return "There is already an account with that email. Try signing in instead.";
  }
  if (raw.includes("password") && raw.includes("short")) {
    return "That password is too short. Ten characters or more.";
  }
  if (raw.includes("network") || raw.includes("fetch")) {
    return "Could not reach the server. Your garden is safe on this device either way.";
  }
  return "That email and password did not match. Try again.";
}
