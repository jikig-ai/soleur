// #5091 — deterministic safe-commit + PR pipeline for claude-spawn bot crons.
//
// Replaces the prompt-level mandatory-final-step shell blocks (destructive
// PR #5026: a blanket add staged 654 structural deletions produced by the
// ephemeral-workspace scaffolding). The prompt is a suggestion to a model;
// persistence is a platform responsibility — it runs HERE, node-level,
// after the eval, where it is deterministic, replay-tolerant, and outside
// the containment hook's jurisdiction. Each invariant is documented at its
// implementation site below; the #5091 plan carries the full design.

import { existsSync } from "node:fs";
import { join } from "node:path";
import { promisify } from "node:util";
import type { Octokit } from "@octokit/core";
import { emitCronPersistResult } from "@/server/cron-liveness-marker";
import { reportSilentFallback } from "@/server/observability";
import { redactToken, REPO_OWNER, REPO_NAME, type HandlerArgs } from "./_cron-shared";

// 10: above incidental renames (a worktree rename = 1 deletion entry), far
// below the 654-file contamination class. Issue #5091 suggested 50 —
// divergence recorded in the plan + PR body.
export const DEFAULT_MAX_DELETIONS = 10;

// Workspace scaffolding the substrate writes on EVERY run (settings overlay,
// cron-allow.txt). Expected-dirty by construction and never staged —
// excluding them is silent by design; everything else dropped by the
// allowlist filter is mirrored to Sentry. PREFIX semantics (trailing slash
// required): a literal-entry exclusion would let deletions UNDER a scaffolded
// directory flow into the deletion guard on every run (#5091 plan review).
// Workspace scaffolding the substrate itself writes on EVERY run. These are
// excluded BEFORE the allowlist filter so they never reach the loud
// "paths-dropped" report -- that signal exists to catch a bot writing outside
// its allowlist, and a path that appears on every single run would drown it.
// `.soleur-collector-status/` is the #6695 collector-status sidecar, written by
// github-community.sh and read by cron-community-monitor before teardown.
export const STRUCTURAL_EXCLUSION_PREFIXES: readonly string[] = [
  ".claude/",
  ".soleur-collector-status/",
];

// #5111 — the bot-PR-with-synthetic-checks pattern: deterministic data-refresh
// PRs post these check-runs as completed/success so the integration-pinned
// required checks (infra/github/ruleset-ci-required.tf) are satisfied without
// running CI on knowledge-base-only diffs. Consolidated from 5 byte-identical
// per-cron copies (weekly-analytics, compound-promote, content-publisher,
// content-vendor-drift, rule-prune) — verified identical at #5111 deepen time.
export const SYNTHETIC_CHECK_NAMES = [
  "test",
  "dependency-review",
  "e2e",
  "skill-security-scan PR gate",
  "enforce",
  "cla-check",
  "cla-evidence",
] as const;

const BOT_NAME = "github-actions[bot]";
const BOT_EMAIL = "41898282+github-actions[bot]@users.noreply.github.com";

// Sentry-extra / failed.message size bound, mirroring the stderrTail
// convention in _cron-shared (the step return is memoized by Inngest and
// must stay bounded; raw git stderr can reach maxBuffer otherwise).
const MESSAGE_CAP_CHARS = 4000;

