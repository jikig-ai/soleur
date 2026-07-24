"use client";

// A single Workstream kanban card: id, title, a labeled priority pill
// (Addendum item 3), the primary role chip + a secondary user avatar
// (Addendum item 5), and a quiet "Live" marker (Addendum item 4 — green dot +
// green text, NO fill) for active seeded cards.

import { isLive, type WorkstreamIssue } from "@/lib/workstream";
import { AssigneeChip, CreatorChip, UserAvatar } from "./assignee-chip";
import { PriorityPill } from "./priority-pill";

export function IssueCard({
  issue,
  onOpen,
}: {
  issue: WorkstreamIssue;
  onOpen: (id: string) => void;
}) {
  const live = isLive(issue);

  return (
    <button
      type="button"
      onClick={() => onOpen(issue.id)}
      className="block w-full rounded-lg border border-soleur-border-default bg-soleur-bg-surface-1 p-3 text-left transition-colors hover:border-soleur-text-muted hover:bg-soleur-bg-surface-2/40"
    >
      <p className="text-[11px] font-medium uppercase tracking-wider text-soleur-text-tertiary">
        {issue.id}
      </p>
      <p className="mt-1 line-clamp-2 text-sm text-soleur-text-primary">
        {issue.title}
      </p>
      <div className="mt-3 flex flex-wrap items-center justify-between gap-2">
        <div className="flex min-w-0 items-center gap-2">
          {live && (
            <span className="inline-flex items-center gap-1 text-[11px] font-medium text-green-400">
              <span
                aria-hidden="true"
                className="h-1.5 w-1.5 rounded-full bg-green-400"
              />
              Live
            </span>
          )}
          <PriorityPill priority={issue.priority} />
        </div>
        <div className="flex shrink-0 items-center gap-1">
          {issue.creator && <CreatorChip creator={issue.creator} />}
          <AssigneeChip role={issue.assigneeRole} />
          {issue.user && <UserAvatar user={issue.user} />}
        </div>
      </div>
    </button>
  );
}
