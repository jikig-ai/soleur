// #5091 — deterministic safe-commit + PR pipeline for claude-spawn bot crons.
//
// Replaces the prompt-level MANDATORY FINAL STEP shell blocks (destructive
// PR #5026: a blanket add staged 654 structural deletions produced by the
// ephemeral-workspace scaffolding). The prompt is a suggestion to a model;
// persistence is a platform responsibility — it runs HERE, node-level,
// after the eval, where it is deterministic, replay-idempotent, and outside
// the containment hook's jurisdiction.
//
// Contract highlights (see the #5091 plan for the full design):
//   - NON-THROWING: every failure path returns { status: "failed", ... }
//     after mirroring to Sentry. A throw inside the handler's step.run
//     would fail the Inngest run before the heartbeat chain executes,
//     silencing the whole observability surface.
//   - REPLAY-IDEMPOTENT: branch name AND commit dates derive from the
//     handler's memoized runStartedAt, so a retried step re-creates the
//     byte-identical commit SHA; re-push is a no-op and PR-create 422
//     ("already exists") resolves to the existing PR.
//   - SCOPED STAGING: explicit `git add -- <file...>` of allowlist-matched
//     paths only (hr-never-git-add-a-in-user-repo-agents). Structural
//     workspace scaffolding under .claude/ never stages; any OTHER dropped
//     path mirrors to Sentry (cq-silent-fallback-must-mirror-to-sentry) —
//     a silently truncated bot PR that auto-merges green is itself a bug.
//   - DELETION GUARD: more than DEFAULT_MAX_DELETIONS deletions among the
//     allowlist-matched paths aborts the whole persistence step (no branch,
//     no PR) — the #5026 class, bounded structurally.

import { existsSync } from "node:fs";
import { join } from "node:path";
import { promisify } from "node:util";
import type { Octokit } from "@octokit/core";
import { reportSilentFallback } from "@/server/observability";
import { redactToken, REPO_OWNER, REPO_NAME, type HandlerArgs } from "./_cron-shared";

// Module constant, not per-cron config: every wired pipeline shares the same
// threshold until one demonstrably needs an override (then add an optional
// param — a knob with one value is a constant). Issue #5091 suggested 50;
// 10 sits above incidental renames (a worktree rename = 1 deletion entry)
// and far below the 654-file contamination class. Divergence recorded in
// the plan + PR body.
export const DEFAULT_MAX_DELETIONS = 10;

// Workspace scaffolding the substrate writes on EVERY run (settings overlay,
// cron-allow.txt). These paths are expected-dirty by construction and never
// stage — excluding them is silent by design; everything else dropped by the
// allowlist filter is mirrored to Sentry. Prefix semantics (trailing slash)
// per the #5091 plan review: a literal-entry exclusion would let deletions
// UNDER a scaffolded directory flow into the deletion guard on every run.
export const STRUCTURAL_EXCLUSION_PREFIXES: readonly string[] = [".claude/"];

const BOT_NAME = "github-actions[bot]";
const BOT_EMAIL = "41898282+github-actions[bot]@users.noreply.github.com";

export interface SafeCommitConfig {
  spawnCwd: string;
  /** Installation token — used only to build an Octokit when none is injected. */
  installationToken: string;
  cronName: string;
  commitMessage: string;
  prTitle: string;
  prBody: string;
  /** Repo-root-relative path prefixes this cron is allowed to persist. */
  allowedPaths: readonly string[];
  /** The handler's MEMOIZED run-start ISO timestamp (never a fresh Date). */
  runStartedAt: string;
  /** Label of the cron's scheduled output issue — guard/fail visibility comment target. */
  scheduledIssueLabel: string;
  /** Injectable for tests; production callers omit and the token is used. */
  octokit?: Octokit;
  logger?: HandlerArgs["logger"];
}

export type SafeCommitResult =
  | {
      status: "committed";
      prNumber: number;
      branch: string;
      fileCount: number;
      deletionCount: number;
    }
  | { status: "no-changes" }
  | {
      status: "failed";
      stage:
        | "workspace-lost"
        | "status"
        | "deletion-guard"
        | "add"
        | "commit"
        | "push"
        | "pr-create"
        | "auto-merge";
      message: string;
    };

