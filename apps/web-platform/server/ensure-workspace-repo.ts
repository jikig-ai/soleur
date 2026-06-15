import { existsSync } from "node:fs";
import { rm, rename, cp, readdir, mkdir } from "node:fs/promises";
import { join } from "node:path";
import { randomUUID } from "node:crypto";

import { gitWithInstallationAuth } from "@/server/git-auth";
import { reportSilentFallback } from "@/server/observability";
import { createChildLogger } from "@/server/logger";

const log = createChildLogger("ensure-workspace-repo");

// Strict github.com HTTPS allowlist. The clone arg is also `--`-guarded against
// argv flag-smuggling; this format check is defense-in-depth so a malformed /
// non-github repo_url never reaches `git clone` (review PR #4890, HIGH).
const GITHUB_HTTPS_REPO_RE =
  /^https:\/\/github\.com\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+(\.git)?$/;

// Test seam: the orchestration (`ensureWorkspaceRepoCloned`) is unit-tested by
// stubbing the graft mechanic so the decision logic + fail-soft posture are
// covered without touching real git/fs. Production uses the real implementation.
type GraftFn = (
  workspacePath: string,
  repoUrl: string,
  installationId: number,
) => Promise<void>;

let graftFn: GraftFn = realGraftRepoClone;

/** @internal test seam */
export function __setGraftForTests(fn: GraftFn): void {
  graftFn = fn;
}

/**
 * Result of a session-start re-provision attempt (#5340 / #5240 design item #2).
 * Deliberately 2-variant: the only consumer (the cc reconnect honest-message
 * branch) branches solely on `"failed"`. `"ok"` folds every benign exit
 * (not-connected, `.git`-present no-op, skipped-bad-url, cloned) — four success
 * shades nobody reads were cut at plan-review. `"failed"` is ONLY the genuine
 * clone-catch, i.e. the post-recovery-failure signal that gates the honest
 * "workspace reclaimed" message.
 */
export type ReprovisionOutcome = "failed" | "ok";

export interface EnsureWorkspaceRepoArgs {
  userId: string;
  workspacePath: string;
  /** Per-user installation (resolveInstallationId, membership-checked). null = not connected. */
  installationId: number | null;
  /** Per-user connected repo (getCurrentRepoUrl, normalized). null/empty = not connected. */
  repoUrl: string | null;
}

/**
 * Unconditional pre-sandbox workspace-dir guarantee.
 *
 * The agent runs inside an SDK bubblewrap sandbox whose `cwd` is frozen to
 * `workspacePath` at `query()` construction (`agent-runner-query-options.ts`);
 * bwrap `chdir`s into that path and REQUIRES it to EXIST. After a sandbox/host
 * reclaim the dir can be gone — and dir-existence is a STRONGER precondition
 * than clone-eligibility: `ensureWorkspaceRepoCloned` early-returns for
 * not-connected (no `installationId`/`repoUrl`) and `.git`-present workspaces
 * BEFORE it ever reaches `realGraftRepoClone`'s own mkdir, so a reclaimed
 * not-connected (or `.git`-present-but-root-deleted) workspace would otherwise
 * get NO dir re-creation and the sandbox builds against a non-existent CWD
 * (the "configured CWD `/workspaces/<uuid>` doesn't exist" symptom). This mkdir
 * is therefore UNCONDITIONAL and independent of the clone (PR #5367's conditional
 * mkdir stays — it is correct for the clone; this is the wider precondition).
 *
 * Fail-soft-but-loud (per the not-connected fail-soft hazard): one bounded retry,
 * then mirror to Sentry (`cq-silent-fallback-must-mirror-to-sentry`) and THROW.
 * It must NOT silently proceed to construct a sandbox against a still-missing dir
 * — for the not-connected case there is no clone to recover and no clone-`"failed"`
 * to surface the honest "workspace reclaimed" message, so silent-proceed would
 * reconstruct the exact original symptom with only a swallowed Sentry event. The
 * throw rides the caller's existing `query()`-construction catch, which surfaces
 * the retryable error envelope to the conversation.
 *
 * Creates ONLY the workspace root (`recursive: true`), never `.git` — so the
 * clone's `.git`-absent no-op guard and `"failed"` honest-message path are
 * unperturbed. Recursive mkdir on an existing dir is idempotent.
 */
