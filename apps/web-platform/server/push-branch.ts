/**
 * Branch push handler for platform MCP tools (#1929).
 *
 * Pushes commits from the agent workspace to a feature branch.
 * Uses the credential helper pattern from workspace.ts for auth.
 *
 * Safety guards:
 * - Protected branch rejection (main, master, stored default)
 * - Force-push blocking
 * - Credential helper cleanup in finally block
 * - Git author set to Soleur Agent identity (legacy path only)
 * - Hardened (cc) path: the approved commit is pushed from a server-created isolated GIT_DIR (ADR-309 flip item 9b)
 */

import { execFileSync } from "child_process";

import { COMMIT_SHA_RE } from "./approval/canonical";
import { validateBranchFormat } from "./branch-validation";
import { gitWithInstallationAuth } from "./git-auth";
import { HARDENED_GIT_ARGS, buildIsolatedGitEnv } from "./git-hardened-env";
import { IsolatedPushDirRefusal, createIsolatedPushDir, type IsolatedPushDirHandle } from "./git-isolated-push-dir";
import { createChildLogger } from "./logger";
import { reportSilentFallback } from "./observability";

const log = createChildLogger("push-branch");

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

export const PROTECTED_BRANCHES = ["main", "master"] as const;
const AGENT_AUTHOR_NAME = "Soleur Agent";
const AGENT_AUTHOR_EMAIL = "agent@soleur.ai";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface PushBranchOptions {
  installationId: number;
  owner: string;
  repo: string;
  workspacePath: string;
  branch: string;
  force: boolean;
  defaultBranch?: string;
  /**
   * The exact commit the workspace Owner approved (#4672 execution grant). When set, that commit (not whatever HEAD is
   * at execution time) is pushed: a commit sha content-addresses its whole history, so a HEAD that moved during the
   * approval wait cannot change what lands on the remote. Absent = legacy `HEAD` (approval flow never ran).
   */
  commitSha?: string;
  /**
   * Opt-in hardened form (#11636, ADR-309 9b, the cc push only): the approved commit is pushed from a server-created isolated
   * bare GIT_DIR (`createIsolatedPushDir`) that reads the workspace object store only as an alternate, so no workspace
   * config, hook, ref or `commondir` file is read by the git child that carries the installation token. Requires `commitSha`
   * (exactly 40 lowercase hex). Every git child runs with the shared hardening args and an allowlisted environment (no
   * server secrets). A workspace whose object store redirects (a symlinked `.git`/`objects` entry, `alternates`) is
   * refused, and the directory is removed in a `finally`. Unset = the legacy path, byte-identical.
   */
  hardened?: true;
}

/**
 * The commit the Owner approved cannot be pushed (not a full sha, or not in the workspace repository). Typed so the tool
 * handler reports it as an `approval-grant-refused` (reason `commit_unavailable`) and returns the terminal refusal.
 */
export class ApprovedCommitUnavailableError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "ApprovedCommitUnavailableError";
  }
}

export interface PushResult {
  branch: string;
  pushed: boolean;
}

// ---------------------------------------------------------------------------
// Hardened (isolated GIT_DIR) helpers
// ---------------------------------------------------------------------------

/** Upper bound of each synchronous git child on the hardened path: a stalled child costs at most this long, not indefinitely. */
const HARDENED_SYNC_GIT_TIMEOUT_MS = 10_000;

/** Exactly 40 lowercase hex: the hardened push is sha1-only (a 64-hex id is refused here, and the gate reader refuses to show one). */
const HARDENED_COMMIT_SHA_RE = /^[0-9a-f]{40}$/;

const PUSH_FEATURE = "cc-push";

/** The ONE place a hardened-push refusal is reported: a closed `reason`, never the Error (#8629 class), no path, no sha. */
function reportIsolatedRefusal(reason: string): void {
  log.warn({ reason }, "Hardened push refused before the push ran");
  reportSilentFallback(null, { feature: PUSH_FEATURE, op: "isolated-dir-refused", extra: { reason } });
}

