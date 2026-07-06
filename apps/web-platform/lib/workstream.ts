// Workstream board — pure data model + display helpers (no React, no
// `components/` import: keeping this layer node-unit-testable and avoiding a
// `lib → components` layering inversion, arch P2-1). The role→color map is a
// SELF-CONTAINED copy of the leader palette values (components/chat/
// leader-colors.ts) — duplicated on purpose so this module stays leaf.
//
// Design Revision Addendum (operator sign-off 2026-06-26) is binding here:
//   1. per-column subtle tint + colored header dot (COLUMNS[].accent)
//   2. count badge pills (rendered in issue-column.tsx)
//   3. priority = labeled pill (priorityLabel + priorityPillClass), 5 levels
//   4. "Live" marker = green dot + green text, no fill (rendered in issue-card)
//   5. `user` field — a PERSON distinct from the role assignee

// Column vocabulary mirrors the canonical GitHub Project v2 board "Soleur Kanban"
// (ADR-091): Backlog, Ready, In progress, In review, Blocked, Pending, Done.
// The board has no Cancelled column, so closed issues fold to `done`.
export type WorkstreamStatus =
  | "backlog"
  | "ready"
  | "in_progress"
  | "in_review"
  | "blocked"
  | "pending"
  | "done";

export type WorkstreamPriority = "urgent" | "high" | "medium" | "low" | "none";

/** Role assignee ids — the agent organization's leaders (+ CEO/founder). */
export type WorkstreamRole =
  | "cto"
  | "cmo"
  | "cpo"
  | "cfo"
  | "cro"
  | "coo"
  | "clo"
  | "cco"
  | "ceo";

/** A specific person associated with an issue — semantically distinct from the
 *  role assignee (CTO/COO/…). Addendum item 5. */
export interface WorkstreamUser {
  name: string;
  initials: string;
}

export interface WorkstreamIssue {
  /** The GitHub repo issue number as a string, e.g. "5652" (also the React key
   *  and the `?issue=` deep-link param). Optimistic-local cards use "SOLAA-N*". */
  id: string;
  title: string;
  description: string;
  status: WorkstreamStatus;
  priority: WorkstreamPriority;
  /** Role assignee (CTO/COO/…) or null when unassigned. */
  assigneeRole: WorkstreamRole | null;
  /** A specific person (distinct from the role assignee). Optional. */
  user?: WorkstreamUser;
  /** "Live" flag — set when an open issue carries the `in-progress` label.
   *  User-created optimistic cards never set this (spec-flow #14). */
  live?: boolean;
  /** All `domain/*` labels on the issue (filter dimension 1d). OPTIONAL +
   *  additive — absent for every pre-existing construction site, so existing
   *  constructors stay valid (arch review D1). Distinct from `assigneeRole`,
   *  which collapses only the FIRST domain label into a role. */
  domains?: string[];
  createdAt: string; // ISO-8601
  updatedAt: string; // ISO-8601
}

// ---------------------------------------------------------------------------
// Columns config (ordered) — Addendum item 1: each column carries an `accent`
// hex used for a faint background tint + a matching header status dot.
// ---------------------------------------------------------------------------
export interface ColumnConfig {
  status: WorkstreamStatus;
  label: string;
  /** Low-luminance accent hex (header dot + faint column tint). */
  accent: string;
}

export const COLUMNS: readonly ColumnConfig[] = [
  { status: "backlog", label: "Backlog", accent: "#9AA3B2" },
  { status: "ready", label: "Ready", accent: "#5E84C4" },
  { status: "in_progress", label: "In Progress", accent: "#E0A93B" },
  { status: "in_review", label: "In Review", accent: "#A87BE0" },
  { status: "blocked", label: "Blocked", accent: "#E5534B" },
  { status: "pending", label: "Pending", accent: "#3FA6B0" },
  { status: "done", label: "Done", accent: "#3FB950" },
] as const;

/** Ordered list of statuses (column order). */
export const STATUS_ORDER: readonly WorkstreamStatus[] = COLUMNS.map(
  (c) => c.status,
);

export function statusLabel(status: WorkstreamStatus): string {
  return COLUMNS.find((c) => c.status === status)?.label ?? status;
}