interface StatusEntry {
  /** Staged (X) and worktree (Y) status columns. */
  x: string;
  y: string;
  /** Destination path (rename/copy entries report dest first under -z). */
  path: string;
}

/**
 * Parse `git status --porcelain=v1 -z` output. Each entry is
 * `XY <path>\0` — EXCEPT `R`/`C` entries which carry a second
 * NUL-terminated field: `XY <dest>\0<orig>\0` (destination FIRST).
 * Consuming both fields is load-bearing: a one-field parser misaligns
 * every subsequent entry (precedent: 2026-04-27 autoloop PR-quality fence).
 */
export function parsePorcelainZ(raw: string): StatusEntry[] {
  const fields = raw.split("\0");
  const entries: StatusEntry[] = [];
  let i = 0;
  while (i < fields.length) {
    const field = fields[i];
    if (!field) {
      i++;
      continue;
    }
    const x = field[0] ?? " ";
    const y = field[1] ?? " ";
    const path = field.slice(3);
    entries.push({ x, y, path });
    // Rename/copy in either column → skip the trailing <orig> field.
    if (x === "R" || x === "C" || y === "R" || y === "C") {
      i += 2;
    } else {
      i += 1;
    }
  }
  return entries;
}

/** `ci/<cronName minus cron-> -<YYYY-MM-DD-HHMMSS>` — refname-safe (no `:`/`.`). */
export function deriveBranchName(cronName: string, runStartedAt: string): string {
  const prefix = cronName.replace(/^cron-/, "");
  // "2026-06-10T11:00:03.123Z" → "2026-06-10-110003"
  const ts = runStartedAt.slice(0, 19).replace("T", "-").replace(/:/g, "");
  return `ci/${prefix}-${ts}`;
}

async function runGit(
  spawnCwd: string,
  args: string[],
  extraEnv?: Record<string, string>,
): Promise<{ ok: boolean; stdout: string; stderr: string }> {
  // Lazy import: many sibling cron TEST files vi.mock("node:child_process")
  // with spawn-only factories; a top-level promisify(execFile) would crash
  // at module load in every file that imports a migrated cron. Importing at
  // call time keeps this module loadable under those mocks (runGit itself is
  // only exercised by cron-safe-commit.test.ts, which does not mock it).
  const { execFile } = await import("node:child_process");
  const execFileP = promisify(execFile);
  try {
    const { stdout, stderr } = await execFileP("git", args, {
      cwd: spawnCwd,
      env: { ...process.env, ...extraEnv },
      maxBuffer: 32 * 1024 * 1024,
    });
    return { ok: true, stdout, stderr };
  } catch (err) {
    const e = err as Error & { stdout?: string; stderr?: string };
    return { ok: false, stdout: e.stdout ?? "", stderr: e.stderr ?? e.message };
  }
}

// GraphQL auto-merge enable, extracted from cron-bug-fixer (PR #5091) so both
// callers share one "already enabled" tolerance. Returns the reason string on
// hard failure; null on success/tolerated outcomes. The "clean status" case
// (no pending required checks — possible for path-filtered workflows on
// knowledge-base-only diffs, where arming auto-merge would otherwise hang
// forever) is signalled distinctly so callers can fall back to direct merge.
export async function enableAutoMergeSquash(
  octokit: Pick<Octokit, "graphql">,
  pullRequestId: string,
): Promise<{ enabled: boolean; cleanStatus: boolean; reason?: string }> {
  const mutation = `
    mutation EnableAutoMerge($pullRequestId: ID!) {
      enablePullRequestAutoMerge(input: {
        pullRequestId: $pullRequestId,
        mergeMethod: SQUASH
      }) {
        pullRequest { autoMergeRequest { enabledAt } }
      }
    }
  `;
  try {
    await octokit.graphql(mutation, { pullRequestId });
    return { enabled: true, cleanStatus: false };
  } catch (err) {
    const message = ((err as Error).message ?? "").toLowerCase();
    if (
      message.includes("auto merge is already enabled") ||
      message.includes("auto-merge is already enabled") ||
      message.includes("already enabled auto merge") ||
      message.includes("already enabled auto-merge")
    ) {
      return { enabled: true, cleanStatus: false };
    }
    if (message.includes("clean status")) {
      return { enabled: false, cleanStatus: true };
    }
    return { enabled: false, cleanStatus: false, reason: (err as Error).message };
  }
}

