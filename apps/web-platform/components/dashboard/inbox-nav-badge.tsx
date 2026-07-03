"use client";

// feat-inbox-attention-badge — a count badge on the Inbox left-nav item showing
// the number of active (unarchived) inbox items. It reuses the Inbox Active
// tab's shared SWR key (swrKeys.inboxEmails("active")) + fetcher (TR3), so the
// badge and the Inbox list are fed by ONE request (free dedup via SWRConfig's
// dedupingInterval) and can never disagree (G3). Mounting inside the dashboard
// layout's <SWRConfig> (ADR-067) is what makes the dedup work — see layout.tsx.
//
// Honesty contract (FR6, user-brand-critical): a loading OR errored fetch must
// NEVER render as a false "0". We omit the badge in both cases — a count of 0
// is shown ONLY when the fetch resolved to an empty active feed. A stale/failed
// count silently reading "0 attention items" is the exact single-user incident
// the user-impact-reviewer gates on.

import useSWR from "swr";
import { fetchInboxItems } from "@/components/inbox/inbox-surface";
import { swrKeys } from "@/lib/swr-config";

// Shared pill visuals (FR5): neutral fill via the soleur-bg-badge token, white
// 11/600 text, fully rounded. Gold is deliberately NOT used — it is reserved
// for the active-state left bar + label, and a gold badge would blur into that
// "active" signal.
const PILL_BASE =
  "inline-flex items-center justify-center rounded-full bg-soleur-bg-badge font-semibold leading-none text-white";

export function InboxNavBadge({ collapsed }: { collapsed: boolean }) {
  const { data, error } = useSWR(swrKeys.inboxEmails("active"), fetchInboxItems);

  // FR6: omit on error (never a false "0") and while loading (data undefined).
  if (error || data === undefined) return null;

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
          span's own `${collapsed ? "md:hidden" : ""}` rule in layout.tsx. */}
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
          md:flex`) — on the mobile drawer the pill above is the sole form. */}
      {collapsed && (
        <span
          data-testid="inbox-nav-badge-collapsed"
          aria-label={label}
          className={`pointer-events-none absolute right-1 top-1 hidden h-4 min-w-[1rem] px-1 text-[10px] ring-2 ring-soleur-bg-surface-1 md:flex ${PILL_BASE}`}
        >
          {display}
        </span>
      )}
    </>
  );
}
