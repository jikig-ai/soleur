// ---------------------------------------------------------------------------
// Session sync: pull before session, push after session
//
// Keeps the user's workspace in sync with their connected GitHub repo.
// All operations are best-effort — failures are logged but never block
// the agent session.
// ---------------------------------------------------------------------------

import { execFileSync, type ExecFileSyncOptions } from "child_process";
import { lstatSync, readdirSync } from "fs";
import { join } from "path";
import type { SupabaseClient } from "@supabase/supabase-js";
import {
  getFreshTenantClient,
  RuntimeAuthError,
} from "@/lib/supabase/tenant";
import {
  hashUserId,
  mirrorWithDebounce,
  reportSilentFallback,
  warnSilentFallback,
} from "@/server/observability";
import { gitWithInstallationAuth } from "./git-auth";
import { ALLOW_PROTOCOL_NONE, HostGitRefusedError, hostGitInvocation } from "./host-git";
import { KbSyncError, publishKbOnly, reportPushHeld, type KbWorkspaceWriter } from "./kb-sync-publish";
import { HEX40, readWorkspaceHeadRef } from "./approval/workspace-head";
import { validateBranchFormat } from "./branch-validation";
import { writeRepoColsToWorkspace } from "./workspace-repo-mirror";
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
  // #12600 (CTO rulings R12, R19, R20): the KB sync's only two workspace WRITE verbs, each behind the exact-argv guard
  // in `assertConnectedRepoArgv`. Decision verbs (hash checks, tree and commit builds) never run here: they run token-free
  // in the isolated GIT_DIR (server/git-isolated-local.ts).
  "update-ref",
  "unpack-objects",
]);

/** An object id the guarded `update-ref` shapes accept: 40 lowercase hex, never all-zero (git reads it as "delete" / "must not exist"). */
function guardedSha(sha: string | undefined): boolean {
  return typeof sha === "string" && HEX40.test(sha) && !/^0+$/.test(sha);
}

/** A branch name the guarded `update-ref` shapes accept (git's ref-format rules; throws a static error otherwise). */
function guardedBranch(name: string): boolean {
  try {
    validateBranchFormat(name);
    return true;
  } catch {
    return false;
  }
}

/**
 * The exact argv shapes of the two guarded write verbs (#12600):
 *   - `["update-ref", "--no-deref", "refs/heads/<b>", <40hex new>, <40hex old>]` (CAS mandatory, R1/R19), and
 *   - `["update-ref", "--no-deref", "refs/remotes/origin/<b>", <40hex>]` (the advisory tracking ref, R8/R17);
 *   - `["unpack-objects", "-q"]` (the pack arrives on stdin).
 * Any other argv for these verbs throws.
 */
function assertGuardedWriteArgv(argv: readonly string[]): void {
  const refuse = (): never => {
    throw new Error(`connected-repo git: '${argv[0]}' argv is not one of the guarded shapes`);
  };
  if (argv[0] === "unpack-objects") {
    if (argv.length !== 2 || argv[1] !== "-q") refuse();
    return;
  }
  if (argv[0] !== "update-ref") return;
  // R19: a symref planted at the ref must be replaced, never followed to the branch it names.
  if (argv[1] !== "--no-deref") throw new Error("connected-repo git: 'update-ref' requires --no-deref");
  const ref = argv[2] ?? "";
  if (ref.startsWith("refs/heads/")) {
    if (argv.length !== 5 || !guardedBranch(ref.slice("refs/heads/".length))) refuse();
    if (!guardedSha(argv[3]) || !guardedSha(argv[4])) refuse();
    return;
  }
  if (ref.startsWith("refs/remotes/origin/")) {
    if (argv.length !== 4 || !guardedBranch(ref.slice("refs/remotes/origin/".length))) refuse();
    if (!guardedSha(argv[3])) refuse();
    return;
  }
  refuse();
}

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

export { classifyPushError, type PushErrorClass } from "./kb-sync-publish";

