import { existsSync } from "node:fs";
import { rm, rename, cp, readdir, mkdir } from "node:fs/promises";
import { join, basename } from "node:path";
import { randomUUID } from "node:crypto";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

import { gitWithInstallationAuth, sanitizeGitStderr } from "@/server/git-auth";
import { reportSilentFallback } from "@/server/observability";
import { reportRepoCloneFailed } from "@/server/repo-resolver-divergence";
import { createChildLogger } from "@/server/logger";
import {
  isValidGitWorkTree,
  isEmptyCorruptGitDir,
  probeGitWorktreeShape,
  isStrandingFilePointer,
} from "@/server/git-worktree-validity";
import { withWorkspacePermissionLock } from "@/server/workspace-permission-lock";
import { isGitDataStoreEnabled } from "@/server/workspace-resolver";
import { fetchFromGitData } from "@/server/git-data-client";
import { resolveWorktreeId } from "@/server/worktree-write-lease";
import { seedWorktreeConfig } from "@/server/worktree-config-seed";

const log = createChildLogger("ensure-workspace-repo");
const execFileAsync = promisify(execFile);

// Sub-PR 3.D (#5274 Phase 3, ADR-068) — the clone-from-git-data overlay runs a
// handful of LOCAL, network-free git ops (rev-parse / show-ref / reset --hard)
// against the freshly-cloned workspace. These are deliberately NOT routed
// through `gitWithInstallationAuth`: that helper injects the GitHub App
// installation token via GIT_ASKPASS for the AUTHED clone, but these ops touch
// only the local object store / refs — no network, no credentials. A plain
// `execFile` array form (no shell → no argv/flag-smuggling) with cwd pinned to
// the workspace is the correct, least-authority tool (mirrors the local,
// token-free rev-parse probe in git-worktree-validity.ts).
type LocalGitFn = (args: string[], cwd: string) => Promise<{ stdout: string }>;

const realLocalGit: LocalGitFn = async (args, cwd) => {
  const { stdout } = await execFileAsync("git", args, {
    cwd,
    timeout: 30_000,
    killSignal: "SIGKILL",
    maxBuffer: 1024 * 1024,
  });
  return { stdout: stdout.toString() };
};

let localGitFn: LocalGitFn = realLocalGit;

/** @internal test seam — the local (network-free) git exec used by the git-data
 * overlay, injectable so show-ref present/absent is controllable without a live
 * git or real refs. */
