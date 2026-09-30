"use client";

// feat-nav-attention-badges — a count badge on the Workstream left-nav item
// showing how many workstream items need the founder's attention/decision.
// Reuses the board's shared SWR key (swrKeys.workstreamIssues()) + jsonFetcher,
// mounted inside the layout's <SWRConfig>, so the badge and the Workstream board
// are fed by ONE request (free dedup) and can never disagree.

import { useRef } from "react";
import { jsonFetcher, swrKeys } from "@/lib/swr-config";
import { usePostFcp } from "@/hooks/use-post-fcp";
import { isClosed, type WorkstreamIssue } from "@/lib/workstream";
import {
  NavCountBadge,
  useNavAttentionCount,
} from "@/components/dashboard/nav-count-badge";

type IssuesResponse = { issues: WorkstreamIssue[]; partial?: boolean };

/**
 * "Needs founder attention/decision" for a workstream item (there is no
 * dedicated field, so this is the definition). An OPEN item (not done/cancelled)
 * that is EITHER blocked (stuck, needs unblocking) OR routed to the founder
 * (`assigneeRole === "ceo"`). Single source of the predicate so it can be tuned
 * in one place if the founder wants a different definition.
 */
export function isWorkstreamAttentionItem(i: WorkstreamIssue): boolean {
  if (isClosed(i)) return false;
  return i.status === "blocked" || i.assigneeRole === "ceo";
}

export function WorkstreamNavBadge({ collapsed }: { collapsed: boolean }) {
  // #9178 — non-critical chrome: defer the count fetch past first paint.
  const postFcp = usePostFcp();
  // The board's progressive SSE feed commits partial subsets into this shared
  // key — a streamed-subset count is a confidently-wrong attention signal, so
  // hold the last COMPLETE snapshot while `partial` is set (omit entirely when
  // only partial data has ever been seen — same as a cold load).
  const lastComplete = useRef<WorkstreamIssue[] | undefined>(undefined);
  const count = useNavAttentionCount(
    postFcp ? swrKeys.workstreamIssues() : null,
    jsonFetcher<IssuesResponse>,
    (data) => {
      if (!data.partial) lastComplete.current = data.issues;
      const effective = data.partial ? lastComplete.current : data.issues;
      return (effective ?? []).filter(isWorkstreamAttentionItem).length;
    },
    "workstream-nav-badge",
  );
  if (count === null || count === 0) return null;

  return (
    <NavCountBadge
      count={count}
      collapsed={collapsed}
      testId="workstream-nav-badge"
      label={`${count} workstream ${count === 1 ? "item" : "items"} needing attention`}
    />
  );
}
