"use client";

// feat-inbox-attention-badge — a count badge on the Inbox left-nav item showing
// the number of active (unarchived) inbox items. It reuses the Inbox Active
// tab's shared SWR key (swrKeys.inboxEmails("active")) + fetcher (TR3), so the
// badge and the Inbox list are fed by ONE request (free dedup via SWRConfig's
// dedupingInterval) and can never disagree (G3). Mounting inside the dashboard
// layout's <SWRConfig> (ADR-067) is what makes the dedup work — see layout.tsx.
//
// Honesty contract (FR6, user-brand-critical). The failure mode to avoid is a
// stale/failed count reading as "0 attention items" — under-representing an
// unhandled statutory/legal/security item is the single-user incident this
// gates on. So:
//   - COLD (no count yet — first load, or the first fetch errored → data
//     undefined): omit the badge entirely. Never render "0" from a failed load.
//   - WARM + background revalidation error (SWR keeps the last-good `data` and
//     sets `error`): keep showing the last-good count. A vanished badge would
//     read as a false "0" — the very thing FR6 forbids — so we do NOT omit on
//     `error` alone. Mirrors InboxSurface's own stale-on-error behavior (it
//     keeps the list visible with a retry bar). The error is also mirrored to
//     Sentry (below) so a persistently-degraded count is observable
//     (cq-silent-fallback-must-mirror-to-sentry).
//   - count === 0 (a genuinely empty resolved feed): omit (FR3).

import useSWR from "swr";
import { fetchInboxItems } from "@/components/inbox/inbox-surface";
import { swrKeys } from "@/lib/swr-config";
import { warnSilentFallback } from "@/lib/client-observability";

// Shared pill visuals (FR5): neutral fill via the soleur-bg-badge token, white
// 11/600 text, fully rounded. Gold is deliberately NOT used — it is reserved
// for the active-state left bar + label, and a gold badge would blur into that
// "active" signal.
const PILL_BASE =
  "inline-flex items-center justify-center rounded-full bg-soleur-bg-badge font-semibold leading-none text-white";

export function InboxNavBadge({ collapsed }: { collapsed: boolean }) {
  const { data } = useSWR(swrKeys.inboxEmails("active"), fetchInboxItems, {
    // A failed count fetch is a silent degradation on non-Inbox routes (where
    // InboxSurface isn't mounted to surface it), so mirror it. warn-level: the
    // count is non-critical and self-heals on the next good fetch. SWR fires
    // this once per failed request, not per render.
    onError: (err) =>
      warnSilentFallback(err, {
        feature: "inbox-nav-badge",
        op: "count-fetch",
      }),
  });

  // COLD state (no resolved count): omit — never render a false "0" from a
  // pending or hard-failed first load. A warm cache surviving a background
  // error keeps `data` defined, so this does NOT blank a known-good count.
  if (data === undefined) return null;

  const count = data.length;
  // FR3: zero-state hides the badge entirely — never an empty pill.
  if (count === 0) return null;

  // FR5: large counts cap at "99+".
  const display = count > 99 ? "99+" : String(count);
  const label = `${count} ${count === 1 ? "item" : "items"} needing attention`;

  return (
    <>
      {/* Expanded (240px rail) + mobile drawer: a trailing pill after the label.
          `ml-auto` right-aligns it in the flex row. When the rail is collapsed
          it is hidden at md+ (the corner dot takes over) but still shows in the
          mobile drawer, where labels are always visible — mirrors the label
          span's own `${collapsed ? "md:hidden" : ""}` rule in layout.tsx. The
          aria-label composes with the visible "Inbox" label so the link reads
          "Inbox, N items needing attention". */}
      <span
        data-testid="inbox-nav-badge"
        aria-label={label}
        className={`ml-auto h-[18px] min-w-[18px] px-1 text-[11px] ${PILL_BASE} ${collapsed ? "md:hidden" : ""}`}
      >
        {display}
      </span>
      {/* Collapsed (56px icon rail): a corner-overlay mini-count on the icon's
          top-right, ringed in the rail bg (FR4) so it reads as cut out of the
          icon. Only exists when collapsed, and only paints at md+ (`hidden
          md:flex`) — on the mobile drawer the pill above is the sole form.
          aria-hidden: in the collapsed rail the label span is `md:hidden`, so a
          labelled dot would become the Inbox link's ENTIRE accessible name and
          drop "Inbox". Hiding it keeps the link's `title="Inbox"` name (matching
          every other collapsed nav item); the count stays a visual-only cue
          there. */}
      {collapsed && (
        <span
          data-testid="inbox-nav-badge-collapsed"
          aria-hidden="true"
          className={`pointer-events-none absolute right-1 top-1 hidden h-[16px] min-w-[16px] px-1 text-[10px] ring-2 ring-soleur-bg-surface-1 md:flex ${PILL_BASE}`}
        >
          {display}
        </span>
      )}
    </>
  );
}
