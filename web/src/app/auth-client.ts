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

/**
 * Ask for another verification email.
 *
 * Not `authClient.sendVerificationEmail`: that reaches better-auth directly,
 * which has no rate limit on it and reports whether the address exists. This
 * goes through our own endpoint, which throttles and answers identically either
 * way. The distinction matters because this is the one mail-sending route an
 * anonymous caller can reach.
 */
export async function resendVerification(
  email: string,
): Promise<{ ok: true } | { ok: false; message: string }> {
  let response: Response;
  try {
    response = await fetch("/api/account/resend-verification", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email }),
    });
  } catch {
    return { ok: false, message: "Could not reach the server. Try again in a moment." };
  }

  if (response.ok) return { ok: true };

  const body = await response.json().catch(() => ({})) as { error?: unknown };
  const message = typeof body.error === "string"
    ? body.error
    : "We could not send that email just now. Try again shortly.";
  return { ok: false, message };
}

/**
 * Ask for a password reset email.
 *
 * Through our own endpoint rather than better-auth's, for the same reasons as
 * `resendVerification`: it is throttled there, and it answers identically
 * whether or not the address exists.
 */
export async function requestPasswordReset(
  email: string,
): Promise<{ ok: true } | { ok: false; message: string }> {
  let response: Response;
  try {
    response = await fetch("/api/account/forgot-password", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email }),
    });
  } catch {
    return { ok: false, message: "Could not reach the server. Try again in a moment." };
  }
  if (response.ok) return { ok: true };
  const body = await response.json().catch(() => ({})) as { error?: unknown };
  return {
    ok: false,
    message: typeof body.error === "string"
      ? body.error
      : "We could not send that email just now. Try again shortly.",
  };
}

/** Set a new password from a reset token. better-auth validates the token. */
export async function completePasswordReset(
  token: string, newPassword: string,
): Promise<{ ok: true } | { ok: false; message: string }> {
  const result = await authClient.resetPassword({ newPassword, token });
  if (result.error !== null && result.error !== undefined) {
    const raw = (result.error.message ?? "").toLowerCase();
    if (raw.includes("token") || raw.includes("expired") || raw.includes("invalid")) {
      return {
        ok: false,
        message: "That link has expired or has already been used. Ask for a new one.",
      };
    }
    return { ok: false, message: readableAuthError(result.error.message) };
  }
  return { ok: true };
}