export function columnAccent(status: WorkstreamStatus): string {
  return COLUMNS.find((c) => c.status === status)?.accent ?? "#9AA3B2";
}

/** Tailwind text-color class for a status pill (detail Sheet status row).
 *  In Progress is AMBER to match the recolored In Progress column tint. */
export function statusPillClass(status: WorkstreamStatus): string {
  switch (status) {
    case "backlog":
      return "text-slate-300";
    case "ready":
      return "text-blue-300";
    case "in_progress":
      return "text-amber-300";
    case "in_review":
      return "text-violet-300";
    case "blocked":
      return "text-red-300";
    case "pending":
      return "text-teal-300";
    case "done":
      return "text-green-300";
  }
}

// ---------------------------------------------------------------------------
// Priority — Addendum item 3: a labeled pill (color accent bar + color text),
// 5 distinct levels. Replaces the old bare dot.
// ---------------------------------------------------------------------------
export function priorityLabel(priority: WorkstreamPriority): string {
  switch (priority) {
    case "urgent":
      return "Urgent";
    case "high":
      return "High";
    case "medium":
      return "Medium";
    case "low":
      return "Low";
    case "none":
      return "None";
  }
}

/** Tailwind text-color class for the priority pill label. */
export function priorityPillClass(priority: WorkstreamPriority): string {
  switch (priority) {
    case "urgent":
      return "text-red-400";
    case "high":
      return "text-orange-400";
    case "medium":
      return "text-yellow-400";
    case "low":
      return "text-slate-400";
    case "none":
      return "text-soleur-text-tertiary";
  }
}

/** Tailwind bg-color class for the small priority accent bar. */
export function priorityBarClass(priority: WorkstreamPriority): string {
  switch (priority) {
    case "urgent":
      return "bg-red-500";
    case "high":
      return "bg-orange-500";
    case "medium":
      return "bg-yellow-500";
    case "low":
      return "bg-slate-500";
    case "none":
      return "bg-neutral-600";
  }
}

// ---------------------------------------------------------------------------
// Assignee role — SELF-CONTAINED initials + color map (copied from the leader
// palette; do NOT import from components/).
// ---------------------------------------------------------------------------

/** Role → Tailwind bg-color class for the initials chip. */
const ROLE_BG_COLORS: Record<WorkstreamRole, string> = {
  cmo: "bg-pink-500",
  cto: "bg-blue-500",
  cfo: "bg-emerald-500",
  cpo: "bg-violet-500",
  cro: "bg-orange-500",
  coo: "bg-amber-500",
  clo: "bg-slate-400",
  cco: "bg-cyan-500",
  ceo: "bg-neutral-600",
};

/** Role → human title (detail Sheet assignee row). */
const ROLE_TITLES: Record<WorkstreamRole, string> = {
  cmo: "Chief Marketing (role lead)",
  cto: "Chief Technology (role lead)",
  cfo: "Chief Financial (role lead)",
  cpo: "Chief Product (role lead)",
  cro: "Chief Revenue (role lead)",
  coo: "Chief Operations (role lead)",
  clo: "Chief Legal (role lead)",
  cco: "Chief Communications (role lead)",
  ceo: "Chief Executive (role lead)",
};

/** Uppercase initials for a role chip (e.g. "CTO"), or "—" when unassigned. */
export function assigneeInitials(role: WorkstreamRole | null): string {
  return role ? role.toUpperCase() : "—";
}

export function roleColorClass(role: WorkstreamRole | null): string {
  return role ? ROLE_BG_COLORS[role] : "bg-neutral-700";
}

export function roleTitle(role: WorkstreamRole | null): string {
  return role ? ROLE_TITLES[role] : "Unassigned";
}

// ---------------------------------------------------------------------------
// "Live" marker — derived from seed data only (status In Progress + `live`).
// ---------------------------------------------------------------------------
export function isLive(issue: WorkstreamIssue): boolean {
  return issue.status === "in_progress" && issue.live === true;
}

