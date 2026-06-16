// Leaf module: `git pull --ff-only` workspace reconcile + gated self-heal,
// extracted from kb-route-helpers so it can be imported by surfaces that must
// stay OUT of the App-Router `next/headers` graph — specifically `c4-writer`,
// which is bundled into the WS/custom server (cc-dispatcher). kb-route-helpers
// re-exports `syncWorkspace`/`SyncWorkspaceResult` so its existing callers are
// unaffected.
//
// Deliberately imports NOTHING from `@/lib/supabase/server` (next/headers).
// Deps: observability (clean), a type-only KbSyncErrorClass, pino's Logger
// type, and a LAZY `@/server/git-auth` import inside syncWorkspace.
import {
  reportSilentFallback,
  warnSilentFallback,
} from "@/server/observability";
import type { KbSyncErrorClass } from "@/server/session-sync";
import type { Logger } from "pino";

// Re-declared as local constants typed by the shared union (the union is the
// source of truth; these are the literal members, NOT a new union). Kept local
// so this module stays free of a runtime session-sync import.
const ERROR_CLASS_NON_FAST_FORWARD: KbSyncErrorClass = "non_fast_forward";
const ERROR_CLASS_SYNC_FAILED: KbSyncErrorClass = "sync_failed";

export type SyncWorkspaceResult =
  | { ok: true; recovered?: boolean }
  | { ok: false; error: unknown; errorClass: KbSyncErrorClass };

/**
 * Classify a failed-git error into a {@link KbSyncErrorClass}. Two distinct
 * `git pull --ff-only` aborts (diverged clone, dirty working tree) are
 * self-healable via the same gated `reset --hard origin/<default>`, so both map
 * to `non_fast_forward`; everything else is `sync_failed`.
 */
function classifyGitSyncError(err: unknown): KbSyncErrorClass {
  const text =
    err instanceof Error
      ? `${err.message}\n${(err as { stderr?: string }).stderr ?? ""}`
      : String(err);
  if (
    text.includes("Not possible to fast-forward") ||
    text.includes("would be overwritten by merge") ||
    text.includes("commit your changes or stash")
  ) {
    return ERROR_CLASS_NON_FAST_FORWARD;
  }
  return ERROR_CLASS_SYNC_FAILED;
}

/**
 * Resolve the workspace clone's default branch as `<short>` (e.g. `main`) via
 * `git symbolic-ref --short refs/remotes/origin/HEAD`. Falls back to `main`
 * only if the symbolic ref is missing.
 */
