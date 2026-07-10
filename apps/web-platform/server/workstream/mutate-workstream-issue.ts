// The single shared WRITE accessor for the Workstream board (ADR-109). BOTH the
// HTTP write routes (app/api/workstream/issues[/[number]]) AND the agent write
// tools (server/workstream/workstream-tools) call this — never the route.
//
// NON-NEGOTIABLE invariants (the load-bearing review findings):
//   - ALL writes route through the AUDITED seam
//     `createGitHubAppClient(installationId, founderId).rest.issues.*` — the ONLY
//     path that writes the `audit_github_token_use` row per call (Art. 30 PA-16).
//     A naked `generateInstallationToken()` write path (github-app.ts) is
//     unaudited and is NOT used here.
//   - owner/repo/installation resolve ONLY from the server-side active workspace
//     (ADR-044) — mirroring getWorkstreamIssues — never from request input, so
//     there is no cross-tenant write.
//   - `founderId` = the session user id (threaded as the audit attribution).
//   - `initiatorLogin` is resolved SERVER-SIDE (resolveGithubLogin) — a login in
//     the request body is ignored; appendInitiatorMarker strips any smuggled
//     marker so the trusted stamp wins (anti-spoof).
//   - "Delete" = close/reopen only. done → close(state_reason); reopen →
//     state=open. There is no Cancelled column — both close reasons fold to Done.
//   - Status = labels. setIssueStatus does read-modify-write: GET current labels,
//     then ONE atomic `setLabels` PUT of the full computed set (no remove/add
//     delta that could half-fail). The removal set is single-sourced with
//     deriveColumn (lib/workstream STATUS_LABELS).
//
// Every helper THROWS on failure (octokit errors carry `.status`; empty title /
// no-repo / no-install throw a typed WorkstreamWriteError) so the route surfaces
// 422/403/409/502 and the tool returns isError — a write failure never
// masquerades as success (fail-loud, PA-16).

import {
  appendInitiatorMarker,
  computeStatusLabels,
  githubIssueToWorkstreamIssue,
  STATUS_WRITE_LABEL,
  type BoardIssueInput,
  type WorkstreamIssue,
  type WorkstreamStatus,
} from "@/lib/workstream";
import { createGitHubAppClient } from "@/server/github/app-client";
import { getCurrentRepoUrl } from "@/server/current-repo-url";
import { parseConnectedRepo } from "@/server/github-repo-parse";
import { resolveInstallationId } from "@/server/resolve-installation-id";
import { resolveEffectiveInstallationId } from "@/server/cc-effective-installation";
import { resolveGithubLogin } from "@/server/github-login";
import { getAppSlug } from "@/server/github-app";
import { createServiceClient } from "@/lib/supabase/service";
import { reportSilentFallback } from "@/server/observability";
import { createChildLogger } from "@/server/logger";

const log = createChildLogger("workstream-write");

/** GitHub `state_reason` values a close can carry (both fold to Done). */
export type CloseReason = "completed" | "not_planned";

/** A typed write failure with an HTTP status the route maps 1:1. Distinct from a
 *  raw octokit RequestError (which also carries `.status`, handled the same). */
export class WorkstreamWriteError extends Error {
  status: number;
  code: string;
  constructor(code: string, message: string, status: number) {
    super(message);
    this.name = "WorkstreamWriteError";
    this.code = code;
    this.status = status;
  }
}

// ---------------------------------------------------------------------------
// Structural Octokit shape (only .rest.issues.* is used). Kept local so the
// accessor doesn't depend on the full @octokit type surface (the undo route
// uses the same narrowing pattern).
// ---------------------------------------------------------------------------

interface GhIssuePayload {
  number: number;
  title: string;
  body: string | null;
  labels: Array<string | { name?: string | null }>;
  assignees: Array<{ login: string }>;
  state: string;
  state_reason: string | null;
  user: { login: string } | null;
  created_at: string;
  updated_at: string;
}

interface IssuesRest {
  create(p: Record<string, unknown>): Promise<{ data: GhIssuePayload }>;
  update(p: Record<string, unknown>): Promise<{ data: GhIssuePayload }>;
  get(p: Record<string, unknown>): Promise<{ data: GhIssuePayload }>;
  setLabels(p: Record<string, unknown>): Promise<{ data: unknown }>;
}

interface OctokitLike {
  rest: { issues: IssuesRest };
}

interface WriteContext {
  owner: string;
  repo: string;
  octokit: OctokitLike;
  botSlug: string | null;
}

// ---------------------------------------------------------------------------
// Resolution (ADR-044) — mirrors getWorkstreamIssues exactly.
// ---------------------------------------------------------------------------