type PushFailureClass = "unpack" | "auth" | "non_fast_forward" | "timeout" | "other";

/** A closed enum derived from the child's failure; stderr is only pattern-matched here and never emitted. */
function classifyPushFailure(err: unknown, stderr: string): PushFailureClass {
  const e = err as { killed?: boolean; signal?: string; code?: unknown } | null;
  if (e?.killed === true || e?.signal === "SIGTERM" || e?.code === "ETIMEDOUT" || /timeout exceeded|timed out/i.test(stderr)) {
    return "timeout";
  }
  if (/unpack|unpacker error|eof before pack header/i.test(stderr)) return "unpack";
  if (/Authentication failed|could not read (Username|Password)|terminal prompts disabled|HTTP 40[13]|Invalid username or token/i.test(stderr)) {
    return "auth";
  }
  if (/non-fast-forward|fetch first|\[rejected\]/i.test(stderr)) return "non_fast_forward";
  return "other";
}

/** A failing `dispose()` never changes the push result: it is reported by class name only (no path). */
function disposeIsolated(isolated: IsolatedPushDirHandle | undefined): void {
  if (!isolated) return;
  try {
    isolated.dispose();
  } catch (err) {
    const cls = (err as Error | undefined)?.name ?? "unknown";
    log.warn({ class: cls }, "Isolated push directory could not be removed");
    reportSilentFallback(null, { feature: PUSH_FEATURE, op: "isolated-dir-dispose-failed", extra: { class: cls } });
  }
}

/**
 * Hardened path only: validate the approved sha, create the isolated directory and prove the commit exists through it (the
 * alternate). Refusals carry static text (no path echo). The four workspace-tamper reasons are typed so the tool handler
 * reports them as `commit_unavailable`; an infrastructure failure (`setup_failed`, `env_path_unsafe`: the environment is the
 * server's, not the agent's) is a plain static error that flows through the tool-error path. On ANY throw the directory is
 * already removed. Not an atomic guarantee: a sandbox process that outlives the tool call can swap the workspace object store
 * after the check (ADR-309 9b residual, object bytes only).
 */
function prepareIsolatedPush(workspacePath: string, commitSha: string | undefined): IsolatedPushDirHandle {
  if (commitSha === undefined || !HARDENED_COMMIT_SHA_RE.test(commitSha)) {
    reportIsolatedRefusal("sha_invalid");
    throw new ApprovedCommitUnavailableError("Approved commit is not a valid full commit sha");
  }
  let isolated: IsolatedPushDirHandle;
  try {
    isolated = createIsolatedPushDir(workspacePath);
  } catch (err) {
    const reason = err instanceof IsolatedPushDirRefusal ? err.reason : "setup_failed";
    reportIsolatedRefusal(reason);
    if (reason === "setup_failed" || reason === "env_path_unsafe") throw new Error("Push could not be prepared");
    throw new ApprovedCommitUnavailableError("Workspace git directory is not a plain repository directory");
  }
  const gitCwd = isolated.gitDir;
  try {
    execFileSync("git", [...HARDENED_GIT_ARGS, "cat-file", "-e", `${commitSha}^{commit}`], {
      cwd: gitCwd,
      stdio: "pipe",
      env: buildIsolatedGitEnv(isolated),
      timeout: HARDENED_SYNC_GIT_TIMEOUT_MS,
    });
  } catch {
    disposeIsolated(isolated);
    reportIsolatedRefusal("commit_absent");
    throw new ApprovedCommitUnavailableError("Approved commit is not present in the workspace repository");
  }
  return isolated;
}

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

/**
 * Reject pushes to protected branches.
 * Throws if the branch matches main, master, or the stored default branch.
 */
