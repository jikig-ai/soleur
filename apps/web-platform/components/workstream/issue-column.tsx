"use client";

// One kanban column. Addendum item 1: a per-column accent wash + a matching
// colored status dot in the header (driven by ColumnConfig.accent, a soft tint
// behind the cards, NOT a saturated block). Addendum item 2: the count is a
// small rounded pill, right-aligned and typographically de-emphasized.
//
// Collapsible (v2): a ChevronDownIcon toggle-button in the header collapses the
// column to a narrow vertical strip showing the rotated column name + count
// (Linear-style). Collapsed state is owned by the board (persisted in
// localStorage).

import type {
  ColumnConfig,
  WorkstreamIssue,
  WorkstreamStatus,
} from "@/lib/workstream";
import { ChevronDownIcon } from "@/components/icons";
import { IssueCard } from "./issue-card";

// ~15% accent wash — a visible soft tint behind the cards, not a saturated
// block (operator sign-off 2026-06-26, matches 01-workstream-kanban-board.png).
// Shared across both render branches so the expanded column and the collapsed
// strip stay in lockstep. hex 0x26 = 38/255 ≈ 15% (tunable band 0x1f–0x33).
const COLUMN_TINT_ALPHA = "26";

export function IssueColumn({
  column,
  issues,
  onOpen,
  collapsed = false,
  onToggleCollapse,
}: {
  column: ColumnConfig;
  issues: WorkstreamIssue[];
  onOpen: (id: string) => void;
  collapsed?: boolean;
  onToggleCollapse?: (status: WorkstreamStatus) => void;
}) {
  if (collapsed) {
    return (
      <section
        aria-label={column.label}
        className="flex w-10 shrink-0 flex-col items-center rounded-xl border border-soleur-border-default/60 py-2"
        style={{ backgroundColor: `${column.accent}${COLUMN_TINT_ALPHA}` }}
      >
        <button
          type="button"
          aria-label={`Expand ${column.label}`}
          aria-expanded={false}
          onClick={() => onToggleCollapse?.(column.status)}
          className="flex h-6 w-6 items-center justify-center rounded-md text-soleur-text-tertiary transition-colors hover:bg-soleur-bg-surface-2 hover:text-soleur-text-primary focus-visible:bg-soleur-bg-surface-2 focus-visible:text-soleur-text-primary focus-visible:outline-none"
        >
          {/* Down chevron rotated −90° points right = "expand". */}
          <ChevronDownIcon className="h-3.5 w-3.5 -rotate-90" />
        </button>
        <span
          aria-hidden="true"
          className="mt-2 h-2 w-2 rounded-full"
          style={{ backgroundColor: column.accent }}
        />
        <span className="mt-2 rounded-md bg-soleur-bg-surface-2 px-1.5 py-0.5 text-[11px] font-medium text-soleur-text-tertiary">
          {issues.length}
        </span>
        <h2
          className="mt-2 text-sm font-medium text-soleur-text-primary"
          style={{ writingMode: "vertical-rl" }}
        >
          {column.label}
        </h2>
      </section>
    );
  }

  return (
    <section
      aria-label={column.label}
      className="flex w-72 shrink-0 flex-col rounded-xl border border-soleur-border-default/60 p-2"
      // Soft ~15% accent wash — visible tint behind the cards, not a block.
      style={{ backgroundColor: `${column.accent}${COLUMN_TINT_ALPHA}` }}
    >
      <header className="flex items-center gap-2 px-1 py-2">
        <button
          type="button"
          aria-label={`Collapse ${column.label}`}
          aria-expanded={true}
          onClick={() => onToggleCollapse?.(column.status)}
          className="flex h-5 w-5 items-center justify-center rounded-md text-soleur-text-tertiary transition-colors hover:bg-soleur-bg-surface-2 hover:text-soleur-text-primary focus-visible:bg-soleur-bg-surface-2 focus-visible:text-soleur-text-primary focus-visible:outline-none"
        >
          {/* Down chevron = "collapse". */}
          <ChevronDownIcon className="h-3.5 w-3.5" />
        </button>
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
