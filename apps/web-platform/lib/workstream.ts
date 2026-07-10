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
// (ADR-097): Backlog, Ready, In progress, In review, Blocked, Pending, Done.
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

/** Who CREATED the issue — the GitHub author, semantically distinct from both
 *  the role assignee and the `user` (assignee person). A human-opened issue's
 *  author is that person's login; an issue Soleur/Concierge opened is authored
 *  by the Soleur GitHub-App bot, in which case `isSoleur` is true and — when the
 *  issue body carries the initiator marker — `initiatorLogin` names the human who
 *  asked Soleur to file it. Optional + additive: absent when the author is
 *  unknown (mirrors the `user`/`domains` optional convention). */
export interface WorkstreamCreator {
  /** Raw GitHub author login, e.g. "octocat" or the Soleur bot's `<slug>[bot]`. */
  login: string;
  /** True when the author is the Soleur GitHub-App bot (slug-derived). */
  isSoleur: boolean;
  /** Human initiator login parsed from the issue-body marker (PART B) — present
   *  only for Soleur-authored issues that carry the marker. */
  initiatorLogin?: string;
  /** Display chip (name + initials): the human author, a "Soleur" label, or the
   *  human initiator when known. Reuses the WorkstreamUser chip shape. */
  display: WorkstreamUser;
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
  /** Who created the issue (GitHub author + Soleur-bot/initiator attribution).
   *  Distinct from `user` (assignee). Optional + additive — absent when the
   *  author login is unknown (e.g. pre-existing constructors that pass no
   *  `authorLogin`). */
  creator?: WorkstreamCreator;
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
  /** GitHub issue author login (`raw.user.login`) — the CREATOR, distinct from
   *  `assignees`. Optional + additive: absent for pre-existing constructors, in
   *  which case no `creator` is derived. */
  authorLogin?: string | null;
  created_at: string;
  updated_at: string;
  /** Canonical GitHub Project v2 board Status option name (Phase 2, ADR-097) —
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

/** Canonical GitHub board Status option name → app column (ADR-097). Keyed
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
 * when present + mappable (ADR-097); the state+label derivation below is the
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
  // open — precedence + aliases single-sourced in OPEN_LABEL_PRECEDENCE so the
  // write removal set (STATUS_LABELS) cannot drift from what this READS (AC12).
  for (const { labels: candidates, column } of OPEN_LABEL_PRECEDENCE) {
    if (candidates.some((l) => labels.includes(l))) return column;
  }
  return "backlog";
}

// ---------------------------------------------------------------------------
// Status-label WRITE vocabulary — single-sourced with deriveColumn's READ set
// (arch review P1 / ADR-109). A status write REMOVES every label in
// STATUS_LABELS then adds the ONE canonical write-label for the target column,
// in a single atomic `setLabels` PUT (see server/workstream/
// mutate-workstream-issue.ts). STATUS_LABELS MUST equal exactly the labels
// deriveColumn's open branch inspects — a test asserts write-set ≡ read-set so
// the read-derive and the write can never drift (AC12). `backlog` writes no
// status label (bare removal); `done` is a STATE transition (close), never a
// label. Mirrors the INITIATED_BY_MARKER single-source pattern above.
// ---------------------------------------------------------------------------

/** Ordered open-issue label→column precedence (first match wins). SINGLE SOURCE
 *  for both `deriveColumn` (read) and `STATUS_LABELS` (the write removal set) —
 *  they cannot drift because both derive from this one table (ADR-109 / AC12). */
const OPEN_LABEL_PRECEDENCE: readonly {
  labels: readonly string[];
  column: WorkstreamStatus;
}[] = [
  { labels: ["blocked"], column: "blocked" },
  { labels: ["pending"], column: "pending" },
  { labels: ["in-progress"], column: "in_progress" },
  { labels: ["review", "needs-review"], column: "in_review" },
  { labels: ["ready", "todo"], column: "ready" },
];

/** Every status label `deriveColumn` reads (the removal set for a status write),
 *  derived from OPEN_LABEL_PRECEDENCE so it can never drift from the read. */
export const STATUS_LABELS: readonly string[] = OPEN_LABEL_PRECEDENCE.flatMap(
  (r) => r.labels,
);

/** Canonical write-label for each column (the label ADDED after removing all
 *  STATUS_LABELS). `backlog` → none (bare removal); `done` → none (close).
 *  Every value is a member of STATUS_LABELS and derives back to its key via
 *  deriveColumn (AC13 round-trip). */
export const STATUS_WRITE_LABEL: Readonly<
  Partial<Record<WorkstreamStatus, string>>
> = {
  ready: "ready",
  in_progress: "in-progress",
  in_review: "review",
  blocked: "blocked",
  pending: "pending",
};

/** True when moving to `target` CLOSES the issue (Done spans state, not labels). */
export function isTerminalColumn(target: WorkstreamStatus): boolean {
  return target === "done";
}

/** Compute the FULL label set for an atomic setLabels PUT that moves an issue to
 *  `target`: preserve every NON-status label, drop all STATUS_LABELS, then add
 *  the target's canonical write-label (none for backlog/done). Pure — the
 *  accessor's read-modify-write feeds current labels in and PUTs the result, so
 *  a half-failed remove-then-add can never leave a wrong column (ADR-109). */
export function computeStatusLabels(
  currentLabels: string[],
  target: WorkstreamStatus,
): string[] {
  const statusSet = new Set<string>(STATUS_LABELS);
  const preserved = currentLabels.filter((l) => !statusSet.has(l));
  const write = STATUS_WRITE_LABEL[target];
  return write ? [...preserved, write] : preserved;
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
  return { name: login, initials: loginInitials(login) };
}

// ---------------------------------------------------------------------------
// Creator attribution — GitHub author + Soleur-bot detection + human-initiator
// marker (single-sourced emit/parse contract, so the write helper and the read
// parser can never drift). All PURE + DEFENSIVE (never throw; null/false/undefined
// on missing/malformed input), matching this module's leaf convention.
// ---------------------------------------------------------------------------

/** Canonical initiator marker. The `<!-- soleur:<verb> … -->` HTML-comment family
 *  (sibling of `soleur:followthrough` / `soleur:auto-close-stale-scope-out`):
 *  invisible in rendered markdown, carries no `@mention` (no spurious notify) and
 *  no close-keyword (cannot trip GitHub autoclose). BOTH `appendInitiatorMarker`
 *  and `parseInitiatorLogin` derive from this so the byte contract is single. */
export const INITIATED_BY_MARKER = {
  /** Build the exact marker line for a login. */
  build: (login: string) => `<!-- soleur:initiated-by ${login} -->`,
  /** Global matcher — GitHub login charset (1–39 chars, alnum + internal hyphen).
   *  Non-line-anchored by design: it runs only on Soleur-controlled bot bodies,
   *  and the write side strips strays so the trailing server-stamped marker wins. */
  regex: /<!--\s*soleur:initiated-by\s+([A-Za-z0-9](?:[A-Za-z0-9-]{0,38})?)\s*-->/g,
  /** Strip pattern (any marker, malformed included) — used for unconditional strip.
   *  BOUNDED quantifiers (`{0,64}` / `{0,200}?`) keep this linear: an unbounded
   *  `\s*…[\s\S]*?-->` is O(n²) on attacker-controlled bodies with many
   *  `<!--…initiated-by` prefixes and no closing `-->` (CodeQL js/polynomial-redos).
   *  A real marker's gap is < 50 chars, so the caps never truncate a valid one. */
  stripRegex: /<!--\s{0,64}soleur:initiated-by[\s\S]{0,200}?-->/g,
} as const;

/** True iff `login` is the Soleur GitHub-App bot for `botSlug` (case-insensitive
 *  `` `${botSlug}[bot]` ``). Biases to FALSE when the slug is empty/unresolved —
 *  a `login.endsWith("[bot]")` fallback would misclassify `dependabot[bot]` /
 *  `renovate[bot]` as Soleur, the exact confusion this feature removes. */
export function isSoleurBotLogin(
  login: string | null | undefined,
  botSlug: string | null | undefined,
): boolean {
  if (!login || !botSlug) return false;
  return login.toLowerCase() === `${botSlug.toLowerCase()}[bot]`;
}

/** Extract the human initiator login from an issue body's marker, or null when
 *  absent/malformed. Returns the LAST occurrence so a server-stamped trailing
 *  marker wins over any smuggled one. Never throws (null body → null). */
export function parseInitiatorLogin(
  body: string | null | undefined,
): string | null {
  if (!body) return null;
  let login: string | null = null;
  // Fresh matcher state per call (the shared regex is /g).
  const re = new RegExp(INITIATED_BY_MARKER.regex.source, "g");
  let m: RegExpExecArray | null;
  while ((m = re.exec(body)) !== null) login = m[1];
  return login;
}

/** WRITE-side builder (co-located with the parser so emit/parse can't drift).
 *  Unconditionally strips ALL pre-existing `soleur:initiated-by` markers first —
 *  even when `login` is falsy — so a smuggled fake marker in a caller-supplied
 *  body can never survive (spoof defense; the server controls the last write).
 *  Appends the trusted marker only when `login` is present. Never throws. */
export function appendInitiatorMarker(
  body: string | null | undefined,
  login: string | null | undefined,
): string {
  const stripped = (body ?? "").replace(INITIATED_BY_MARKER.stripRegex, "").trimEnd();
  if (!login) return stripped;
  const marker = INITIATED_BY_MARKER.build(login);
  return stripped ? `${stripped}\n\n${marker}` : marker;
}

/** Human-readable initials for a login (first 2 chars, upper) — mirrors
 *  `deriveUser`'s rule. */
function loginInitials(login: string): string {
  return login.slice(0, 2).toUpperCase();
}

/** Derive the `creator` attribution from the GitHub author login + issue body +
 *  the Soleur bot slug. Returns undefined when `authorLogin` is falsy (no chip —
 *  graceful). For a Soleur-bot author, the body is parsed for the human initiator
 *  (only bot bodies are trusted — a human author's body is never marker-parsed).
 *  The display chip prefers the human initiator, then a "Soleur" label, then the
 *  raw human author. Never throws. */
export function deriveCreator(
  authorLogin: string | null | undefined,
  body: string | null | undefined,
  botSlug: string | null | undefined,
): WorkstreamCreator | undefined {
  if (!authorLogin) return undefined;
  const isSoleur = isSoleurBotLogin(authorLogin, botSlug);
  const initiatorLogin = isSoleur
    ? (parseInitiatorLogin(body) ?? undefined)
    : undefined;
  const display: WorkstreamUser = initiatorLogin
    ? { name: initiatorLogin, initials: loginInitials(initiatorLogin) }
    : isSoleur
      ? { name: "Soleur", initials: "SO" }
      : { name: authorLogin, initials: loginInitials(authorLogin) };
  return {
    login: authorLogin,
    isSoleur,
    ...(initiatorLogin ? { initiatorLogin } : {}),
    display,
  };
}

/** Human-readable "created by" label for a creator — the single source of truth
 *  for the card tooltip and the detail-sheet row. Three variants:
 *  `Soleur · initiated by <login>` / `Soleur` / the human author login. */
export function creatorLabel(creator: WorkstreamCreator): string {
  if (creator.isSoleur && creator.initiatorLogin) {
    return `Soleur · initiated by ${creator.initiatorLogin}`;
  }
  if (creator.isSoleur) return "Soleur";
  return creator.login;
}

/** The effective "created by" identity used as the CREATOR-FILTER key: the human
 *  initiator when known, else `"Soleur"` for a bot-authored issue with no
 *  initiator, else the human author login. So filtering by a person surfaces BOTH
 *  the issues they opened directly AND the Soleur-created issues they initiated. */
export function creatorFilterKey(creator: WorkstreamCreator): string {
  if (creator.initiatorLogin) return creator.initiatorLogin;
  return creator.isSoleur ? "Soleur" : creator.login;
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
  botSlug?: string | null,
): WorkstreamIssue {
  const user = deriveUser(input.assignees);
  const domains = input.labels.filter((l) => l.startsWith("domain/"));
  const creator = deriveCreator(input.authorLogin, input.body, botSlug);
  return {
    id: String(input.number),
    title: input.title,
    description: input.body ?? "",
    status: deriveColumn(input),
    priority: derivePriority(input.labels),
    assigneeRole: deriveRole(input.labels),
    ...(user ? { user } : {}),
    ...(creator ? { creator } : {}),
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
 *  board has no Cancelled column, ADR-097). */
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
  /** Creator-filter keys (`creatorFilterKey` values) — who created the issue. */
  creators: Set<string>;
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
    creators: new Set(),
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
  // Creator (who created the issue)
  if (f.creators.size > 0) {
    const key = i.creator ? creatorFilterKey(i.creator) : null;
    if (key === null || !f.creators.has(key)) return false;
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
    f.domains.size > 0 ||
    f.creators.size > 0
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
  /** Distinct creator-filter keys present in the loaded set (alphabetical). */
  creators: string[];
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
  const creators = new Set<string>();
  let hasUnassigned = false;
  for (const i of issues) {
    priorities.add(i.priority);
    if (i.assigneeRole !== null) roles.add(i.assigneeRole);
    if (i.user !== undefined) users.add(i.user.name);
    if (i.assigneeRole === null && i.user === undefined) hasUnassigned = true;
    for (const d of i.domains ?? []) domains.add(d);
    if (i.creator !== undefined) creators.add(creatorFilterKey(i.creator));
  }
  return {
    priorities: PRIORITY_ORDER.filter((p) => priorities.has(p)),
    roles: ROLE_ORDER.filter((r) => roles.has(r)),
    users: [...users].sort(),
    hasUnassigned,
    domains: [...domains].sort(),
    creators: [...creators].sort(),
  };
}

/** Per-column client render cap (separate from the 500-issue fetch cap). */
export const COLUMN_RENDER_CAP = 200;

/** EXACT mandated copy shown when a column exceeds the render cap (single
 *  source of truth — asserted by tests; the plural "columns" is intentional). */
export const COLUMN_CAP_NOTICE =
  "Some board columns are showing up to 200 issues. Refine filters or search to reveal the rest.";