async function resolveContext(userId: string): Promise<WriteContext> {
  const repoUrl = await getCurrentRepoUrl(userId);
  const parsed = parseConnectedRepo(repoUrl);
  if (!parsed) {
    throw new WorkstreamWriteError(
      "no_connected_repo",
      "The active workspace has no connected GitHub repo to write to.",
      409,
    );
  }
  const stored = await resolveInstallationId(userId);
  const installationId = await resolveEffectiveInstallationId({
    userId,
    installationId: stored,
    repoUrl,
  });
  if (installationId === null) {
    throw new WorkstreamWriteError(
      "no_installation",
      "No GitHub App installation resolves for the connected repo.",
      403,
    );
  }
  // The AUDITED seam — every .rest.issues.* call writes an audit row attributed
  // to founderId = userId.
  const octokit = (await createGitHubAppClient(
    installationId,
    userId,
  )) as unknown as OctokitLike;
  const botSlug = await safeAppSlug();
  return { owner: parsed.owner, repo: parsed.repo, octokit, botSlug };
}

/** Bot slug for creator attribution — degrade-safe (null renders a plain human),
 *  mirrored to Sentry (never throws), matching the read path. */
async function safeAppSlug(): Promise<string | null> {
  try {
    return await getAppSlug();
  } catch (err) {
    reportSilentFallback(err, {
      feature: "workstream",
      op: "workstream-write-botslug-degrade",
    });
    return null;
  }
}

/** Server-resolved GitHub login for the initiator marker — NEVER request input.
 *  Degrade-safe: a resolution failure yields null (no marker stamped) and is
 *  mirrored to Sentry rather than throwing (a create must not fail on an
 *  attribution hiccup). */
async function resolveInitiatorLogin(userId: string): Promise<string | null> {
  try {
    const service = createServiceClient();
    const { data } = await service
      .from("users")
      .select("github_username")
      .eq("id", userId)
      .maybeSingle();
    const stored = (data as { github_username?: string | null } | null)
      ?.github_username;
    return await resolveGithubLogin(service, userId, stored ?? null);
  } catch (err) {
    reportSilentFallback(err, {
      feature: "workstream",
      op: "resolve-initiator-login",
      extra: { userId },
    });
    return null;
  }
}

// ---------------------------------------------------------------------------
// Canonical mapping — re-derive the WorkstreamIssue from GitHub's response so
// the client reconciles from STORED truth, not a bare 2xx. No boardStatus is
// passed: for a user's own repo labels/state ARE canonical (ADR-109); the org
// board mirror is grant-gated + read-only-consulted.
// ---------------------------------------------------------------------------

function labelNames(labels: GhIssuePayload["labels"]): string[] {
  return labels
    .map((l) => (typeof l === "string" ? l : (l?.name ?? "")))
    .filter((n): n is string => n.length > 0);
}

function toCanonical(raw: GhIssuePayload, botSlug: string | null): WorkstreamIssue {
  const input: BoardIssueInput = {
    number: raw.number,
    title: raw.title,
    body: raw.body ?? null,
    assignees: (raw.assignees ?? []).map((a) => a.login),
    labels: labelNames(raw.labels ?? []),
    state: raw.state === "closed" ? "closed" : "open",
    state_reason: raw.state_reason ?? null,
    authorLogin: raw.user?.login ?? null,
    created_at: raw.created_at,
    updated_at: raw.updated_at,
  };
  return githubIssueToWorkstreamIssue(input, botSlug);
}

function logWrite(verb: string, number: number): void {
  // Liveness signal — parity with the board-read log; cosmetic, no alert target.
  log.info({ op: "workstream-issue-write", verb, number }, "workstream write");
}

// ---------------------------------------------------------------------------
// Public write operations. Each resolves the workspace context + audited client
// itself so a single call is self-contained (route + tool share these).
// ---------------------------------------------------------------------------

export interface CreateInput {
  title: string;
  body?: string;
  status?: WorkstreamStatus;
}

export async function createWorkstreamIssue(
  userId: string,
  input: CreateInput,
): Promise<WorkstreamIssue> {
  const title = (input.title ?? "").trim();
  if (!title) {
    throw new WorkstreamWriteError("empty_title", "Title is required.", 422);
  }
  const { owner, repo, octokit, botSlug } = await resolveContext(userId);
  const initiatorLogin = await resolveInitiatorLogin(userId);
  const body = appendInitiatorMarker(input.body ?? "", initiatorLogin);
  const labels: string[] = [];
  if (input.status) {
    const write = STATUS_WRITE_LABEL[input.status];
    if (write) labels.push(write);
  }
  const res = await octokit.rest.issues.create({ owner, repo, title, body, labels });
  logWrite("create", res.data.number);
  return toCanonical(res.data, botSlug);
}

export async function updateWorkstreamIssueTitle(
  userId: string,
  issueNumber: number,
  title: string,
): Promise<WorkstreamIssue> {
  const next = (title ?? "").trim();
  if (!next) {
    throw new WorkstreamWriteError("empty_title", "Title is required.", 422);
  }
  const { owner, repo, octokit, botSlug } = await resolveContext(userId);
  const res = await octokit.rest.issues.update({
    owner,
    repo,
    issue_number: issueNumber,
    title: next,
  });
  logWrite("update_title", issueNumber);
  return toCanonical(res.data, botSlug);
}

/**
 * The ONE atomic status primitive (ADR-109). `done` → close(state_reason). Any
 * non-terminal column → read-modify-write the label set in a single `setLabels`
 * PUT, and reopen (state=open) if the issue was closed. Returns the canonical
 * resulting issue re-derived from GitHub.
 */
