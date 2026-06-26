"use client";

// One kanban column. Addendum item 1: a faint per-column tint + a matching
// colored status dot in the header (driven by ColumnConfig.accent, NOT a
// saturated block). Addendum item 2: the count is a small rounded pill,
// right-aligned and typographically de-emphasized.

import type { ColumnConfig, WorkstreamIssue } from "@/lib/workstream";
import { IssueCard } from "./issue-card";

export function IssueColumn({
  column,
  issues,
  onOpen,
}: {
  column: ColumnConfig;
  issues: WorkstreamIssue[];
  onOpen: (id: string) => void;
}) {
  return (
    <section
      aria-label={column.label}
      className="flex w-72 shrink-0 flex-col rounded-xl border border-soleur-border-default/60 p-2"
      // Faint, low-luminance tint (~5% of the accent) — subtle, not a block.
      style={{ backgroundColor: `${column.accent}0d` }}
    >
      <header className="flex items-center gap-2 px-1 py-2">
        <span
          aria-hidden="true"
          className="h-2 w-2 rounded-full"
          style={{ backgroundColor: column.accent }}
        />
        <h2 className="text-sm font-medium text-soleur-text-primary">
          {column.label}
        </h2>
        <span className="ml-auto rounded-md bg-soleur-bg-surface-2 px-1.5 py-0.5 text-[11px] font-medium text-soleur-text-tertiary">
          {issues.length}
        </span>
      </header>
      <div className="flex flex-col gap-2 px-1 pb-1">
        {issues.length === 0 ? (
          <p className="px-1 py-2 text-xs text-soleur-text-tertiary">No issues</p>
        ) : (
          issues.map((issue) => (
            <IssueCard key={issue.id} issue={issue} onOpen={onOpen} />
          ))
        )}
      </div>
    </section>
  );
}
