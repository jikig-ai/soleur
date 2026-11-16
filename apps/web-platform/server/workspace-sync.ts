// Leaf module: `git pull --ff-only` workspace reconcile + gated self-heal,
// extracted from kb-route-helpers so it can be imported by surfaces that must
// stay OUT of the App-Router `next/headers` graph — specifically `c4-writer`,
// which is bundled into the WS/custom server (cc-dispatcher). kb-route-helpers
// re-exports `syncWorkspace`/`SyncWorkspaceResult` so its existing callers are
// unaffected.
//
// Deliberately imports NOTHING from `@/lib/supabase/server` (next/headers).
// Deps: observability (clean), a type-only KbSyncErrorClass, pino's Logger
// type, the token-free local runner (a host-git leaf), and a LAZY
// `@/server/git-auth` import inside syncWorkspace.
import {
  mirrorWarnWithDebounce,
  reportSilentFallback,
  warnSilentFallback,
} from "@/server/observability";
import type { KbSyncErrorClass } from "@/server/session-sync";
import { runWorkspaceLocalGit, type WorkspaceLocalGitRunner } from "@/server/workspace-local-git";
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
 * `git status --porcelain -z --untracked-files=no` output names at least one tracked change, `knowledge-base/` included
 * (#12600, CTO ruling D6b: the R18 KB exemption is gone, since a `reset --hard` erases an in-flight KB edit exactly as it
 * erases a code edit). Untracked files are not listed, and survive a reset unless an incoming tracked path collides.
 */
function hasTrackedChange(out: Buffer | string): boolean {
  return out.toString().split("\0").some((entry) => entry.length >= 4);
}

