"use client";

import React, { useState } from "react";
import type { DomainLeaderId } from "@/server/domain-leaders";
import { DOMAIN_LEADERS } from "@/server/domain-leaders";
import type { SubagentCompleteStatus } from "@/lib/types";
import { LeaderAvatar } from "@/components/leader-avatar";
import { LEADER_COLORS } from "@/components/chat/leader-colors";

/**
 * Stage 4 (#2886) — SubagentGroup component.
 *
 * Renders a parent leader's assessment + nested per-child sub-bubbles, one
 * per spawned subagent (Option A from brainstorm Q#3). Default expanded if
 * `subagents.length <= SUBAGENT_GROUP_AUTO_EXPAND_MAX`; collapsed otherwise
 * (with a toggle).
 *
 * Per-child status badges:
 *   - success → checkmark
 *   - error   → red x
 *   - timeout → amber clock
 *   - undefined (still running) → pulse dot (`in_flight`)
 *
 * Test hooks (per `cq-jsdom-no-layout-gated-assertions`):
 *   - `data-parent-spawn-id` on the group root
 *   - `data-expanded` on the group root ("true" | "false")
 *   - `data-child-spawn-id` on each child row
 *   - `data-child-status` on each child row
 *   - `data-testid="subagent-group-toggle"` on the expand button (when present)
 */

/** Review F18 (#2886): module-scope constants extracted from inline literals
 *  so the indentation and auto-expand thresholds are referenced by name and
 *  visible to greps. */
export const SUBAGENT_CHILD_INDENT_CLASS = "ml-6";
export const SUBAGENT_GROUP_AUTO_EXPAND_MAX = 2;

export interface SubagentChild {
  spawnId: string;
  leaderId: DomainLeaderId;
  task?: string;
  status?: SubagentCompleteStatus;
}

interface SubagentGroupProps {
  parentSpawnId: string;
  parentLeaderId: DomainLeaderId;
  parentTask?: string;
  /** Review F20 (#2886): renamed from `children` so it doesn't shadow
   *  React's reserved prop semantics. The wire-side reducer field is also
   *  named `children` on `ChatSubagentGroupMessage`; the rename is local to
   *  the component prop only. */
  subagents: SubagentChild[];
  getDisplayName?: (id: DomainLeaderId) => string;
  getIconPath?: (id: DomainLeaderId) => string | null;
  variant?: "full" | "sidebar";
}

function statusKey(status?: SubagentCompleteStatus): string {
  return status ?? "in_flight";
}

function StatusBadge({ status }: { status?: SubagentCompleteStatus }) {
  if (status === "success") {
    return (
      <span
        className="flex h-4 w-4 items-center justify-center rounded-full bg-emerald-900/40 text-emerald-400"
        aria-label="Subagent succeeded"
      >
        <svg width="10" height="10" viewBox="0 0 12 12" fill="none" aria-hidden="true">
          <path d="M2 6.5L4.5 9L10 3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </span>
    );
  }
  if (status === "error") {
    return (
      <span
        className="flex h-4 w-4 items-center justify-center rounded-full bg-red-900/40 text-red-400"
        aria-label="Subagent errored"
      >
        <svg width="10" height="10" viewBox="0 0 12 12" fill="none" aria-hidden="true">
          <path d="M3 3L9 9M9 3L3 9" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
        </svg>
      </span>
    );
  }
  if (status === "timeout") {
    return (
      <span
        className="flex h-4 w-4 items-center justify-center rounded-full bg-amber-900/40 text-amber-400"
        aria-label="Subagent timed out"
      >
        <svg width="10" height="10" viewBox="0 0 12 12" fill="none" aria-hidden="true">
          <circle cx="6" cy="6" r="4" stroke="currentColor" strokeWidth="1.2" />
          <path d="M6 4v2.5l1.5 1" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" />
        </svg>
      </span>
    );
  }
  // in-flight pulse
  return (
    <span
      className="h-2 w-2 animate-pulse rounded-full bg-amber-500"
      aria-label="Subagent in flight"
    />
  );
}

export function SubagentGroup({
  parentSpawnId,
  parentLeaderId,
  parentTask,
  subagents,
  getDisplayName,
  getIconPath,
}: SubagentGroupProps) {
  const initialExpanded = subagents.length <= SUBAGENT_GROUP_AUTO_EXPAND_MAX;
  const [expanded, setExpanded] = useState<boolean>(initialExpanded);

  const parentLeader = DOMAIN_LEADERS.find((l) => l.id === parentLeaderId);
  const parentName = getDisplayName?.(parentLeaderId) ?? parentLeader?.name ?? parentLeaderId;
  const parentIcon = getIconPath?.(parentLeaderId) ?? null;
  const parentColor = LEADER_COLORS[parentLeaderId] ?? "border-l-neutral-500";

  return (
    <div
      data-parent-spawn-id={parentSpawnId}
      data-expanded={expanded ? "true" : "false"}
      className={`rounded-xl border border-soleur-border-default bg-soleur-bg-surface-1/40 px-4 py-3 ${parentColor} border-l-2`}
    >
      <div className="flex items-center gap-3">
        <LeaderAvatar leaderId={parentLeaderId} size="md" customIconPath={parentIcon} />
        <div className="flex min-w-0 flex-1 flex-col">
          <div className="flex items-center gap-2">
            <span className="text-xs font-semibold text-soleur-text-primary">{parentName}</span>
            <span className="rounded-full bg-soleur-bg-surface-2 px-2 py-0.5 text-[10px] text-soleur-text-secondary">
              {subagents.length} subagents spawned
            </span>
          </div>
          {parentTask ? (
            <span className="mt-0.5 text-xs text-soleur-text-muted">{parentTask}</span>
          ) : null}
        </div>
        {subagents.length > SUBAGENT_GROUP_AUTO_EXPAND_MAX ? (
          <button
            type="button"
            data-testid="subagent-group-toggle"
            onClick={() => setExpanded((v) => !v)}
            className="rounded-md border border-soleur-border-default px-2 py-0.5 text-xs text-soleur-text-secondary hover:border-soleur-border-emphasized"
          >
            {expanded ? "Collapse" : `Show ${subagents.length}`}
          </button>
        ) : null}
      </div>

      {expanded ? (
        <div className="mt-3 space-y-2">
          {subagents.map((c) => {
            const childLeader = DOMAIN_LEADERS.find((l) => l.id === c.leaderId);
            const childName =
              getDisplayName?.(c.leaderId) ?? childLeader?.name ?? c.leaderId;
            const childIcon = getIconPath?.(c.leaderId) ?? null;
            return (
              <div
                key={c.spawnId}
                data-child-spawn-id={c.spawnId}
                data-child-status={statusKey(c.status)}
                className={`${SUBAGENT_CHILD_INDENT_CLASS} flex items-center gap-2 rounded-lg border border-soleur-border-default/60 bg-soleur-bg-surface-1/40 px-3 py-2`}
                /* Review F21 (#2886): the redundant `data-parent-id` attribute
                   was removed — the wrapping group already exposes
                   `data-parent-spawn-id`, which is the canonical hook. */
              >
                <LeaderAvatar leaderId={c.leaderId} size="sm" customIconPath={childIcon} />
                <div className="flex min-w-0 flex-1 flex-col">
                  <span className="text-xs font-semibold text-soleur-text-primary">{childName}</span>
                  {c.task ? (
                    <span className="truncate text-xs text-soleur-text-muted">{c.task}</span>
                  ) : null}
                </div>
                <StatusBadge status={c.status} />
              </div>
            );
          })}
        </div>
      ) : null}
    </div>
  );
}