async function resolveDefaultBranch(
  gitWithInstallationAuth: (
    args: string[],
    installationId: number,
    opts: { cwd: string; timeout: number },
  ) => Promise<Buffer | string>,
  installationId: number,
  workspacePath: string,
): Promise<string> {
  try {
    const out = await gitWithInstallationAuth(
      ["symbolic-ref", "--short", "refs/remotes/origin/HEAD"],
      installationId,
      { cwd: workspacePath, timeout: 30_000 },
    );
    const ref = out.toString().trim(); // e.g. "origin/main"
    const branch = ref.replace(/^origin\//, "");
    return branch || "main";
  } catch {
    return "main";
  }
}

/**
 * Pull the workspace to sync local files with the remote repo after a
 * successful GitHub mutation. On a `non_fast_forward` (diverged clone OR dirty
 * working tree) it attempts a GATED, OBSERVABLE self-heal: it resets to
 * `origin/<default>` when the clone holds ZERO un-pushed local commits, and —
 * for un-pushable auto-sync orphan commits stranded on the default branch —
 * branches them aside first (preserving them on a durable ref) before the
 * reset, never destroying agent-session work (feature-branch / detached-HEAD
 * divergence still aborts). Returns a {@link SyncWorkspaceResult}.
 *
 * Reporting is split by recoverability so a self-healed abort does NOT page the
 * operator: the self-healable `non_fast_forward` class logs only an info
 * breadcrumb here and lets the self-heal branches own Sentry escalation
 * (op:self-heal-aborted-dirty / op:self-heal-failed on a real freeze,
 * op:self-heal-reset warn on recovery); only the non-self-healable `sync_failed`
 * class emits the error-level `log.error`+`reportSilentFallback` mirror. See
 * Sentry 9ccf1d86… — the unconditional pre-self-heal `log.error({ err })`
 * pino-mirrored to Sentry on every push for a benign, recovered dirty-tree
 * abort (historically the c4 re-render published model.likec4.json into the
 * tracked tree; that source was removed in #4976, but the self-heal stays as
 * general defense against any other dirty-tree cause).
 */
export async function syncWorkspace(
  installationId: number,
  workspacePath: string,
  log: Logger,
  context: {
    userId: string;
    op: "delete" | "rename" | "upload" | "push" | "manual";
  },
): Promise<SyncWorkspaceResult> {
  const { gitWithInstallationAuth } = await import("@/server/git-auth");
  try {
    await gitWithInstallationAuth(["pull", "--ff-only"], installationId, {
      cwd: workspacePath,
      timeout: 30_000,
    });
    return { ok: true };
  } catch (syncError) {
    const errorClass = classifyGitSyncError(syncError);

    if (errorClass === ERROR_CLASS_NON_FAST_FORWARD) {
      // Self-healable: a diverged clone OR a dirty working tree (e.g. a
      // spurious mirror edit; historically also the c4 re-render's tracked-path
      // write to model.likec4.json, removed in #4976). A blocked ff-only pull
      // that the gated `reset --hard`
      // recovers is BENIGN churn — do NOT emit an error-level mirror here. The
      // pino `log.error({ err })` path mirrors to Sentry (logger.ts →
      // captureException, tag feature:"pino-mirror", level error), which paged
      // the operator on every push for a condition that self-heals (Sentry
      // 9ccf1d86…). Record an info breadcrumb only (Better Stack drain; below
      // the WARN+ Sentry-mirror threshold, and no `err` key so nothing is
      // captured) and let selfHealNonFastForward own escalation: it mirrors
      // op:self-heal-aborted-dirty (feature-branch) /
      // op:self-heal-aborted-detached-head (detached) / op:self-heal-failed
      // when recovery does NOT happen, and warns op:self-heal-reset (phantom
      // zero-commit reset) / op:self-heal-recovered-diverged (un-pushed
      // default-branch commits branched aside + reset) on success.
      log.info(
        { userId: context.userId, op: context.op, errorClass },
        `kb/${context.op}: ff-only pull blocked — attempting gated self-heal`,
      );
      return await selfHealNonFastForward(
        gitWithInstallationAuth,
        installationId,
        workspacePath,
        log,
        context,
      );
    }

    // Non-self-healable (`sync_failed`) — a genuine failure worth paging.
    log.error(
      { err: syncError, userId: context.userId, op: context.op, errorClass },
      `kb/${context.op}: workspace sync failed`,
    );
    reportSilentFallback(syncError, {
      feature: "kb-route-helpers",
      op: `workspace-sync-${context.op}`,
      // workspacePath omitted — the path embeds raw userId
      // (workspacePath = `<root>/<userId>`) and bypasses the
      // hashExtraUserId top-level rename (Recital 26).
      extra: { userId: context.userId },
      message: `kb/${context.op}: workspace sync failed`,
    });
    return { ok: false, error: syncError, errorClass };
  }
}

/**
 * Gated self-heal for a `non_fast_forward` clone. Fetches the default branch,
 * counts un-pushed local commits (`rev-list --count @{u}..HEAD`), and recovers
 * by branch (one of):
 *  - ZERO un-pushed commits (phantom divergence) → `reset --hard origin/<default>`
 *    (op:self-heal-reset).
 *  - un-pushed commits AND HEAD is the DEFAULT branch → these are un-pushable
 *    auto-sync orphans (session-sync auto-commits `knowledge-base/**` onto the
 *    checked-out default branch; a protected-branch push rejection strands
 *    them). Branch them aside FIRST (`git branch <recovery> HEAD`, preserving
 *    the commit objects on a durable ref), THEN `reset --hard`
 *    (op:self-heal-recovered-diverged). Provably non-destructive: the branch
 *    ref is a gc-root, so the reset discards nothing.
 *  - un-pushed commits on a FEATURE branch (genuine agent work) → abort,
 *    protect (op:self-heal-aborted-dirty).
 *  - detached HEAD (`--abbrev-ref` → literal "HEAD") or an un-countable
 *    rev-list → abort with a distinct op:self-heal-aborted-detached-head slug.
 * Payloads OMIT workspacePath (raw userId) per the Recital 26 omission above.
 */
async function selfHealNonFastForward(
  gitWithInstallationAuth: (
    args: string[],
    installationId: number,
    opts: { cwd: string; timeout: number },
  ) => Promise<Buffer | string>,
  installationId: number,
  workspacePath: string,
  log: Logger,
  context: { userId: string; op: string },
): Promise<SyncWorkspaceResult> {
  const gitOpts = { cwd: workspacePath, timeout: 30_000 };
  try {
    const defaultBranch = await resolveDefaultBranch(
      gitWithInstallationAuth,
      installationId,
      workspacePath,
    );

    await gitWithInstallationAuth(
      ["fetch", "origin", defaultBranch],
      installationId,
      gitOpts,
    );

    // Local-commit guard — mirrors session-sync.ts:200-208.
    const revListOut = await gitWithInstallationAuth(
      ["rev-list", "--count", "@{u}..HEAD"],
      installationId,
      gitOpts,
    );
    const localCommits = parseInt(revListOut.toString().trim(), 10);

    // `recoveryBranch` is set ONLY when we branch un-pushed commits aside on a
    // diverged default-branch clone; it distinguishes the recovered-diverged
    // path from the benign phantom (zero-commit) reset for observability below.
    let recoveryBranch: string | null = null;

    if (Number.isNaN(localCommits) || localCommits > 0) {
      // The clone holds un-pushed local commits (or an un-countable count).
      // Decide by which branch HEAD is on. `--abbrev-ref HEAD` emits the
      // branch's short name, or the literal "HEAD" when detached. Issued
      // through the injected wrapper (NOT a direct shell-out) so the seam
      // stays scriptable; trim the trailing newline before comparing.
      const headRef = (
        await gitWithInstallationAuth(
          ["rev-parse", "--abbrev-ref", "HEAD"],
          installationId,
          gitOpts,
        )
      )
        .toString()
        .trim();

      // Recover ONLY a countable divergence whose HEAD is the default branch:
      // session-sync auto-commits knowledge-base/** onto the checked-out
      // default branch, and a protected-branch push rejection strands those
      // commits as un-pushable orphans — the permanent dead-end this fixes.
      const onDefaultBranch =
        !Number.isNaN(localCommits) && headRef === defaultBranch;

      if (!onDefaultBranch) {
        // Feature branch (genuine agent work targeting a PR), detached HEAD, or
        // an un-countable rev-list — fail safe and do NOT destroy work. A
        // detached HEAD gets a DISTINCT, queryable slug so it is never silently
        // bucketed into the dirty abort (a misclassified detached HEAD would
        // re-trap the very dead-end this fix removes).
        const detached = headRef === "HEAD";
        const abortOp = detached
          ? "self-heal-aborted-detached-head"
          : "self-heal-aborted-dirty";
        log.error(
          { userId: context.userId, op: context.op, localCommits },
          `kb/${context.op}: self-heal aborted — ${
            detached ? "detached HEAD" : "feature-branch"
          } clone holds un-pushed local commits`,
        );
        reportSilentFallback(
          new Error(
            detached
              ? "self-heal aborted: detached HEAD with un-pushed local commits"
              : "self-heal aborted: un-pushed local commits present",
          ),
          {
            feature: "kb-route-helpers",
            op: abortOp,
            extra: { userId: context.userId },
            message: `kb/${context.op}: self-heal aborted (${
              detached ? "detached HEAD" : "un-pushed local commits"
            })`,
          },
        );
        return {
          ok: false,
          error: new Error("non-fast-forward with un-pushed local commits"),
          errorClass: ERROR_CLASS_NON_FAST_FORWARD,
        };
      }

      // Diverged on the default branch: branch the un-pushed commits aside
      // BEFORE the reset so the commit objects live on a durable named ref
      // (recoverable without SSH) and the subsequent `reset --hard` discards
      // NOTHING. The timestamp avoids clobbering a prior recovery branch.
      recoveryBranch = `soleur/recovered-kb-sync-${Date.now()}`;
      await gitWithInstallationAuth(
        ["branch", recoveryBranch, "HEAD"],
        installationId,
        gitOpts,
      );
    }

    // Reset the default branch to origin. Reached either by the phantom
    // (zero-commit) divergence OR after the branch-aside above (un-pushed
    // commits already preserved on `recoveryBranch`).
    await gitWithInstallationAuth(
      ["reset", "--hard", `origin/${defaultBranch}`],
      installationId,
      gitOpts,
    );

    if (recoveryBranch) {
      // Recovered a real divergence — record a distinct, queryable WARN op
      // (recovery rate vs. aborts) that does NOT page.
      log.warn(
        {
          userId: context.userId,
          op: context.op,
          defaultBranch,
          localCommits,
          recoveryBranch,
        },
        `kb/${context.op}: self-heal recovered diverged default-branch clone — branched ${localCommits} un-pushed commit(s) aside to ${recoveryBranch}, reset to origin/${defaultBranch}`,
      );
      warnSilentFallback(
        new Error("workspace self-healed via branch-aside + reset --hard"),
        {
          feature: "kb-route-helpers",
          op: "self-heal-recovered-diverged",
          extra: { userId: context.userId },
          message: `kb/${context.op}: diverged clone recovered (branched ${localCommits} un-pushed commit(s) to ${recoveryBranch}, reset to origin/${defaultBranch})`,
        },
      );
      return { ok: true, recovered: true };
    }

    // Phantom divergence (upstream force-push / corrupted ref). Safe reset, no
    // commits were stranded.
    log.warn(
      { userId: context.userId, op: context.op, defaultBranch },
      `kb/${context.op}: self-heal reset clone to origin/${defaultBranch}`,
    );
    warnSilentFallback(new Error("workspace self-healed via reset --hard"), {
      feature: "kb-route-helpers",
      op: "self-heal-reset",
      extra: { userId: context.userId },
      message: `kb/${context.op}: workspace clone self-healed (reset to origin/${defaultBranch})`,
    });
    return { ok: true, recovered: true };
  } catch (healError) {
    log.error(
      { err: healError, userId: context.userId, op: context.op },
      `kb/${context.op}: self-heal failed`,
    );
    reportSilentFallback(healError, {
      feature: "kb-route-helpers",
      op: "self-heal-failed",
      extra: { userId: context.userId },
      message: `kb/${context.op}: self-heal failed`,
    });
    return {
      ok: false,
      error: healError,
      errorClass: ERROR_CLASS_NON_FAST_FORWARD,
    };
  }
}
