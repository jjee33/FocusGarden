/**
 * Achievements: recognition for effort already spent.
 *
 * Twenty-four are defined in content and evaluated by the session pipeline on
 * every completed session, with progress cached on each `AchievementState` so
 * opening this screen does not re-run every requirement. All of that shipped
 * months ago and had nowhere to appear.
 *
 * LOCKED ONES SHOW THEIR PROGRESS BAR, not a question mark. "Focus for 50 hours"
 * with a bar at 38 hours is an invitation; a row of grey padlocks is a wall. The
 * exceptions are the ones content marks `hidden`, which stay unnamed until
 * unlocked because being surprised is the whole point of them.
 */

import { useMemo } from "react";

import { Icon } from "../components/Icon.js";
import type { useGarden } from "../useGarden.js";
import { ALL_ACHIEVEMENTS } from "../../content/content.js";
import { RARITY_NAMES } from "../../domain/species.js";
import { formatDatetime } from "../../domain/time-util.js";
import type { AchievementState } from "../../domain/achievement-state.js";

interface Props {
  garden: ReturnType<typeof useGarden>;
}

export function AchievementsScreen({ garden }: Props) {
  const { save } = garden;

  const byId = useMemo(() => {
    const map = new Map<string, AchievementState>();
    for (const a of save.achievements) map.set(a.achievementId, a);
    return map;
  }, [save.achievements]);

  const rows = useMemo(() => ALL_ACHIEVEMENTS
    .map((def) => ({ def, state: byId.get(def.id) ?? null }))
    .filter(({ def, state }) => !def.hidden || state?.unlocked === true)
    // Unlocked first, then whatever is closest to unlocking. Sorting by content
    // order would bury a bar at 90% under twelve that have not started.
    .sort((a, b) => {
      const au = a.state?.unlocked === true ? 1 : 0;
      const bu = b.state?.unlocked === true ? 1 : 0;
      if (au !== bu) return bu - au;
      if (au === 1) return (b.state?.unlockedAtUtc ?? 0) - (a.state?.unlockedAtUtc ?? 0);
      return (b.state?.progressRatio ?? 0) - (a.state?.progressRatio ?? 0);
    }),
    [byId]);

  const unlocked = rows.filter((r) => r.state?.unlocked === true).length;

  // Grouped by the category content already assigns, because twenty-four in one
  // column is a list and four groups of six is a shape.
  const groups = useMemo(() => {
    const map = new Map<string, typeof rows>();
    for (const row of rows) {
      const key = row.def.category === "" ? "Other" : row.def.category;
      map.set(key, [...(map.get(key) ?? []), row]);
    }
    return [...map.entries()];
  }, [rows]);

  return (
    <>
      <header className="greet">
        <h1>Achievements</h1>
        <p>{unlocked} of {rows.length} earned</p>
      </header>

      {groups.map(([category, items]) => (
        <section className="card ach-group" key={category}>
          <h2>{category}</h2>
          <ul className="ach-list">
            {items.map(({ def, state }) => {
              const done = state?.unlocked === true;
              const ratio = Math.max(0, Math.min(1, state?.progressRatio ?? 0));
              return (
                <li className={`ach${done ? " ach--done" : ""}`} key={def.id}>
                  <span className="ach__mark" aria-hidden="true">
                    <Icon name={done ? "achievements" : "lock"} size={1.25} />
                  </span>

                  <div className="ach__text">
                    <h3>{def.title}</h3>
                    <p>{def.description}</p>

                    {done ? (
                      <p className="ach__when">
                        {state !== null && state.unlockedAtUtc > 0
                          ? `Earned ${formatDatetime(state.unlockedAtUtc)}`
                          : "Earned"}
                      </p>
                    ) : def.trackProgress ? (
                      <div className="ach__bar">
                        {/* Width AND a number: a bar alone cannot be read out, and
                            cannot be judged precisely by anyone. */}
                        <div className="ach__fill" style={{ width: `${ratio * 100}%` }} />
                        <span className="ach__pct">{Math.floor(ratio * 100)}%</span>
                      </div>
                    ) : null}
                  </div>

                  <span className="rarity" style={{
                    background: `var(--rarity-${def.rarity})`,
                    color: `var(--rarity-ink-${def.rarity})`,
                  }}>
                    {RARITY_NAMES[def.rarity]}
                  </span>
                </li>
              );
            })}
          </ul>
        </section>
      ))}
    </>
  );
}
