/**
 * One player's progress against one achievement definition.
 * Port of models/achievement_state.gd.
 *
 * Split from the definition for the same reason a plant is split from its
 * species: the definition ships with the game, the state belongs to the player.
 * A definition removed in a future update leaves an orphan state, which is
 * PRESERVED rather than deleted.
 */

import type { Json } from "./dict-util.js";
import { getBool, getClampedFloat, getFloat, getString } from "./dict-util.js";

export interface AchievementState {
  achievementId: string;
  unlocked: boolean;
  unlockedAtUtc: number;
  /**
   * Cached 0..1 progress, so the achievements screen does not re-evaluate every
   * requirement on every open.
   */
  progressRatio: number;
}

export function makeAchievementState(achievementId = ""): AchievementState {
  return { achievementId, unlocked: false, unlockedAtUtc: 0, progressRatio: 0 };
}

/**
 * Marks unlocked, returning true only on the transition so the reveal animation
 * and journal entry fire exactly once.
 */
export function unlock(state: AchievementState, nowUnixUtc = Date.now() / 1000): boolean {
  if (state.unlocked) return false;
  state.unlocked = true;
  state.unlockedAtUtc = nowUnixUtc;
  state.progressRatio = 1;
  return true;
}

export function achievementStateToDict(s: AchievementState): Json {
  return {
    achievement_id: s.achievementId,
    unlocked: s.unlocked,
    unlocked_at_utc: s.unlockedAtUtc,
    progress_ratio: s.progressRatio,
  };
}

export function achievementStateFromDict(data: Json): AchievementState {
  const state = makeAchievementState(getString(data, "achievement_id"));
  state.unlocked = getBool(data, "unlocked");
  state.unlockedAtUtc = getFloat(data, "unlocked_at_utc");
  state.progressRatio = getClampedFloat(data, "progress_ratio", 0, 1);
  // An unlocked achievement is complete by definition; a save claiming 0.4
  // progress on an unlocked one is repaired rather than believed.
  if (state.unlocked) state.progressRatio = 1;
  return state;
}