async function resolveOctokit(config: SafeCommitConfig): Promise<Octokit> {
  if (config.octokit) return config.octokit;
  const { Octokit: OctokitCtor } = await import("@octokit/core");
  return new OctokitCtor({ auth: config.installationToken }) as unknown as Octokit;
}

/**
 * Best-effort operator visibility: a guard abort or persistence failure with
 * a green output issue is invisible to a non-technical operator ("the issue
 * says fixes were applied but there is no PR anywhere"). Comment on the run's
 * scheduled issue; a comment failure mirrors to Sentry and never escalates.
 */
async function commentOnScheduledIssue(
  octokit: Octokit,
  config: SafeCommitConfig,
  body: string,
): Promise<void> {
  try {
    const issues = (await octokit.request("GET /repos/{owner}/{repo}/issues", {
      owner: REPO_OWNER,
      repo: REPO_NAME,
      labels: config.scheduledIssueLabel,
      state: "open",
      sort: "created",
      direction: "desc",
      per_page: 1,
      headers: { "X-GitHub-Api-Version": "2022-11-28" },
    })) as { data: Array<{ number: number }> };
    const issue = issues.data[0];
    if (!issue) return;
    await octokit.request(
      "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
      {
        owner: REPO_OWNER,
        repo: REPO_NAME,
        issue_number: issue.number,
        body,
      },
    );
  } catch (err) {
    reportSilentFallback(err, {
      feature: config.cronName,
      op: "safe-commit-issue-comment-failed",
      message: "Could not post safe-commit visibility comment on scheduled issue",
      extra: { fn: config.cronName, label: config.scheduledIssueLabel },
    });
  }
}

function failure(
  config: SafeCommitConfig,
  stage: Extract<SafeCommitResult, { status: "failed" }>["stage"],
  message: string,
  extra?: Record<string, unknown>,
): SafeCommitResult {
  const redacted = redactToken(message, config.installationToken);
  reportSilentFallback(new Error(`safeCommitAndPr ${stage}: ${redacted}`), {
    feature: config.cronName,
    op: stage === "deletion-guard" ? "safe-commit-deletion-guard" : "safe-commit-failed",
    message: `safeCommitAndPr failed at stage ${stage}`,
    extra: { fn: config.cronName, stage, ...extra },
  });
  return { status: "failed", stage, message: redacted };
}

