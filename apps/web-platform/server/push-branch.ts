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
import { HEX40 } from "./approval/workspace-head";
import { validateBranchFormat } from "./branch-validation";
import { gitWithInstallationAuth } from "./git-auth";
import { HARDENED_GIT_ARGS, buildIsolatedGitEnv } from "./git-hardened-env";
import {
  IsolatedPushDirRefusal,
  createIsolatedPushDir,
  type IsolatedPushDirHandle,
  type IsolatedPushDirReason,
} from "./git-isolated-push-dir";
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

/** Upper bound of the hardened commit check: a stalled child costs at most this long, not indefinitely. */
const HARDENED_COMMIT_CHECK_TIMEOUT_MS = 10_000;

const PUSH_FEATURE = "cc-push";

/** Static, per-op Sentry messages: a Sentry group is one condition, never the shared `cc-push silent fallback` default. */
const REFUSED_MESSAGE = "cc-push: the hardened push was refused before it ran; nothing was pushed";
const PUSH_FAILED_MESSAGE = "cc-push: the hardened push failed after the Owner's approval was consumed";
const DISPOSE_FAILED_MESSAGE = "cc-push: the isolated push directory could not be removed";

/** Shown to the model for an infrastructure refusal (the server's state, not the workspace): static, no path, no cause. */
const PREPARE_FAILED_TEXT = "Push could not be prepared (server-side setup problem); nothing was pushed";
/** The object store has more entries than the walk cap: infrastructure, with its own static text so the model can say what to do. No path. */
const OBJECT_STORE_TOO_LARGE_TEXT =
  "Push could not be prepared: the workspace repository has too many object entries to push from; run git gc in the workspace; nothing was pushed";
const PUSH_TIMED_OUT_TEXT =
  "Git push failed: the push timed out and the branch MAY HAVE been pushed to the remote. Ask the user to check the remote branch before asking for a new approval.";

/** Every reason a hardened push can be refused before the push ran: the creator's, the sha check's and the commit check's. */
export type IsolatedRefusalReason =
  | IsolatedPushDirReason
  | "sha_invalid"
  | "commit_absent"
  | "commit_check_failed"
  | "commit_check_timeout";

/**
 * The workspace-tamper reasons: the agent (or a bad actor in the workspace) caused the refusal, and the model is told the
 * approved commit is unavailable. An EXPLICIT allowlist: a reason added later is infrastructure (the plain error that does
 * not say "do not retry") until someone argues it belongs here.
 */
const TAMPER_REASONS: ReadonlySet<IsolatedRefusalReason> = new Set<IsolatedRefusalReason>([
  "git_dir_not_plain",
  "object_store_redirect",
  "alternate_path_unsafe",
  "shallow_invalid",
]);

/** The ONE place a hardened-push refusal is reported: a closed `reason` (tag and extra), never the Error (#8629 class), no path, no sha. */
function reportIsolatedRefusal(reason: IsolatedRefusalReason): void {
  reportSilentFallback(null, {
    feature: PUSH_FEATURE,
    op: "isolated-dir-refused",
    message: REFUSED_MESSAGE,
    tags: { reason },
    extra: { reason },
  });
}

type PushFailureClass = "unpack" | "auth" | "non_fast_forward" | "timeout" | "other";

/** The agent-chosen names that must not steer the classifier. */
interface PushFailureNames {
  readonly branch: string;
  readonly slug: string;
}

const escapeRegExp = (s: string): string => s.replace(/[.*+?^${}()|[\]\\/-]/g, "\\$&");

/**
 * Replaces the agent-chosen names with a placeholder that cannot join its neighbours into a class word. The branch is removed only
 * as a whole ref token (optionally spelled `refs/heads/<branch>`), bounded by characters that cannot be part of a ref name, so a
 * one-letter branch never eats letters out of "Authentication"; the `owner/repo` slug contains a slash and is removed as a whole.
 */