/**
 * What a failed auto-commit may carry to Sentry: the stage, the exit status and a CLOSED stderr bucket, never the
 * raw error (its message is the full argv, which names tenant file paths, plus git's stderr). The raw error stays in
 * the local `log.warn`. `null` = nothing to report (an empty commit is not a failure).
 */
function autoCommitFailure(err: unknown, stage: "pull" | "push"): Error | null {
  if (err instanceof HostGitRefusedError) return new Error(`auto-commit-${stage} refused: ${err.reason}`);
  const e = err as { status?: number; stdout?: unknown; stderr?: unknown };
  const text = `${String(e?.stdout ?? "")}\n${String(e?.stderr ?? "")}`;
  let bucket = "other";
  if (/nothing (added )?to commit|no changes added to commit/i.test(text)) return null;
  if (/Author identity unknown|unable to auto-detect email/i.test(text)) bucket = "identity";
  else if (/index\.lock/i.test(text)) bucket = "index-lock";
  else if (/not a git repository/i.test(text)) bucket = "not-a-repository";
  else if (/Permission denied|Operation not permitted/i.test(text)) bucket = "permission";
  return new Error(`auto-commit-${stage} failed (exit ${typeof e?.status === "number" ? e.status : "unknown"}, ${bucket})`);
}

/**
 * The argv-shape guard of `runConnectedRepoGit`, exported for its unit rows: the subcommand allowlist, the forbidden
 * flags on every allowed subcommand, and the exact shapes of the guarded write verbs. Throws before any git runs.
 */
export function assertConnectedRepoArgv(argv: readonly string[]): void {
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
  assertGuardedWriteArgv(argv);
}

/**
 * Connected-repo git wrapper. Runs `execFileSync("git", ...)` through the shared host-git invocation
 * (hardening arguments, scrubbed environment, `GIT_WORK_TREE=<cwd>`) with
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
/** Upper bound of one connected-repo git child (D13): a stalled `.lock` or a wedged filesystem costs at most this long. */
export const CONNECTED_REPO_GIT_TIMEOUT_MS = 60_000;

