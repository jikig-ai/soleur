"use client";

// feat-inbox-attention-badge — a count badge on the Inbox left-nav item showing
// the number of active (unarchived) inbox items. Reuses the Inbox Active tab's
// shared SWR key (swrKeys.inboxEmails("active")) + fetcher (TR3), so the badge
// and the Inbox list are fed by ONE request (free dedup via SWRConfig's
// dedupingInterval) and can never disagree (G3). Mounting inside the dashboard
// layout's <SWRConfig> (ADR-067) is what makes the dedup work — see layout.tsx.
//
// The neutral visual + the honesty contract (never a false "0") live in the
// shared NavCountBadge / useNavAttentionCount primitives (nav-count-badge.tsx).

import { fetchInboxItems } from "@/components/inbox/inbox-surface";
import { swrKeys } from "@/lib/swr-config";
import {
  NavCountBadge,
  useNavAttentionCount,
} from "@/components/dashboard/nav-count-badge";

export function InboxNavBadge({ collapsed }: { collapsed: boolean }) {
  const count = useNavAttentionCount(
    swrKeys.inboxEmails("active"),
    fetchInboxItems,
    (items) => items.length,
    "inbox-nav-badge",
  );
  if (count === null || count === 0) return null;

  return (
    <NavCountBadge
      count={count}
      collapsed={collapsed}
      testId="inbox-nav-badge"
      label={`${count} ${count === 1 ? "item" : "items"} needing attention`}
    />
  );
}