export async function safeCommitAndPr(
  config: SafeCommitConfig,
): Promise<SafeCommitResult> {
  const { spawnCwd, cronName, allowedPaths, runStartedAt, logger } = config;
  const branch = deriveBranchName(cronName, runStartedAt);
  const gitIdentityEnv: Record<string, string> = {
    GIT_AUTHOR_NAME: BOT_NAME,
    GIT_AUTHOR_EMAIL: BOT_EMAIL,
    GIT_COMMITTER_NAME: BOT_NAME,
    GIT_COMMITTER_EMAIL: BOT_EMAIL,
    // Deterministic dates ⇒ replay-stable commit SHA ⇒ idempotent push
    // across Inngest retries (the load-bearing property; identity-via-env
    // also sidesteps `git config`, which the containment hook denies for
    // the SPAWNED claude — though this node-level path is outside the
    // hook's jurisdiction anyway).
    GIT_AUTHOR_DATE: runStartedAt,
    GIT_COMMITTER_DATE: runStartedAt,
  };

  try {
    // -- 1. Workspace-lost check (replay after container restart: the
    //       memoized setup-workspace step points at a deleted directory).
    //       Distinct from no-changes — this run's work is GONE.
    if (!existsSync(join(spawnCwd, ".git"))) {
      return failure(config, "workspace-lost", `spawnCwd missing or not a git repo: ${spawnCwd}`);
    }

    // -- 2. Replay-resume: a prior attempt already created the deterministic
    //       commit (crash between commit and push/PR). HEAD sits on the
    //       target branch — skip scan+commit, resume at push.
    const headRef = await runGit(spawnCwd, ["rev-parse", "--abbrev-ref", "HEAD"]);
    const resuming = headRef.ok && headRef.stdout.trim() === branch;

    let fileCount = 0;
    let deletionCount = 0;

    if (!resuming) {
      // -- 3. Scan. --untracked-files=all is load-bearing: without it, new
      //       files inside an untracked directory collapse to one `dir/`
      //       entry, defeating per-file filtering and the deletion count.
      const status = await runGit(spawnCwd, [
        "status",
        "--porcelain=v1",
        "-z",
        "--untracked-files=all",
      ]);
      if (!status.ok) {
        return failure(config, "status", status.stderr);
      }
      const entries = parsePorcelainZ(status.stdout);

      // -- 4. Structural exclusion (silent by design — recurs every run).
      const nonStructural = entries.filter(
        (e) => !STRUCTURAL_EXCLUSION_PREFIXES.some((p) => e.path.startsWith(p)),
      );

      // -- 5. Allowlist filter; non-structural drops are LOUD.
      const matched = nonStructural.filter((e) =>
        allowedPaths.some((p) => e.path.startsWith(p)),
      );
      const dropped = nonStructural.filter(
        (e) => !allowedPaths.some((p) => e.path.startsWith(p)),
      );
      if (dropped.length > 0) {
        reportSilentFallback(
          new Error(
            `safeCommitAndPr dropped ${dropped.length} changed path(s) outside allowedPaths for ${cronName}`,
          ),
          {
            feature: cronName,
            op: "safe-commit-paths-dropped",
            message: "Bot run changed paths outside the cron's allowlist — committed subset may be incomplete",
            extra: {
              fn: cronName,
              droppedCount: dropped.length,
              sample: dropped.slice(0, 10).map((e) => e.path),
              allowedPaths,
            },
          },
        );
      }

      // -- 6. Deletion guard (the #5026 class, bounded structurally).
      deletionCount = matched.filter((e) => e.x === "D" || e.y === "D").length;
      if (deletionCount > DEFAULT_MAX_DELETIONS) {
        const sample = matched
          .filter((e) => e.x === "D" || e.y === "D")
          .slice(0, 10)
          .map((e) => e.path);
        const result = failure(
          config,
          "deletion-guard",
          `${deletionCount} staged-or-worktree deletions inside allowedPaths exceed max ${DEFAULT_MAX_DELETIONS}`,
          { deletionCount, max: DEFAULT_MAX_DELETIONS, sample },
        );
        const octokit = await resolveOctokit(config);
        await commentOnScheduledIssue(
          octokit,
          config,
          `PR withheld: deletion guard (${deletionCount} deletions > max ${DEFAULT_MAX_DELETIONS} in \`${branch}\`). ` +
            `Sample: ${sample.map((p) => `\`${p}\``).join(", ")}. ` +
            `See knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md.`,
        );
        return result;
      }

      // -- 7. No changes. The symlink-shadow class (plugin-docs writes that
      //       land outside the clone) surfaces here — keep it greppable.
      if (matched.length === 0) {
        logger?.info(
          { fn: cronName, op: "safe-commit-no-changes" },
          `safeCommitAndPr: no committable changes inside allowedPaths for ${cronName}`,
        );
        return { status: "no-changes" };
      }
      fileCount = matched.length;

      // -- 8. Branch + scoped add + deterministic commit.
      const checkout = await runGit(spawnCwd, ["checkout", "-B", branch]);
      if (!checkout.ok) {
        return failure(config, "commit", `checkout -B ${branch}: ${checkout.stderr}`);
      }
      const add = await runGit(spawnCwd, [
        "add",
        "--",
        ...matched.map((e) => e.path),
      ]);
      if (!add.ok) {
        return failure(config, "add", add.stderr);
      }
      const commit = await runGit(
        spawnCwd,
        ["commit", "-m", config.commitMessage],
        gitIdentityEnv,
      );
      if (!commit.ok) {
        return failure(config, "commit", commit.stderr);
      }
    }

    // -- 9. Push (idempotent: deterministic SHA ⇒ re-push is up-to-date).
    const push = await runGit(spawnCwd, ["push", "-u", "origin", branch]);
    if (!push.ok) {
      const result = failure(
        config,
        "push",
        `${push.stderr} (a 401/403 here can mean the memoized installation token expired across a delayed replay)`,
      );
      const octokit = await resolveOctokit(config);
      await commentOnScheduledIssue(
        octokit,
        config,
        `PR withheld: push failed for \`${branch}\`. See Sentry op safe-commit-failed (fn=${cronName}).`,
      );
      return result;
    }

    // -- 10. PR create; 422 "already exists" is replay success.
    const octokit = await resolveOctokit(config);
    let prNumber: number;
    let prNodeId: string;
    try {
      const created = (await octokit.request("POST /repos/{owner}/{repo}/pulls", {
        owner: REPO_OWNER,
        repo: REPO_NAME,
        title: config.prTitle,
        body: config.prBody,
        head: branch,
        base: "main",
        headers: { "X-GitHub-Api-Version": "2022-11-28" },
      })) as { data: { number: number; node_id: string } };
      prNumber = created.data.number;
      prNodeId = created.data.node_id;
    } catch (err) {
      const e = err as Error & { status?: number };
      const alreadyExists =
        e.status === 422 && /pull request already exists/i.test(e.message ?? "");
      if (!alreadyExists) {
        const result = failure(config, "pr-create", e.message ?? String(err));
        await commentOnScheduledIssue(
          octokit,
          config,
          `PR withheld: PR creation failed for \`${branch}\`. See Sentry op safe-commit-failed (fn=${cronName}).`,
        );
        return result;
      }
      const existing = (await octokit.request("GET /repos/{owner}/{repo}/pulls", {
        owner: REPO_OWNER,
        repo: REPO_NAME,
        head: `${REPO_OWNER}:${branch}`,
        state: "open",
        per_page: 1,
        headers: { "X-GitHub-Api-Version": "2022-11-28" },
      })) as { data: Array<{ number: number; node_id: string }> };
      const pr = existing.data[0];
      if (!pr) {
        return failure(
          config,
          "pr-create",
          `PR-create returned 422 already-exists but no open PR found for head ${branch}`,
        );
      }
      prNumber = pr.number;
      prNodeId = pr.node_id;
    }

    // -- 11. Auto-merge (squash); "clean status" → direct merge fallback
    //        (repo has delete_branch_on_merge=true, so branch cleanup is
    //        handled by GitHub in both paths).
    const autoMerge = await enableAutoMergeSquash(octokit, prNodeId);
    if (!autoMerge.enabled) {
      if (autoMerge.cleanStatus) {
        try {
          await octokit.request("PUT /repos/{owner}/{repo}/pulls/{pull_number}/merge", {
            owner: REPO_OWNER,
            repo: REPO_NAME,
            pull_number: prNumber,
            merge_method: "squash",
            headers: { "X-GitHub-Api-Version": "2022-11-28" },
          });
        } catch (err) {
          return failure(config, "auto-merge", (err as Error).message, { prNumber });
        }
      } else {
        return failure(
          config,
          "auto-merge",
          autoMerge.reason ?? "enablePullRequestAutoMerge failed",
          { prNumber },
        );
      }
    }

    logger?.info(
      { fn: cronName, op: "safe-commit-pr", prNumber, branch, fileCount },
      `safeCommitAndPr: opened PR #${prNumber} from ${branch}`,
    );
    return { status: "committed", prNumber, branch, fileCount, deletionCount };
  } catch (err) {
    // Belt-and-suspenders: the contract is non-throwing; anything that
    // escapes the per-stage handling above still resolves to a failure
    // result so the handler's heartbeat chain always runs.
    return failure(config, "status", (err as Error).message ?? String(err));
  }
}