function redactAgentNames(text: string, names: PushFailureNames): string {
  let out = text;
  if (names.branch) {
    const token = `(?<![A-Za-z0-9_./-])(?:refs/heads/)?${escapeRegExp(names.branch)}(?![A-Za-z0-9_/-])(?!\\.[A-Za-z0-9])`;
    out = out.replace(new RegExp(token, "g"), " ");
  }
  if (names.slug) out = out.split(names.slug).join(" ");
  return out;
}

/** The git-authored text of a push failure: ref-status lines contribute only their status word and trailing reason. */
function gitAuthoredText(stderr: string, names: PushFailureNames): string {
  const out: string[] = [];
  for (const line of redactAgentNames(stderr, names).split(/\r?\n/)) {
    const status = /^\s*! \[(rejected|remote rejected)\]/.exec(line);
    if (status) {
      // ` ! [remote rejected] <sha> -> <name> (<reason>)`: the name is agent-chosen, the parenthetical at the end is git's or the host's.
      const reason = /\s\(([^()]*)\)\s*$/.exec(line);
      out.push(`${status[1]} ${reason ? reason[1] : ""}`);
    } else if (/^(fatal|error|remote): /.test(line)) {
      out.push(line);
    }
  }
  return out.join("\n");
}

/**
 * A closed enum derived from the child's failure; stderr is only pattern-matched here and never emitted. `timeout` comes from the
 * child's own kill signal or error code, never from text: Node's execFile error `message` is `Command failed: <cmd>\n<stderr>`, so a
 * marker searched in it would be stderr by another route (a real timeout carries none). Agent-chosen names (the branch, the
 * repository) are removed, and ref-status lines contribute only their status word and trailing reason, before matching; text a remote
 * echoes from the pushed content (for example a file name in a `remote:` line) can still influence the class, which is diagnostic only.
 */
function classifyPushFailure(err: unknown, stderr: string, names: PushFailureNames): PushFailureClass {
  const e = err as { killed?: boolean; signal?: string; code?: unknown } | null;
  if (e?.killed === true || e?.signal === "SIGTERM" || e?.code === "ETIMEDOUT") return "timeout";
  const text = gitAuthoredText(stderr, names);
  if (/unpack|unpacker error|eof before pack header/i.test(text)) return "unpack";
  if (
    /Authentication failed|could not read (Username|Password)|terminal prompts disabled|HTTP 40[13]|returned error: 40[13]|Invalid username or token|Permission to .+ denied/i.test(
      text,
    )
  ) {
    return "auth";
  }
  if (/non-fast-forward|fetch first|^rejected\b/im.test(text)) return "non_fast_forward";
  return "other";
}

/** A failing `dispose()` never changes the push result: it is reported by errno code only (no path, no message). */
function disposeIsolated(isolated: IsolatedPushDirHandle | undefined): void {
  if (!isolated) return;
  try {
    isolated.dispose();
  } catch (err) {
    const code = (err as { code?: unknown } | undefined)?.code;
    const cls = typeof code === "string" && /^E[A-Z]+$/.test(code) ? code : "unknown";
    reportSilentFallback(null, {
      feature: PUSH_FEATURE,
      op: "isolated-dir-dispose-failed",
      message: DISPOSE_FAILED_MESSAGE,
      tags: { class: cls },
      extra: { class: cls },
    });
  }
}

type CommitCheck = "present" | "absent" | "timeout" | "failed";

/**
 * `git rev-parse --verify --quiet <sha>^{commit}` in the isolated directory (async: the event loop is never blocked, and a stalled
 * child is killed at the timeout). Exit status 1 is git's documented answer for "not a valid commit here"; any other outcome (a
 * timeout, a spawn failure such as ENOENT or EMFILE, exit 128 for a broken store, a synchronous throw) says nothing about the commit
 * and is not `absent`. (`cat-file -e <sha>^{commit}` is not used: for a missing object it exits 128, the same status as every other
 * fatal error.) `^{commit}` peels an annotated tag object to the commit it points at, so a zero exit alone would accept a tag-object
 * sha; the printed sha must equal the approved one, else the commit is `absent` (the push of a non-commit sha would only be
 * rejected by the remote after the approval is spent). Everything, the import included, runs inside the `try`: the caller has a
 * directory to remove and no handle to remove it with, so this function never rejects.
 */
