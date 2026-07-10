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
import { NavCountBadge, NavDotBadge } from "@/components/dashboard/nav-count-badge";
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
    return (
      <NavDotBadge
        collapsed={collapsed}
        testId="inbox-nav-badge-dot"
        label="New updates in your inbox"
      />
    );
  }

  // Genuinely nothing — omit (never "0").
  return null;
}