// ---------------------------------------------------------------------------
// GitHub-issue → WorkstreamIssue PURE mapping (no IO — the IO accessor lives in
// server/workstream/get-workstream-issues.ts). Keeps this module a node-unit-
// testable leaf. The reader (server/github-read-tools.ts:listRepoIssues) narrows
// the raw REST payload to `BoardIssueInput`; this maps it to the board model.
//
// Mapping is DEFENSIVE: an unmapped / missing label degrades to null/none/backlog
// and NEVER throws (real repos won't carry the soleur label taxonomy verbatim).
// ---------------------------------------------------------------------------

/** The narrowed GitHub-issue shape the pure mapper consumes (no IO). */
export interface BoardIssueInput {
  number: number;
  title: string;
  body: string | null;
  /** Assignee login handles (first one becomes the `user`). */
  assignees: string[];
  /** Label names (e.g. "domain/engineering", "priority/p0-critical", "blocked"). */
  labels: string[];
  state: "open" | "closed";
  /** GitHub `state_reason`: completed | reopened | not_planned | duplicate | null. */
  state_reason: string | null;
  created_at: string;
  updated_at: string;
  /** Canonical GitHub Project v2 board Status option name (Phase 2, ADR-091) —
   *  e.g. "In progress"/"Pending". When present AND mappable it OVERRIDES the
   *  label/state derivation below; absent (issue not on the board, or the board
   *  read degraded) falls back to derivation. */
  boardStatus?: string;
}

/** `domain/*` label → role chip. First matching label (in issue order) wins. */
export const DOMAIN_LABEL_TO_ROLE: Record<string, WorkstreamRole> = {
  "domain/engineering": "cto",
  "domain/product": "cpo",
  "domain/marketing": "cmo",
  "domain/operations": "coo",
  "domain/finance": "cfo",
  "domain/legal": "clo",
  "domain/sales": "cro",
  "domain/support": "cco",
};

/** `priority/*` label → priority. Absent → `none`. */
export const PRIORITY_LABEL_TO_PRIORITY: Record<string, WorkstreamPriority> = {
  "priority/p0-critical": "urgent",
  "priority/p1-high": "high",
  "priority/p2-medium": "medium",
  "priority/p3-low": "low",
};

/** Canonical GitHub board Status option name → app column (ADR-091). Keyed
 *  lowercase so "In progress"/"In Progress" both map. Unknown → null (fall back
 *  to label/state derivation). */
const BOARD_STATUS_TO_WORKSTREAM: Record<string, WorkstreamStatus> = {
  backlog: "backlog",
  ready: "ready",
  "in progress": "in_progress",
  "in review": "in_review",
  blocked: "blocked",
  pending: "pending",
  done: "done",
};

/** Map a GitHub Project v2 board Status option name to the app column, or null
 *  when the name isn't one of the 7 canonical columns. */
export function boardStatusToWorkstreamStatus(
  name: string,
): WorkstreamStatus | null {
  return BOARD_STATUS_TO_WORKSTREAM[name.trim().toLowerCase()] ?? null;
}

/**
 * Derive the kanban column. The canonical GitHub Project v2 board Status WINS
 * when present + mappable (ADR-091); the state+label derivation below is the
 * FALLBACK for issues not on the board (or when the board read degraded). The
 * board has no Cancelled column, so every closed issue folds to `done`
 * (not_planned / duplicate closed issues render under Done).
 * Fallback precedence (open):
 *   `blocked` → blocked; else `pending` → pending; else `in-progress` →
 *   in_progress; else `review`/`needs-review` → in_review; else `ready`/`todo`
 *   → ready; else backlog.
 */
export function deriveColumn(input: BoardIssueInput): WorkstreamStatus {
  // Board Status is canonical when present and recognized.
  if (input.boardStatus) {
    const mapped = boardStatusToWorkstreamStatus(input.boardStatus);
    if (mapped) return mapped;
  }
  const labels = input.labels;
  if (input.state === "closed") {
    // Board has no Cancelled column — all closed issues fold to done.
    return "done";
  }
  // open
  if (labels.includes("blocked")) return "blocked";
  if (labels.includes("pending")) return "pending";
  if (labels.includes("in-progress")) return "in_progress";
  if (labels.includes("review") || labels.includes("needs-review")) {
    return "in_review";
  }
  if (labels.includes("ready") || labels.includes("todo")) return "ready";
  return "backlog";
}

