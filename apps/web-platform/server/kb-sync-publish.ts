// ---------------------------------------------------------------------------
// KB sync publish: the push half of the post-session sync (#12600, CTO ruling R6).
//
// Guard 1 (KB-only publish gate, plan "Guard Contract"): every ref update the post-session sync sends (the default
// branch or `soleur/kb-sync`) names a commit the server built, whose root tree equals the hash-verified remote base's
// root tree in every entry except `knowledge-base`, whose message and identity are Soleur's, and which never drops
// knowledge-base content the remote holds and the workspace never saw. Every sync push call site lives in this module.
// ---------------------------------------------------------------------------

import { gitWithInstallationAuth } from "./git-auth";
import { createChildLogger } from "./logger";

const log = createChildLogger("session-sync");

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
export async function runProtectedFallback(
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

/** The post-session push of the workspace's checked-out branch (legacy arm). */
export async function pushWorkspaceDefault(installationId: number, workspacePath: string): Promise<void> {
  await gitWithInstallationAuth(
    ["push"],
    installationId,
    { cwd: workspacePath, timeout: 60_000 },
  );
}
