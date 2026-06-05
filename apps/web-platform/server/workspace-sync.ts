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
 * working tree) it attempts a GATED, OBSERVABLE self-heal: reset to
 * `origin/<default>` ONLY when the clone holds ZERO un-pushed local commits —
 * never destroying agent-session work. Returns a {@link SyncWorkspaceResult}.
 *
 * Reporting is split by recoverability so a self-healed abort does NOT page the
 * operator: the self-healable `non_fast_forward` class logs only an info
 * breadcrumb here and lets the self-heal branches own Sentry escalation
 * (op:self-heal-aborted-dirty / op:self-heal-failed on a real freeze,
 * op:self-heal-reset warn on recovery); only the non-self-healable `sync_failed`
 * class emits the error-level `log.error`+`reportSilentFallback` mirror. See
 * Sentry 9ccf1d86… — the unconditional pre-self-heal `log.error({ err })`
 * pino-mirrored to Sentry on every push for a benign, recovered dirty-tree
 * abort (the c4 re-render writes model.likec4.json into the tracked tree).
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
      // Self-healable: a diverged clone OR a dirty working tree (e.g. the c4
      // re-render's tracked-path write to model.likec4.json, or a spurious
      // mirror edit). A blocked ff-only pull that the gated `reset --hard`
      // recovers is BENIGN churn — do NOT emit an error-level mirror here. The
      // pino `log.error({ err })` path mirrors to Sentry (logger.ts →
      // captureException, tag feature:"pino-mirror", level error), which paged
      // the operator on every push for a condition that self-heals (Sentry
      // 9ccf1d86…). Record an info breadcrumb only (Better Stack drain; below
      // the WARN+ Sentry-mirror threshold, and no `err` key so nothing is
      // captured) and let selfHealNonFastForward own escalation: it mirrors
      // op:self-heal-aborted-dirty / op:self-heal-failed when recovery does NOT
      // happen, and warns op:self-heal-reset on success.
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
 * checks for un-pushed local commits, and ONLY resets when there are none.
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

    if (Number.isNaN(localCommits) || localCommits > 0) {
      // Real, un-pushed agent-session work — do NOT destroy it.
      log.error(
        { userId: context.userId, op: context.op, localCommits },
        `kb/${context.op}: self-heal aborted — diverged clone holds un-pushed local commits`,
      );
      reportSilentFallback(
        new Error("self-heal aborted: un-pushed local commits present"),
        {
          feature: "kb-route-helpers",
          op: "self-heal-aborted-dirty",
          extra: { userId: context.userId },
          message: `kb/${context.op}: self-heal aborted (un-pushed local commits)`,
        },
      );
      return {
        ok: false,
        error: new Error("non-fast-forward with un-pushed local commits"),
        errorClass: ERROR_CLASS_NON_FAST_FORWARD,
      };
    }

    // Phantom divergence (upstream force-push / corrupted ref). Safe to reset.
    await gitWithInstallationAuth(
      ["reset", "--hard", `origin/${defaultBranch}`],
      installationId,
      gitOpts,
    );

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
