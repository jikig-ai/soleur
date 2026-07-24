"use client";

// Mobile-only status selector for the Workstream board: a horizontally
// scrollable tab strip of the 7 statuses (accent dot + label + count pill). The
// selected tab carries a gold ring + aria-selected. Follows the codebase tab
// a11y model (role=tablist/tab, roving tabIndex, Left/Right arrow moves
// selection) — see components/crm/crm-surface.tsx for the simpler precedent.

import { useEffect, useRef } from "react";
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

  // Keep the selected tab in view even when selection changes via a card-panel
  // swipe (not just keyboard), so the active tab never sits off-screen.
  useEffect(() => {
    tabRefs.current[selected]?.scrollIntoView({ block: "nearest", inline: "center" });
  }, [selected]);

  function selectByIndex(idx: number) {
    const next = columns[idx];
    if (!next) return;
    onSelect(next.status);
    tabRefs.current[next.status]?.focus();
    tabRefs.current[next.status]?.scrollIntoView({ block: "nearest", inline: "center" });
  }

  function moveSelection(delta: number) {
    const idx = columns.findIndex((c) => c.status === selected);
    if (idx === -1) return;
    selectByIndex((idx + delta + columns.length) % columns.length);
  }

  return (
    <div
      role="tablist"
      aria-label="Workstream status"
      aria-orientation="horizontal"
      className="-mx-1 flex gap-2 overflow-x-auto px-1 pb-1 [mask-image:linear-gradient(to_right,black_calc(100%_-_28px),transparent)]"
      onKeyDown={(e) => {
        if (e.key === "ArrowRight") {
          e.preventDefault();
          moveSelection(1);
        } else if (e.key === "ArrowLeft") {
          e.preventDefault();
          moveSelection(-1);
        } else if (e.key === "Home") {
          e.preventDefault();
          selectByIndex(0);
        } else if (e.key === "End") {
          e.preventDefault();
          selectByIndex(columns.length - 1);
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
            // Explicit name: the visible count pill is a bare trailing number
            // ("In Progress 5") — spell it out for AT.
            aria-label={`${column.label}, ${counts[column.status]} issues`}
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
