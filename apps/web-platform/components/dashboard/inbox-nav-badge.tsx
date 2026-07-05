"use client";

// Inbox left-nav attention badge (feat-severity-ranked-inbox #6007). Counts
// OUTSTANDING action_required items only (a read-but-un-acted decision still
// nudges) — NOT total unread. Reuses the Inbox Active tab's shared SWR key
// (swrKeys.inbox("active")) + fetcher, so the badge and the list are fed by ONE
// request (free dedup) and can never disagree, and runs the SAME
// severity/clock logic via the shared lib (a naive status='new' count drifts).
//
// Honesty contract (user-brand-critical, FR6): a loading/errored fetch must
// NEVER render a false "0" — COLD (undefined data) omits entirely. Three states:
//   - action_required > 0 → numeric pill (9+ cap, Appendix A)
//   - else + unread FYI    → a calm gold dot, no number ("New updates…")
//   - else                 → omit

import useSWR from "swr";
import { fetchMergedInbox } from "@/components/inbox/inbox-surface";
import { swrKeys } from "@/lib/swr-config";
import { NavCountBadge } from "@/components/dashboard/nav-count-badge";
import { warnSilentFallback } from "@/lib/client-observability";
import {
  countOutstandingActionRequired,
  type MergedInboxItem,
} from "@/lib/inbox-severity";

function hasUnreadFyi(items: MergedInboxItem[]): boolean {
  return items.some((m) => {
    if (m.severity === "action_required") return false;
    // Native rows track read_at; email rows are "unread" while status is new.
    return m.kind === "inbox"
      ? m.inbox.read_at === null
      : m.email.status === "new";
  });
}

export function InboxNavBadge({ collapsed }: { collapsed: boolean }) {
  const { data } = useSWR<MergedInboxItem[]>(
    swrKeys.inbox("active"),
    fetchMergedInbox,
    {
      onError: (err) =>
        warnSilentFallback(err, { feature: "inbox-nav-badge", op: "count-fetch" }),
    },
  );

  // COLD (undefined data, incl. a hard-failed first load): omit — never a false "0".
  if (data === undefined) return null;

  const count = countOutstandingActionRequired(data);
  if (count > 0) {
    return (
      <NavCountBadge
        count={count}
        collapsed={collapsed}
        testId="inbox-nav-badge"
        cap={9}
        label={`${count} ${count === 1 ? "item needs" : "items need"} your decision`}
      />
    );
  }

  // No decisions pending, but unread updates → a calm gold dot (no number).
  if (hasUnreadFyi(data)) {
    return collapsed ? (
      <span
        data-testid="inbox-nav-badge-dot-collapsed"
        aria-hidden="true"
        className="pointer-events-none absolute right-1.5 top-1.5 hidden h-2 w-2 rounded-full bg-soleur-accent-gold-fill ring-2 ring-soleur-bg-surface-1 md:block"
      />
    ) : (
      <span
        data-testid="inbox-nav-badge-dot"
        aria-label="New updates in your inbox"
        className="ml-auto h-2 w-2 shrink-0 rounded-full bg-soleur-accent-gold-fill"
      />
    );
  }

  // Genuinely nothing — omit (never "0").
  return null;
}
