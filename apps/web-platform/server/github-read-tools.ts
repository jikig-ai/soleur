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
import { createChildLogger } from "./logger";
import { reportSilentFallback } from "./observability";

const log = createChildLogger("github-read-tools");

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
  // Historical GitHub responses have returned label objects with `name: null`
  // in rare cases — coerce to empty string so downstream `labels: string[]`
  // contract holds.
  if (typeof label === "string") return label;
  return label.name ?? "";
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
 * Fetches both endpoints in parallel. If both fail, the worse of the two
 * errors propagates so the caller's tool wrapper reports `isError: true`
 * instead of silently returning `[]`. If exactly one fails, we return the
 * surviving kind's comments and mirror the failure to Sentry so on-call
 * sees the degraded read — the agent would otherwise reason over an empty
 * list as if the PR had no comments (cq-silent-fallback-must-mirror-to-sentry).
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

  // Both endpoints failed — surface one error rather than silently returning [].
  if (reviewResult.status === "rejected" && convoResult.status === "rejected") {
    throw reviewResult.reason ?? convoResult.reason;
  }

  const review = reviewResult.status === "fulfilled"
    ? reviewResult.value.map((c) => narrowComment(c, "review"))
    : [];
  const convo = convoResult.status === "fulfilled"
    ? convoResult.value.map((c) => narrowComment(c, "conversation"))
    : [];

  // Partial failure: one kind failed, the other succeeded. Log + Sentry so the
  // silent-fallback is visible; the agent still gets the data it could read.
  if (reviewResult.status === "rejected") {
    log.warn(
      { err: reviewResult.reason, owner, repo, pullNumber },
      "Failed to fetch PR review comments — returning conversation comments only",
    );
    reportSilentFallback(reviewResult.reason, {
      feature: "github-read-tools",
      op: "list-pr-comments-partial",
      extra: { owner, repo, pullNumber, missingKind: "review" },
    });
  }
  if (convoResult.status === "rejected") {
    log.warn(
      { err: convoResult.reason, owner, repo, pullNumber },
      "Failed to fetch PR conversation comments — returning review comments only",
    );
    reportSilentFallback(convoResult.reason, {
      feature: "github-read-tools",
      op: "list-pr-comments-partial",
      extra: { owner, repo, pullNumber, missingKind: "conversation" },
    });
  }

  return [...review, ...convo];
}
