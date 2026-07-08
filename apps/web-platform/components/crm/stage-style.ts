// UI styling for the beta-CRM pipeline stages (feat-beta-crm-ui #6172). The
// ORDERED stage enum is imported from the single source of truth
// (server/crm/stage-probability.ts) and never re-declared here (AC7) — these
// maps are keyed by stage (unquoted identifiers, not string literals) so a
// stage-list grep finds nothing, and Record<Stage, …> makes a missing stage a
// COMPILE error (a free drift guard). Accent hexes mirror the operator-approved
// wireframe (knowledge-base/product/design/crm/beta-crm-pipeline.pen).

import { STAGES, type Stage } from "@/server/crm/stage-probability";

export { STAGES };
export type { Stage };

/** Title-case display label per stage. */
export const STAGE_LABEL: Record<Stage, string> = {
  new: "New",
  contacted: "Contacted",
  qualified: "Qualified",
  evaluating: "Evaluating",
  committed: "Committed",
  closed_won: "Closed Won",
  closed_lost: "Closed Lost",
};

/** Per-stage accent hex — the column dot, the funnel bar, the drawer pill. */
export const STAGE_ACCENT: Record<Stage, string> = {
  new: "#5b8def",
  contacted: "#d9a441",
  qualified: "#c99a3a",
  evaluating: "#8b6fc9",
  committed: "#3a9a9a",
  closed_won: "#3fa85f",
  closed_lost: "#c0453f",
};

/** The linear funnel order (closed_lost is a terminal branch, not a column/bar). */
export const FUNNEL_STAGES: Stage[] = STAGES.filter((s) => s !== "closed_lost");

/** Hex alpha (~15%) appended to an accent for the column background wash. */
export const COLUMN_TINT_ALPHA = "22";