export async function setWorkstreamIssueStatus(
  userId: string,
  issueNumber: number,
  target: WorkstreamStatus,
  stateReason?: CloseReason,
): Promise<WorkstreamIssue> {
  const { owner, repo, octokit, botSlug } = await resolveContext(userId);

  if (target === "done") {
    const res = await octokit.rest.issues.update({
      owner,
      repo,
      issue_number: issueNumber,
      state: "closed",
      state_reason: stateReason ?? "completed",
    });
    logWrite("close", issueNumber);
    return toCanonical(res.data, botSlug);
  }

  // Non-terminal: atomic setLabels PUT of the full computed set. GET first so we
  // preserve non-status labels + know the current state (TOCTOU last-write-wins
  // is accepted at the single-user threshold, P1-4).
  const cur = await octokit.rest.issues.get({
    owner,
    repo,
    issue_number: issueNumber,
  });
  const nextLabels = computeStatusLabels(labelNames(cur.data.labels ?? []), target);
  await octokit.rest.issues.setLabels({
    owner,
    repo,
    issue_number: issueNumber,
    labels: nextLabels,
  });

  // A closed card is closed — removing labels alone leaves it in Done. Reopen.
  let canonicalRaw: GhIssuePayload = { ...cur.data, labels: nextLabels };
  if (cur.data.state === "closed") {
    const reopened = await octokit.rest.issues.update({
      owner,
      repo,
      issue_number: issueNumber,
      state: "open",
    });
    canonicalRaw = { ...reopened.data, labels: nextLabels, state_reason: null };
  }
  logWrite("set_status", issueNumber);
  return toCanonical(canonicalRaw, botSlug);
}

/**
 * Reopen a closed issue (`PATCH state=open`) WITHOUT touching labels — the card
 * leaves Done and lands in the column its surviving labels derive (else
 * Backlog). Distinct from setStatus-to-a-specific-column (which also relabels).
 */
export async function reopenWorkstreamIssue(
  userId: string,
  issueNumber: number,
): Promise<WorkstreamIssue> {
  const { owner, repo, octokit, botSlug } = await resolveContext(userId);
  const res = await octokit.rest.issues.update({
    owner,
    repo,
    issue_number: issueNumber,
    state: "open",
  });
  logWrite("reopen", issueNumber);
  return toCanonical(res.data, botSlug);
}

// ---------------------------------------------------------------------------
// Dispatcher — the single accessor the routes AND the MCP tools call. Keeps the
// verb-set in one place (parity between the HTTP surface and the agent surface).
// ---------------------------------------------------------------------------

export type WorkstreamMutation =
  | { verb: "create"; title: string; body?: string; status?: WorkstreamStatus }
  | { verb: "update_title"; number: number; title: string }
  | {
      verb: "set_status";
      number: number;
      status: WorkstreamStatus;
      state_reason?: CloseReason;
    }
  | { verb: "reopen"; number: number };

export async function mutateWorkstreamIssue(
  userId: string,
  m: WorkstreamMutation,
): Promise<WorkstreamIssue> {
  switch (m.verb) {
    case "create":
      return createWorkstreamIssue(userId, {
        title: m.title,
        body: m.body,
        status: m.status,
      });
    case "update_title":
      return updateWorkstreamIssueTitle(userId, m.number, m.title);
    case "set_status":
      return setWorkstreamIssueStatus(userId, m.number, m.status, m.state_reason);
    case "reopen":
      return reopenWorkstreamIssue(userId, m.number);
  }
}

// ---------------------------------------------------------------------------
// Board-precedence meta — drives the UI drag/affordance gating (AC11/AC14). For
// the dogfood org repo (owner === SOLEUR_KANBAN_ORG) the Project board Status
// WINS over labels on read, and the board-status-sync workflow needs
// `organization_projects:write` (still ungranted) to mirror a label write — so
// intermediate-column moves would snap back. Gate on the GRANT STATE
// (SOLEUR_KANBAN_PROJECT_WRITABLE), which lifts the disable automatically once
// the grant lands. A user's OWN repo never reads the board → fully live.
// ---------------------------------------------------------------------------

export interface WorkstreamBoardMeta {
  /** The connected repo is owned by the dogfood Kanban org (board precedence). */
  onKanbanOrg: boolean;
  /** The org Project board is writable (organization_projects:write granted). */
  projectWritable: boolean;
}

export async function resolveWorkstreamBoardMeta(
  userId: string,
): Promise<WorkstreamBoardMeta> {
  const repoUrl = await getCurrentRepoUrl(userId);
  const parsed = parseConnectedRepo(repoUrl);
  const org = process.env.SOLEUR_KANBAN_ORG?.trim().toLowerCase();
  const onKanbanOrg = Boolean(
    parsed && org && parsed.owner.toLowerCase() === org,
  );
  const projectWritable = process.env.SOLEUR_KANBAN_PROJECT_WRITABLE === "1";
  return { onKanbanOrg, projectWritable };
}
