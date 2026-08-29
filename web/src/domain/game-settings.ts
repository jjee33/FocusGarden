/**
 * All user-configurable preferences. Port of models/game_settings.gd.
 *
 * Defaults are deliberately conservative: audio starts quiet so a first launch
 * is never loud, notifications are on but minimal, and nothing that nags is
 * enabled by default.
 *
 * EVERY NUMERIC FIELD IS CLAMPED ON LOAD, and that is the whole point of this
 * module. A corrupted 0-minute focus duration would make the timer unusable with
 * no way to fix it from inside the app - the setting that repairs it lives
 * behind the timer it broke.
 */

import { clampi } from "./gd.js";
import type { Json } from "./dict-util.js";
import { getBool, getClampedFloat, getInt, getString } from "./dict-util.js";

export const WINDOW_MODES = ["windowed", "fullscreen", "borderless"] as const;
export const THEME_MODES = ["light", "dark"] as const;
export type WindowMode = (typeof WINDOW_MODES)[number];
export type ThemeMode = (typeof THEME_MODES)[number];

export interface GameSettings {
  // Timer
  focusDurationMinutes: number;
  shortBreakMinutes: number;
  longBreakMinutes: number;
  sessionsBeforeLongBreak: number;
  autoStartBreaks: boolean;
  autoStartFocus: boolean;
  /** Sessions shorter than this award no plant growth. 0 disables the gate. */
  minimumCreditMinutes: number;

  // Appearance
  windowMode: WindowMode;
  themeMode: ThemeMode;
  uiScale: number;
  reducedMotion: boolean;
  animationIntensity: number;

  // Audio
  volumeMaster: number;
  volumeMusic: number;
  volumeAmbient: number;
  volumeUi: number;
  volumeTimer: number;
  ambientTrackId: string;

  // Notifications
  notifyFocusComplete: boolean;
  notifyBreakComplete: boolean;

  // Gameplay
  dailyGoalMinutes: number;
  /** Minutes of focus that count a day toward the streak. */
  streakThresholdMinutes: number;
  confirmBeforeCancelSession: boolean;

  // Desktop-only, carried so a bundle round-trips without losing them
  checkForUpdates: boolean;
  customSaveDirectory: string;
}

export function makeGameSettings(overrides: Partial<GameSettings> = {}): GameSettings {
  return {
    focusDurationMinutes: 25, shortBreakMinutes: 5, longBreakMinutes: 15,
    sessionsBeforeLongBreak: 4, autoStartBreaks: false, autoStartFocus: false,
    minimumCreditMinutes: 1,
    windowMode: "windowed", themeMode: "light", uiScale: 1,
    reducedMotion: false, animationIntensity: 1,
    volumeMaster: 0.7, volumeMusic: 0.4, volumeAmbient: 0.5,
    volumeUi: 0.6, volumeTimer: 0.8, ambientTrackId: "none",
    notifyFocusComplete: true, notifyBreakComplete: true,
    dailyGoalMinutes: 50, streakThresholdMinutes: 25,
    confirmBeforeCancelSession: true,
    checkForUpdates: true, customSaveDirectory: "",
    ...overrides,
  };
}

export function gameSettingsToDict(s: GameSettings): Json {
  return {
    focus_duration_minutes: s.focusDurationMinutes,
    short_break_minutes: s.shortBreakMinutes,
    long_break_minutes: s.longBreakMinutes,
    sessions_before_long_break: s.sessionsBeforeLongBreak,
    auto_start_breaks: s.autoStartBreaks,
    auto_start_focus: s.autoStartFocus,
    minimum_credit_minutes: s.minimumCreditMinutes,
    window_mode: s.windowMode,
    theme_mode: s.themeMode,
    ui_scale: s.uiScale,
    reduced_motion: s.reducedMotion,
    animation_intensity: s.animationIntensity,
    volume_master: s.volumeMaster,
    volume_music: s.volumeMusic,
    volume_ambient: s.volumeAmbient,
    volume_ui: s.volumeUi,
    volume_timer: s.volumeTimer,
    ambient_track_id: s.ambientTrackId,
    notify_focus_complete: s.notifyFocusComplete,
    notify_break_complete: s.notifyBreakComplete,
    daily_goal_minutes: s.dailyGoalMinutes,
    streak_threshold_minutes: s.streakThresholdMinutes,
    confirm_before_cancel_session: s.confirmBeforeCancelSession,
    check_for_updates: s.checkForUpdates,
    custom_save_directory: s.customSaveDirectory,
  };
}

function oneOf<T extends string>(options: readonly T[], value: string, fallback: T): T {
  return (options as readonly string[]).includes(value) ? (value as T) : fallback;
}

export function gameSettingsFromDict(data: Json): GameSettings {
  return {
    focusDurationMinutes: getClampedFloat(data, "focus_duration_minutes", 1, 480, 25),
    shortBreakMinutes: getClampedFloat(data, "short_break_minutes", 1, 120, 5),
    longBreakMinutes: getClampedFloat(data, "long_break_minutes", 1, 120, 15),
    sessionsBeforeLongBreak: clampi(getInt(data, "sessions_before_long_break", 4), 1, 12),
    autoStartBreaks: getBool(data, "auto_start_breaks"),
    autoStartFocus: getBool(data, "auto_start_focus"),
    minimumCreditMinutes: getClampedFloat(data, "minimum_credit_minutes", 0, 60, 1),

    windowMode: oneOf(WINDOW_MODES, getString(data, "window_mode", "windowed"), "windowed"),
    themeMode: oneOf(THEME_MODES, getString(data, "theme_mode", "light"), "light"),
    uiScale: getClampedFloat(data, "ui_scale", 0.75, 2, 1),
    reducedMotion: getBool(data, "reduced_motion"),
    animationIntensity: getClampedFloat(data, "animation_intensity", 0, 1, 1),

    volumeMaster: getClampedFloat(data, "volume_master", 0, 1, 0.7),
    volumeMusic: getClampedFloat(data, "volume_music", 0, 1, 0.4),
    volumeAmbient: getClampedFloat(data, "volume_ambient", 0, 1, 0.5),
    volumeUi: getClampedFloat(data, "volume_ui", 0, 1, 0.6),
    volumeTimer: getClampedFloat(data, "volume_timer", 0, 1, 0.8),
    ambientTrackId: getString(data, "ambient_track_id", "none"),

    notifyFocusComplete: getBool(data, "notify_focus_complete", true),
    notifyBreakComplete: getBool(data, "notify_break_complete", true),

    dailyGoalMinutes: getClampedFloat(data, "daily_goal_minutes", 5, 960, 50),
    streakThresholdMinutes: getClampedFloat(data, "streak_threshold_minutes", 1, 480, 25),
    confirmBeforeCancelSession: getBool(data, "confirm_before_cancel_session", true),

    checkForUpdates: getBool(data, "check_for_updates", true),
    customSaveDirectory: getString(data, "custom_save_directory"),
  };
}
