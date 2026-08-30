/**
 * The devices allowed to sync without signing in through a browser.
 *
 * This exists for the desktop app, which is a Godot binary with no cookie jar
 * and nowhere to land an OAuth redirect. A token created here and pasted into
 * its settings is explicit, revocable, and never asks anyone to type their
 * password into a native window.
 *
 * THE TOKEN IS SHOWN ONCE. The server keeps only a hash, so it genuinely cannot
 * be recovered - and the copy in this component's state is the only copy that
 * will ever exist outside the person's clipboard. The interface says so plainly
 * rather than letting someone discover it by coming back tomorrow.
 */

import { useCallback, useEffect, useState } from "react";

import { Icon } from "../components/Icon.js";
import {
  createDeviceToken, listDeviceTokens, revokeDeviceToken, type DeviceToken,
} from "../auth-client.js";
import { formatDatetime } from "../../domain/time-util.js";

export function DeviceTokens() {
  const [tokens, setTokens] = useState<DeviceToken[]>([]);
  const [label, setLabel] = useState("");
  const [fresh, setFresh] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState("");
  const [copied, setCopied] = useState(false);

  const refresh = useCallback(async () => {
    setTokens(await listDeviceTokens());
  }, []);

  useEffect(() => { void refresh(); }, [refresh]);

  const add = async (event: React.FormEvent): Promise<void> => {
    event.preventDefault();
    setBusy(true);
    setError("");
    setCopied(false);
    const result = await createDeviceToken(label.trim());
    setBusy(false);
    if (!result.ok) { setError(result.message); return; }
    setFresh(result.token);
    setLabel("");
    await refresh();
  };

  const revoke = async (id: string, name: string): Promise<void> => {
    // Irreversible for that device, but harmless: it stops syncing and the
    // garden on it is untouched. A confirm dialog here would be friction with
    // nothing behind it.
    if (!window.confirm(`Stop "${name}" from syncing? It can be set up again with a new token.`)) return;
    await revokeDeviceToken(id);
    await refresh();
  };

  return (
    <section className="setting-group" aria-labelledby="devices-heading">
      <h2 id="devices-heading">Desktop &amp; other devices</h2>

      {fresh !== "" && (
        <div className="token-reveal">
          <p>
            <b>Copy this now.</b> It is shown once and cannot be recovered — we
            only keep a fingerprint of it. Paste it into the desktop app under
            Settings → Sync.
          </p>
          <code className="token-reveal__value">{fresh}</code>
          <div className="danger__actions">
            <button
              className="btn btn--ghost"
              type="button"
              onClick={() => {
                void navigator.clipboard?.writeText(fresh)
                  .then(() => { setCopied(true); })
                  .catch(() => { setCopied(false); });
              }}
            >
              {copied ? "Copied" : "Copy"}
            </button>
            <button className="btn btn--quiet" type="button" onClick={() => { setFresh(""); }}>
              Done
            </button>
          </div>
        </div>
      )}

      {tokens.length > 0 && (
        <ul className="token-list">
          {tokens.map((t) => (
            <li key={t.id}>
              <span className="token-list__mark" aria-hidden="true"><Icon name="clock" /></span>
              <div>
                <b>{t.label}</b>
                <span>
                  {t.lastUsedAt === 0
                    ? "Never used"
                    : `Last synced ${formatDatetime(t.lastUsedAt)}`}
                </span>
              </div>
              <button
                className="btn btn--quiet"
                type="button"
                onClick={() => { void revoke(t.id, t.label); }}
              >
                Revoke
              </button>
            </li>
          ))}
        </ul>
      )}

      <form className="token-add" onSubmit={(e) => void add(e)}>
        <label className="auth__field">
          <span>Add a device</span>
          <input
            className="field-input"
            type="text"
            value={label}
            maxLength={60}
            placeholder="Desktop PC"
            onChange={(e) => setLabel(e.target.value)}
          />
        </label>
        {error !== "" && <p className="auth__error" role="alert">{error}</p>}
        <button className="btn btn--ghost" type="submit" disabled={busy || label.trim() === ""}>
          {busy ? "Creating…" : "Create token"}
        </button>
      </form>
    </section>
  );
}
