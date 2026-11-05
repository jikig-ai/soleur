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
 * - Git author set to Soleur Agent identity
 */

import { execFileSync } from "child_process";
import { lstatSync, type Stats } from "fs";
import { join } from "path";

import { COMMIT_SHA_RE } from "./approval/canonical";
import { validateBranchFormat } from "./branch-validation";
import { gitWithInstallationAuth } from "./git-auth";
import { HARDENED_GIT_ARGS, buildHardenedGitEnv } from "./git-hardened-env";
import { createChildLogger } from "./logger";

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
   * Opt-in hardened form (#11636, the cc push only): refuses unless `<workspace>/.git` is a real directory with no symlinked
   * or redirecting entries (alternates, commondir, ...),
   * applies the shared git hardening args to the push, the `cat-file` and the `git config` calls, and runs every git child
   * with an allowlisted environment (no server secrets) and a pinned `GIT_DIR`. Unset = the legacy path, byte-identical.
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
// Validation
// ---------------------------------------------------------------------------

/**
 * `.git` entries git reads or writes THROUGH: a symlink at any of them is refused, not followed. Mirrors
 * `GIT_DIR_NO_SYMLINK_ENTRIES` in `inngest/functions/_cron-safe-commit.ts` (#7122 P1-B), which is module-private and sits in a
 * heavy graph (observability, cron liveness) this module must not import; keep the two lists in step.
 */
const GIT_DIR_NO_SYMLINK_ENTRIES: readonly string[] = [
  "config",
  "info",
  "hooks",
  "objects",
  "objects/info",
  "refs",
  "refs/replace",
  "HEAD",
  "index",
  "packed-refs",
  "shallow",
];

/**
 * Files whose mere existence redirects or extends where git reads objects, refs or config from: refused when present. Mirrors the
 * redirecting subset of `GIT_DIR_REDIRECT_FILES` in `_cron-safe-commit.ts`; that list also names `info/exclude`,
 * `info/attributes` and `info/sparse-checkout`, which the sanitizer deletes and which exist in a normal repository, so they are
 * not refusals here (the hardened args already neutralise attributes and hooks).
 */
const GIT_DIR_REDIRECT_FILES: readonly string[] = [
  "commondir",
  "config.worktree",
  "objects/info/alternates",
  "objects/info/http-alternates",
  "info/grafts",
];

/** Upper bound of each synchronous git child on the hardened path: a FIFO planted in `.git` must not freeze the server. */
const HARDENED_SYNC_GIT_TIMEOUT_MS = 10_000;

/**
 * Hardened path only: `<workspace>/.git` must be a REAL directory (not a `gitdir:` file, not a symlink), none of the entries git
 * reads or writes through may be a symlink, and none of the files that redirect where git reads objects, refs or config from may
 * exist. The agent can write the workspace, so otherwise it could point the server-side git at another repository. The
 * environment also pins `GIT_COMMON_DIR` and `GIT_OBJECT_DIRECTORY`. Static refusal text (no path echo), typed so the tool handler
 * reports it as `commit_unavailable`. This is a pre-flight, not an atomic guarantee: a sandbox process that outlives the tool call
 * can change the workspace after the check (see ADR-309 flip item 9a/9b; the structural closure is an isolated GIT_DIR).
 */
function assertPlainGitDir(workspacePath: string): void {
  const refuse = (): never => {
    throw new ApprovedCommitUnavailableError("Workspace git directory is not a plain repository directory");
  };
  const gitDir = join(workspacePath, ".git");
  let st: Stats;
  try {
    st = lstatSync(gitDir);
  } catch {
    return refuse();
  }
  if (st.isSymbolicLink() || !st.isDirectory()) refuse();
  for (const entry of GIT_DIR_NO_SYMLINK_ENTRIES) {
    try {
      if (lstatSync(join(gitDir, entry)).isSymbolicLink()) refuse();
    } catch (err) {
      if (err instanceof ApprovedCommitUnavailableError) throw err;
      if ((err as NodeJS.ErrnoException)?.code !== "ENOENT") refuse();
    }
  }
  for (const rel of GIT_DIR_REDIRECT_FILES) {
    try {
      lstatSync(join(gitDir, rel));
    } catch (err) {
      if ((err as NodeJS.ErrnoException)?.code === "ENOENT") continue;
      refuse();
    }
    refuse();
  }
}

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

  // 3a. Hardened: the repository the server-side git will operate on must be the plain directory it appears to be.
  if (hardened) assertPlainGitDir(workspacePath);
  const gitPrefix: string[] = hardened ? [...HARDENED_GIT_ARGS] : [];
  const gitEnv = hardened ? { env: buildHardenedGitEnv(workspacePath), timeout: HARDENED_SYNC_GIT_TIMEOUT_MS } : {};

  // 3b. A pinned commit must be a full sha that exists in the workspace repository.
  if (commitSha !== undefined) {
    if (!COMMIT_SHA_RE.test(commitSha)) {
      throw new ApprovedCommitUnavailableError("Approved commit is not a valid full commit sha");
    }
    try {
      execFileSync("git", [...gitPrefix, "cat-file", "-e", `${commitSha}^{commit}`], {
        cwd: workspacePath,
        stdio: "pipe",
        ...gitEnv,
      });
    } catch {
      throw new ApprovedCommitUnavailableError("Approved commit is not present in the workspace repository");
    }
  }

  // 4. Set git author to Soleur Agent identity
  try {
    execFileSync("git", [...gitPrefix, "config", "user.name", AGENT_AUTHOR_NAME], {
      cwd: workspacePath,
      stdio: "pipe",
      ...gitEnv,
    });
    execFileSync("git", [...gitPrefix, "config", "user.email", AGENT_AUTHOR_EMAIL], {
      cwd: workspacePath,
      stdio: "pipe",
      ...gitEnv,
    });
  } catch (err) {
    log.warn({ err }, "Failed to set git author — push may use existing config");
  }

  // 5. Push to remote via authenticated git invocation
  try {
    const repoUrl = `https://github.com/${owner}/${repo}.git`;
    await gitWithInstallationAuth(
      ["push", repoUrl, `${commitSha ?? "HEAD"}:refs/heads/${branch}`],
      installationId,
      { cwd: workspacePath, timeout: 120_000, ...(hardened ? { hardened: true as const } : {}) },
    );

    log.info({ branch, owner, repo }, "Branch pushed successfully");

    return { branch, pushed: true };
  } catch (err) {
    const rawStderr = (err as { stderr?: Buffer })?.stderr?.toString() ?? "";
    // Strip internal paths to avoid leaking server filesystem layout
    const stderr = rawStderr.replace(/\/[^\s:]+/g, "<path>");
    throw new Error(`Git push failed: ${stderr || (err as Error).message}`);
  }
}
