"use client";

// Mobile-only status selector for the Workstream board: a horizontally
// scrollable tab strip of the 7 statuses (accent dot + label + count pill). The
// selected tab carries a gold ring + aria-selected. Follows the codebase tab
// a11y model (role=tablist/tab, roving tabIndex, Left/Right arrow moves
// selection) — see components/crm/crm-surface.tsx for the simpler precedent.

import { useRef } from "react";
import type { ColumnConfig, WorkstreamStatus } from "@/lib/workstream";

export function MobileStatusSelector({
  columns,
  counts,
  selected,
  onSelect,
}: {
  columns: readonly ColumnConfig[];
  counts: Record<WorkstreamStatus, number>;
  selected: WorkstreamStatus;
  onSelect: (status: WorkstreamStatus) => void;
}) {
  const tabRefs = useRef<Record<string, HTMLButtonElement | null>>({});

  function moveSelection(delta: number) {
    const idx = columns.findIndex((c) => c.status === selected);
    if (idx === -1) return;
    const next = columns[(idx + delta + columns.length) % columns.length];
    onSelect(next.status);
    // Move focus + scroll the newly selected tab into view.
    tabRefs.current[next.status]?.focus();
    tabRefs.current[next.status]?.scrollIntoView({ block: "nearest", inline: "center" });
  }

  return (
    <div
      role="tablist"
      aria-label="Workstream status"
      aria-orientation="horizontal"
      className="-mx-1 flex gap-2 overflow-x-auto px-1 pb-1"
      onKeyDown={(e) => {
        if (e.key === "ArrowRight") {
          e.preventDefault();
          moveSelection(1);
        } else if (e.key === "ArrowLeft") {
          e.preventDefault();
          moveSelection(-1);
        }
      }}
    >
      {columns.map((column) => {
        const isSelected = column.status === selected;
        return (
          <button
            key={column.status}
            ref={(el) => {
              tabRefs.current[column.status] = el;
            }}
            type="button"
            role="tab"
            id={`workstream-tab-${column.status}`}
            aria-selected={isSelected}
            aria-controls="workstream-mobile-panel"
            tabIndex={isSelected ? 0 : -1}
            onClick={() => onSelect(column.status)}
            className={`flex min-h-11 shrink-0 items-center gap-2 rounded-full border px-4 text-sm font-medium transition-colors ${
              isSelected
                ? "border-transparent bg-soleur-bg-surface-2 text-soleur-text-primary ring-2 ring-soleur-accent-gold-fg"
                : "border-soleur-border-default bg-transparent text-soleur-text-secondary hover:text-soleur-text-primary"
            }`}
          >
            <span
              aria-hidden="true"
              className="h-2 w-2 shrink-0 rounded-full"
              style={{ backgroundColor: column.accent }}
            />
            <span>{column.label}</span>
            <span className="rounded-full bg-soleur-bg-surface-1 px-1.5 text-xs tabular-nums text-soleur-text-tertiary">
              {counts[column.status]}
            </span>
          </button>
        );
      })}
    </div>
  );
}