/** Live only when the derived column is in_progress — mirrors deriveColumn so
 *  `live` is never set on a card that lands in another column (e.g. an open
 *  issue labelled BOTH `blocked` + `in-progress` resolves to `blocked`, where
 *  `blocked` wins, so it must not also read as live). */
export function deriveLive(input: BoardIssueInput): boolean {
  return deriveColumn(input) === "in_progress";
}

/** First assignee login → a board user; none → undefined. */
export function deriveUser(assignees: string[]): WorkstreamUser | undefined {
  const login = assignees[0];
  if (!login) return undefined;
  return { name: login, initials: login.slice(0, 2).toUpperCase() };
}

/** First `priority/*` label (in issue order) → priority; absent → `none`. */
export function derivePriority(labels: string[]): WorkstreamPriority {
  for (const label of labels) {
    const mapped = PRIORITY_LABEL_TO_PRIORITY[label];
    if (mapped) return mapped;
  }
  return "none";
}

/** First `domain/*` label (in issue order) → role; none → null. */
export function deriveRole(labels: string[]): WorkstreamRole | null {
  for (const label of labels) {
    const mapped = DOMAIN_LABEL_TO_ROLE[label];
    if (mapped) return mapped;
  }
  return null;
}

/**
 * Map one narrowed GitHub issue to a `WorkstreamIssue`. Never throws on
 * missing/unmapped labels (degrades to null/none/backlog). `id` is
 * `String(number)` — repo-scoped, collision-free, also the React key + the
 * `?issue=` deep-link param.
 */
export function githubIssueToWorkstreamIssue(
  input: BoardIssueInput,
): WorkstreamIssue {
  const user = deriveUser(input.assignees);
  const domains = input.labels.filter((l) => l.startsWith("domain/"));
  return {
    id: String(input.number),
    title: input.title,
    description: input.body ?? "",
    status: deriveColumn(input),
    priority: derivePriority(input.labels),
    assigneeRole: deriveRole(input.labels),
    ...(user ? { user } : {}),
    ...(deriveLive(input) ? { live: true } : {}),
    ...(domains.length ? { domains } : {}),
    createdAt: input.created_at,
    updatedAt: input.updated_at,
  };
}

// ---------------------------------------------------------------------------
// Filtering, search, faceted options + render-cap constants (client-side, pure).
// All operate over the already-fetched issue set — no IO, node-unit-testable.
// ---------------------------------------------------------------------------

/** Statuses that read as "closed" — the single source of truth shared by
 *  `isClosed` and the Status filter (arch review D4; mirrors `deriveColumn`'s
 *  closed branch, which now maps every closed GitHub issue to `done` since the
 *  board has no Cancelled column, ADR-091). */
export const CLOSED_STATUSES: ReadonlySet<WorkstreamStatus> = new Set([
  "done",
]);

/** An issue reads as closed iff its column is `done`. Sound + complete for
 *  GitHub-sourced issues (`deriveColumn` sends every closed issue to `done`); an
 *  optimistic local move to done also reads closed, which is semantically
 *  correct. */
export function isClosed(i: WorkstreamIssue): boolean {
  return CLOSED_STATUSES.has(i.status);
}

/** Board filter state. AND across dimensions, OR within. Empty set / `"all"`
 *  ⇒ that dimension is inactive (passes everything). In-memory only (not
 *  persisted), matching the existing `search` precedent (D5). */
export interface WorkstreamFilters {
  priorities: Set<WorkstreamPriority>;
  /** Tri-state radio (D4); default `"all"`. */
  status: "all" | "open" | "closed";
  roles: Set<WorkstreamRole>;
  /** `user.name` values. */
  users: Set<string>;
  /** Assignee dimension: include unassigned issues (role null && no user). */
  unassigned: boolean;
  /** `domain/*` label values. */
  domains: Set<string>;
}

/** The neutral, show-everything filter state. */
export function emptyFilters(): WorkstreamFilters {
  return {
    priorities: new Set(),
    status: "all",
    roles: new Set(),
    users: new Set(),
    unassigned: false,
    domains: new Set(),
  };
}