/** Exit status of a `diff --quiet` (0 = no difference, 1 = difference); any other outcome throws (fail closed). */
async function diffQuietExit(
  runLocal: WorkspaceLocalGitRunner,
  args: string[],
  opts: { cwd: string; timeout: number },
): Promise<0 | 1> {
  try {
    await runLocal(args, opts);
    return 0;
  } catch (err) {
    if ((err as { code?: unknown }).code === 1) return 1;
    throw err;
  }
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
 * working tree) it attempts a GATED, OBSERVABLE self-heal on the default
 * branch: a `reset --hard origin/<default>` that runs only when it can lose
 * nothing (a clean tracked tree, and local commits whose content is already
 * upstream, which are first branched aside to a durable ref). Anything else
 * refuses (see {@link selfHealNonFastForward}). Returns a
 * {@link SyncWorkspaceResult}.
 *
 * Reporting is split by recoverability so a self-healed abort does NOT page the
 * operator: the self-healable `non_fast_forward` class logs only an info
 * breadcrumb here and lets the self-heal branches own Sentry escalation
 * (op:self-heal-aborted-dirty / -detached-head / op:self-heal-failed at error,
 * the designed holds op:self-heal-aborted-dirty-tracked / -held-commits at
 * warning, op:self-heal-reset warn on recovery); only the non-self-healable `sync_failed`
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
      // at error and op:self-heal-aborted-dirty-tracked /
      // op:self-heal-aborted-held-commits at warning when recovery does NOT
      // happen, and warns op:self-heal-reset (phantom zero-commit reset) /
      // op:self-heal-recovered-diverged (upstream-equivalent default-branch
      // commits branched aside + reset) on success.
      log.info(
        { userId: context.userId, op: context.op, errorClass },
        `kb/${context.op}: ff-only pull blocked — attempting gated self-heal`,
      );
      return await selfHealNonFastForward(
        gitWithInstallationAuth,
        runWorkspaceLocalGit,
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

/** Interim `reason` of `self-heal-aborted-held-commits` until the Phase 9 hardened pull-merge (#12718) is called here. */
const HELD_COMMITS_REASON_INTERIM = "merge_not_attempted";

/**
 * Gated self-heal for a `non_fast_forward` clone (#12600, CTO rulings D6-D8). A `reset --hard` runs only when it can
 * lose nothing. In order:
 *  1. `fetch origin <default>` (token-bearing, X3), then read `rev-parse --abbrev-ref HEAD` and
 *     `status --porcelain -z --untracked-files=no` ONCE, above the zero/non-zero commit split, so both arms are gated.
 *  2. HEAD not on the default branch -> abort: detached (op:self-heal-aborted-detached-head) or a feature branch / an
 *     un-countable rev-list (op:self-heal-aborted-dirty). Both arms, the phantom one included (D6f).
 *  3. ANY tracked change, `knowledge-base/` included -> refuse (op:self-heal-aborted-dirty-tracked, warning, D6b).
 *  4. `rev-list --count @{u}..HEAD`:
 *     - 0 (phantom divergence: HEAD is already in origin's history) -> `reset --hard origin/<default>`
 *       (op:self-heal-reset);
 *     - > 0 -> reset (with the branch-aside to `soleur/recovered-kb-sync-*`, op:self-heal-recovered-diverged) ONLY when
 *       the local commits carry no content upstream lacks: `diff --quiet origin/D...HEAD -- . ':(exclude)knowledge-base/'`
 *       exits 0 AND the `knowledge-base` trees of HEAD and origin/D are equal (the squash-merged side-PR case);
 *       otherwise refuse (op:self-heal-aborted-held-commits, warning, tags `held_kind` = nonkb | kb and `reason`).
 * Every local verb runs token-free through `runLocal` (D6d); only `fetch origin` and `resolveDefaultBranch` carry the
 * token. Every emit passes a null error and carries its details in tags / extra (D8, the #8629 Error-path tag loss).
 * The two refusals are designed holds the next session-start pull resolves, so they warn, debounced per workspace (D7,
 * D6e); `self-heal-failed` stays error. Payloads OMIT workspacePath (raw userId) per the Recital 26 omission above; the
 * debounce key is in-process only.
 */
async function selfHealNonFastForward(
  gitWithInstallationAuth: (
    args: string[],
    installationId: number,
    opts: { cwd: string; timeout: number },
  ) => Promise<Buffer | string>,
  runLocal: WorkspaceLocalGitRunner,
  installationId: number,
  workspacePath: string,
  log: Logger,
  context: { userId: string; op: string },
): Promise<SyncWorkspaceResult> {
  const gitOpts = { cwd: workspacePath, timeout: 30_000 };
  const extra = { userId: context.userId };
  const refuse = (reason: string): SyncWorkspaceResult => ({
    ok: false,
    error: new Error(reason),
    errorClass: ERROR_CLASS_NON_FAST_FORWARD,
  });
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

    // D6a: both reads hoisted above the zero/non-zero commit split. `--abbrev-ref HEAD` emits the branch's short name,
    // or the literal "HEAD" when detached. A failing read throws into the catch below (fail closed: no reset).
    const headRef = (await runLocal(["rev-parse", "--abbrev-ref", "HEAD"], gitOpts)).toString().trim();
    const statusOut = await runLocal(["status", "--porcelain", "-z", "--untracked-files=no"], gitOpts);

    // Local-commit count. Read before the branch check so an un-countable count (NaN) aborts like a feature branch.
    let localCommits = Number.NaN;
    if (headRef !== "HEAD") {
      localCommits = parseInt((await runLocal(["rev-list", "--count", "@{u}..HEAD"], gitOpts)).toString().trim(), 10);
    }

    // D6f: recover ONLY on the default branch, on BOTH arms. A phantom `reset --hard origin/<D>` on a feature branch
    // would move that branch onto the default branch. A detached HEAD gets a DISTINCT, queryable slug so it is never
    // bucketed into the feature-branch abort.
    if (Number.isNaN(localCommits) || headRef !== defaultBranch) {
      const detached = headRef === "HEAD";
      const abortOp = detached ? "self-heal-aborted-detached-head" : "self-heal-aborted-dirty";
      const what = detached ? "detached HEAD" : "not on the default branch";
      log.error({ userId: context.userId, op: context.op, localCommits }, `kb/${context.op}: self-heal aborted — ${what}`);
      reportSilentFallback(null, {
        feature: "kb-route-helpers",
        op: abortOp,
        tags: { head: detached ? "detached" : "non_default" },
        extra,
        message: `kb/${context.op}: self-heal aborted (${what})`,
      });
      return refuse(`non-fast-forward clone ${what}`);
    }

    // D6b: any tracked change refuses, knowledge-base/ included. The stall ends at the next session-start
    // `pull --no-rebase --autostash`; #5221 keeps the broader recovery-and-lock work.
    if (hasTrackedChange(statusOut)) {
      const op = "self-heal-aborted-dirty-tracked";
      log.warn({ userId: context.userId, op: context.op, localCommits }, `kb/${context.op}: self-heal aborted — tracked changes in the working tree`);
      mirrorWarnWithDebounce(
        null,
        { feature: "kb-route-helpers", op, extra, message: `kb/${context.op}: self-heal aborted (tracked changes in the working tree)` },
        workspacePath,
        op,
      );
      return refuse("non-fast-forward with tracked changes in the working tree");
    }

    // `recoveryBranch` is set ONLY when un-pushed commits are branched aside; it distinguishes the recovered-diverged
    // path from the phantom (zero-commit) reset for observability below.
    let recoveryBranch: string | null = null;

    if (localCommits > 0) {
      // D6c: reset only when the local commits' content is already upstream. Tree-to-tree diffs: no worktree read, no
      // clean/smudge filter; `--no-ext-diff --no-textconv` keep any configured diff helper out. The KB check compares
      // the two `knowledge-base` trees (equal trees <=> no diff under that pathspec, both-absent included).
      const nonKbHeld =
        (await diffQuietExit(
          runLocal,
          ["diff", "--quiet", "--no-ext-diff", "--no-textconv", `origin/${defaultBranch}...HEAD`, "--", ".", ":(exclude)knowledge-base/"],
          gitOpts,
        )) === 1;
      const kbHeld =
        !nonKbHeld &&
        (await diffQuietExit(
          runLocal,
          ["diff", "--quiet", "--no-ext-diff", "--no-textconv", `origin/${defaultBranch}`, "HEAD", "--", "knowledge-base/"],
          gitOpts,
        )) === 1;
      if (nonKbHeld || kbHeld) {
        // Phase 9 (D6c): call the hardened pull-merge routine (X1) here; on any X1 refusal emit this op with its reason.
        const op = "self-heal-aborted-held-commits";
        const heldKind = nonKbHeld ? "nonkb" : "kb";
        log.warn(
          { userId: context.userId, op: context.op, localCommits, heldKind },
          `kb/${context.op}: self-heal aborted — local commits hold content upstream lacks`,
        );
        mirrorWarnWithDebounce(
          null,
          {
            feature: "kb-route-helpers",
            op,
            tags: { held_kind: heldKind, reason: HELD_COMMITS_REASON_INTERIM },
            extra: { ...extra, localCommits },
            message: `kb/${context.op}: self-heal aborted (held ${heldKind} commits)`,
          },
          workspacePath,
          op,
        );
        return refuse("non-fast-forward with held local commits");
      }

      // The local commits' content is upstream (a squash-merged side PR): keep the commit objects on a durable named
      // ref (recoverable without SSH), then reset. The timestamp avoids clobbering a prior recovery branch.
      recoveryBranch = `soleur/recovered-kb-sync-${Date.now()}`;
      await runLocal(["branch", recoveryBranch, "HEAD"], gitOpts);
    }

    // Reached by the phantom (zero-commit) divergence OR after the branch-aside above, on a clean tracked tree.
    await runLocal(["reset", "--hard", `origin/${defaultBranch}`], gitOpts);

    if (recoveryBranch) {
      log.warn(
        { userId: context.userId, op: context.op, defaultBranch, localCommits, recoveryBranch },
        `kb/${context.op}: self-heal recovered diverged default-branch clone — branched ${localCommits} commit(s) aside to ${recoveryBranch}, reset to origin/${defaultBranch}`,
      );
      warnSilentFallback(null, {
        feature: "kb-route-helpers",
        op: "self-heal-recovered-diverged",
        extra: { ...extra, localCommits },
        message: `kb/${context.op}: diverged clone recovered (branched ${localCommits} commit(s) aside, reset to origin/${defaultBranch})`,
      });
      return { ok: true, recovered: true };
    }

    // Phantom divergence (upstream force-push / corrupted ref). Safe reset, no commits were stranded.
    log.warn(
      { userId: context.userId, op: context.op, defaultBranch },
      `kb/${context.op}: self-heal reset clone to origin/${defaultBranch}`,
    );
    warnSilentFallback(null, {
      feature: "kb-route-helpers",
      op: "self-heal-reset",
      extra,
      message: `kb/${context.op}: workspace clone self-healed (reset to origin/${defaultBranch})`,
    });
    return { ok: true, recovered: true };
  } catch (healError) {
    // No `err` key (the pino error mirror would capture it untagged first, #8629) and no message (argv); the name only.
    const errName = healError instanceof Error ? healError.name : typeof healError;
    log.error({ userId: context.userId, op: context.op, errName }, `kb/${context.op}: self-heal failed`);
    reportSilentFallback(null, {
      feature: "kb-route-helpers",
      op: "self-heal-failed",
      extra: { ...extra, errName },
      message: `kb/${context.op}: self-heal failed`,
    });
    return {
      ok: false,
      error: healError,
      errorClass: ERROR_CLASS_NON_FAST_FORWARD,
    };
  }
}