async function checkCommitPresent(isolated: IsolatedPushDirHandle, commitSha: string): Promise<CommitCheck> {
  try {
    // Imported lazily, like inflight-checkpoint.ts: sibling test files mock `child_process` with factories that lack `execFile`,
    // and a module-level binding of it would crash at load in every file that transitively imports this one.
    const { execFile } = await import("node:child_process");
    return await new Promise<CommitCheck>((resolve) => {
      try {
        execFile(
          "git",
          [...HARDENED_GIT_ARGS, "rev-parse", "--verify", "--quiet", `${commitSha}^{commit}`],
          {
            cwd: isolated.gitDir,
            env: buildIsolatedGitEnv(isolated),
            timeout: HARDENED_COMMIT_CHECK_TIMEOUT_MS,
          },
          (err, stdout) => {
            if (!err) return resolve(String(stdout).trim() === commitSha ? "present" : "absent");
            const e = err as { code?: unknown; killed?: boolean; signal?: string };
            if (e.killed === true || e.signal === "SIGTERM") return resolve("timeout");
            resolve(e.code === 1 ? "absent" : "failed");
          },
        );
      } catch {
        resolve("failed");
      }
    });
  } catch {
    return "failed";
  }
}

/**
 * Hardened path only: validate the approved sha, create the isolated directory and prove the commit exists through it (the
 * alternate). Refusals carry static text (no path echo). The workspace-tamper reasons (`TAMPER_REASONS`) and an absent commit are typed
 * so the tool handler reports them as `commit_unavailable`; every other reason (`setup_failed`, `env_path_unsafe`,
 * `object_store_too_large`, a commit check that timed out or could not run) is a plain static error that flows through the
 * tool-error path. On ANY throw the directory is already removed. Not an atomic guarantee: a sandbox process that outlives the
 * tool call can swap the workspace object store after the check (ADR-309 9b residual, object bytes only).
 */
async function prepareIsolatedPush(workspacePath: string, commitSha: string | undefined): Promise<IsolatedPushDirHandle> {
  if (commitSha === undefined || !HEX40.test(commitSha)) {
    reportIsolatedRefusal("sha_invalid");
    throw new ApprovedCommitUnavailableError("Approved commit is not a valid full commit sha");
  }
  let isolated: IsolatedPushDirHandle;
  try {
    isolated = createIsolatedPushDir(workspacePath);
  } catch (err) {
    const reason: IsolatedRefusalReason = err instanceof IsolatedPushDirRefusal ? err.reason : "setup_failed";
    reportIsolatedRefusal(reason);
    if (TAMPER_REASONS.has(reason)) {
      throw new ApprovedCommitUnavailableError("Workspace git directory is not a plain repository directory");
    }
    throw new Error(reason === "object_store_too_large" ? OBJECT_STORE_TOO_LARGE_TEXT : PREPARE_FAILED_TEXT);
  }
  const check = await checkCommitPresent(isolated, commitSha);
  if (check === "present") return isolated;
  disposeIsolated(isolated);
  if (check === "absent") {
    reportIsolatedRefusal("commit_absent");
    throw new ApprovedCommitUnavailableError("Approved commit is not present in the workspace repository");
  }
  reportIsolatedRefusal(check === "timeout" ? "commit_check_timeout" : "commit_check_failed");
  throw new Error(PREPARE_FAILED_TEXT);
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
      isolated = await prepareIsolatedPush(workspacePath, commitSha);
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
        const failureClass = classifyPushFailure(err, rawStderr, { branch, slug: `${owner}/${repo}` });
        reportSilentFallback(null, {
          feature: PUSH_FEATURE,
          op: "push-failed-after-consume",
          message: PUSH_FAILED_MESSAGE,
          tags: { class: failureClass },
          extra: { class: failureClass },
        });
        // A timeout or killed child can fail the call after the remote already accepted the ref.
        if (failureClass === "timeout") throw new Error(PUSH_TIMED_OUT_TEXT);
      }
      throw new Error(`Git push failed: ${stderr || (err as Error).message}`);
    }
  } finally {
    disposeIsolated(isolated);
  }
}