export function rejectProtectedBranch(
  branch: string,
  defaultBranch?: string,
): void {
  const protectedSet = new Set<string>([...PROTECTED_BRANCHES]);
  if (defaultBranch) protectedSet.add(defaultBranch);

  if (protectedSet.has(branch)) {
    throw new Error(
      `Push to protected branch '${branch}' is not allowed from cloud agents. ` +
      "Push to a feature branch instead.",
    );
  }
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Push the current workspace HEAD (or, with `commitSha`, the approved commit) to a feature branch on the remote.
 *
 * The gating (review gate) is handled by canUseTool — this function
 * only executes after the founder has approved.
 */
export async function pushBranch(options: PushBranchOptions): Promise<PushResult> {
  const { installationId, owner, repo, workspacePath, branch, force, defaultBranch, commitSha, hardened } = options;

  // 1. Reject force-push unconditionally
  if (force) {
    throw new Error(
      "Force-push is not allowed from cloud agents. " +
      "Use a regular push or create a new branch.",
    );
  }

  // 2. Validate branch name format (all 10 git ref format rules)
  validateBranchFormat(branch);

  // 3. Reject pushes to protected branches (main, master, default)
  rejectProtectedBranch(branch, defaultBranch);

  // 3a. Hardened: the push runs from a server-created isolated GIT_DIR and the approved commit must exist in it (through the
  // workspace object store, as an alternate). Nothing below reads the workspace `.git/config`, hooks, refs or `commondir`.
  let isolated: IsolatedPushDirHandle | undefined;
  try {
    if (hardened) {
      isolated = prepareIsolatedPush(workspacePath, commitSha);
    } else {
      // 3b. A pinned commit must be a full sha that exists in the workspace repository.
      if (commitSha !== undefined) {
        if (!COMMIT_SHA_RE.test(commitSha)) {
          throw new ApprovedCommitUnavailableError("Approved commit is not a valid full commit sha");
        }
        try {
          execFileSync("git", ["cat-file", "-e", `${commitSha}^{commit}`], {
            cwd: workspacePath,
            stdio: "pipe",
          });
        } catch {
          throw new ApprovedCommitUnavailableError("Approved commit is not present in the workspace repository");
        }
      }

      // 4. Set git author to Soleur Agent identity
      try {
        execFileSync("git", ["config", "user.name", AGENT_AUTHOR_NAME], {
          cwd: workspacePath,
          stdio: "pipe",
        });
        execFileSync("git", ["config", "user.email", AGENT_AUTHOR_EMAIL], {
          cwd: workspacePath,
          stdio: "pipe",
        });
      } catch (err) {
        log.warn({ err }, "Failed to set git author — push may use existing config");
      }
    }

    // 5. Push to remote via authenticated git invocation
    try {
      const repoUrl = `https://github.com/${owner}/${repo}.git`;
      await gitWithInstallationAuth(
        ["push", repoUrl, `${commitSha ?? "HEAD"}:refs/heads/${branch}`],
        installationId,
        { timeout: 120_000, ...(isolated ? { hardened: isolated } : { cwd: workspacePath }) },
      );

      log.info({ branch, owner, repo }, "Branch pushed successfully");

      return { branch, pushed: true };
    } catch (err) {
      const rawStderr = (err as { stderr?: Buffer })?.stderr?.toString() ?? "";
      // Strip internal paths to avoid leaking server filesystem layout
      const stderr = rawStderr.replace(/\/[^\s:]+/g, "<path>");
      if (isolated) {
        // The approval was consumed before this handler ran: classify (closed enum) for diagnosis, never the Error or stderr.
        const failureClass = classifyPushFailure(err, rawStderr);
        reportSilentFallback(null, { feature: PUSH_FEATURE, op: "push-failed-after-consume", extra: { class: failureClass } });
        // A timeout or killed child can fail the call after the remote already accepted the ref.
        if (failureClass === "timeout") throw new Error("Git push failed: the push timed out and MAY have landed on the remote");
      }
      throw new Error(`Git push failed: ${stderr || (err as Error).message}`);
    }
  } finally {
    disposeIsolated(isolated);
  }
}
