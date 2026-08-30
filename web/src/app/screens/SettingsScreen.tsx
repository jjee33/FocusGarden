/**
 * Preferences.
 *
 * Every control here writes straight into GameSettings, which is the model that
 * clamps each value on load. That matters more than it sounds: a corrupted
 * 0-minute focus duration would make the timer unusable, and the setting that
 * repairs it lives behind the timer it broke.
 *
 * Reduced motion and animation intensity are wired to the `--motion` token here.
 * Until now the app honoured only the OS media query, which meant someone who
 * wanted stillness inside the app but not system-wide had no way to ask for it -
 * and the desktop's policy has always been that these are settings, not just
 * environment.
 */

import { useEffect } from "react";

import type { useGarden } from "../useGarden.js";
import type { GameSettings, ThemeMode } from "../../domain/game-settings.js";
import { formatDuration } from "../../domain/time-util.js";
import type { ThemeChoice } from "../usePlatform.js";
import { useTheme } from "../usePlatform.js";
import { signOut, useSession } from "../auth-client.js";
import type { useSync } from "../useSync.js";
import { formatDatetime } from "../../domain/time-util.js";

interface Props {
  garden: ReturnType<typeof useGarden>;
  sync: ReturnType<typeof useSync>;
  /** Lets the shell offer the account again once someone signs out. */
  onSignedOut: () => void;
}

export function SettingsScreen({ garden, sync, onSignedOut }: Props) {
  const { save, updateSettings } = garden;
  const settings = save.settings;
  const theme = useTheme();
  const { data: authSession } = useSession();

  // The in-app motion preference, applied as a multiplier on every duration
  // token. Zero when reduced motion is on, which is what switches looping
  // effects OFF rather than merely shortening them.
  useEffect(() => {
    const scale = settings.reducedMotion ? 0 : settings.animationIntensity;
    document.documentElement.style.setProperty("--motion", String(scale));
    return () => {
      document.documentElement.style.removeProperty("--motion");
    };
  }, [settings.reducedMotion, settings.animationIntensity]);

  const set = <K extends keyof GameSettings>(key: K, value: GameSettings[K]): void => {
    updateSettings({ [key]: value } as Partial<GameSettings>);
  };

  return (
    <>
      <div className="greet">
        <h1>Settings</h1>
        <p>Everything here is yours to change, and changing it changes nothing you have grown.</p>
      </div>

      <div className="settings">
        <section className="setting-group" aria-labelledby="timer-heading">
          <h2 id="timer-heading">Timer</h2>
          <Slider
            label="Focus session"
            hint="How long a focus session runs by default."
            value={settings.focusDurationMinutes} min={1} max={120} step={5}
            format={formatDuration}
            onChange={(v) => set("focusDurationMinutes", v)}
          />
          <Slider
            label="Short break"
            value={settings.shortBreakMinutes} min={1} max={30} step={1}
            format={formatDuration}
            onChange={(v) => set("shortBreakMinutes", v)}
          />
          <Slider
            label="Long break"
            value={settings.longBreakMinutes} min={5} max={60} step={5}
            format={formatDuration}
            onChange={(v) => set("longBreakMinutes", v)}
          />
          <Slider
            label="Sessions before a long break"
            value={settings.sessionsBeforeLongBreak} min={1} max={12} step={1}
            format={(v) => String(v)}
            onChange={(v) => set("sessionsBeforeLongBreak", v)}
          />
          <Slider
            label="Minimum for growth"
            hint="Sessions shorter than this still earn XP, but do not advance a plant."
            value={settings.minimumCreditMinutes} min={0} max={30} step={1}
            format={(v) => (v === 0 ? "No minimum" : formatDuration(v))}
            onChange={(v) => set("minimumCreditMinutes", v)}
          />
        </section>

        <section className="setting-group" aria-labelledby="appearance-heading">
          <h2 id="appearance-heading">Appearance</h2>
          <Row label="Theme" hint="System follows whatever your device is set to.">
            <div className="seg-group" role="group" aria-label="Theme">
              {(["system", "light", "dark"] as ThemeChoice[]).map((choice) => (
                <button
                  key={choice}
                  type="button"
                  className="preset"
                  aria-pressed={theme.choice === choice}
                  onClick={() => {
                    theme.setChoice(choice);
                    if (choice !== "system") set("themeMode", choice as ThemeMode);
                  }}
                >
                  {choice[0]!.toUpperCase() + choice.slice(1)}
                </button>
              ))}
            </div>
          </Row>
          <Toggle
            label="Reduced motion"
            hint="Turns looping movement off entirely rather than just speeding it up."
            checked={settings.reducedMotion}
            onChange={(v) => set("reducedMotion", v)}
          />
          <Slider
            label="Animation"
            hint="How much everything else moves."
            value={settings.animationIntensity} min={0} max={1} step={0.1}
            format={(v) => `${Math.round(v * 100)}%`}
            disabled={settings.reducedMotion}
            onChange={(v) => set("animationIntensity", v)}
          />
        </section>

        <section className="setting-group" aria-labelledby="goals-heading">
          <h2 id="goals-heading">Goals</h2>
          <Slider
            label="Daily goal"
            value={settings.dailyGoalMinutes} min={5} max={480} step={5}
            format={formatDuration}
            onChange={(v) => set("dailyGoalMinutes", v)}
          />
          <Slider
            label="Streak threshold"
            hint="Focus at least this much and the day counts. A missed day resets a number and nothing else."
            value={settings.streakThresholdMinutes} min={1} max={240} step={5}
            format={formatDuration}
            onChange={(v) => set("streakThresholdMinutes", v)}
          />
          <Toggle
            label="Confirm before discarding a session"
            checked={settings.confirmBeforeCancelSession}
            onChange={(v) => set("confirmBeforeCancelSession", v)}
          />
        </section>

        <section className="setting-group" aria-labelledby="account-heading">
          <h2 id="account-heading">Account</h2>
          {authSession === null ? (
            <Row
              label="Not signed in"
              hint="This garden lives on this device only. An account keeps it on every device you use, and nothing is lost when you add one."
            >
              <button
                className="btn"
                type="button"
                onClick={() => {
                  // Clearing the flag is what brings the sign-in screen back;
                  // it is a preference, not a session.
                  try {
                    localStorage.removeItem("fg.localOnly");
                  } catch {
                    /* the reload below still shows it for this session */
                  }
                  onSignedOut();
                }}
              >
                Sign in
              </button>
            </Row>
          ) : (
            <Row label="Signed in" hint="Your garden syncs to every device you sign in on.">
              <span className="account-row">
                <b>{authSession.user.email}</b>
                <span>{authSession.user.emailVerified ? "Email confirmed" : "Email not confirmed yet"}</span>
              </span>
            </Row>
          )}
          {authSession !== null && (
            <Row
              label="Sync"
              hint={
                sync.status.state === "offline"
                  ? "No connection. Everything you do is kept here and sent when you are back."
                  : sync.status.message !== ""
                    ? sync.status.message
                    : sync.status.lastSyncedAt > 0
                      ? `Last synced ${formatDatetime(sync.status.lastSyncedAt)}.`
                      : "Not synced yet."
              }
            >
              <button
                className="btn btn--ghost"
                type="button"
                disabled={sync.status.state === "syncing"}
                onClick={() => { void sync.sync(); }}
              >
                {sync.status.state === "syncing" ? "Syncing…" : "Sync now"}
              </button>
            </Row>
          )}
          {authSession !== null && (
            <Row
              label="Sign out"
              hint="Your garden stays on this device. Signing back in picks it up again."
            >
              <button
                className="btn btn--ghost"
                type="button"
                onClick={() => { void signOut().then(onSignedOut); }}
              >
                Sign out
              </button>
            </Row>
          )}
        </section>

        <section className="setting-group" aria-labelledby="data-heading">
          <h2 id="data-heading">Your data</h2>
          <Row
            label="Export a copy"
            hint="Everything, in one file: your profile and every session. The desktop app reads the same format."
          >
            <button className="btn btn--ghost" type="button" onClick={garden.downloadBundle}>
              Export
            </button>
          </Row>
          <Row
            label="Import a garden"
            hint="Replaces everything currently here. You will be shown what the file contains first."
          >
            <button className="btn btn--ghost" type="button" onClick={garden.pickBundleToImport}>
              Import
            </button>
          </Row>
        </section>
      </div>
    </>
  );
}

