"use client";

// Shared nav count-badge primitive (feat-nav-attention-badges). Extracted from
// the shipped Inbox badge so the Inbox / Dashboard / Workstream nav items render
// one identical visual (the neutral soleur-bg-badge pill + collapsed corner dot) — see
// inbox-attention-badge.pen. The per-surface wrappers (inbox-nav-badge,
// conversations-nav-badge, workstream-nav-badge) supply only the count + label +
// testId; the visual + a11y + responsive rules live here once.

import useSWR, { type BareFetcher, type Key } from "swr";
import { warnSilentFallback } from "@/lib/client-observability";

// FR5 visuals: neutral fill via the soleur-bg-badge token, white 11/600 text,
// fully rounded. Gold is deliberately NOT used — it is reserved for the
// active-state left bar + label, and a gold badge would blur into that signal.
const PILL_BASE =
  "inline-flex items-center justify-center rounded-full bg-soleur-bg-badge font-semibold leading-none text-white";

/**
 * The honesty hook shared by every nav count badge (user-brand-critical). It
 * returns the count to render, or `null` meaning "omit the badge entirely".
 *
 * The failure mode to avoid is a stale/failed count reading as a false "0" —
 * under-representing items that need the founder's attention. So:
 *   - COLD (no count yet — first load, or the first fetch errored → data
 *     undefined, OR the SWR key is gated `null`): return null (omit). Never a
 *     false "0" from a pending/hard-failed load.
 *   - WARM + background revalidation error (SWR keeps the last-good `data`):
 *     return the last-good count. A vanished badge would read as a false "0".
 *   - The error is mirrored to Sentry (warn) so a persistently-degraded count
 *     is observable (cq-silent-fallback-must-mirror-to-sentry).
 * The caller omits at count 0 (a genuinely empty resolved feed).
 */
export function useNavAttentionCount<T>(
  key: Key,
  fetcher: BareFetcher<T>,
  selectCount: (data: T) => number,
  feature: string,
): number | null {
  const { data } = useSWR<T>(key, fetcher, {
    onError: (err) => warnSilentFallback(err, { feature, op: "count-fetch" }),
  });
  // COLD (undefined data, incl. a gated null key): omit — never a false "0".
  if (data === undefined) return null;
  // WARM data (even alongside a revalidation error): render the real count.
  return selectCount(data);
}

/**
 * Presentational count badge. Renders the trailing pill (expanded + mobile
 * drawer) and, when collapsed, a corner-overlay dot on the icon. Exactly one
 * form paints per viewport/collapse state (CSS `md:` toggles). Only rendered by
 * a wrapper when count > 0.
 */
export function NavCountBadge({
  count,
  collapsed,
  label,
  testId,
  cap = 99,
}: {
  count: number;
  collapsed: boolean;
  label: string;
  testId: string;
  /** Display cap — counts above it render "<cap>+". Default 99; the inbox
   * attention badge passes 9 (Appendix A). */
  cap?: number;
}) {
  // FR5: large counts cap at "<cap>+".
  const display = count > cap ? `${cap}+` : String(count);

  return (
    <>
      {/* Expanded (240px rail) + mobile drawer: a trailing pill after the label.
          `ml-auto` right-aligns it. Hidden at md+ when collapsed (the corner dot
          takes over) but still shown in the mobile drawer where labels are always
          visible — mirrors the label span's `${collapsed ? "md:hidden" : ""}`
          rule in layout.tsx. The aria-label composes with the visible nav label
          so the link reads e.g. "Workstream, N items needing attention". */}
      <span
        data-testid={testId}
        aria-label={label}
        className={`ml-auto h-[18px] min-w-[18px] px-1 text-[11px] ${PILL_BASE} ${collapsed ? "md:hidden" : ""}`}
      >
        {display}
      </span>
      {/* Collapsed (56px icon rail): a corner-overlay mini-count on the icon's
          top-right, ringed in the rail bg so it reads as cut out of the icon.
          Only exists when collapsed, only paints at md+ (`hidden md:flex`).
          aria-hidden: the collapsed rail hides the nav label, so a labelled dot
          would hijack the link's accessible name; the link keeps its
          title-based name and the count is a visual-only cue there. */}
      {collapsed && (
        <span
          data-testid={`${testId}-collapsed`}
          aria-hidden="true"
          className={`pointer-events-none absolute right-1 top-1 hidden h-[16px] min-w-[16px] px-1 text-[10px] ring-2 ring-soleur-bg-surface-1 md:flex ${PILL_BASE}`}
        >
          {display}
        </span>
      )}
    </>
  );
}

/**
 * Presentational "calm gold dot" — a numberless FYI cue for nav items that have
 * something new but nothing to count (unread inbox updates, a newly-published
 * release). Gold is used here (unlike NavCountBadge's neutral pill) because a
 * dot can't be confused with the active-state bar. Renders the trailing dot
 * expanded/mobile, and a ringed corner dot when collapsed — exactly one paints
 * per viewport via `md:` toggles, mirroring NavCountBadge's two-form rule.
 */
export function NavDotBadge({
  collapsed,
  testId,
  label,
}: {
  collapsed: boolean;
  /** Base test id; the collapsed corner variant appends `-collapsed`. */
  testId: string;
  /** Accessible name for the expanded dot; composes with the nav label. */
  label: string;
}) {
  return collapsed ? (
    <span
      data-testid={`${testId}-collapsed`}
      aria-hidden="true"
      className="pointer-events-none absolute right-1.5 top-1.5 hidden h-2 w-2 rounded-full bg-soleur-accent-gold-fill ring-2 ring-soleur-bg-surface-1 md:block"
    />
  ) : (
    <span
      data-testid={testId}
      aria-label={label}
      className="ml-auto h-2 w-2 shrink-0 rounded-full bg-soleur-accent-gold-fill"
    />
  );
}
