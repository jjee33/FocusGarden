/**
 * Identity and progression state. Port of models/player_profile.gd.
 *
 * Level is NOT stored. It is derived from `totalXp` by the XP formula, which is
 * the single authoritative level calculation. Storing a level alongside the XP
 * that determines it would let the two disagree after any formula change.
 *
 * Streak fields ARE stored, as a cache: recomputing a streak means walking every
 * session record, which is not something to do on every screen open. They can be
 * rebuilt from sessions at any time.
 */

import { maxi } from "./gd.js";
import type { Json } from "./dict-util.js";
import { getBool, getFloat, getInt, getString, getStringArray } from "./dict-util.js";

export interface PlayerProfile {
  displayName: string;
  createdAtUtc: number;
  totalXp: number;
  /** What the player is currently growing and working on. */
  activePlantUid: string;
  activeProjectId: string;
  /** Unlock ids already granted, so an unlock event can only fire once. */
  unlockedIds: string[];
  currentStreak: number;
  longestStreak: number;
  lastFocusDateKey: string;
  /**
   * Focus sessions completed since the last long break. Persisted so closing the
   * app mid-cycle does not reset the player's place in it.
   */
  focusSessionsInCycle: number;
  onboardingCompleted: boolean;
}

export function makePlayerProfile(overrides: Partial<PlayerProfile> = {}): PlayerProfile {
  return {
    displayName: "Gardener", createdAtUtc: 0, totalXp: 0,
    activePlantUid: "", activeProjectId: "", unlockedIds: [],
    currentStreak: 0, longestStreak: 0, lastFocusDateKey: "",
    focusSessionsInCycle: 0, onboardingCompleted: false,
    ...overrides,
  };
}

export function hasUnlock(profile: PlayerProfile, unlockId: string): boolean {
  return profile.unlockedIds.includes(unlockId);
}

/**
 * Returns true only the first time an unlock is granted, so callers can fire the
 * celebration exactly once.
 */
export function grantUnlock(profile: PlayerProfile, unlockId: string): boolean {
  if (unlockId === "" || profile.unlockedIds.includes(unlockId)) return false;
  profile.unlockedIds.push(unlockId);
  return true;
}

export function playerProfileToDict(p: PlayerProfile): Json {
  return {
    display_name: p.displayName,
    created_at_utc: p.createdAtUtc,
    total_xp: p.totalXp,
    active_plant_uid: p.activePlantUid,
    active_project_id: p.activeProjectId,
    unlocked_ids: [...p.unlockedIds],
    current_streak: p.currentStreak,
    longest_streak: p.longestStreak,
    last_focus_date_key: p.lastFocusDateKey,
    focus_sessions_in_cycle: p.focusSessionsInCycle,
    onboarding_completed: p.onboardingCompleted,
  };
}

export function playerProfileFromDict(data: Json): PlayerProfile {
  const profile = makePlayerProfile({
    displayName: getString(data, "display_name", "Gardener"),
    createdAtUtc: getFloat(data, "created_at_utc"),
    totalXp: maxi(0, getInt(data, "total_xp")),
    activePlantUid: getString(data, "active_plant_uid"),
    activeProjectId: getString(data, "active_project_id"),
    unlockedIds: getStringArray(data, "unlocked_ids"),
    currentStreak: maxi(0, getInt(data, "current_streak")),
    longestStreak: maxi(0, getInt(data, "longest_streak")),
    lastFocusDateKey: getString(data, "last_focus_date_key"),
    focusSessionsInCycle: maxi(0, getInt(data, "focus_sessions_in_cycle")),
    onboardingCompleted: getBool(data, "onboarding_completed"),
  });

  // longest can never be below current; a save written mid-update could disagree.
  profile.longestStreak = maxi(profile.longestStreak, profile.currentStreak);
  return profile;
}