export interface SafeCommitConfig {
  spawnCwd: string;
  /** Installation token — used only to build an Octokit when none is injected. */
  installationToken: string;
  cronName: string;
  /** Also the PR title stem: `<commitMessage> <YYYY-MM-DD from runStartedAt>`. */
  commitMessage: string;
  /**
   * Repo-root-relative path prefixes this cron is allowed to persist.
   * Directory entries MUST end with "/" — matching is bare startsWith, so a
   * bare "foo" would also match "foobar.md".
   */
  allowedPaths: readonly string[];
  /** The handler's MEMOIZED run-start ISO timestamp (never a fresh Date). */
  runStartedAt: string;
  /** Label of the cron's scheduled output issue — guard/fail visibility comment target. */
  scheduledIssueLabel: string;
  /** Injectable for tests/callers with an existing client; production
   *  callers may omit and the installation token is used. Structural type
   *  (the two members the helper uses) so injection sites need no cast. */
  octokit?: Pick<Octokit, "request" | "graphql">;
  logger?: HandlerArgs["logger"];
  // -- #5111 option surface (all optional; defaults preserve #5091 behavior) --
  /** Override the derived `ci/<name>-<ts>` branch (compound-promote's
   *  per-cluster `self-healing/auto-<hash>-<date>`). Must be refname-safe;
   *  the helper rejects `:` `.` whitespace at stage "checkout". */
  branchName?: string;
  /** Second `-m` paragraph (compound-promote provenance trailers). */
  commitBody?: string;
  /** Full PR title override (no date appended). Default stays
   *  `${commitMessage} ${YYYY-MM-DD}`. */
  prTitle?: string;
  /** PR body stem override. The dropped-path ⚠️ marker is appended
   *  regardless of override when the scan runs (the loud-truncation
   *  invariant survives overrides; a replay-resume skips the scan and
   *  relies on the original attempt's Sentry warn). */
  prBody?: string;
  prDraft?: boolean;
  /** Labels applied after PR create (best-effort: label failure mirrors to
   *  Sentry, never fails the run — labels are advisory metadata). */
  prLabels?: readonly string[];
  /** Post synthetic check-runs on the head SHA after PR create (the
   *  bot-pr-with-synthetic-checks pattern carried by the 5 legacy crons). */
  syntheticChecks?: { names: readonly string[]; summary: string };
  /** "auto" (default): enablePullRequestAutoMerge + clean-status direct
   *  fallback — #5091 behavior. "direct": PUT …/merge squash immediately
   *  (legacy live pipelines); on failure falls back to arming auto-merge,
   *  then to failure stage "auto-merge" (PR stays open + loud). "none":
   *  create only (compound-promote human-review draft PRs). */
  mergeMode?: "auto" | "direct" | "none";
}

