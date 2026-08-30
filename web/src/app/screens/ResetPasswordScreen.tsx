/**
 * Setting a new password from an emailed link.
 *
 * Reached at /reset?token=..., where better-auth sends people after it has
 * checked the token is real and unexpired. The token is still validated again on
 * submit - this screen only proves someone opened the link, and the server is
 * what decides whether it counts.
 *
 * There is no "confirm password" field. A second box catches a typo that the
 * reset flow itself already catches - you would simply ask for another link -
 * and it doubles the work on a phone keyboard at the exact moment somebody is
 * already annoyed. Showing the password instead is the better trade.
 */

import { useState } from "react";

import { completePasswordReset } from "../auth-client.js";

interface Props {
  token: string;
  /** Clears the reset URL and returns to the normal app. */
  onDone: () => void;
}

export function ResetPasswordScreen({ token, onDone }: Props) {
  const [password, setPassword] = useState("");
  const [reveal, setReveal] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [done, setDone] = useState(false);

  const submit = async (event: React.FormEvent): Promise<void> => {
    event.preventDefault();
    setError("");
    setBusy(true);
    const result = await completePasswordReset(token, password);
    setBusy(false);
    if (!result.ok) {
      setError(result.message);
      return;
    }
    setDone(true);
  };

  if (done) {
    return (
      <main className="auth">
        <div className="auth__panel">
          <div className="auth__brand">
            <b>Focus Garden</b>
            <span>grow what you give time to</span>
          </div>
          <h1>That is set.</h1>
          <p>Your new password is in place. Your garden is exactly as you left it.</p>
          <div className="auth__actions">
            <button className="btn" type="button" onClick={onDone}>Sign in</button>
          </div>
        </div>
      </main>
    );
  }

  return (
    <main className="auth">
      <div className="auth__panel">
        <div className="auth__brand">
          <b>Focus Garden</b>
          <span>grow what you give time to</span>
        </div>
        <h1>Choose a new password</h1>
        <p>Ten characters or more. Nothing you have grown is affected by this.</p>

        <form className="auth__form" onSubmit={(e) => void submit(e)}>
          <label className="auth__field">
            <span>New password</span>
            <input
              className="field-input"
              type={reveal ? "text" : "password"}
              value={password}
              required
              minLength={10}
              autoComplete="new-password"
              autoFocus
              onChange={(e) => setPassword(e.target.value)}
            />
          </label>

          {error !== "" && <p className="auth__error" role="alert">{error}</p>}

          <button className="btn" type="submit" disabled={busy}>
            {busy ? "One moment…" : "Set new password"}
          </button>
        </form>

        <div className="auth__actions">
          <button className="btn btn--quiet" type="button" onClick={() => setReveal(!reveal)}>
            {reveal ? "Hide password" : "Show password"}
          </button>
        </div>
        <button className="auth__skip" type="button" onClick={onDone}>
          Cancel and go back
        </button>
      </div>
    </main>
  );
}

/**
 * The link was spent, or it timed out.
 *
 * better-auth checks the token before redirecting and sends
 * `?error=INVALID_TOKEN` when it fails, with no token attached. Without a screen
 * for that case those people land in the app with no explanation for why the
 * thing they just clicked appeared to do nothing - which reads as the reset
 * being broken rather than the link being old.
 */
export function ResetLinkExpiredScreen({ onDone }: { onDone: () => void }) {
  return (
    <main className="auth">
      <div className="auth__panel">
        <div className="auth__brand">
          <b>Focus Garden</b>
          <span>grow what you give time to</span>
        </div>
        <h1>That link has expired.</h1>
        <p>
          Reset links last an hour and work once. Ask for a fresh one and it will
          be waiting in your inbox in a minute.
        </p>
        <div className="auth__actions">
          <button className="btn" type="button" onClick={onDone}>
            Ask for a new link
          </button>
        </div>
      </div>
    </main>
  );
}
