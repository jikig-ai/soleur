// RQ8 — the SOLE authority for "is this dashboard route drilled, and into what".
// A pure function (NOT a hook: no state, no effects) so it can be called from
// render bodies, route guards, and tests alike. Every existing
// `pathname.startsWith("/dashboard/(kb|settings|chat)")` literal routes through
// this (AC4c) — adding a parallel check is a regression.
//
// Allowlist, NOT denylist (RQ6 / Kieran P0-1): only kb|settings|chat drill into
// a secondary-nav rail. `/dashboard/admin/analytics` (and any future
// `/dashboard/admin/*`) stays at the top level — a denylist of known top-level
// routes would wrongly drill the admin tree just because it is deeper.

export type DrillLevel = "kb" | "settings" | "chat";

// Order is irrelevant — segments are mutually exclusive path prefixes.
export const DRILL_SEGMENTS: readonly DrillLevel[] = ["kb", "settings", "chat"];

/**
 * Map a dashboard pathname to its drill level, or `null` at the top level.
 *
 * A route is "drilled" when it is exactly `/dashboard/<seg>` or nested below it
 * (`/dashboard/<seg>/...`) for one of the allowlisted segments. Deeper content
 * within a section (a KB file, a chat conversation) is still the SAME drill
 * level — depth within a section is content, not a further rail drill (RQ6).
 */
export function segmentToDrillLevel(pathname: string): DrillLevel | null {
  for (const seg of DRILL_SEGMENTS) {
    const root = `/dashboard/${seg}`;
    if (pathname === root || pathname.startsWith(`${root}/`)) {
      return seg;
    }
  }
  return null;
}
