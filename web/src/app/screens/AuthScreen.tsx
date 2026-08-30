/**
 * Create an account, or sign in, or neither.
 *
 * THE THIRD OPTION IS DELIBERATE. This app is local-first: every rule runs in
 * the browser and the whole garden lives in IndexedDB, so an account buys
 * exactly one thing - the same garden on another device. Making people sign up
 * before they can try a focus timer would be asking for an email in exchange for
 * nothing they can see yet, and the architecture does not need it.
 *
 * So the account is offered, not demanded, and someone who skips it can sign up
 * later without losing anything: the local garden is pushed up on first sync.
 *
 * Nothing here reports whether an address is registered. "No account with that
 * email" is a lookup service for whoever asks, so every failure that could
 * distinguish an unknown account from a wrong password says the same thing.
 *
 * THE RESEND PATH IS NOT A CONVENIENCE. An account is created before its
 * verification email is sent, so a mail failure - or a link left to expire, or a
 * spam folder never checked - leaves someone with an account they cannot use and
 * cannot re-create, because signing up again says the address is taken. Without
 * a way to ask for another link that is a dead end, and the only exit is
 * emailing whoever runs the site.
 */

import { useState } from "react";

import { readableAuthError, resendVerification, signIn, signUp } from "../auth-client.js";

type Mode = "choose" | "signup" | "signin";

interface Props {
  /** Continue without an account. The garden stays on this device. */
  onSkip: () => void;
}

export function AuthScreen({ onSkip }: Props) {
  const [mode, setMode] = useState<Mode>("choose");
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [sentTo, setSentTo] = useState("");
  // Set when a sign-in failed specifically because the address is unverified,
  // which is the one failure where naming the cause helps rather than leaks: the
  // person already proved they know the password.
  const [unverified, setUnverified] = useState(false);
  const [resendState, setResendState] = useState<"idle" | "busy" | "sent">("idle");

  const resend = async (address: string): Promise<void> => {
    setResendState("busy");
    setError("");
    const result = await resendVerification(address);
    if (result.ok) {
      setResendState("sent");
      return;
    }
    setResendState("idle");
    setError(result.message);
  };

  const google = async (): Promise<void> => {
    setError("");
    setBusy(true);
    try {
      await signIn.social({ provider: "google", callbackURL: "/" });
    } catch (caught) {
      setError(readableAuthError(caught instanceof Error ? caught.message : undefined));
      setBusy(false);
    }
  };

  const submit = async (event: React.FormEvent): Promise<void> => {
    event.preventDefault();
    setError("");
    setUnverified(false);
    setResendState("idle");
    setBusy(true);

    const result = mode === "signup"
      ? await signUp.email({ name: name.trim(), email: email.trim(), password })
      : await signIn.email({ email: email.trim(), password });

    setBusy(false);
    if (result.error !== null && result.error !== undefined) {
      const raw = (result.error.message ?? "").toLowerCase();
      setUnverified(raw.includes("verif"));
      setError(readableAuthError(result.error.message));
      return;
    }
    // Verification is required before sign-in, so a successful sign-up does not
    // land you in the app - it lands you at your inbox.
    if (mode === "signup") setSentTo(email.trim());
  };

  if (sentTo !== "") {
    return (
      <div className="auth">
        <div className="auth__panel">
          <h1>Check your email</h1>
          <p>
            We sent a link to <b>{sentTo}</b>. Open it and your garden is ready.
            The link is good for an hour.
          </p>
          <p className="hint">
            Nothing arrived? It can take a minute, and it is worth a look in spam.
          </p>

          {error !== "" && <p className="auth__error" role="alert">{error}</p>}
          {resendState === "sent" && (
            <p className="hint" role="status">
              Sent again. If this one does not arrive either, the address may already
              be confirmed — try signing in.
            </p>
          )}

          <div className="auth__actions">
            <button
              className="btn btn--ghost"
              type="button"
              disabled={resendState !== "idle"}
              onClick={() => void resend(sentTo)}
            >
              {resendState === "busy" ? "Sending…" : "Send it again"}
            </button>
            <button className="btn btn--quiet" type="button" onClick={() => {
              setSentTo("");
              setResendState("idle");
              setError("");
            }}>
              Back
            </button>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="auth">
      <div className="auth__panel">
        <div className="auth__brand">
          <b>Focus Garden</b>
          <span>grow what you give time to</span>
        </div>

        {mode === "choose" && (
          <>
            <h1>Every plant here grew out of time you spent focusing.</h1>
            <p>
              An account keeps your garden on every device you use. You do not need
              one to start - and you can add one later without losing anything.
            </p>
            <div className="auth__actions">
              <button className="btn" type="button" disabled={busy} onClick={() => void google()}>
                Continue with Google
              </button>
              <button className="btn btn--ghost" type="button" onClick={() => setMode("signup")}>
                Sign up with email
              </button>
              <button className="btn btn--quiet" type="button" onClick={() => setMode("signin")}>
                I already have an account
              </button>
            </div>
            <button className="auth__skip" type="button" onClick={onSkip}>
              Just let me start — keep it on this device
            </button>
          </>
        )}

        {mode !== "choose" && (
          <>
            <h1>{mode === "signup" ? "Create your account" : "Welcome back"}</h1>
            <form className="auth__form" onSubmit={(e) => void submit(e)}>
              {mode === "signup" && (
                <label className="auth__field">
                  <span>Name</span>
                  <input
                    className="field-input" type="text" value={name} required maxLength={40}
                    autoComplete="name" onChange={(e) => setName(e.target.value)}
                  />
                </label>
              )}
              <label className="auth__field">
                <span>Email</span>
                <input
                  className="field-input" type="email" value={email} required
                  autoComplete="email" onChange={(e) => setEmail(e.target.value)}
                />
              </label>
              <label className="auth__field">
                <span>Password</span>
                <input
                  className="field-input" type="password" value={password} required
                  minLength={10}
                  autoComplete={mode === "signup" ? "new-password" : "current-password"}
                  onChange={(e) => setPassword(e.target.value)}
                />
                {mode === "signup" && <small>Ten characters or more.</small>}
              </label>

              {error !== "" && <p className="auth__error" role="alert">{error}</p>}
              {unverified && resendState !== "sent" && (
                <button
                  className="btn btn--quiet"
                  type="button"
                  disabled={resendState !== "idle" || email.trim() === ""}
                  onClick={() => void resend(email.trim())}
                >
                  {resendState === "busy" ? "Sending…" : "Send me the link again"}
                </button>
              )}
              {resendState === "sent" && (
                <p className="hint" role="status">
                  On its way. Open the link and you are in.
                </p>
              )}

              <button className="btn" type="submit" disabled={busy}>
                {busy ? "One moment…" : mode === "signup" ? "Create account" : "Sign in"}
              </button>
            </form>

            <div className="auth__actions">
              <button className="btn btn--ghost" type="button" disabled={busy} onClick={() => void google()}>
                Continue with Google
              </button>
              <button
                className="btn btn--quiet"
                type="button"
                onClick={() => {
                  setMode(mode === "signup" ? "signin" : "signup");
                  setError("");
                }}
              >
                {mode === "signup" ? "I already have an account" : "Create an account instead"}
              </button>
            </div>
            <button className="auth__skip" type="button" onClick={onSkip}>
              Just let me start — keep it on this device
            </button>
          </>
        )}
      </div>
    </div>
  );
}