export function __setLocalGitForTests(fn: LocalGitFn): void {
  localGitFn = fn;
}

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
 * Deliberately 2-variant. There are now TWO consumers:
 *   1. the cc reconnect honest-message branch, which keys SOLELY on `"failed"`
 *      (its only question is "did recovery fail?"); and
 *   2. the push-reconcile surface (workspace-reconcile-on-push.ts), which ALSO
 *      reads the `"ok"` variant — but NOT as a heal proxy: `"ok"` folds every
 *      benign exit (not-connected, `.git`-present no-op, skipped-bad-url, cloned),
 *      so the reconcile caller pairs it with a readiness RE-PROBE
 *      (`outcome === "ok" && isReadyGitWorkTree(...)`, #5733 — NOT
 *      `isValidGitWorkTree`, which would falsely classify a re-clone-over-pointer
 *      since a `.git` FILE pointer passes the lstat-structural check) to
 *      distinguish an actual re-clone from a benign skip that healed nothing.
 * `"failed"` is ONLY the genuine clone-catch / honest-block signal. Callers may
 * key on `"ok"` (with a validity re-probe), not only on `"failed"`.
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

  // #5733 — STRANDING gitdir-POINTER heal (BEFORE the validity no-op below). A
  // `.git` FILE at a workspace ROOT is never a legitimate linked-worktree (a
  // personal workspace is always a top-level clone), yet `isValidGitWorkTree`
  // treats it as VALID (git-worktree-validity.ts:60). When that pointer's
  // `gitdir:` target ESCAPES the workspace (unreadable under the sandbox's
  // `denyRead:["/workspaces"]`), the agent's IN-BWRAP `git rev-parse` strands.
  // Only the ESCAPING/unclassifiable pointer is healed (`isStrandingFilePointer`)
  // — a non-escaping in-workspace pointer is readable in-sandbox, does NOT
  // strand, and is left untouched (never needlessly re-cloned, never risks user
  // work). Remove the stale pointer FILE and fall through to a fresh
  // self-contained clone from origin HEAD. This is NOT a widening of the
  // empty-corrupt rm fingerprint (a RECURSIVE `.git` DIR removal of an
  // object-bearing dir); a `.git` FILE is a single pointer with NO objects —
  // nothing to lose. Lock-guarded with an under-lock re-check (a racer that
  // grafted a valid dir wins); the emit fires ONLY after a confirmed unlink.
  if (isStrandingFilePointer(probeGitWorktreeShape(workspacePath))) {
    let removedPointer = false;
    try {
      await withWorkspacePermissionLock(workspacePath, async () => {
        if (isStrandingFilePointer(probeGitWorktreeShape(workspacePath))) {
          await rm(join(workspacePath, ".git"), { force: true }); // single FILE, NOT recursive
          removedPointer = true;
        }
      });
    } catch (err) {
      reportSilentFallback(err, {
        feature: "ensure-workspace-repo",
        op: "gitdir-pointer-rm",
        extra: { userId, hasInstallation: true },
        message:
          "failed to remove stale gitdir pointer under lock; honest-blocking",
      });
      return "failed";
    }
    if (removedPointer) {
      reportSilentFallback(new Error("workspace .git was a stale gitdir pointer"), {
        feature: "ensure-workspace-repo",
        op: "gitdir-pointer-reclone",
        extra: { userId, hasInstallation: true },
        message:
          "personal workspace .git was an escaping FILE pointer (strands the agent's in-bwrap git rev-parse); removed the pointer and re-cloning a self-contained repo",
      });
    }
    // Pointer removed (or a racer landed a valid `.git`) → fall through to the
    // validity gate + clone below, which re-checks the now-absent/now-valid state.
  }

  // NEVER touch a VALID repo (Start-Fresh, already-cloned, or a different origin
  // the user is intentionally using). Validity — not mere presence — is the
  // no-op gate (2026-06-19): a `.git` that exists but is corrupt must NOT mask
  // the heal the way bare `existsSync` did. (A STRANDING `.git` FILE pointer was
  // handled and removed just above; a non-stranding in-workspace pointer is a
  // valid linked tree we intentionally preserve here.)
  if (isValidGitWorkTree(workspacePath)) {
    // #4826 — re-seed the worktree-config prerequisites HOST-SIDE on every session
    // boot of an EXISTING valid workspace. The #6064 provision-time seed only reaches
    // workspaces created AFTER it shipped; a workspace provisioned earlier persists on
    // the volume and would keep wedging in-sandbox worktree creation (the SDK masks
    // `.git/config.lock`) forever. This heals that population idempotently. Best-effort
    // (never throws); a failure just falls back to the in-sandbox write path.
    seedWorktreeConfig(workspacePath);
    return "ok";
  }

  // `.git` EXISTS but is INVALID. The destructive removal is authorized ONLY by
  // the POSITIVE empty-corrupt fingerprint (`.git` dir + HEAD ENOENT + objects
  // ENOENT — no objects = no commits to lose). A populated-but-broken `.git`, an
  // EACCES/EIO blip, or a `.git` FILE does NOT match → honest-block ("failed"),
  // NEVER rm (deepen-plan F2: never destroy on the negation of validity).
  if (existsSync(join(workspacePath, ".git"))) {
    if (!isEmptyCorruptGitDir(workspacePath)) {
      reportSilentFallback(
        new Error("corrupt .git not safely removable"),
        {
          feature: "ensure-workspace-repo",
          op: "corrupt-worktree-block",
          extra: { userId, hasInstallation: true },
          message:
            "workspace .git exists but is invalid and does NOT match the empty-corrupt fingerprint (populated-broken / EACCES / gitdir-file); honest-blocking, NOT removing",
        },
      );
      return "failed";
    }
    // Empty-corrupt fingerprint matched → remove `.git` UNDER THE WORKSPACE LOCK
    // (F3: the rm is a second `.git` writer the graft sentinel never guarded; a
    // racer must not delete a winner's freshly-valid `.git`). Re-check validity
    // inside the lock so the loser no-ops on the winner's result.
    try {
      await withWorkspacePermissionLock(workspacePath, async () => {
        if (isValidGitWorkTree(workspacePath)) return; // racer already grafted
        if (isEmptyCorruptGitDir(workspacePath)) {
          await rm(join(workspacePath, ".git"), { recursive: true, force: true });
        }
      });
    } catch (err) {
      reportSilentFallback(err, {
        feature: "ensure-workspace-repo",
        op: "corrupt-worktree-rm",
        extra: { userId, hasInstallation: true },
        message: "failed to remove empty-corrupt .git under lock; honest-blocking",
      });
      return "failed";
    }
    // `.git` removed (or a racer already landed a valid one) → fall through to
    // the clone below, which re-checks the (now-absent / now-valid) sentinel.
  }

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

    // #4826 — seed worktree-config prerequisites into the freshly-grafted `.git`
    // (host-side, before the sandbox mask), same as the provision-time clone path.
    seedWorktreeConfig(workspacePath);

    // Sub-PR 3.D (#5274 Phase 3, ADR-068) — clone-from-git-data read-source
    // OVERLAY. Rehydration = clone(GitHub) → overlay(git-data). git-data ⊇ the
    // GitHub origin in committed-ref completeness (syncPush only auto-commits
    // knowledge-base/** + reroutes protected-branch pushes to a PR branch, while
    // replicateToGitData force-pushes ALL refs), so a fresh GitHub clone can be
    // strictly BEHIND the user's latest committed tip on git-data. After a fresh
    // graft we fetch the user's worktree namespace into refs/remotes/git-data/*
    // and, if the primary branch has a git-data tip, reset --hard onto it.
    //
    // SAFETY INVARIANT (the CTO's proof): this block is reachable ONLY on the
    // fresh-graft path, which sits AFTER the early-return
    // `if (isValidGitWorkTree(workspacePath)) return "ok"` above. Any LIVE
    // worktree that could hold local-only commits returns BEFORE reaching here —
    // by construction zero local-only commits exist at the reset point, so the
    // reset can never discard user work.
    //
    // FAIL-SOFT: git-data is an OVERLAY, not a hard dependency — the GitHub clone
    // is a valid standalone fallback. A git-data reachability blip must NEVER
    // fail the clone, so the whole overlay is wrapped and any error is mirrored
    // to Sentry (cq-silent-fallback-must-mirror-to-sentry) while we still
    // `return "ok"`.
    if (isGitDataStoreEnabled()) {
      try {
        const workspaceId = basename(workspacePath);
        const worktreeId = resolveWorktreeId(userId); // validates + returns per-user id
        await fetchFromGitData({ userId, workspaceId, worktreeId, workspacePath });

        // Resolve the freshly-cloned primary branch (LOCAL, network-free).
        const { stdout } = await localGitFn(
          ["rev-parse", "--abbrev-ref", "HEAD"],
          workspacePath,
        );
        const primary = stdout.trim();
        const dataRef = `refs/remotes/git-data/${primary}`;

        // Does git-data hold a tip for this branch? `show-ref --verify --quiet`
        // exits non-zero (rejects) when the ref is absent (empty git-data /
        // first-ever session) — in which case we keep the GitHub clone as-is.
        let refPresent = true;
        try {
          await localGitFn(["show-ref", "--verify", "--quiet", dataRef], workspacePath);
        } catch {
          refPresent = false;
        }

        if (refPresent) {
          // Overlay the git-data tip. Re-check validity UNDER THE WORKSPACE LOCK
          // (mirror the corrupt-rm block above) as defense-in-depth against a
          // concurrent graft: only reset a still-valid worktree.
          await withWorkspacePermissionLock(workspacePath, async () => {
            if (!isValidGitWorkTree(workspacePath)) return;
            await localGitFn(["reset", "--hard", dataRef], workspacePath);
          });
        }
      } catch (err) {
        reportSilentFallback(err, {
          feature: "ensure-workspace-repo",
          op: "git-data-overlay",
          extra: { userId },
        });
        // fall through — the GitHub clone stands; overlay is best-effort.
      }
    }
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
    // #5733 P2 (review) — sanitize the exception VALUE before capture: the
    // execFile rejection `.message` is `Command failed: git … <workspacePath>
    // <repoUrl>\n<stderr>`, carrying the absolute `/workspaces/<uuid>` path
    // (== solo userId) + repo URL, which the key-based `scrubSentryEvent` does
    // NOT scrub from `event.exception.values[].value`. Mirror the sibling
    // `reportRepoCloneFailed` sanitization so this op:clone breadcrumb does not
    // defeat the PR's own redaction in the same catch.
    const safeCloneErr =
      err instanceof Error
        ? new Error(sanitizeGitStderr(err.message))
        : new Error(sanitizeGitStderr(String(err)));
    reportSilentFallback(safeCloneErr, {
      feature: "ensure-workspace-repo",
      op: "clone",
      extra: { userId, hasInstallation: true },
      message: "ensure-workspace-repo clone failed; Concierge proceeds degraded (no clone)",
    });
    // #5733 D0 — also emit the DISTINCT, queryable + paging `repo_clone_failed`
    // event so the previously SWALLOWED clone failure is loud for EVERY caller
    // (cold/warm/reconcile). The reason is sanitized at the reporter's write
    // boundary (no token — askpass env; no absolute path / repo URL). The
    // workspace id is `basename(workspacePath)` (`<root>/<uuid>`), pre-hashed in
    // the reporter (== raw userId for a solo workspace). DEFENSIVE: a telemetry
    // failure must NEVER escape this catch and convert a graceful `"failed"`
    // clone outcome into an uncaught exception that crashes the dispatch.
    try {
      reportRepoCloneFailed({
        userId,
        activeWorkspaceId: basename(workspacePath),
        reason: err instanceof Error ? err.message : String(err),
      });
    } catch {
      // swallow — the op:clone mirror above already recorded the failure.
    }
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
    // while this one was cloning. A VALID `.git` (2026-06-19 — not mere
    // presence) is the all-or-nothing success sentinel, so if a valid one now
    // exists we lost the race — leave the winner's clone intact and skip, rather
    // than `rename`-ing onto a populated `.git` (which throws ENOTEMPTY and would
    // mirror a spurious failure to Sentry). A stale empty-corrupt `.git` does NOT
    // satisfy this, so the winner still grafts over it.
    if (isValidGitWorkTree(workspacePath)) return;
    // .git LAST — the success sentinel. A failure before this leaves the
    // workspace `.git`-less so the next cold dispatch retries cleanly.
    await rename(join(tmp, ".git"), join(workspacePath, ".git")); // same fs
  } finally {
    await rm(tmp, { recursive: true, force: true }).catch(() => {});
  }
}
