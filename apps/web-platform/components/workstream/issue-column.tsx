"use client";

// One kanban column. Addendum item 1: a per-column accent wash + a matching
// colored status dot in the header (driven by ColumnConfig.accent, a soft tint
// behind the cards, NOT a saturated block). Addendum item 2: the count is a
// small rounded pill, right-aligned and typographically de-emphasized.
//
// Collapsible (v6): a SINGLE persistent <section> whose width class toggles
// (w-72 ↔ w-10) with a real transition-[width] animation — a conditional-render
// swap would NOT animate (no prior committed frame; learning 2026-06-09 / SE1).
// Only ONE control button exists at a time (Collapse when expanded / Expand when
// collapsed). Inner content fades in via a rAF mount-reveal. The board owns the
// persisted collapse choice.
//
// Default + override rule (v6):
//   - A column WITH content is OPEN by default and CAN be collapsed by the user
//     (Collapse toggle → persisted strip with an Expand toggle to reopen).
//   - A column with 0 issues is COLLAPSED by default and has NO toggle (there is
//     nothing to expand to). The persisted flag is left untouched while empty, so
//     a column's prior choice re-applies once it repopulates.
//   isCollapsed = isEmpty || collapsed  — empty forces the strip; otherwise the
//   user's persisted choice decides.
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
  type WorkstreamStatus,
} from "@/lib/workstream";
import { ChevronDownIcon } from "@/components/icons";
import { IssueCard } from "./issue-card";

// ~15% accent wash — a visible soft tint behind the cards, not a saturated
// block (operator sign-off 2026-06-26, matches 01-workstream-kanban-board.png).
// hex 0x26 = 38/255 ≈ 15% (tunable band 0x1f–0x33).
const COLUMN_TINT_ALPHA = "26";

const TOGGLE_BTN_CLASS =
  "flex h-5 w-5 items-center justify-center rounded-md text-soleur-text-tertiary transition-colors hover:bg-soleur-bg-surface-2 hover:text-soleur-text-primary focus-visible:bg-soleur-bg-surface-2 focus-visible:text-soleur-text-primary focus-visible:outline-none";

/** Fades its children in on mount (opacity 0→1 via a rAF state flip). Pairs with
 *  the persistent-section width transition so collapsing/expanding glides rather
 *  than snapping. `motion-reduce` makes it instant. */
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
  collapsed = false,
  onToggleCollapse,
}: {
  column: ColumnConfig;
  issues: WorkstreamIssue[];
  onOpen: (id: string) => void;
  collapsed?: boolean;
  onToggleCollapse?: (status: WorkstreamStatus) => void;
}) {
  const isEmpty = issues.length === 0;
  // Empty forces the collapsed strip (no content to show); otherwise the user's
  // persisted choice decides. So content is OPEN by default (collapsed defaults
  // false) but CAN be collapsed. The persisted flag is never mutated for empty
  // columns, so a prior choice re-applies on repopulate.
  const isCollapsed = isEmpty || collapsed;
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
            {/* A user-collapsed NON-empty strip gets an Expand toggle; an empty
                strip has none (nothing to expand to). */}
            {!isEmpty ? (
              <button
                type="button"
                aria-label={`Expand ${column.label}`}
                aria-expanded={false}
                onClick={() => onToggleCollapse?.(column.status)}
                className={TOGGLE_BTN_CLASS}
              >
                {/* Down chevron rotated −90° points right = "expand". */}
                <ChevronDownIcon className="h-3.5 w-3.5 -rotate-90" />
              </button>
            ) : null}
            {/* Empty strip: the sr-only text is the canonical empty announcement
                so a screen reader doesn't hear a bare, ambiguous "0"; the visible
                "0" pill is aria-hidden when empty. */}
            {isEmpty ? <span className="sr-only">No issues</span> : null}
            <span
              aria-hidden="true"
              className="mt-2 h-2 w-2 rounded-full"
              style={{ backgroundColor: column.accent }}
            />
            <span
              aria-hidden={isEmpty ? true : undefined}
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
            {/* The expanded branch only renders for NON-empty columns
                (isEmpty ⇒ isCollapsed), so the Collapse toggle is always present
                here — every content column can be collapsed. */}
            <button
              type="button"
              aria-label={`Collapse ${column.label}`}
              aria-expanded={true}
              onClick={() => onToggleCollapse?.(column.status)}
              className={TOGGLE_BTN_CLASS}
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