function Row({
  label, hint, children,
}: { label: string; hint?: string; children: React.ReactNode }) {
  return (
    <div className="setting-row">
      <span className="setting-row__label">
        <b>{label}</b>
        {hint !== undefined && <span>{hint}</span>}
      </span>
      <span className="setting-row__control">{children}</span>
    </div>
  );
}

function Toggle({
  label, hint, checked, onChange,
}: { label: string; hint?: string; checked: boolean; onChange: (v: boolean) => void }) {
  return (
    <Row label={label} {...(hint === undefined ? {} : { hint })}>
      <input
        className="switch"
        type="checkbox"
        checked={checked}
        aria-label={label}
        onChange={(e) => onChange(e.target.checked)}
      />
    </Row>
  );
}

function Slider({
  label, hint, value, min, max, step, format, disabled = false, onChange,
}: {
  label: string; hint?: string; value: number; min: number; max: number; step: number;
  format: (v: number) => string; disabled?: boolean; onChange: (v: number) => void;
}) {
  return (
    <Row label={label} {...(hint === undefined ? {} : { hint })}>
      <input
        type="range"
        min={min} max={max} step={step} value={value}
        disabled={disabled}
        aria-label={label}
        onChange={(e) => onChange(Number(e.target.value))}
      />
      <span className="setting-row__value">{format(value)}</span>
    </Row>
  );
}
