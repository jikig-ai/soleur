"use client";

// Mobile-only Workstream board (below md). Replaces the cramped 7-column
// horizontal scroller with a status-selector tab strip + a single full-width
// card column for the selected status. Consumes the parent's ALREADY-FILTERED
// `issues` array + `onOpen`, so filters/search, ?issue URL↔drawer sync,
// optimistic writes (ADR-109), and read-only/429 handling are all preserved in
// the parent with zero duplication here. Desktop board is untouched.

import { useEffect, useMemo, useRef, useState } from "react";
import {
  COLUMNS,
  COLUMN_CAP_NOTICE,
  COLUMN_RENDER_CAP,
  STATUS_ORDER,
  statusLabel,
  type WorkstreamIssue,
  type WorkstreamStatus,
} from "@/lib/workstream";
import { IssueCard } from "./issue-card";
import { MobileStatusSelector } from "./mobile-status-selector";

const SELECTED_STATUS_KEY = "workstream:mobile-status-v1";

function isWorkstreamStatus(value: string): value is WorkstreamStatus {
  return (STATUS_ORDER as readonly string[]).includes(value);
}

/** Zeroed per-status count map, then filled from the passed issues. */
function countByStatus(issues: WorkstreamIssue[]): Record<WorkstreamStatus, number> {
  const counts = Object.fromEntries(
    STATUS_ORDER.map((s) => [s, 0]),
  ) as Record<WorkstreamStatus, number>;
  for (const issue of issues) counts[issue.status] += 1;
  return counts;
}

/** Default selection: stored value if valid, else the first non-empty column in
 *  board order, else `in_progress`. */
function initialStatus(issues: WorkstreamIssue[]): WorkstreamStatus {
  try {
    const stored = window.sessionStorage.getItem(SELECTED_STATUS_KEY);
    if (stored && isWorkstreamStatus(stored)) return stored;
  } catch {
    // sessionStorage unavailable (private mode) — fall through to a derived default.
  }
  const counts = countByStatus(issues);
  const firstNonEmpty = STATUS_ORDER.find((s) => counts[s] > 0);
  return firstNonEmpty ?? "in_progress";
}

export function MobileBoard({
  issues,
  onOpen,
  className,
}: {
  issues: WorkstreamIssue[];
  onOpen: (id: string) => void;
  className?: string;
}) {
  const [selectedStatus, setSelectedStatus] = useState<WorkstreamStatus>(() =>
    initialStatus(issues),
  );

  // Persist the selection (do not persist on unmount; write on every change).
  useEffect(() => {
    try {
      window.sessionStorage.setItem(SELECTED_STATUS_KEY, selectedStatus);
    } catch {
      // Non-persistent (private mode) — the in-memory selection still works.
    }
  }, [selectedStatus]);

  const counts = useMemo(() => countByStatus(issues), [issues]);
  const columnIssues = useMemo(
    () => issues.filter((i) => i.status === selectedStatus),
    [issues, selectedStatus],
  );
  const overCap = columnIssues.length > COLUMN_RENDER_CAP;

  // Hand-rolled horizontal swipe on the card panel to advance status (no dep).
  // The panel is a VERTICAL scroll region, so a swipe only counts when it is
  // horizontally dominant (|dx| > |dy|) — otherwise a thumb scroll that drifts
  // sideways would silently switch the status column mid-scroll.
  const touchStart = useRef<{ x: number; y: number } | null>(null);
  function advance(delta: number) {
    const idx = STATUS_ORDER.indexOf(selectedStatus);
    if (idx === -1) return;
    setSelectedStatus(STATUS_ORDER[(idx + delta + STATUS_ORDER.length) % STATUS_ORDER.length]);
  }

  return (
    <div className={`flex flex-col ${className ?? ""}`}>
      <MobileStatusSelector
        columns={COLUMNS}
        counts={counts}
        selected={selectedStatus}
        onSelect={setSelectedStatus}
      />

      <div
        id="workstream-mobile-panel"
        role="tabpanel"
        aria-labelledby={`workstream-tab-${selectedStatus}`}
        // APG: a tabpanel with no focusable child (the empty state) gets
        // tabIndex=0 so keyboard users can move focus into it; when cards are
        // present they are the focusable descendants, so no panel tabIndex.
        tabIndex={columnIssues.length === 0 ? 0 : undefined}
        className="mt-3 flex flex-col gap-3 safe-bottom"
        onTouchStart={(e) => {
          const t = e.touches[0];
          touchStart.current = t ? { x: t.clientX, y: t.clientY } : null;
        }}
        onTouchEnd={(e) => {
          const start = touchStart.current;
          touchStart.current = null;
          if (start == null) return;
          const end = e.changedTouches[0];
          if (!end) return;
          const dx = end.clientX - start.x;
          const dy = end.clientY - start.y;
          // Only a decisive, horizontally-dominant swipe changes status —
          // vertical/diagonal scroll gestures are ignored.
          if (Math.abs(dx) < 48 || Math.abs(dx) <= Math.abs(dy)) return;
          advance(dx < 0 ? 1 : -1);
        }}
      >
        {columnIssues.length === 0 ? (
          <p className="py-8 text-center text-sm text-soleur-text-muted">
            No issues in {statusLabel(selectedStatus)}.
          </p>
        ) : (
          <>
            {columnIssues.slice(0, COLUMN_RENDER_CAP).map((issue) => (
              <IssueCard key={issue.id} issue={issue} onOpen={onOpen} />
            ))}
            {overCap && (
              <p className="px-1 py-2 text-xs text-soleur-text-muted">{COLUMN_CAP_NOTICE}</p>
            )}
          </>
        )}
      </div>
    </div>
  );
}
