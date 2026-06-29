"use client";

// One kanban column. Addendum item 1: a per-column accent wash + a matching
// colored status dot in the header (driven by ColumnConfig.accent, a soft tint
// behind the cards, NOT a saturated block). Addendum item 2: the count is a
// small rounded pill, right-aligned and typographically de-emphasized.
//
// Collapse rule (v5): a column's open/closed state is driven SOLELY by whether
// it has content. A column with content is ALWAYS expanded; a column with 0
// issues is ALWAYS collapsed (a thin w-10 strip with the dot, a 0 count, the
// vertical label, and an sr-only "No issues"). There is NO manual collapse
// toggle and no persisted state — emptiness is the only input. The width toggles
// (w-72 ↔ w-10) on a SINGLE persistent <section> with a real transition-[width]
// animation so filtering a column to/from empty glides rather than snapping (a
// conditional-render swap would NOT animate — learning 2026-06-09 / SE1). Inner
// content fades in via a rAF mount-reveal.
//
// Render cap: at most COLUMN_RENDER_CAP cards render; beyond that the exact
// COLUMN_CAP_NOTICE shows at the column bottom. The count pill always shows the
// true (uncapped) count of THIS column's post-filter issues — i.e. the cap
// limits rendered cards, never the displayed total.

import { useEffect, useState } from "react";
import {
  COLUMN_CAP_NOTICE,
  COLUMN_RENDER_CAP,
  type ColumnConfig,
  type WorkstreamIssue,
} from "@/lib/workstream";
import { IssueCard } from "./issue-card";

// ~15% accent wash — a visible soft tint behind the cards, not a saturated
// block (operator sign-off 2026-06-26, matches 01-workstream-kanban-board.png).
// hex 0x26 = 38/255 ≈ 15% (tunable band 0x1f–0x33).
const COLUMN_TINT_ALPHA = "26";

/** Fades its children in on mount (opacity 0→1 via a rAF state flip). Pairs with
 *  the persistent-section width transition so a column gliding to/from its
 *  collapsed strip fades rather than snapping. `motion-reduce` makes it instant. */
function MountReveal({ children }: { children: React.ReactNode }) {
  const [shown, setShown] = useState(false);
  useEffect(() => {
    const id = requestAnimationFrame(() => setShown(true));
    return () => cancelAnimationFrame(id);
  }, []);
  return (
    <div
      className={`transition-opacity duration-200 motion-reduce:transition-none ${
        shown ? "opacity-100" : "opacity-0"
      }`}
    >
      {children}
    </div>
  );
}

export function IssueColumn({
  column,
  issues,
  onOpen,
}: {
  column: ColumnConfig;
  issues: WorkstreamIssue[];
  onOpen: (id: string) => void;
}) {
  const isEmpty = issues.length === 0;
  // Emptiness is the SOLE driver: content ⇒ open, empty ⇒ collapsed. No manual
  // toggle, no persisted state.
  const isCollapsed = isEmpty;
  const tint = { backgroundColor: `${column.accent}${COLUMN_TINT_ALPHA}` };
  const overCap = issues.length > COLUMN_RENDER_CAP;

  return (
    <section
      aria-label={column.label}
      className={`shrink-0 rounded-xl border border-soleur-border-default/60 transition-[width] duration-200 ease-out motion-reduce:transition-none ${
        isCollapsed ? "flex w-10 flex-col items-center py-2" : "flex w-72 flex-col p-2"
      }`}
      style={tint}
    >
      {isCollapsed ? (
        <MountReveal key="collapsed">
          <div className="flex flex-col items-center">
            {/* Empty strip: the sr-only text is the canonical empty announcement
                so a screen reader doesn't hear a bare, ambiguous "0"; the visible
                "0" pill is aria-hidden. There is no toggle — an empty column
                cannot be expanded. */}
            <span className="sr-only">No issues</span>
            <span
              aria-hidden="true"
              className="h-2 w-2 rounded-full"
              style={{ backgroundColor: column.accent }}
            />
            <span
              aria-hidden="true"
              className="mt-2 rounded-md bg-soleur-bg-surface-2 px-1.5 py-0.5 text-[11px] font-medium text-soleur-text-tertiary"
            >
              {issues.length}
            </span>
            <h2
              className="mt-2 text-sm font-medium text-soleur-text-primary"
              style={{ writingMode: "vertical-rl" }}
            >
              {column.label}
            </h2>
          </div>
        </MountReveal>
      ) : (
        <MountReveal key="expanded">
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
            {issues.slice(0, COLUMN_RENDER_CAP).map((issue) => (
              <IssueCard key={issue.id} issue={issue} onOpen={onOpen} />
            ))}
            {overCap ? (
              <p className="px-1 py-2 text-xs text-soleur-text-tertiary">
                {COLUMN_CAP_NOTICE}
              </p>
            ) : null}
          </div>
        </MountReveal>
      )}
    </section>
  );
}