function runConnectedRepoGit(
  argv: string[],
  // No `env`: the environment is the helper's (scrubbed, hardened), never a caller's.
  opts: Omit<ExecFileSyncOptions, "env"> & { cwd: string },
): Buffer {
  assertConnectedRepoArgv(argv);
  // Host-side git in a workspace an agent session may have authored: shared hardening arguments + a scrubbed env
  // (ADR-050 amendment; see server/host-git.ts for what that does and does not close).
  const h = hostGitInvocation(argv, { cwd: opts.cwd, allowProtocol: ALLOW_PROTOCOL_NONE });
  return execFileSync("git", h.args, { timeout: CONNECTED_REPO_GIT_TIMEOUT_MS, ...opts, env: h.env }) as Buffer;
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
  } catch (err) {
    mirrorGitRefusal(err, "getAllowlistedChanges");
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

/**
 * A refused `.git` (a gitfile, a symlink, `commondir`, a redirecting entry) stops EVERY sync for that workspace at the
 * first gate below, so it must not look like "no remote" or "nothing changed": mirror it once, with the reason only (no
 * path, no user id in the message). Returns true when `err` was a refusal.
 */
function mirrorGitRefusal(err: unknown, gate: string): boolean {
  if (!(err instanceof HostGitRefusedError)) return false;
  log.warn({ reason: err.reason, gate }, "Host git refused the workspace .git; sync skipped");
  reportSilentFallback(new Error(`session-sync refused: ${err.reason}`), {
    feature: "session-sync",
    op: "git-refused",
    extra: { gate },
    message: "Host git refused the workspace .git shape",
  });
  return true;
}

function hasRemote(workspacePath: string): boolean {
  try {
    const result = runConnectedRepoGit(["remote", "-v"], {
      cwd: workspacePath,
      stdio: "pipe",
    });
    return result.toString().trim().length > 0;
  } catch (err) {
    mirrorGitRefusal(err, "hasRemote");
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
  } catch (outer) {
    if (mirrorGitRefusal(outer, "hasLocalCommits")) return false;
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
 * Trims to the last 14 entries (the RPC's `p_cap: 14` reproduces the old
 * `.slice(-14)` — read-merge-cap happens inside the function under a
 * row-level lock). Best-effort — failures are logged and mirrored to Sentry
 * via `reportSilentFallback`, never thrown.
 *
 * #11193: routed through the `append_kb_sync_row` SECURITY DEFINER RPC
 * (migration 053) — the same instrumented path `appendKbSyncRow` below uses.
 * Migration 178 re-narrows `users` to SELECT + column-level UPDATE on the
 * Note C census set, and migration 017's RESTRICTIVE policy pins
 * kb_sync_history for any authenticated UPDATE regardless of grants, so a
 * direct `.update({ kb_sync_history })` cannot survive the narrow. The RPC
 * is the only tenant-callable write path (it also removes the lost-update
 * race the JS-side fetch + update had under concurrent sync calls).
 */
async function recordKbSyncHistory(
  userId: string,
  workspacePath: string,
): Promise<void> {
  // PR-C §2.1 (#3244): tenant-scoped client (authenticated role).
  const tenant = await getFreshTenantClient(userId);
  const kbPath = join(workspacePath, "knowledge-base");
  const fileCount = countMdFiles(kbPath);
  const today = new Date().toISOString().slice(0, 10);

  const { error } = await tenant.rpc("append_kb_sync_row", {
    p_row: { date: today, count: fileCount } satisfies LegacyKbSyncRow,
    p_cap: 14,
  });

  if (error) {
    reportSilentFallback(error, {
      feature: "session-sync",
      op: "appendKbSyncRow",
      extra: { userId },
      message: "append_kb_sync_row RPC failed (recordKbSyncHistory)",
    });
    return;
  }
  const uidHash = hashUserId(userId);
  log.debug({ userIdHash: uidHash, fileCount }, "Recorded KB sync history");
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
//
// Bumped "2"→"3" (ADR-044 Amendment 2026-06-17b): `founderId` removed from
// the payload (it was vestigial — the consumer re-derives workspaces from
// (installation_id, repo_url) and never read it for routing). Dropping a
// payload field is a schema-boundary change; in-flight v=2 events deadletter
// via the non-throwing schema-gate and the next push re-drives (reconcile is
// idempotent by (installation_id, repo_url)). See plan R6/P2-3.
export const WORKSPACE_RECONCILE_SCHEMA_V = "3" as const;
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
  // "reconcile_backfill" (#5689 item 2): a system-initiated sync that arm-1 of
  // cron-workspace-sync-health fires immediately after backfilling a missing
  // github_installation_id — truthfully distinct from a user-driven "webhook_push".
  // Write-only label (no reader switches on `trigger`); free-form JSONB, no migration.
  trigger: "webhook_push" | "manual" | "session" | "reconcile_backfill";
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

/**
 * ADR-044 PR-B: write `repo_last_synced_at` to the AUTHORITATIVE
 * `workspaces` row (the repo/status read moved there in PR-2, so a `users`
 * write would freeze the displayed timestamp forever).
 *
 * Signature is `(service, workspaceId)` — NO `userId`, NO internal resolve,
 * NO `userId` fallback. The id is the caller's ONE membership-verified
 * resolution (agent-runner.ts resolves `resolveActiveWorkspace` once and
 * threads the id into BOTH the on-disk path and here), which forbids the
 * #5435 dual-resolver divergence class: a team-active member's write lands on
 * the TEAM workspace, never their solo `userId`. session-sync.ts does NOT
 * acquire a service-role client (it is tenant-only, off `.service-role-allowlist`);
 * the caller injects the service client (writeRepoColsToWorkspace needs it —
 * `workspaces` has no UPDATE RLS policy). Best-effort: writeRepoColsToWorkspace
 * Sentry-mirrors a write error / 0-row no-op but does not throw.
 */
async function updateLastSynced(
  service: SupabaseClient,
  workspaceId: string,
): Promise<void> {
  await writeRepoColsToWorkspace(service, workspaceId, {
    repo_last_synced_at: new Date().toISOString(),
  });
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
  // ADR-044 PR-B: injected service client + the caller's ONE resolved active
  // workspace id (resolve-id-first; see agent-runner.ts). Threaded straight
  // into `updateLastSynced(service, workspaceId)` — session-sync never
  // re-resolves the workspace (forbids the #5435 dual-resolver divergence).
  service: SupabaseClient,
  workspaceId: string,
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
      const failure = autoCommitFailure(err, "pull");
      if (failure) {
        reportSilentFallback(failure, {
          feature: "session-sync",
          op: "auto-commit-pull",
          extra: { userId },
          message: "Auto-commit before sync pull failed",
        });
      }
    }

    // Use merge (not rebase) — shallow clones lack sufficient history for rebase
    await gitWithInstallationAuth(
      ["pull", "--no-rebase", "--autostash"],
      installationId,
      { cwd: workspacePath, timeout: 60_000 },
    );

    await updateLastSynced(service, workspaceId);
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

/** The KB sync's workspace writes (#12600): only the guarded verbs of `runConnectedRepoGit`. */
function kbWorkspaceWriter(workspacePath: string): KbWorkspaceWriter {
  const opts = { cwd: workspacePath, stdio: "pipe" as const };
  return {
    unpack: (pack) => {
      runConnectedRepoGit(["unpack-objects", "-q"], { ...opts, input: pack });
    },
    casBranch: (branch, next, prev) => {
      runConnectedRepoGit(["update-ref", "--no-deref", `refs/heads/${branch}`, next, prev], opts);
    },
    setTracking: (branch, sha) => {
      runConnectedRepoGit(["update-ref", "--no-deref", `refs/remotes/origin/${branch}`, sha], opts);
    },
  };
}

/** `git status --porcelain=v1` XY codes of an unmerged (conflicted) index entry. */
const UNMERGED_XY = new Set(["DD", "AU", "UD", "UA", "DU", "AA", "UU"]);

/**
 * A merge is in progress, so neither commit nor push (R11): `.git/MERGE_HEAD` present (any type, or unreadable), OR the
 * index holds an unmerged entry without one (a conflicted `stash pop`, `cherry-pick` or `rebase`; D13), which an auto-commit
 * `add` would resolve by committing the conflict markers. A status that cannot run is not a merge (the auto-commit's own
 * status then fails the same way).
 */
function mergeInProgress(workspacePath: string): boolean {
  try {
    lstatSync(join(workspacePath, ".git", "MERGE_HEAD"));
    return true;
  } catch (err) {
    const code = (err as { code?: unknown } | null)?.code;
    if (code !== "ENOENT" && code !== "ENOTDIR") return true;
  }
  let out: string;
  try {
    out = runConnectedRepoGit(["status", "--porcelain=v1", "-z", "--untracked-files=no"], { cwd: workspacePath, stdio: "pipe" }).toString();
  } catch (err) {
    mirrorGitRefusal(err, "mergeInProgress");
    return false;
  }
  const tokens = out.split("\0");
  for (let i = 0; i < tokens.length; i++) {
    const entry = tokens[i];
    if (entry.length < 4) continue;
    if (UNMERGED_XY.has(entry.slice(0, 2))) return true;
    if (entry[0] === "R" || entry[0] === "C") i++; // the source path of a rename / copy
  }
  return false;
}

/**
 * Push the session's knowledge-base changes after an agent session (#12600). Only a commit the server built reaches the
 * remote: `S` = the remote tip's verified root with HEAD's `knowledge-base` entry, parent the remote tip, Soleur's
 * message and identity (server/kb-sync-publish.ts). Best-effort: failures are logged but never throw.
 */
export async function syncPush(
  userId: string,
  workspacePath: string,
  // ADR-044 PR-B: injected service client + the caller's ONE resolved active
  // workspace id (see syncPull / agent-runner.ts).
  service: SupabaseClient,
  workspaceId: string,
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

  const ctx = { userId, workspaceId };
  try {
    // A conflicted session-start merge: committing would publish conflict markers (matrix 17).
    if (mergeInProgress(workspacePath)) {
      reportPushHeld("merge_in_progress", "held", ctx);
      return;
    }

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
      const failure = autoCommitFailure(err, "push");
      if (failure) {
        reportSilentFallback(failure, {
          feature: "session-sync",
          op: "auto-commit-push",
          extra: { userId },
          message: "Auto-commit before sync push failed",
        });
      }
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

    // Frozen HEAD, read from the files (no git child): the sha every later step builds on and CASes against.
    let head: { sha: string; refName: string | null };
    try {
      head = readWorkspaceHeadRef(workspacePath);
    } catch {
      throw new KbSyncError("head_unreadable");
    }
    if (head.refName === null) {
      reportPushHeld("detached_head", "held", ctx);
      return;
    }

    const result = await publishKbOnly({
      ...ctx,
      workspacePath,
      installationId,
      headSha: head.sha,
      refName: head.refName,
      writer: kbWorkspaceWriter(workspacePath),
    });

    if (result.kind === "fallback_failed") {
      // `reason` discriminates "the fallback ran and failed" from the
      // persistent_other branch below (which never entered the fallback)
      // WITHOUT splitting the Sentry op — the issue-alert + its op-contract
      // test pin the single `kb-sync.protected-fallback-failed` op. The closed
      // `fallback_reason` tag names the step (#12600).
      // CTO ruling D8: a null error (an Error loses these tags to the pino-mirror capture, #8629), debounced per
      // workspace and reason (the fallback can fail every turn, R16).
      mirrorWithDebounce(
        null,
        {
          feature: "session-sync",
          op: "kb-sync.protected-fallback-failed",
          extra: { userId, reason: "fallback_failed" },
          tags: {
            reason: "fallback_failed",
            fallback_reason: result.fallbackReason,
            push_class: result.pushErr?.pushClass ?? "none",
          },
          message:
            "KB-sync protected-branch fallback failed — writes preserved on default for retry",
        },
        workspaceId,
        `kb-sync-fallback-failed:${result.fallbackReason}`,
      );
      return;
    }
    if (result.kind === "fallback") {
      // #5426 — protected default: writes routed to soleur/kb-sync + PR.
      warnSilentFallback(null, {
        feature: "session-sync",
        op: "kb-sync.push-protected-fallback",
        extra: {
          userId,
          prUrl: result.prUrl,
          commitCount: result.commitCount,
        },
        message:
          "KB-sync push rejected by branch protection — routed to soleur/kb-sync + PR",
      });
      // Fall through to history recording + last-synced (writes delivered).
    } else if (result.kind !== "pushed") {
      // Held or nothing to sync: no push happened, so no bookkeeping (CPO condition C4).
      return;
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

    await updateLastSynced(service, workspaceId);
    log.info({ userId }, "Sync push completed");
  } catch (err) {
    if (err instanceof KbSyncError && err.pushClass === "persistent_other") {
      // Non-protection persistent reject (e.g. shallow update not allowed) —
      // retrying would loop forever. Emit a distinct op and stop here.
      // D8: null error, the cause in tags (the Error path's tags are lost to the pino-mirror capture, #8629).
      reportSilentFallback(null, {
        feature: "session-sync",
        op: "kb-sync.protected-fallback-failed",
        extra: { userId, reason: "persistent_other" },
        tags: { reason: "persistent_other", push_class: "persistent_other" },
        message:
          "KB-sync push persistently rejected (non-protection) — not retried",
      });
      return;
    }
    log.warn({ err, userId }, "Sync push failed — next session will retry");
    // D8: null error, the closed reason and push class in tags. A non-KbSyncError carries only its class name: its
    // message is git's argv (the URL and the refspec, R2), so it never reaches Sentry.
    const kbErr = err instanceof KbSyncError ? err : null;
    reportSilentFallback(null, {
      feature: "session-sync",
      op: "syncPush",
      // workspacePath dropped — see syncPull catch for the rationale.
      extra: kbErr ? { userId } : { userId, errName: err instanceof Error ? err.name : typeof err },
      tags: { reason: kbErr ? kbErr.reason : "unclassified", push_class: kbErr?.pushClass ?? "none" },
      message: "Sync push failed — next session will retry",
    });
  }
}