export type SafeCommitResult =
  | {
      status: "committed";
      prNumber: number;
      branch: string;
      /** 0 on a replay-resume (counts are not recomputed for an existing commit). */
      fileCount: number;
      deletionCount: number;
      /**
       * Repo-relative paths that entered the commit, from the allowlist-matched
       * scan. **OPTIONAL, and `undefined` means "NOT DETERMINED" — never
       * "nothing was committed"** (#6714 R21): on the replay-resume branch the
       * scan never runs, so there is nothing to report even though the artifact
       * did land. A caller asserting "my artifact is in here" MUST treat
       * `undefined` as inconclusive and consult `resumed` before turning red.
       *
       * Optional rather than required because the replay-resume branch cannot
       * know a value to supply — it never runs the allowlist scan. (An earlier
       * draft justified this with "~38 consumers construct this arm"; that
       * number is the count of files REFERENCING safeCommitAndPr. Only 12 sites
       * across 7 files construct the committed arm, so the blast-radius claim
       * was ~5x overstated. The decision stands on the replay-resume leg.)
       */
      paths?: string[];
      /**
       * Set only on the replay-resume branch (a prior attempt already created
       * the commit). Its presence is what licenses a liveness check to stay
       * GREEN despite `paths` being undetermined.
       */
      resumed?: true;
    }
  | { status: "no-changes" }
  | {
      status: "failed";
      stage:
        | "workspace-lost"
        | "status"
        | "dirty-index"
        | "deletion-guard"
        | "checkout"
        | "add"
        | "commit"
        | "push"
        | "pr-create"
        | "auto-merge"
        | "unexpected";
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
 * Staged R/C entries cannot reach the commit path in practice (the
 * dirty-index precondition rejects any pre-staged index), so the orig
 * field needs no allowlist treatment here.
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

/** `ci/<cronName minus cron->-<YYYY-MM-DD-HHMMSS>` — refname-safe (no `:`/`.`). */
export function deriveBranchName(cronName: string, runStartedAt: string): string {
  const prefix = cronName.replace(/^cron-/, "");
  // "2026-06-10T11:00:03.123Z" → "2026-06-10-110003"
  const ts = runStartedAt.slice(0, 19).replace("T", "-").replace(/:/g, "");
  return `ci/${prefix}-${ts}`;
}

/** Neutralize markdown-breaking chars in untrusted strings (paths) before
 * interpolating into issue-comment code spans (mirrors formatTailForIssue). */
function safeMd(s: string): string {
  return s.replace(/[`\r\n|]/g, "ʼ");
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
      // Isolate from host/container git config (signing, hooksPath,
      // templates) — fixture determinism in tests AND prod predictability.
      env: {
        ...process.env,
        GIT_CONFIG_GLOBAL: "/dev/null",
        GIT_CONFIG_SYSTEM: "/dev/null",
        GIT_CONFIG_NOSYSTEM: "1",
        ...extraEnv,
      },
      maxBuffer: 32 * 1024 * 1024,
    });
    return { ok: true, stdout, stderr };
  } catch (err) {
    const e = err as Error & { stdout?: string; stderr?: string };
    return { ok: false, stdout: e.stdout ?? "", stderr: e.stderr ?? e.message };
  }
}

// GraphQL auto-merge enable, extracted from cron-bug-fixer (PR #5091) so both
// callers share one "already enabled" tolerance (expected under Inngest
// replay — callers MUST NOT page on it; `alreadyEnabled` lets them log the
// replay distinctly). The "clean status" case (no pending required checks —
// possible for path-filtered workflows on knowledge-base-only diffs, where
// arming auto-merge would otherwise hang forever) is signalled distinctly so
// callers can fall back to direct merge.
export async function enableAutoMergeSquash(
  octokit: Pick<Octokit, "graphql">,
  pullRequestId: string,
): Promise<{
  enabled: boolean;
  alreadyEnabled: boolean;
  cleanStatus: boolean;
  reason?: string;
}> {
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
    return { enabled: true, alreadyEnabled: false, cleanStatus: false };
  } catch (err) {
    const message = ((err as Error).message ?? "").toLowerCase();
    if (
      message.includes("auto merge is already enabled") ||
      message.includes("auto-merge is already enabled") ||
      message.includes("already enabled auto merge") ||
      message.includes("already enabled auto-merge")
    ) {
      return { enabled: true, alreadyEnabled: true, cleanStatus: false };
    }
    if (message.includes("clean status")) {
      return { enabled: false, alreadyEnabled: false, cleanStatus: true };
    }
    return {
      enabled: false,
      alreadyEnabled: false,
      cleanStatus: false,
      reason: (err as Error).message,
    };
  }
}

async function resolveOctokit(
  config: SafeCommitConfig,
): Promise<Pick<Octokit, "request" | "graphql">> {
  if (config.octokit) return config.octokit;
  const { Octokit: OctokitCtor } = await import("@octokit/core");
  return new OctokitCtor({ auth: config.installationToken }) as unknown as Octokit;
}

/**
 * Best-effort operator visibility: a guard abort or persistence failure with
 * a green output issue is invisible to a non-technical operator ("the issue
 * says fixes were applied but there is no PR anywhere"). Comments on the
 * MOST RECENT open issue carrying the cron's label — if the run died before
 * creating its own issue, the comment lands on the previous run's issue
 * (accepted: still operator-visible, still labeled). A comment failure
 * mirrors to Sentry and never escalates.
 */
async function commentOnScheduledIssue(
  octokit: Pick<Octokit, "request" | "graphql">,
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
    if (!issue) {
      // No open issue carries the label — the comment channel is dead for
      // this cron (the 5 pure-TS pipelines pass their Sentry monitor slug,
      // which only the claude-spawn crons create issues under). Mirror the
      // drop so triage knows Sentry is the ONLY signal for this failure.
      reportSilentFallback(
        new Error(`no open issue labeled ${config.scheduledIssueLabel}`),
        {
          feature: config.cronName,
          op: "safe-commit-comment-no-target",
          message:
            "Safe-commit visibility comment had no labeled open issue to land on — Sentry is the only signal for this run's failure",
          extra: { fn: config.cronName, label: config.scheduledIssueLabel },
        },
      );
      return;
    }
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

/**
 * Uniform failure exit: scrub + bound the message, mirror to Sentry, and
 * post the operator-visibility comment on the scheduled issue for EVERY
 * failed stage (the plan's "any stage" contract — an add/commit/status
 * failure is exactly as operator-invisible as a deletion-guard abort).
 * Callers may pass `comment` for stage-specific richer text. Never throws.
 */
async function failure(
  config: SafeCommitConfig,
  stage: Extract<SafeCommitResult, { status: "failed" }>["stage"],
  message: string,
  opts?: { extra?: Record<string, unknown>; comment?: string },
): Promise<SafeCommitResult> {
  const scrubbed = redactToken(message, config.installationToken)
    // Drift-proof remote-URL scrub: a delayed-replay push can echo a remote
    // URL embedding a token that no longer equals the memoized one.
    .replace(/x-access-token:[^@\s]+@/g, "x-access-token:[REDACTED]@")
    .slice(0, MESSAGE_CAP_CHARS);
  reportSilentFallback(new Error(`safeCommitAndPr ${stage}: ${scrubbed}`), {
    feature: config.cronName,
    op: stage === "deletion-guard" ? "safe-commit-deletion-guard" : "safe-commit-failed",
    message: `safeCommitAndPr failed at stage ${stage}`,
    extra: { fn: config.cronName, stage, ...opts?.extra },
  });
  try {
    const octokit = await resolveOctokit(config);
    await commentOnScheduledIssue(
      octokit,
      config,
      opts?.comment ??
        `PR withheld: safe-commit failed at stage \`${stage}\` for \`${config.cronName}\`. ` +
          `See Sentry op \`safe-commit-failed\` (fn=${config.cronName}) and the "PR withheld by safe-commit" ` +
          `section of knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md.`,
    );
  } catch (err) {
    reportSilentFallback(err, {
      feature: config.cronName,
      op: "safe-commit-issue-comment-failed",
      message: "failure() could not post the visibility comment",
      extra: { fn: config.cronName, stage },
    });
  }
  emitCronPersistResult({
    cron: config.cronName,
    status: "failed",
    files: 0,
    pr: null,
    stage,
  });
  return { status: "failed", stage, message: scrubbed };
}

export async function safeCommitAndPr(
  config: SafeCommitConfig,
): Promise<SafeCommitResult> {
  const { spawnCwd, cronName, allowedPaths, runStartedAt, logger } = config;
  // #5111: a fast-fail SUBSET of git-check-ref-format (not exhaustive) —
  // rejects `:` `.` whitespace and option-shaped leading `-` at stage
  // "checkout" BEFORE any git mutation. Callers compute branch names from
  // dynamic data (cluster hashes) and a bad name must fail loudly, not
  // surface as an opaque git error (or an injected git flag) mid-pipeline.
  // Anything this subset misses still fails loudly at the real checkout.
  if (config.branchName && /^-|[:.\s]/.test(config.branchName)) {
    return failure(
      config,
      "checkout",
      `branchName override is not refname-safe (leading '-', ':', '.', or whitespace): ${config.branchName}`,
    );
  }
  const branch = config.branchName ?? deriveBranchName(cronName, runStartedAt);
  const prTitle = config.prTitle ?? `${config.commitMessage} ${runStartedAt.slice(0, 10)}`;
  const gitIdentityEnv: Record<string, string> = {
    GIT_AUTHOR_NAME: BOT_NAME,
    GIT_AUTHOR_EMAIL: BOT_EMAIL,
    GIT_COMMITTER_NAME: BOT_NAME,
    GIT_COMMITTER_EMAIL: BOT_EMAIL,
    // Pinned dates keep the commit SHA stable if the same tree is ever
    // re-committed (belt-and-suspenders; the replay-resume branch below is
    // the primary replay carrier) and make fixture SHAs deterministic.
    // Identity-via-env also avoids `git config`.
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

    // -- 2. Replay-resume: a prior attempt already created the commit
    //       (crash between commit and push/PR). Branch-name match alone is
    //       NOT enough — a crash between `checkout -B` and `commit` leaves
    //       HEAD on the branch at main's tip, and skipping the scan there
    //       would push a commit-less branch and strand the run's work
    //       (multi-agent review P2). Require commits ahead of origin/main;
    //       otherwise fall through to the scan (idempotent from the branch).
    const headRef = await runGit(spawnCwd, ["rev-parse", "--abbrev-ref", "HEAD"]);
    let resuming = false;
    if (headRef.ok && headRef.stdout.trim() === branch) {
      const ahead = await runGit(spawnCwd, ["rev-list", "origin/main..HEAD", "--count"]);
      resuming = ahead.ok && Number(ahead.stdout.trim()) > 0;
    }

    let fileCount = 0;
    let deletionCount = 0;
    // Hoisted for the SAME reason as fileCount: `matched` is block-scoped inside
    // the `if (!resuming)` below and is NOT in scope at the return statement.
    // Stays `undefined` on the replay-resume branch — see the `paths` doc on
    // SafeCommitResult: undefined is "not determined", not "nothing committed".
    let paths: string[] | undefined;
    const prBodyExtras: string[] = [];

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

      // -- 3.5. Clean-index precondition. `git commit` commits the WHOLE
      //       index, so anything pre-staged would ride into the PR around
      //       the allowlist filter — including rename SOURCE paths the
      //       parser deliberately discards (multi-agent review P2: a staged
      //       rename out of an allowed dir would otherwise commit an
      //       unguarded deletion). Bot workspaces never legitimately
      //       pre-stage (the spawned model's git staging is hook-denied);
      //       a dirty index is an anomaly — refuse loudly.
      const staged = entries.filter((e) => e.x !== " " && e.x !== "?");
      if (staged.length > 0) {
        return failure(
          config,
          "dirty-index",
          `staged index is not clean (${staged.length} pre-staged entr${staged.length === 1 ? "y" : "ies"}) — refusing to commit`,
          { extra: { stagedCount: staged.length, sample: staged.slice(0, 10).map((e) => e.path) } },
        );
      }

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
          .map((e) => safeMd(e.path));
        return failure(
          config,
          "deletion-guard",
          `${deletionCount} staged-or-worktree deletions inside allowedPaths exceed max ${DEFAULT_MAX_DELETIONS}`,
          {
            extra: { deletionCount, max: DEFAULT_MAX_DELETIONS, sample },
            comment:
              `PR withheld: deletion guard (${deletionCount} deletions > max ${DEFAULT_MAX_DELETIONS}). ` +
              `Sample: ${sample.map((p) => `\`${p}\``).join(", ")}. ` +
              `See the "PR withheld by safe-commit" section of knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md.`,
          },
        );
      }

      // -- 7. No changes — distinct from failure; logged for greppability.
      if (matched.length === 0) {
        logger?.info(
          { fn: cronName, op: "safe-commit-no-changes" },
          `safeCommitAndPr: no committable changes inside allowedPaths for ${cronName}`,
        );
        emitCronPersistResult({
          cron: cronName,
          status: "no-changes",
          files: 0,
          pr: null,
          stage: null,
        });
        return { status: "no-changes" };
      }
      fileCount = matched.length;
      paths = matched.map((e) => e.path);

      // -- 8. Branch + scoped add + commit (identity + dates via env).
      const checkout = await runGit(spawnCwd, ["checkout", "-B", branch]);
      if (!checkout.ok) {
        return failure(config, "checkout", `checkout -B ${branch}: ${checkout.stderr}`);
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
        [
          "commit",
          "-m",
          config.commitMessage,
          ...(config.commitBody ? ["-m", config.commitBody] : []),
        ],
        gitIdentityEnv,
      );
      if (!commit.ok) {
        return failure(config, "commit", commit.stderr);
      }

      // PR body is derived here (not caller config): static stem plus a
      // LOUD marker when the allowlist dropped paths, so a truncated PR is
      // visible on the PR itself, not only in Sentry (review P2).
      if (dropped.length > 0) {
        prBodyExtras.push(
          `> ⚠️ ${dropped.length} changed path(s) outside the persistence allowlist were NOT committed ` +
            `(Sentry op \`safe-commit-paths-dropped\`): ${dropped
              .slice(0, 10)
              .map((e) => `\`${safeMd(e.path)}\``)
              .join(", ")}`,
        );
      }
    }

    // -- 9. Push (re-push of an existing commit is a no-op).
    const push = await runGit(spawnCwd, ["push", "-u", "origin", branch]);
    if (!push.ok) {
      return failure(
        config,
        "push",
        `${push.stderr} (a 401/403 here can mean the memoized installation token expired across a delayed replay)`,
        {
          comment: `PR withheld: push failed for \`${branch}\`. See Sentry op safe-commit-failed (fn=${cronName}).`,
        },
      );
    }

    // -- 10. PR create; 422 "already exists" is replay success. The stem is
    //        caller-overridable (#5111) but the dropped-path ⚠️ marker is
    //        appended REGARDLESS — the loud-truncation invariant survives
    //        every override.
    const octokit = await resolveOctokit(config);
    const prBody =
      (config.prBody ??
        `Automated PR from \`${cronName}\` — committed handler-side via safeCommitAndPr (#5091).`) +
      (prBodyExtras.length ? `\n\n${prBodyExtras.join("\n")}` : "");
    let prNumber: number;
    let prNodeId: string;
    try {
      const created = (await octokit.request("POST /repos/{owner}/{repo}/pulls", {
        owner: REPO_OWNER,
        repo: REPO_NAME,
        title: prTitle,
        body: prBody,
        head: branch,
        base: "main",
        ...(config.prDraft ? { draft: true } : {}),
        headers: { "X-GitHub-Api-Version": "2022-11-28" },
      })) as { data: { number: number; node_id: string } };
      prNumber = created.data.number;
      prNodeId = created.data.node_id;
    } catch (err) {
      const e = err as Error & { status?: number };
      const alreadyExists =
        e.status === 422 && /pull request already exists/i.test(e.message ?? "");
      if (!alreadyExists) {
        return failure(config, "pr-create", e.message ?? String(err), {
          comment: `PR withheld: PR creation failed for \`${branch}\`. See Sentry op safe-commit-failed (fn=${cronName}).`,
        });
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

    // -- 10.5. Post-create extras (#5111): labels + synthetic check-runs.
    //          Both best-effort BY DESIGN (a deliberate downgrade from the
    //          legacy pipelines, where a check-run POST throw failed the
    //          step): labels are advisory metadata, and a failed check-run
    //          POST is Sentry-mirrored while the merge tail surfaces the
    //          consequence — except in direct-mode arm-fallback, where the
    //          fell-back op below is the signal.
    if (config.prLabels?.length) {
      try {
        await octokit.request(
          "POST /repos/{owner}/{repo}/issues/{issue_number}/labels",
          {
            owner: REPO_OWNER,
            repo: REPO_NAME,
            issue_number: prNumber,
            labels: [...config.prLabels],
            headers: { "X-GitHub-Api-Version": "2022-11-28" },
          },
        );
      } catch (err) {
        reportSilentFallback(err, {
          feature: cronName,
          op: "safe-commit-label-failed",
          message: "Could not apply PR labels (advisory metadata — run continues)",
          extra: { fn: cronName, prNumber, labels: config.prLabels },
        });
      }
    }
    if (config.syntheticChecks) {
      const head = await runGit(spawnCwd, ["rev-parse", "HEAD"]);
      if (head.ok) {
        const headSha = head.stdout.trim();
        for (const name of config.syntheticChecks.names) {
          try {
            await octokit.request("POST /repos/{owner}/{repo}/check-runs", {
              owner: REPO_OWNER,
              repo: REPO_NAME,
              name,
              head_sha: headSha,
              status: "completed",
              conclusion: "success",
              output: { title: "Bot PR", summary: config.syntheticChecks.summary },
              headers: { "X-GitHub-Api-Version": "2022-11-28" },
            });
          } catch (err) {
            reportSilentFallback(err, {
              feature: cronName,
              op: "safe-commit-check-run-failed",
              message:
                "Could not post a synthetic check-run — merge tail will surface the consequence loudly",
              extra: { fn: cronName, prNumber, checkName: name },
            });
          }
        }
      } else {
        reportSilentFallback(new Error(head.stderr), {
          feature: cronName,
          op: "safe-commit-check-run-failed",
          message: "Could not resolve head SHA for synthetic check-runs",
          extra: { fn: cronName, prNumber },
        });
      }
    }

    // -- 11. Merge tail, by mode (#5111). "auto" (default) preserves #5091
    //        behavior exactly: enablePullRequestAutoMerge with the
    //        "clean status" → direct-merge fallback. "direct" inverts the
    //        ladder for the legacy live pipelines: PUT …/merge first, arm
    //        auto-merge on failure, fail stage "auto-merge" when both lose
    //        (PR stays open + loud — the stage union is deliberately NOT
    //        widened; the runbook row covers both arming and execution
    //        failures). "none" stops after create (human-review drafts).
    //        Repo has delete_branch_on_merge=true, so branch cleanup is
    //        handled by GitHub in all merging paths.
    const mergeMode = config.mergeMode ?? "auto";
    if (mergeMode === "direct") {
      try {
        await octokit.request("PUT /repos/{owner}/{repo}/pulls/{pull_number}/merge", {
          owner: REPO_OWNER,
          repo: REPO_NAME,
          pull_number: prNumber,
          merge_method: "squash",
          headers: { "X-GitHub-Api-Version": "2022-11-28" },
        });
      } catch (mergeErr) {
        const autoMerge = await enableAutoMergeSquash(octokit, prNodeId);
        if (!autoMerge.enabled) {
          return failure(
            config,
            "auto-merge",
            `direct merge failed (${(mergeErr as Error).message}); auto-merge arm also failed (${autoMerge.reason ?? "enablePullRequestAutoMerge failed"})`,
            {
              extra: { prNumber, mergeMode },
              comment: `PR #${prNumber} was created but could not be merged — it needs a manual merge. See Sentry op safe-commit-failed (fn=${cronName}).`,
            },
          );
        }
        // Fallback succeeded — the PR is parked on armed auto-merge instead
        // of merged. MUST be Sentry-visible (cq-silent-fallback-must-mirror):
        // armed auto-merge silently disarms on conflict, so this is the entry
        // into the stale-PR window the #5138 watchdog tracks — for LIVE
        // direct-mode pipelines, not just the Tier-2-dormant auto cohort.
        reportSilentFallback(mergeErr, {
          feature: cronName,
          op: "safe-commit-direct-merge-fell-back",
          message:
            "Direct merge failed; auto-merge was armed instead — PR merges when checks pass, or goes stale on conflict",
          extra: { fn: cronName, prNumber, mergeMode },
        });
      }
    } else if (mergeMode === "auto") {
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
            return failure(config, "auto-merge", (err as Error).message, {
              extra: { prNumber },
              comment: `PR #${prNumber} was created but auto-merge could not be armed — it needs a manual merge. See Sentry op safe-commit-failed (fn=${cronName}).`,
            });
          }
        } else {
          return failure(
            config,
            "auto-merge",
            autoMerge.reason ?? "enablePullRequestAutoMerge failed",
            {
              extra: { prNumber },
              comment: `PR #${prNumber} was created but auto-merge could not be armed — it needs a manual merge. See Sentry op safe-commit-failed (fn=${cronName}).`,
            },
          );
        }
      }
    }
    // mergeMode === "none": create-only — fall through to the success log.

    logger?.info(
      { fn: cronName, op: "safe-commit-pr", prNumber, branch, fileCount },
      `safeCommitAndPr: opened PR #${prNumber} from ${branch}`,
    );
    emitCronPersistResult({
      cron: cronName,
      status: "committed",
      files: fileCount,
      pr: prNumber,
      stage: null,
    });
    return {
      status: "committed",
      prNumber,
      branch,
      fileCount,
      deletionCount,
      // Spread-conditional so the replay-resume arm carries NEITHER key rather
      // than an explicit `paths: undefined` — callers discriminate on presence.
      ...(paths ? { paths } : {}),
      ...(resuming ? { resumed: true as const } : {}),
    };
  } catch (err) {
    // Belt-and-suspenders: the contract is non-throwing; anything that
    // escapes the per-stage handling above still resolves to a failure
    // result so the handler's heartbeat chain always runs.
    return failure(config, "unexpected", (err as Error).message ?? String(err));
  }
}
