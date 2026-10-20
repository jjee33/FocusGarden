/**
 * The idle heading on the focus screen. Port of home_screen.gd's
 * `_build_greeting`, with the same boundaries: morning before noon, afternoon
 * before six, evening otherwise.
 *
 * The web build had hard-coded "Good evening", which greeted someone starting
 * their first session at 8am as though the day were over.
 */

import { localHour } from "../domain/time-util.js";

export function greetingForHour(hour: number): string {
  if (hour < 12) return "Good morning";
  if (hour < 18) return "Good afternoon";
  return "Good evening";
}

export function greeting(displayName: string, nowUnixUtc = Date.now() / 1000): string {
  return `${greetingForHour(localHour(nowUnixUtc))}, ${displayName}`;
}