/** AND across dimensions, OR within each. */
export function matchesFilters(
  i: WorkstreamIssue,
  f: WorkstreamFilters,
): boolean {
  // Priority
  if (f.priorities.size > 0 && !f.priorities.has(i.priority)) return false;
  // Status (tri-state)
  if (f.status !== "all" && isClosed(i) !== (f.status === "closed")) {
    return false;
  }
  // Assignee (role OR person OR unassigned)
  if (f.roles.size > 0 || f.users.size > 0 || f.unassigned) {
    const roleMatch = i.assigneeRole !== null && f.roles.has(i.assigneeRole);
    const userMatch = i.user !== undefined && f.users.has(i.user.name);
    const unassignedMatch =
      f.unassigned && i.assigneeRole === null && i.user === undefined;
    if (!roleMatch && !userMatch && !unassignedMatch) return false;
  }
  // Domain
  if (f.domains.size > 0) {
    const hit = (i.domains ?? []).some((d) => f.domains.has(d));
    if (!hit) return false;
  }
  return true;
}

/** True when ANY filter dimension or the search box is active. Drives the
 *  Reset button's disabled state. */
export function hasActiveFilters(
  f: WorkstreamFilters,
  search: string,
): boolean {
  return (
    search.trim() !== "" ||
    f.priorities.size > 0 ||
    f.status !== "all" ||
    f.roles.size > 0 ||
    f.users.size > 0 ||
    f.unassigned ||
    f.domains.size > 0
  );
}

/** Case-insensitive id/title substring search; empty query passes. Mirrors the
 *  board's prior inline search so search composes with `matchesFilters`. */
export function matchesSearch(i: WorkstreamIssue, query: string): boolean {
  const q = query.trim().toLowerCase();
  if (!q) return true;
  return (
    i.id.toLowerCase().includes(q) || i.title.toLowerCase().includes(q)
  );
}

/** Canonical menu orders so the faceted options render deterministically
 *  (insertion order would vary with which issue loads first). */
const PRIORITY_ORDER: readonly WorkstreamPriority[] = [
  "urgent",
  "high",
  "medium",
  "low",
  "none",
];
const ROLE_ORDER: readonly WorkstreamRole[] = [
  "ceo",
  "cto",
  "cpo",
  "cmo",
  "coo",
  "cfo",
  "cro",
  "clo",
  "cco",
];

/** Shape of the faceted filter options the board derives + the FilterBar reads. */
export interface FilterOptions {
  priorities: WorkstreamPriority[];
  roles: WorkstreamRole[];
  users: string[];
  hasUnassigned: boolean;
  domains: string[];
}

/** Faceted filter options derived from the FULL loaded set (D3) — de-duplicated.
 *  "Hide empty options" ⇒ "present in the loaded set". Priorities/roles render in
 *  canonical order, users/domains alphabetically — deterministic across loads.
 *  Status is a fixed tri-state control, so it has no derived options. */
export function deriveFilterOptions(issues: WorkstreamIssue[]): FilterOptions {
  const priorities = new Set<WorkstreamPriority>();
  const roles = new Set<WorkstreamRole>();
  const users = new Set<string>();
  const domains = new Set<string>();
  let hasUnassigned = false;
  for (const i of issues) {
    priorities.add(i.priority);
    if (i.assigneeRole !== null) roles.add(i.assigneeRole);
    if (i.user !== undefined) users.add(i.user.name);
    if (i.assigneeRole === null && i.user === undefined) hasUnassigned = true;
    for (const d of i.domains ?? []) domains.add(d);
  }
  return {
    priorities: PRIORITY_ORDER.filter((p) => priorities.has(p)),
    roles: ROLE_ORDER.filter((r) => roles.has(r)),
    users: [...users].sort(),
    hasUnassigned,
    domains: [...domains].sort(),
  };
}

/** Per-column client render cap (separate from the 500-issue fetch cap). */
export const COLUMN_RENDER_CAP = 200;

/** EXACT mandated copy shown when a column exceeds the render cap (single
 *  source of truth — asserted by tests; the plural "columns" is intentional). */
export const COLUMN_CAP_NOTICE =
  "Some board columns are showing up to 200 issues. Refine filters or search to reveal the rest.";
