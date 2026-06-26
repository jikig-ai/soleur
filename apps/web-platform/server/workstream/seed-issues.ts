// Workstream board seed data + the single accessor seam.
//
// `getWorkstreamIssues()` is the ONE swap point (the "same shared fn" rule from
// the routines precedent): BOTH the HTTP route (app/api/workstream/issues) AND
// the agent read tool (server/workstream/workstream-tools) import it directly —
// the tool never self-calls the route. When persistence / GitHub-backing lands,
// only this function body changes.
//
// v1 is read-only in-repo seed data: no Supabase table, no migration, no PII.

import type { WorkstreamIssue } from "@/lib/workstream";

const SEED_ISSUES: readonly WorkstreamIssue[] = [
  // ---- Backlog ----
  {
    id: "SOLAA-219",
    title: "Define issue schema & status enum",
    description:
      "Pin the `WorkstreamIssue` shape and the 7-value status union before the\nboard ships, so the accessor seam and the agent read tool agree on one\ncontract.",
    status: "backlog",
    priority: "urgent",
    assigneeRole: "cto",
    createdAt: "2026-06-18T09:00:00.000Z",
    updatedAt: "2026-06-18T09:00:00.000Z",
  },
  {
    id: "SOLAA-211",
    title: "Spec assignee role mapping (CTO/COO/CMO)",
    description:
      "Map the agent-org leaders to role-initial chips and a self-contained\ncolor palette (no `lib → components` import).",
    status: "backlog",
    priority: "medium",
    assigneeRole: "cpo",
    user: { name: "Dana Ortiz", initials: "DO" },
    createdAt: "2026-06-18T10:00:00.000Z",
    updatedAt: "2026-06-19T08:00:00.000Z",
  },
  {
    id: "SOLAA-212",
    title: "Draft empty-state copy for board columns",
    description:
      "Honest, calm empty/no-results copy distinct from the error state.",
    status: "backlog",
    priority: "low",
    assigneeRole: "cmo",
    createdAt: "2026-06-18T11:00:00.000Z",
    updatedAt: "2026-06-18T11:00:00.000Z",
  },
  // ---- Todo ----
  {
    id: "SOLAA-205",
    title: "Build column header with count badge",
    description:
      "Per-column header: colored status dot + title + a right-aligned count\npill (de-emphasized).",
    status: "todo",
    priority: "medium",
    assigneeRole: "cto",
    createdAt: "2026-06-19T09:00:00.000Z",
    updatedAt: "2026-06-19T09:00:00.000Z",
  },
  {
    id: "SOLAA-208",
    title: "Add priority indicator to issue card",
    description:
      "Linear-style labeled priority pill (accent bar + color text), 5 levels:\nUrgent, High, Medium, Low, None.",
    status: "todo",
    priority: "high",
    assigneeRole: "cto",
    user: { name: "Harry Cole", initials: "HC" },
    createdAt: "2026-06-19T10:00:00.000Z",
    updatedAt: "2026-06-20T12:00:00.000Z",
  },
  {
    id: "SOLAA-207",
    title: "Wire Search issues input (client filter)",
    description: "Filter cards by id + title; distinct no-results state.",
    status: "todo",
    priority: "medium",
    assigneeRole: "cpo",
    createdAt: "2026-06-19T11:00:00.000Z",
    updatedAt: "2026-06-19T11:00:00.000Z",
  },
  // ---- In Progress (some Live) ----
  {
    id: "SOLAA-198",
    title: "Wire Workstream board to live issue store",
    description:
      "Connect the Workstream board to the live issue store so columns reflect\nreal status. In v1 the board is a read-only preview — drag-and-drop and\nedits are not persisted yet. Decisions about scope are captured in the\nthread below.",
    status: "in_progress",
    priority: "high",
    assigneeRole: "cto",
    user: { name: "Harry Cole", initials: "HC" },
    live: true,
    createdAt: "2026-06-24T09:00:00.000Z",
    updatedAt: "2026-06-26T08:00:00.000Z",
  },
  {
    id: "SOLAA-199",
    title: "Concierge decision thread (read-only v1)",
    description:
      "Per-issue Decision Making panel — wired but offline in v1, with a\n\"Discuss in Chat\" deep-link to the live chat surface.",
    status: "in_progress",
    priority: "high",
    assigneeRole: "cpo",
    live: true,
    createdAt: "2026-06-24T10:00:00.000Z",
    updatedAt: "2026-06-25T16:00:00.000Z",
  },
  // ---- In Review ----
  {
    id: "SOLAA-195",
    title: "Kanban drag-and-drop reorder",
    description: "Deferred to a follow-up — no new dnd dependency in v1.",
    status: "in_review",
    priority: "medium",
    assigneeRole: "cto",
    createdAt: "2026-06-22T09:00:00.000Z",
    updatedAt: "2026-06-25T09:00:00.000Z",
  },
  {
    id: "SOLAA-192",
    title: "Preview banner + non-persistence note",
    description:
      "Surface the read-only preview honestly: board-level banner + a note at\nthe moment of each optimistic action.",
    status: "in_review",
    priority: "low",
    assigneeRole: "cmo",
    user: { name: "Dana Ortiz", initials: "DO" },
    createdAt: "2026-06-22T10:00:00.000Z",
    updatedAt: "2026-06-25T10:00:00.000Z",
  },
  // ---- Blocked ----
  {
    id: "SOLAA-190",
    title: "Realtime sync (blocked on store API)",
    description: "Blocked until the persistence/store API lands.",
    status: "blocked",
    priority: "urgent",
    assigneeRole: "cto",
    createdAt: "2026-06-20T09:00:00.000Z",
    updatedAt: "2026-06-24T09:00:00.000Z",
  },
  // ---- Done ----
  {
    id: "SOLAA-110",
    title: "Add Workstream tab to dashboard nav",
    description: "Nav entry + ⌘K palette pick-up via the shared NAV_ITEMS.",
    status: "done",
    priority: "medium",
    assigneeRole: "cto",
    createdAt: "2026-06-15T09:00:00.000Z",
    updatedAt: "2026-06-17T09:00:00.000Z",
  },
  {
    id: "SOLAA-172",
    title: "Status pill component",
    description: "Per-status color pill, consistent with the column accents.",
    status: "done",
    priority: "low",
    assigneeRole: "cto",
    createdAt: "2026-06-16T09:00:00.000Z",
    updatedAt: "2026-06-18T09:00:00.000Z",
  },
  {
    id: "SOLAA-176",
    title: "Role-chip avatar component",
    description: "Initials chip for the role assignee + secondary user avatar.",
    status: "done",
    priority: "low",
    assigneeRole: "cco",
    createdAt: "2026-06-16T11:00:00.000Z",
    updatedAt: "2026-06-18T11:00:00.000Z",
  },
];

/**
 * The single accessor seam for the Workstream board. Pure (no IO) in v1 —
 * returns the in-repo seed. Deep-enough copy each call (the nested `user`
 * object is cloned too) so callers cannot mutate the module-level seed —
 * including the agent read tool, which serializes this same payload.
 */
export function getWorkstreamIssues(): WorkstreamIssue[] {
  return SEED_ISSUES.map((i) => ({
    ...i,
    ...(i.user ? { user: { ...i.user } } : {}),
  }));
}
