/**
 * What the time actually adds up to.
 *
 * Every figure here is DERIVED from the session rows, never stored as a total.
 * That is the point of keeping the full history: if a cached figure and the rows
 * ever disagree, the rows win. Nothing on this screen can drift away from what
 * actually happened.
 *
 * The heatmap omits days with no focus rather than drawing 365 zeroes, and it is
 * built from `minutesByDay` - the same function the streak calculation uses, so
 * a day that looks filled here is a day that counted there.
 */

import { useMemo } from "react";

import type { useGarden } from "../useGarden.js";
import { formatDateKey, formatDuration, shiftDateKey, todayKey } from "../../domain/time-util.js";

interface Props {
  garden: ReturnType<typeof useGarden>;
}

/**
 * Six months. A full year is the familiar shape but needs horizontal scrolling
 * on a phone to stay legible, and half of it would be empty for anyone who has
 * not been here a year.
 */
const WEEKS = 26;

export function StatisticsScreen({ garden }: Props) {
  const { stats, save } = garden;
  const threshold = save.settings.streakThresholdMinutes;

  const days = useMemo(() => {
    const today = todayKey();
    // Wind back to the most recent Sunday so rows are weekdays, not an arbitrary
    // seven-day rotation.
    const todayIndex = new Date(`${today}T00:00:00Z`).getUTCDay();
    const lastCell = WEEKS * 7 - 1 - (6 - todayIndex);
    return Array.from({ length: WEEKS * 7 }, (_, i) => {
      const key = shiftDateKey(today, i - lastCell);
      const minutes = stats.dailyTotals.get(key) ?? 0;
      return { key, minutes, future: i > lastCell };
    });
  }, [stats.dailyTotals]);

  const projects = useMemo(() => {
    const rows = [...stats.byProject.entries()]
      .map(([id, minutes]) => ({
        id,
        name: save.projects.find((p) => p.id === id)?.displayName ?? "Unfiled",
        minutes,
      }))
      .sort((a, b) => b.minutes - a.minutes);
    const max = rows.reduce((m, r) => Math.max(m, r.minutes), 0);
    return { rows, max };
  }, [stats.byProject, save.projects]);

  return (
    <>
      <div className="greet">
        <h1>Statistics</h1>
        <p>Every figure here is worked out from your sessions, not stored as a total.</p>
      </div>

      <div className="tiles">
        <Tile label="This week" value={formatDuration(stats.focusWeek)} />
        <Tile label="This month" value={formatDuration(stats.focusMonth)} />
        <Tile label="Lifetime" value={formatDuration(stats.focusLifetime)} />
        <Tile label="Days focused" value={String(stats.daysFocused)} />
      </div>

      <div className="tiles">
        <Tile label="Sessions" value={String(stats.sessionCount)} />
        <Tile label="Average session" value={formatDuration(stats.averageSessionMinutes)} />
        <Tile label="Longest session" value={formatDuration(stats.longestSessionMinutes)} />
        <Tile label="Longest streak" value={`${stats.longestStreak} days`} />
      </div>

      <section className="card" style={{ padding: "var(--sp-md)" }} aria-labelledby="heatmap-heading">
        <div className="section-head" style={{ marginBottom: "var(--sp-sm)" }}>
          <h2 id="heatmap-heading">The last six months</h2>
          <span className="eyebrow">
            {stats.currentStreak > 0 ? `${stats.currentStreak} day streak` : "No streak yet"}
          </span>
        </div>
        <div className="heatmap" role="img" aria-label={
          `Focus over the last ${WEEKS} weeks. ${stats.daysFocused} days with focus.`
        }>
          {days.map((day) => (
            <span
              key={day.key}
              className="heatmap__cell"
              title={day.future ? undefined : `${formatDateKey(day.key)} · ${formatDuration(day.minutes)}`}
              style={{
                background: day.future
                  ? "transparent"
                  : intensityColor(day.minutes, threshold),
              }}
            />
          ))}
        </div>
        <p className="hint" style={{ marginTop: "var(--sp-sm)" }}>
          A day counts toward the streak at {formatDuration(threshold)}. A missed day
          resets a number and nothing else.
        </p>
      </section>

      <section className="card" style={{ padding: "var(--sp-md)" }} aria-labelledby="projects-heading">
        <div className="section-head" style={{ marginBottom: "var(--sp-sm)" }}>
          <h2 id="projects-heading">Where the time went</h2>
        </div>
        {projects.rows.length === 0 ? (
          <p className="hint">No sessions yet. The first one will show up here.</p>
        ) : (
          <div className="bars">
            {projects.rows.map((row) => (
              <div className="bar-row" key={row.id}>
                <span className="bar-row__name">{row.name}</span>
                <span className="bar">
                  <i style={{
                    width: `${projects.max === 0 ? 0 : Math.round((row.minutes / projects.max) * 100)}%`,
                  }} />
                </span>
                <span className="bar-row__value">{formatDuration(row.minutes)}</span>
              </div>
            ))}
          </div>
        )}
      </section>
    </>
  );
}

/**
 * Four steps keyed to the player's OWN streak threshold, not a fixed scale.
 * Someone whose day counts at 15 minutes and someone whose day counts at two
 * hours should both see their good days read as good days.
 */
function intensityColor(minutes: number, threshold: number): string {
  // A day with no focus is a quiet ground, not a filled cell. At full --track the
  // empty grid read as busy, which made a good week look no different from a bad
  // one at a glance - the one job a heatmap has.
  if (minutes <= 0) return "color-mix(in oklab, var(--track) 42%, var(--bg-raised))";
  const ratio = minutes / Math.max(1, threshold);
  if (ratio < 0.5) return "color-mix(in oklab, var(--moss) 28%, var(--track))";
  if (ratio < 1) return "color-mix(in oklab, var(--moss) 55%, var(--track))";
  if (ratio < 2) return "var(--moss)";
  return "var(--moss-deep)";
}

function Tile({ label, value }: { label: string; value: string }) {
  return (
    <div className="card tile">
      <span className="eyebrow">{label}</span>
      <b>{value}</b>
    </div>
  );
}
