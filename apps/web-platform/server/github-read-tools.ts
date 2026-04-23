/**
 * Read-only GitHub tool handler functions for platform MCP (#2843).
 *
 * Separated from ci-tools.ts for cohesion: CI/workflow reads live there,
 * issue/PR reads live here. Both use github-api.ts for authenticated
 * requests — the agent subprocess never sees GitHub tokens.
 *
 * Response narrowing: REST payloads include user avatar URLs, event URLs,
 * labels-as-objects, and other metadata that bloats token budgets without
 * helping the agent. Each function returns only the fields an agent
 * actually reasons about. Bodies are truncated at 10 KB (issues/PRs) or
 * 4 KB (comments) with a marker pointing at html_url for the full text.
 */

import { githubApiGet } from "./github-api";

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const ISSUE_BODY_CAP = 10 * 1024;
const COMMENT_BODY_CAP = 4 * 1024;
const PER_PAGE_MAX = 50;
const PER_PAGE_DEFAULT = 10;

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

export interface IssueSummary {
  number: number;
  title: string;
  state: string;
  body: string;
  labels: string[];
  assignees: string[];
  milestone: string | null;
  created_at: string;
  updated_at: string;
  html_url: string;
  user: string;
}

export interface PullRequestSummary extends IssueSummary {
  draft: boolean;
  merged: boolean;
  mergeable: boolean | null;
  mergeable_state: string;
  head_ref: string;
  base_ref: string;
  merged_at: string | null;
}

export interface CommentSummary {
  id: number;
  kind: "conversation" | "review";
  user: string;
  body: string;
  created_at: string;
  html_url: string;
}

// ---------------------------------------------------------------------------
// GitHub REST response types (narrowed to fields we use)
// ---------------------------------------------------------------------------

interface GhUser { login: string }
interface GhLabel { name: string }
interface GhMilestone { title: string }

interface GhIssueResponse {
  number: number;
  title: string;
  state: string;
  body: string | null;
  labels: Array<GhLabel | string>;
  assignees: GhUser[];
  milestone: GhMilestone | null;
  created_at: string;
  updated_at: string;
  html_url: string;
  user: GhUser;
}

interface GhPullRequestResponse extends GhIssueResponse {
  draft: boolean;
  merged: boolean;
  mergeable: boolean | null;
  mergeable_state: string;
  merged_at: string | null;
  head: { ref: string };
  base: { ref: string };
}

interface GhCommentResponse {
  id: number;
  user: GhUser;
  body: string | null;
  created_at: string;
  html_url: string;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function truncateBody(body: string | null | undefined, cap: number, htmlUrl: string): string {
  const text = body ?? "";
  if (text.length <= cap) return text;
  return `${text.slice(0, cap)}\n…(truncated, view full at ${htmlUrl})`;
}

function normalizeLabel(label: GhLabel | string): string {
  return typeof label === "string" ? label : label.name;
}

function narrowIssue(raw: GhIssueResponse): IssueSummary {
  return {
    number: raw.number,
    title: raw.title,
    state: raw.state,
    body: truncateBody(raw.body, ISSUE_BODY_CAP, raw.html_url),
    labels: raw.labels.map(normalizeLabel),
    assignees: raw.assignees.map((a) => a.login),
    milestone: raw.milestone?.title ?? null,
    created_at: raw.created_at,
    updated_at: raw.updated_at,
    html_url: raw.html_url,
    user: raw.user.login,
  };
}

function narrowComment(raw: GhCommentResponse, kind: CommentSummary["kind"]): CommentSummary {
  return {
    id: raw.id,
    kind,
    user: raw.user.login,
    body: truncateBody(raw.body, COMMENT_BODY_CAP, raw.html_url),
    created_at: raw.created_at,
    html_url: raw.html_url,
  };
}

function clampPerPage(requested: number | undefined): number {
  const n = requested ?? PER_PAGE_DEFAULT;
  if (!Number.isFinite(n) || n < 1) return PER_PAGE_DEFAULT;
  return Math.min(Math.trunc(n), PER_PAGE_MAX);
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Read a single issue by number.
 * Returns a narrowed summary (title, state, truncated body, labels, etc.).
 */
export async function readIssue(
  installationId: number,
  owner: string,
  repo: string,
  issueNumber: number,
): Promise<IssueSummary> {
  const raw = await githubApiGet<GhIssueResponse>(
    installationId,
    `/repos/${owner}/${repo}/issues/${issueNumber}`,
  );
  return narrowIssue(raw);
}

/**
 * Read conversation comments on an issue (ordered oldest-first per GitHub
 * default). Narrowed to { id, user, body, created_at, html_url } and tagged
 * `kind: "conversation"` for symmetry with PR comment listings.
 */
export async function readIssueComments(
  installationId: number,
  owner: string,
  repo: string,
  issueNumber: number,
  options?: { per_page?: number },
): Promise<CommentSummary[]> {
  const perPage = clampPerPage(options?.per_page);
  const raw = await githubApiGet<GhCommentResponse[]>(
    installationId,
    `/repos/${owner}/${repo}/issues/${issueNumber}/comments?per_page=${perPage}`,
  );
  return raw.map((c) => narrowComment(c, "conversation"));
}

/**
 * Read a pull request by number. Returns the issue fields plus PR-specific
 * review state (draft, merged, mergeable, head/base refs) — the fields an
 * agent needs to decide "should I push a fix, or is this already merged."
 */
export async function readPullRequest(
  installationId: number,
  owner: string,
  repo: string,
  pullNumber: number,
): Promise<PullRequestSummary> {
  const raw = await githubApiGet<GhPullRequestResponse>(
    installationId,
    `/repos/${owner}/${repo}/pulls/${pullNumber}`,
  );
  return {
    ...narrowIssue(raw),
    draft: raw.draft,
    merged: raw.merged,
    mergeable: raw.mergeable,
    mergeable_state: raw.mergeable_state,
    head_ref: raw.head.ref,
    base_ref: raw.base.ref,
    merged_at: raw.merged_at,
  };
}

/**
 * List both review comments (`/pulls/:n/comments`) and conversation comments
 * (`/issues/:n/comments`) on a PR. Returned entries are tagged with
 * `kind: "review" | "conversation"` so the agent can filter.
 *
 * Fetches both endpoints in parallel. A failure on either is treated as an
 * empty list for that kind rather than failing the whole call — callers get
 * partial data with the kind they could read.
 */
export async function listPullRequestComments(
  installationId: number,
  owner: string,
  repo: string,
  pullNumber: number,
  options?: { per_page?: number },
): Promise<CommentSummary[]> {
  const perPage = clampPerPage(options?.per_page);
  const reviewPath = `/repos/${owner}/${repo}/pulls/${pullNumber}/comments?per_page=${perPage}`;
  const convoPath = `/repos/${owner}/${repo}/issues/${pullNumber}/comments?per_page=${perPage}`;

  const [reviewResult, convoResult] = await Promise.allSettled([
    githubApiGet<GhCommentResponse[]>(installationId, reviewPath),
    githubApiGet<GhCommentResponse[]>(installationId, convoPath),
  ]);

  const review = reviewResult.status === "fulfilled"
    ? reviewResult.value.map((c) => narrowComment(c, "review"))
    : [];
  const convo = convoResult.status === "fulfilled"
    ? convoResult.value.map((c) => narrowComment(c, "conversation"))
    : [];

  return [...review, ...convo];
}
