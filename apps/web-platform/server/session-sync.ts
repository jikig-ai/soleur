// ---------------------------------------------------------------------------
// Session sync: pull before session, push after session
//
// Keeps the user's workspace in sync with their connected GitHub repo.
// All operations are best-effort — failures are logged but never block
// the agent session.
// ---------------------------------------------------------------------------

import { execFileSync } from "child_process";
import { readdirSync } from "fs";
import { join } from "path";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  getFreshTenantClient,
  RuntimeAuthError,
} from "@/lib/supabase/tenant";
import {
  hashUserId,
  reportSilentFallback,
  warnSilentFallback,
} from "@/server/observability";
import { gitWithInstallationAuth } from "./git-auth";
import { createChildLogger } from "./logger";

const log = createChildLogger("session-sync");

// Path-allowlist for the auto-commit sweep. Only paths under
// `knowledge-base/` are eligible for automatic staging during syncPull/syncPush.
// Everything else (`.claude/`, `.github/`, `apps/`, root config files, ...)
// is left dirty in the working tree so it never lands in PRs the loop did
// not explicitly author. See #2905 for the failure modes this prevents.
const ALLOWED_AUTOCOMMIT_PATHS = [/^knowledge-base\//];

// Auto-commit headlines used by syncPull / syncPush. Exported as named
// constants so .github/scripts/check-auto-commit-density.sh can stay in
// sync (the regex there must reference these exact strings).
export const AUTO_COMMIT_MSG_PULL = "Auto-commit before sync pull";
export const AUTO_COMMIT_MSG_PUSH = "Auto-commit after session";

// Allowlist of git subcommands the connected-repo writer may invoke.
// Anything destructive (rm, reset, clean, branch -D, checkout -- ...) is
// rejected at the wrapper. See #2905 for the failure-class this prevents.
const ALLOWED_GIT_SUBCOMMANDS = new Set([
  "status",
  "add",
  "commit",
  "remote",
  "rev-list",
]);

// Forbidden flags — applied across ANY allowed subcommand. Reject in argv,
// not just at the start, so `commit --amend` or `push --force` (if either
// ever reaches this wrapper) gets blocked regardless of position.
const FORBIDDEN_GIT_FLAGS = new Set([
  "--force",
  "-f",
  "--hard",
  "--amend",
  "--no-verify",
]);

// #5426 — push-error classification for the protected-branch fallback.
// `protected_branch` routes to the side-branch + PR fallback; `persistent_other`
// is a non-protection reject that must NOT silently retry-loop (notably
// `shallow update not allowed` — these are shallow clones); `other` keeps the
// existing best-effort retry-next-session behaviour (auth/network/transient).
export type PushErrorClass = "protected_branch" | "persistent_other" | "other";

/**
 * Classify a failed `git push` error. Keys on GitHub's protected-branch
 * rejection signatures (`GH006`, `protected branch hook declined`) and
 * tolerates varied tails (required-review, required-status-check, "Changes
 * must be made through a pull request"). Narrow by design: auth/network
 * rejections must fall through to `other`.
 */
export function classifyPushError(err: unknown): PushErrorClass {
  const text =
    err instanceof Error
      ? `${err.message}\n${(err as { stderr?: string }).stderr ?? ""}`
      : typeof err === "string"
        ? err
        : "";
  if (
    text.includes("GH006") ||
    text.includes("protected branch hook declined") ||
    text.includes("Protected branch update failed") ||
    // GitHub always prefixes protected-branch rejects with GH006, but key on
    // the require-PR tail too (plan §Phase 1) so a future stderr-format drift
    // that drops the GH006 prefix still routes to the fallback rather than
    // silently looping the divergence treadmill.
    text.includes("Changes must be made through a pull request")
  ) {
    return "protected_branch";
  }
  if (text.includes("shallow update not allowed")) {
    return "persistent_other";
  }
  return "other";
}

// #5426 — protected-branch fallback. When the user's default branch is
// protected, the post-session KB commit can't be pushed onto it; instead we
// accrete the latest KB tree onto a durable side branch in the user's OWN repo
// and open/update a never-auto-merged PR into their default branch.
const KB_SYNC_SIDE_BRANCH = "soleur/kb-sync";
const KB_SYNC_SIDE_COMMIT_MSG = "Soleur: sync knowledge-base";
const KB_SYNC_PR_TITLE = "Soleur: knowledge-base sync";

// GitHub owner/repo charset (mirrors agent-runner.ts:1525-1538 GITHUB_NAME_RE).
const GITHUB_NAME_RE = /^[a-zA-Z0-9._-]+$/;

function kbSyncPrBody(defaultBranch: string): string {
  return [
    "Soleur keeps your knowledge-base in sync after every session.",
    "",
    `Your default branch (\`${defaultBranch}\`) is protected, so these`,
    `knowledge-base updates were routed to the \`${KB_SYNC_SIDE_BRANCH}\` branch`,
    "instead of being pushed directly.",
    "",
    "Merge this PR whenever you're ready — Soleur will never auto-merge it.",
    "Future sessions accrete onto this same branch and PR.",
  ].join("\n");
}

/**
 * Parse `{owner, repo}` from a connected-repo URL using the same shape as
 * agent-runner.ts (URL pathname split + GITHUB_NAME_RE guard, ADR-044 canonical
 * workspace read). `getCurrentRepoUrl` already strips a trailing `.git` via
 * `normalizeRepoUrl`; the defensive strip here tolerates an un-normalized row.
 * Returns empty strings when the URL is null/malformed — the caller treats that
 * as a fallback abort (writes preserved).
 */
function parseOwnerRepo(repoUrl: string | null): {
  owner: string;
  repo: string;
} {
  if (!repoUrl) return { owner: "", repo: "" };
  let owner = "";
  let repo = "";
  try {
    const segments = new URL(repoUrl).pathname.split("/").filter(Boolean);
    owner = segments[0] ?? "";
    repo = (segments[1] ?? "").replace(/\.git$/i, "");
  } catch {
    return { owner: "", repo: "" };
  }
  if (!GITHUB_NAME_RE.test(owner) || !GITHUB_NAME_RE.test(repo)) {
    return { owner: "", repo: "" };
  }
  return { owner, repo };
}

/**
 * Resolve the remote default branch (mirrors `workspace-sync.ts`'s
 * `resolveDefaultBranch`: `symbolic-ref --short refs/remotes/origin/HEAD`,
 * stripping the `origin/` prefix). Falls back to `main` on any error so the
 * fallback never hard-fails on a missing origin/HEAD ref.
 */
async function resolveDefaultBranchForFallback(
  installationId: number,
  workspacePath: string,
): Promise<string> {
  try {
    const out = await gitWithInstallationAuth(
      ["symbolic-ref", "--short", "refs/remotes/origin/HEAD"],
      installationId,
      { cwd: workspacePath, timeout: 30_000 },
    );
    const branch = out.toString().trim().replace(/^origin\//, "");
    return branch || "main";
  } catch {
    return "main";
  }
}

/**
 * Protected-branch fallback for `syncPush`. Accretes the latest KB tree onto a
 * durable `soleur/kb-sync` side branch via TREE-OVERLAY (not cherry-pick, not
 * `checkout -B` from default — both would lose the side branch's prior commits;
 * see plan R1/AC4) and opens/updates a non-draft, never-auto-merged PR into the
 * user's default branch.
 *
 * Ordering is load-bearing: the local default branch is reset to
 * `origin/<default>` ONLY AFTER the side-branch push + PR succeed. On any
 * failure the un-pushed commit stays on default (default NOT reset) and HEAD is
 * restored to the default branch, so next session retries with no data loss
 * (AC6). All git runs via `gitWithInstallationAuth` — `runConnectedRepoGit`
 * forbids checkout/branch/reset/push.
 *
 * Returns `{ ok: false }` on any failure (the caller emits the failure op);
 * never throws.
 */
async function runProtectedFallback(
  userId: string,
  workspacePath: string,
  installationId: number,
): Promise<{ ok: boolean; prUrl?: string; commitCount?: number }> {
  const git = (args: string[]) =>
    gitWithInstallationAuth(args, installationId, {
      cwd: workspacePath,
      timeout: 60_000,
    });

  let defaultBranch = "main";
  let restoredClean = false;
  try {
    defaultBranch = await resolveDefaultBranchForFallback(
      installationId,
      workspacePath,
    );

    const { getCurrentRepoUrl } = await import("./current-repo-url");
    const repoUrl = await getCurrentRepoUrl(userId);
    const { owner, repo } = parseOwnerRepo(repoUrl);
    if (!owner || !repo) {
      throw new Error(
        "protected-fallback: could not resolve owner/repo from repo_url",
      );
    }

    // Capture the stranded default tip — its KB tree is what we overlay onto
    // the side branch. Captured BEFORE any branch switch.
    const defaultHead = (await git(["rev-parse", "HEAD"])).toString().trim();

    let commitCount = 0;
    try {
      commitCount =
        parseInt(
          (
            await git([
              "rev-list",
              "--count",
              `origin/${defaultBranch}..HEAD`,
            ])
          )
            .toString()
            .trim(),
          10,
        ) || 0;
    } catch {
      commitCount = 0;
    }

    // Bring origin/<default> and the side branch (may not exist yet) up to date.
    await git(["fetch", "origin", defaultBranch]);
    let sideExists = false;
    try {
      await git(["fetch", "origin", KB_SYNC_SIDE_BRANCH]);
      sideExists = true;
    } catch {
      sideExists = false;
    }
    if (!sideExists) {
      try {
        await git([
          "rev-parse",
          "--verify",
          "--quiet",
          `refs/remotes/origin/${KB_SYNC_SIDE_BRANCH}`,
        ]);
        sideExists = true;
      } catch {
        sideExists = false;
      }
    }

    // Tree-overlay accretion. Base the local side branch on the EXISTING side
    // branch (preserving its prior commits) when present, else branch it from
    // origin/<default>. Never base it on the stranded default tip.
    //
    // `-f`: the auto-commit allowlist (ALLOWED_AUTOCOMMIT_PATHS) deliberately
    // leaves non-`knowledge-base/` tracked files dirty. Without -f, this
    // branch switch aborts ("local changes would be overwritten") whenever a
    // dirty tracked non-KB file differs in the side branch's tree — silently
    // stranding the fallback every session. Forcing discards only those
    // never-synced working-tree edits (they are never committed, never pushed,
    // and the success-path `reset --hard origin/<default>` below already
    // discards them), so -f loses nothing the fallback wouldn't drop anyway.
    await git([
      "checkout",
      "-f",
      "-B",
      KB_SYNC_SIDE_BRANCH,
      sideExists
        ? `origin/${KB_SYNC_SIDE_BRANCH}`
        : `origin/${defaultBranch}`,
    ]);
    // Overlay the latest KB tree from the captured default tip.
    await git(["checkout", defaultHead, "--", "knowledge-base"]);

    // Commit only when the overlay introduced changes (idempotent re-entry, AC7).
    let hasStaged = true;
    try {
      await git(["diff", "--cached", "--quiet"]);
      hasStaged = false;
    } catch {
      hasStaged = true;
    }
    if (hasStaged) {
      await git(["commit", "-m", KB_SYNC_SIDE_COMMIT_MSG]);
    }

    // Push the side branch fast-forward (no --force). A non-fast-forward reject
    // (concurrent co-member push, R3) throws → caught below → default NOT reset.
    await git(["push", "origin", `HEAD:refs/heads/${KB_SYNC_SIDE_BRANCH}`]);

    // Create-or-update the PR in the user's OWN repo. Dynamic import keeps
    // github-app out of session-sync's static graph (sibling tests mock
    // git-auth but not github-app).
    const { createPullRequest, findOpenPullRequest } = await import(
      "./github-app"
    );
    const existing = await findOpenPullRequest(
      installationId,
      owner,
      repo,
      KB_SYNC_SIDE_BRANCH,
      defaultBranch,
    );
    let prUrl: string | undefined;
    if (existing) {
      prUrl = existing.htmlUrl;
    } else {
      const pr = await createPullRequest(
        installationId,
        owner,
        repo,
        KB_SYNC_SIDE_BRANCH,
        defaultBranch,
        KB_SYNC_PR_TITLE,
        kbSyncPrBody(defaultBranch),
      );
      prUrl = pr.htmlUrl;
    }

    // SUCCESS — only now drop the orphan commit from default so it ends `==
    // origin/<default>` (selfHeal then stays cold; AC3/R2).
    await git(["checkout", defaultBranch]);
    await git(["reset", "--hard", `origin/${defaultBranch}`]);
    restoredClean = true;

    return { ok: true, prUrl, commitCount };
  } catch (err) {
    // Failure preserves writes: do NOT reset default. Restore HEAD to the
    // default branch (without reset) so the un-pushed commit survives there for
    // next-session retry and the workspace isn't left parked on the side branch.
    if (!restoredClean) {
      try {
        await git(["checkout", defaultBranch]);
      } catch {
        // best-effort
      }
    }
    log.warn({ err, userId }, "Protected-branch fallback failed");
    return { ok: false };
  }
}

/**
 * Connected-repo git wrapper. Wraps `execFileSync("git", argv, opts)` with
 * an argv-shape guard that rejects:
 *   - subcommands outside the allowlist (`rm`, `reset`, `clean`, `checkout`,
 *     `branch`, `tag`, `cherry-pick`, ...) — categorically destructive or
 *     branch-switching surfaces the auto-commit sweep has no business in.
 *   - forbidden flags (`--force`, `--hard`, `--amend`, `--no-verify`) on
 *     any allowed subcommand.
 *
 * Throws a descriptive Error on rejection so the caller's try/catch logs
 * a meaningful warning rather than silently swallowing the violation.
 */
function runConnectedRepoGit(
  argv: string[],
  opts: Parameters<typeof execFileSync>[2],
): Buffer {
  if (argv.length === 0) {
    throw new Error("connected-repo git: argv must include a subcommand");
  }
  const subcmd = argv[0];
  if (!ALLOWED_GIT_SUBCOMMANDS.has(subcmd)) {
    throw new Error(
      `connected-repo git: subcommand '${subcmd}' is not allowed (allowed: ${[...ALLOWED_GIT_SUBCOMMANDS].join(", ")})`,
    );
  }
  for (const arg of argv) {
    if (FORBIDDEN_GIT_FLAGS.has(arg)) {
      throw new Error(
        `connected-repo git: flag '${arg}' is forbidden (subcommand: ${subcmd})`,
      );
    }
  }
  return execFileSync("git", argv, opts) as Buffer;
}

/**
 * Parse `git status --porcelain=v1 -z` output and return the subset of
 * paths matching ALLOWED_AUTOCOMMIT_PATHS.
 *
 * The `-z` flag emits NUL-separated entries with no C-quoting, so paths
 * containing tabs, newlines, quotes, or non-ASCII characters round-trip
 * cleanly to `git add --`. For renames (R) and copies (C), git emits the
 * destination path first, then the source path as a separate NUL entry —
 * this parser skips the source.
 */
export function getAllowlistedChanges(workspacePath: string): string[] {
  let output: string;
  try {
    output = runConnectedRepoGit(
      ["status", "--porcelain=v1", "-z"],
      { cwd: workspacePath, stdio: "pipe" },
    ).toString();
  } catch {
    return [];
  }

  const paths: string[] = [];
  const tokens = output.split("\0");
  for (let i = 0; i < tokens.length; i++) {
    const entry = tokens[i];
    if (entry.length < 4) continue; // status (2 chars) + space + path
    const status = entry.slice(0, 2);
    const path = entry.slice(3);
    if (ALLOWED_AUTOCOMMIT_PATHS.some((re) => re.test(path))) {
      paths.push(path);
    }
    // R (rename) and C (copy) are followed by an extra NUL-separated
    // entry containing the SOURCE path — skip it.
    if (status[0] === "R" || status[0] === "C") {
      i++;
    }
  }
  return paths;
}

// PR-C §2.1 (#3244): all four `.from("users")` sites in this file migrate
// from service-role to tenant-scoped (RLS `auth.uid() = id` on `users`).
// Module-level lazy service-role cache is gone — `getFreshTenantClient`
// has its own per-userId TTL cache, so per-call mint cost is bounded
// regardless of fan-out. Offline-dev (no SUPABASE_SERVICE_ROLE_KEY) now
// surfaces as a `RuntimeAuthError` thrown from `getFreshTenantClient`,
// caught by the outer `syncPull`/`syncPush` try/catch (this file's
// best-effort contract — failures never block the agent session).

/**
 * Per-handler RLS-baseline probe. Plan §0.4 form throws
 * `RuntimeAuthError` on probe failure; `session-sync`'s best-effort
 * contract (file header: "failures are logged but never throw") means
 * we mirror to Sentry and return `false` instead, letting the entry
 * function early-return cleanly. Same probe semantics, different
 * failure mode for this file. See learning
 * `2026-04-12-silent-rls-failures-in-team-names` for why this is
 * load-bearing distinct from the implicit `getFreshTenantClient` mint:
 * a cached JWT inside the TTL window does not re-run `precheck_jwt_mint`,
 * so a mid-session jti revocation or RLS policy churn would otherwise
 * silently return zero rows on the first real read.
 */
async function authProbe(userId: string, op: string): Promise<boolean> {
  try {
    const tenant = await getFreshTenantClient(userId);
    const { error: probeErr } = await tenant
      .from("users")
      .select("id")
      .eq("id", userId)
      .maybeSingle();
    if (probeErr) {
      reportSilentFallback(probeErr, {
        feature: "session-sync",
        op: `auth-probe.${op}`,
        extra: { userId },
      });
      return false;
    }
    return true;
  } catch (err) {
    if (err instanceof RuntimeAuthError) {
      reportSilentFallback(err, {
        feature: "session-sync",
        op: `auth-probe.${op}`,
        extra: { userId },
      });
      return false;
    }
    throw err;
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function hasRemote(workspacePath: string): boolean {
  try {
    const result = runConnectedRepoGit(["remote", "-v"], {
      cwd: workspacePath,
      stdio: "pipe",
    });
    return result.toString().trim().length > 0;
  } catch {
    return false;
  }
}

function hasLocalCommits(workspacePath: string): boolean {
  try {
    // Check if there are commits ahead of the remote tracking branch
    const result = runConnectedRepoGit(
      ["rev-list", "--count", "@{u}..HEAD"],
      { cwd: workspacePath, stdio: "pipe" },
    );
    return parseInt(result.toString().trim(), 10) > 0;
  } catch {
    // No upstream tracking branch — if we have any commits at all, attempt push.
    // This handles the case where auto-commit created local commits but no
    // upstream tracking branch is set (first push after clone).
    try {
      const result = runConnectedRepoGit(
        ["rev-list", "--count", "HEAD"],
        { cwd: workspacePath, stdio: "pipe" },
      );
      return parseInt(result.toString().trim(), 10) > 0;
    } catch {
      return false;
    }
  }
}

async function getInstallationId(userId: string): Promise<number | null> {
  const { resolveInstallationId } = await import(
    "@/server/resolve-installation-id"
  );
  return resolveInstallationId(userId);
}

/**
 * Recursively count .md files in a directory.
 * Returns 0 if the directory does not exist.
 */
export function countMdFiles(dirPath: string): number {
  let count = 0;
  try {
    const entries = readdirSync(dirPath, { withFileTypes: true });
    for (const entry of entries) {
      const fullPath = join(dirPath, entry.name);
      if (entry.isDirectory()) {
        count = count + countMdFiles(fullPath);
      } else if (entry.isFile() && entry.name.endsWith(".md")) {
        count = count + 1;
      }
    }
  } catch {
    // Directory does not exist or is not readable
  }
  return count;
}

/**
 * Record the current KB file count in the user's kb_sync_history JSONB array.
 * Trims to the last 14 entries. Best-effort — failures are logged, never thrown.
 */
async function recordKbSyncHistory(
  userId: string,
  workspacePath: string,
): Promise<void> {
  // PR-C §2.1 (#3244): tenant-scoped SELECT + UPDATE on `users`.
  const tenant = await getFreshTenantClient(userId);
  const kbPath = join(workspacePath, "knowledge-base");
  const fileCount = countMdFiles(kbPath);

  const { data: user, error: fetchError } = await tenant
    .from("users")
    .select("kb_sync_history")
    .eq("id", userId)
    .single();

  if (fetchError || !user) {
    log.warn({ err: fetchError, userId }, "Failed to fetch kb_sync_history");
    return;
  }

  const history = Array.isArray(user.kb_sync_history)
    ? (user.kb_sync_history as Array<{ date: string; count: number }>)
    : [];

  const today = new Date().toISOString().slice(0, 10);
  const updated = [...history, { date: today, count: fileCount }].slice(-14);

  const { error: updateError } = await tenant
    .from("users")
    .update({ kb_sync_history: updated })
    .eq("id", userId);

  if (updateError) {
    log.warn({ err: updateError, userId }, "Failed to update kb_sync_history");
  } else {
    log.debug({ userId, fileCount }, "Recorded KB sync history");
  }
}

// #4224 — shared constants for the workspace-reconcile feature.
// Re-exported from the Inngest function module too so test files and
// future consumers have one source of truth.
export const WORKSPACE_RECONCILE_REQUESTED_EVENT =
  "platform/workspace.reconcile.requested" as const;
// Bumped "1"→"2" (ADR-044): the reconcile payload now carries
// `fullName` (repository.full_name) so the consumer can fan out to all
// workspaces matching the repo. Adding a consumer-read field is a schema-
// boundary change; in-flight v=1 events (lacking fullName) drain to
// {ok:false} via the non-throwing schema-gate rather than syncing with a
// missing field. See 2026-04-18-schema-version-must-be-asserted-at-consumer-boundary.
export const WORKSPACE_RECONCILE_SCHEMA_V = "2" as const;
export const WORKSPACE_RECONCILE_SENTRY_FEATURE =
  "workspace-reconcile-push" as const;

// kb_sync_history error_class literals. Load-bearing for the 30-day drift
// analysis (TR4 / DS1 gating in plan §Phase 5).
export const ERROR_CLASS_NON_FAST_FORWARD = "non_fast_forward" as const;
export const ERROR_CLASS_WORKSPACE_NOT_READY = "workspace_not_ready" as const;
export const ERROR_CLASS_SYNC_FAILED = "sync_failed" as const;
export type KbSyncErrorClass =
  | typeof ERROR_CLASS_NON_FAST_FORWARD
  | typeof ERROR_CLASS_WORKSPACE_NOT_READY
  | typeof ERROR_CLASS_SYNC_FAILED;

/**
 * Rich kb_sync_history row shape used by webhook-push reconcile (#4224)
 * and the manual /api/kb/sync route. Heterogeneous with the legacy
 * `{ date, count }` shape produced by `recordKbSyncHistory` — the reader
 * (KbSyncStatus) discriminates inline.
 */
export type KbSyncRow = {
  at: string; // ISO timestamp; anchored to sync_completed_at semantics
  trigger: "webhook_push" | "manual" | "session";
  sha_before?: string;
  sha_after?: string;
  ok: boolean;
  error_class?: KbSyncErrorClass;
  // #self-heal (kb-sync-affordance-reconcile) — set true on an ok:true row
  // when the clone was recovered via a gated `reset --hard origin/<default>`
  // (a diverged clone with zero un-pushed local commits) rather than a clean
  // `pull --ff-only`. Absent on clean syncs and all legacy rows. Keeps the
  // forensic trail distinguishing a reset-recovery from a normal pull.
  recovered?: boolean;
  push_received_at?: number; // Unix ms — only set on webhook_push rows
  sync_completed_at: number; // Unix ms
  // #4728 — workspace discriminator. Set by the webhook-push reconcile
  // producer (workspace-reconcile-on-push.ts), where the iterated
  // workspace id is in scope. Absent on manual-route rows and on all
  // legacy rows; a missing value reads as legacy-single-workspace.
  workspace_id?: string;
};

/** Legacy daily-count row shape produced by `recordKbSyncHistory`. */
export type LegacyKbSyncRow = { date: string; count: number };

const KB_SYNC_HISTORY_CAP = 100;

/**
 * Append a rich `KbSyncRow` to the user's `kb_sync_history` JSONB array,
 * preserving any legacy `{ date, count }` rows already there. Caps at 100.
 * Best-effort — failures are mirrored to Sentry via `reportSilentFallback`
 * but do not throw.
 *
 * Implementation routes through the `append_kb_sync_row` SECURITY DEFINER
 * RPC (migration 053). Direct UPDATE on `kb_sync_history` is blocked by
 * migration 006's column grant (authenticated has UPDATE(email) only) and
 * migration 017's RESTRICTIVE policy; the RPC is the only tenant-callable
 * write path. The RPC also makes the read-modify-write atomic under a
 * row-level lock, removing the lost-update race that a JS-side fetch +
 * update would have under concurrent webhook + manual sync calls.
 *
 * NOTE: `recordKbSyncHistory` is intentionally NOT widened — its
 * `{date,count}` shape continues to serve the daily-count sparkline; this
 * new helper writes the per-event reconciliation rows.
 */
export async function appendKbSyncRow(
  userId: string,
  row: KbSyncRow,
): Promise<void> {
  try {
    const tenant = await getFreshTenantClient(userId);
    const { error } = await tenant.rpc("append_kb_sync_row", {
      p_row: row,
      p_cap: KB_SYNC_HISTORY_CAP,
    });
    if (error) {
      reportSilentFallback(error, {
        feature: "session-sync",
        op: "appendKbSyncRow",
        extra: { userId },
        message: "append_kb_sync_row RPC failed",
      });
    }
  } catch (err) {
    reportSilentFallback(err, {
      feature: "session-sync",
      op: "appendKbSyncRow",
      extra: { userId },
      message: "kb_sync_history append failed",
    });
  }
}

/**
 * #4906 — append a `KbSyncRow` to a workspace's *backing user's*
 * `kb_sync_history`, keyed by `workspaceId` rather than by an authenticated
 * caller. Used by the owner-less reconcile path
 * (`workspace-reconcile-on-push.ts`), which runs in the Inngest worker with no
 * user JWT — so `auth.uid()` is null and `appendKbSyncRow` (the tenant RPC)
 * cannot be used.
 *
 * Routes through the `append_kb_sync_row_for_user` SECURITY DEFINER RPC
 * (migration 100), which is `service_role`-only. The caller passes the
 * service-role `client` in — session-sync.ts must NOT itself acquire a
 * service-role client (it was migrated to tenant-only in PR-C #3244 and removed
 * from `.service-role-allowlist`; the privilege-acquisition site stays in the
 * allowlisted handler). For solo workspaces `workspaces.id = users.id`
 * (ADR-038 N2), so `workspaceId` resolves directly to the backing user row and
 * the audit row lands exactly as an owner-attributed row would. If `workspaceId`
 * is not a `users.id` (a non-solo / org owner-less workspace — itself an
 * invariant drift), the RPC's UPDATE affects zero rows and no audit row lands;
 * the caller's owner-drift warn still fires, so the anomaly is never silent.
 *
 * Best-effort, mirroring `appendKbSyncRow`: failures are reported to Sentry via
 * `reportSilentFallback` but never throw (the reconcile must not fail on a
 * missing audit row).
 */
export async function appendKbSyncRowForWorkspace(
  client: SupabaseClient,
  workspaceId: string,
  row: KbSyncRow,
): Promise<void> {
  try {
    const { error } = await client.rpc("append_kb_sync_row_for_user", {
      // p_user_id ← workspaceId: solo workspaces.id === users.id (ADR-038 N2).
      // Non-solo ids that don't map to a users row UPDATE 0 rows (no error).
      p_user_id: workspaceId,
      p_row: row,
      p_cap: KB_SYNC_HISTORY_CAP,
    });
    if (error) {
      reportSilentFallback(error, {
        feature: "session-sync",
        op: "appendKbSyncRowForWorkspace",
        extra: { workspaceId },
        message: "append_kb_sync_row_for_user RPC failed",
      });
    }
  } catch (err) {
    reportSilentFallback(err, {
      feature: "session-sync",
      op: "appendKbSyncRowForWorkspace",
      extra: { workspaceId },
      message: "kb_sync_history workspace-keyed append failed",
    });
  }
}

async function updateLastSynced(userId: string): Promise<void> {
  // PR-C §2.1 (#3244): tenant-scoped UPDATE on `users`.
  const tenant = await getFreshTenantClient(userId);
  const { error } = await tenant
    .from("users")
    .update({ repo_last_synced_at: new Date().toISOString() })
    .eq("id", userId);

  if (error) {
    log.warn({ err: error, userId }, "Failed to update repo_last_synced_at");
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Pull latest changes from remote before an agent session.
 * Best-effort: failures are logged but never throw.
 */
export async function syncPull(
  userId: string,
  workspacePath: string,
): Promise<void> {
  if (!hasRemote(workspacePath)) {
    return; // Empty workspace, no remote
  }

  // PR-C §2.1 (#3244): per-entry-function RLS-baseline probe — see
  // `authProbe` doc-comment for the load-bearing rationale.
  if (!(await authProbe(userId, "syncPull"))) {
    log.warn({ userIdHash: hashUserId(userId) }, "Sync pull aborted — auth probe failed");
    return;
  }

  try {
    const installationId = await getInstallationId(userId);
    if (!installationId) {
      log.warn({ userId }, "No installation ID found for sync pull");
      return;
    }

    // Auto-commit any uncommitted changes before pulling to avoid conflicts.
    // Path-scoped to ALLOWED_AUTOCOMMIT_PATHS — see #2905.
    try {
      const allowed = getAllowlistedChanges(workspacePath);
      if (allowed.length === 0) {
        log.info(
          { userId },
          "No allowlisted changes to commit — skipping auto-commit",
        );
      } else {
        runConnectedRepoGit(["add", "--", ...allowed], {
          cwd: workspacePath,
          stdio: "pipe",
        });
        runConnectedRepoGit(["commit", "-m", AUTO_COMMIT_MSG_PULL], {
          cwd: workspacePath,
          stdio: "pipe",
        });
      }
    } catch (err) {
      log.warn({ err, userId }, "Auto-commit before pull failed");
    }

    // Use merge (not rebase) — shallow clones lack sufficient history for rebase
    await gitWithInstallationAuth(
      ["pull", "--no-rebase", "--autostash"],
      installationId,
      { cwd: workspacePath, timeout: 60_000 },
    );

    await updateLastSynced(userId);
    log.info({ userId }, "Sync pull completed");
  } catch (err) {
    log.warn({ err, userId }, "Sync pull failed — continuing with local state");
    reportSilentFallback(err, {
      feature: "session-sync",
      op: "syncPull",
      // workspacePath omitted intentionally — it embeds the raw userId
      // (workspacePath = `<root>/<userId>`), which bypasses the
      // hashExtraUserId boundary's top-level rename (Recital 26 +
      // ADR-029 rename-at-boundary). The pseudonymous userId carries the
      // diagnostic value; the path adds no information.
      extra: { userId },
      message: "Sync pull failed — continuing with local state",
    });
  }
}

/**
 * Push local changes to remote after an agent session.
 * Best-effort: failures are logged but never throw.
 */
export async function syncPush(
  userId: string,
  workspacePath: string,
): Promise<void> {
  if (!hasRemote(workspacePath)) {
    return; // Empty workspace, no remote
  }

  // PR-C §2.1 (#3244): per-entry-function RLS-baseline probe — see
  // `authProbe` doc-comment for the load-bearing rationale.
  if (!(await authProbe(userId, "syncPush"))) {
    log.warn({ userIdHash: hashUserId(userId) }, "Sync push aborted — auth probe failed");
    return;
  }

  try {
    // Auto-commit any uncommitted changes before pushing.
    // Path-scoped to ALLOWED_AUTOCOMMIT_PATHS — see #2905.
    try {
      const allowed = getAllowlistedChanges(workspacePath);
      if (allowed.length === 0) {
        log.info(
          { userId },
          "No allowlisted changes to commit — skipping auto-commit",
        );
      } else {
        runConnectedRepoGit(["add", "--", ...allowed], {
          cwd: workspacePath,
          stdio: "pipe",
        });
        runConnectedRepoGit(["commit", "-m", AUTO_COMMIT_MSG_PUSH], {
          cwd: workspacePath,
          stdio: "pipe",
        });
      }
    } catch (err) {
      log.warn({ err, userId }, "Auto-commit before push failed");
    }

    if (!hasLocalCommits(workspacePath)) {
      log.debug({ userId }, "No local commits to push");
      return;
    }

    const installationId = await getInstallationId(userId);
    if (!installationId) {
      log.warn({ userId }, "No installation ID found for sync push");
      return;
    }

    try {
      await gitWithInstallationAuth(
        ["push"],
        installationId,
        { cwd: workspacePath, timeout: 60_000 },
      );
    } catch (pushErr) {
      const pushClass = classifyPushError(pushErr);
      if (pushClass === "protected_branch") {
        // #5426 — protected default: route writes to soleur/kb-sync + PR.
        const fallback = await runProtectedFallback(
          userId,
          workspacePath,
          installationId,
        );
        if (!fallback.ok) {
          // `reason` discriminates "the fallback ran and failed" from the
          // persistent_other branch below (which never entered the fallback)
          // WITHOUT splitting the Sentry op — the issue-alert + its op-contract
          // test pin the single `kb-sync.protected-fallback-failed` op.
          reportSilentFallback(pushErr, {
            feature: "session-sync",
            op: "kb-sync.protected-fallback-failed",
            extra: { userId, reason: "fallback_failed" },
            message:
              "KB-sync protected-branch fallback failed — writes preserved on default for retry",
          });
          return;
        }
        warnSilentFallback(null, {
          feature: "session-sync",
          op: "kb-sync.push-protected-fallback",
          extra: {
            userId,
            prUrl: fallback.prUrl,
            commitCount: fallback.commitCount,
          },
          message:
            "KB-sync push rejected by branch protection — routed to soleur/kb-sync + PR",
        });
        // Fall through to history recording + last-synced (writes delivered).
      } else if (pushClass === "persistent_other") {
        // Non-protection persistent reject (e.g. shallow update not allowed) —
        // retrying would loop forever. Emit a distinct op and stop here.
        reportSilentFallback(pushErr, {
          feature: "session-sync",
          op: "kb-sync.protected-fallback-failed",
          extra: { userId, reason: "persistent_other" },
          message:
            "KB-sync push persistently rejected (non-protection) — not retried",
        });
        return;
      } else {
        // Auth/network/transient — existing best-effort retry-next-session.
        throw pushErr;
      }
    }

    // Best-effort: record KB file count for analytics sparklines
    try {
      await recordKbSyncHistory(userId, workspacePath);
    } catch (err) {
      log.warn({ err, userId }, "KB sync history recording failed");
      reportSilentFallback(err, {
        feature: "session-sync",
        op: "recordKbSyncHistory",
        // workspacePath dropped — see syncPull catch for the rationale.
        extra: { userId },
        message: "KB sync history recording failed",
      });
    }

    await updateLastSynced(userId);
    log.info({ userId }, "Sync push completed");
  } catch (err) {
    log.warn({ err, userId }, "Sync push failed — next session will retry");
    reportSilentFallback(err, {
      feature: "session-sync",
      op: "syncPush",
      // workspacePath dropped — see syncPull catch for the rationale.
      extra: { userId },
      message: "Sync push failed — next session will retry",
    });
  }
}