export async function ensureWorkspaceDirExists(
  workspacePath: string,
  ctx: { feature: string; userId: string },
): Promise<void> {
  try {
    await mkdir(workspacePath, { recursive: true });
  } catch {
    try {
      await mkdir(workspacePath, { recursive: true }); // bounded single retry
    } catch (err) {
      reportSilentFallback(err, {
        feature: ctx.feature,
        op: "ensure-workspace-dir-presandbox",
        extra: { userId: ctx.userId },
        message:
          "pre-sandbox workspace-dir ensure failed; surfacing a retryable error instead of building a sandbox against a non-existent CWD",
      });
      throw new Error(
        "workspace directory could not be ensured before sandbox construction",
      );
    }
  }
}

/**
 * Session-start self-heal: ensure the user's connected repo is cloned into their
 * workspace WHEN — and only when — the workspace has NO git repository at all.
 * Generic per-user/per-repo (owner/repo + installation token are the caller's
 * membership-checked values; nothing is hardcoded).
 *
 * SAFETY (review PR #4890 — brand-survival single-user-incident threshold):
 *   - We ONLY act when `<workspacePath>/.git` is ABSENT (the exact prod symptom:
 *     "No Git repository found"). When ANY `.git` already exists we NO-OP and
 *     never touch it. This deliberately does NOT auto-repair an origin mismatch:
 *     blowing away an existing `.git` could destroy un-pushed commits /
 *     uncommitted edits, and would clobber a "Start Fresh" workspace (which has
 *     a `.git` with no origin by design). Repo *reconnect* is the canonical
 *     `/api/repo/setup` path's job (wipe-and-reclone), not this self-heal.
 *   - A workspace with no `.git` has no git history to lose → grafting is safe.
 *   - Fail-soft: any failure mirrors to Sentry
 *     (`cq-silent-fallback-must-mirror-to-sentry`) and the function resolves —
 *     it NEVER throws into the conversation.
 *   - The graft lands `.git` LAST (success sentinel) so a partial failure leaves
 *     the workspace `.git`-less and the next cold conversation retries — never a
 *     half-grafted state that the no-op guard would permanently mask.
 *
 * The installation token rides GIT_ASKPASS inside `gitWithInstallationAuth`
 * (never in a remote URL, never logged) — `hr-github-app-auth-not-pat`.
 * The clone is shallow (`--depth 1`) — a deliberate first-slice limitation
 * (full-history / branch checkout is follow-up scope).
 */
export async function ensureWorkspaceRepoCloned(
  args: EnsureWorkspaceRepoArgs,
): Promise<ReprovisionOutcome> {
  const { userId, workspacePath, installationId, repoUrl } = args;
  if (installationId === null || !repoUrl) return "ok"; // not connected → nothing to ensure

  // NEVER touch an existing repo (Start-Fresh, already-cloned, or a different
  // origin the user is intentionally using). Only heal the no-`.git` symptom.
  if (existsSync(join(workspacePath, ".git"))) return "ok";

  if (!GITHUB_HTTPS_REPO_RE.test(repoUrl)) {
    reportSilentFallback(new Error("repo_url failed github-https allowlist"), {
      feature: "ensure-workspace-repo",
      op: "validate-repo-url",
      extra: { userId, hasInstallation: true },
      message: "connected repo_url is not a github.com HTTPS URL; skipping self-heal",
    });
    return "ok"; // benign skip — a malformed URL is NOT a recovery failure
  }

  try {
    await graftFn(workspacePath, repoUrl, installationId);
    // No raw `userId` on this direct-logger breadcrumb — the advisory
    // userid-bypass-lint guard (#3698) scans source for `logger({ userId })`
    // sites. Runtime is already safe (pino formatters.log hashes top-level
    // userId), so this is source-hygiene. The two reportSilentFallback sites
    // are guard-allowlisted (they hash via hashExtraUserId) and keep userId.
    log.info({ action: "cloned" }, "ensure-workspace-repo: cloned connected repo");
    return "ok";
  } catch (err) {
    // Fail-soft: surface to Sentry, never crash the conversation. The token is
    // env-only inside gitWithInstallationAuth (never in argv/URL/stderr), so it
    // cannot ride `err`; the format-validated repoUrl is non-sensitive.
    reportSilentFallback(err, {
      feature: "ensure-workspace-repo",
      op: "clone",
      extra: { userId, hasInstallation: true },
      message: "ensure-workspace-repo clone failed; Concierge proceeds degraded (no clone)",
    });
    // The ONLY non-benign outcome: a genuine clone failure (token expired /
    // network / repo gone). This is the post-recovery-failure signal the cc
    // reconnect path threads to the honest "workspace reclaimed" message.
    return "failed";
  }
}

/**
 * Clone the connected repo into a workspace dir that currently has NO `.git`
 * (may hold scaffold dirs like `.claude/`). Retry-safe: clone shallowly into a
 * temp subdir (same filesystem), materialize the tracked tree over the scaffold,
 * then move `.git` in LAST so `.git` presence is the all-or-nothing success
 * sentinel. The token is supplied via GIT_ASKPASS (env) inside
 * `gitWithInstallationAuth`, never embedded in the remote URL, and `--` guards
 * the URL arg against flag-smuggling.
 *
 * CONCURRENCY (review PR #4890 follow-up): the temp dir is unique per attempt
 * (`randomUUID` suffix), NOT a fixed `.ensure-repo-tmp`. Two cold dispatches for
 * the SAME user (two tabs / a rapid re-open) can both observe no `.git` and run
 * this concurrently against the shared `workspacePath`. The unique dir isolates
 * each attempt's clone + cleanup `rm` (a fixed dir let one attempt's `rm` nuke
 * the other's in-flight clone), and the `.git` sentinel move is guarded by a
 * re-check (below) so the loser no-ops instead of `rename`-ing onto the winner's
 * populated `.git` (ENOTEMPTY).
 *   NOTE: the working-tree `cp` loop below is NOT serialized — both racers may
 *   materialize their tree over `workspacePath`. That is benign here ONLY because
 *   both clone the same `repoUrl` at the same shallow HEAD, so the bytes are
 *   identical and `{force:true}` overwrites converge. This holds because the
 *   function acts only on a `.git`-less workspace (no local edits to lose) and
 *   repo *reconnect* (a different origin) is `/api/repo/setup`'s job, never this
 *   self-heal. If that premise ever changes, serialize via the existing
 *   `withWorkspacePermissionLock(workspacePath, …)` instead.
 */
/** @internal — exported only for the direct concurrency unit test (graft-race). */
export async function realGraftRepoClone(
  workspacePath: string,
  repoUrl: string,
  installationId: number,
): Promise<void> {
  // `git clone` creates only the leaf (`.ensure-repo-tmp-<uuid>`), not missing
  // parents, so the workspace root must exist first — it can be gone after a
  // sandbox/host reclaim. Matches the operative mkdir of the signup path
  // (workspace.ts:111); not its symlink-rejection contract, which is irrelevant here.
  await mkdir(workspacePath, { recursive: true });
  const tmp = join(workspacePath, `.ensure-repo-tmp-${randomUUID()}`);
  try {
    await gitWithInstallationAuth(
      ["clone", "--depth", "1", "--", repoUrl, tmp],
      installationId,
      { timeout: 120_000 },
    );
    // Materialize the cloned working tree over the scaffold (everything except
    // .git), overwriting any scaffold path the repo also tracks.
    for (const entry of await readdir(tmp)) {
      if (entry === ".git") continue;
      await cp(join(tmp, entry), join(workspacePath, entry), {
        recursive: true,
        force: true,
      });
    }
    // Re-check the sentinel immediately before the move. A concurrent attempt
    // (another cold dispatch that also saw no `.git`) may have grafted first
    // while this one was cloning. `.git` is the all-or-nothing success sentinel,
    // so if it now exists we lost the race — leave the winner's clone intact and
    // skip, rather than `rename`-ing onto a populated `.git` (which throws
    // ENOTEMPTY and would mirror a spurious failure to Sentry).
    if (existsSync(join(workspacePath, ".git"))) return;
    // .git LAST — the success sentinel. A failure before this leaves the
    // workspace `.git`-less so the next cold dispatch retries cleanly.
    await rename(join(tmp, ".git"), join(workspacePath, ".git")); // same fs
  } finally {
    await rm(tmp, { recursive: true, force: true }).catch(() => {});
  }
}
