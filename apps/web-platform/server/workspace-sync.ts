// Leaf module: `git pull --ff-only` workspace reconcile + gated self-heal,
// extracted from kb-route-helpers so it can be imported by surfaces that must
// stay OUT of the App-Router `next/headers` graph — specifically `c4-writer`,
// which is bundled into the WS/custom server (cc-dispatcher). kb-route-helpers
// re-exports `syncWorkspace`/`SyncWorkspaceResult` so its existing callers are
// unaffected.
//
// Deliberately imports NOTHING from `@/lib/supabase/server` (next/headers).
// Deps: observability (clean), type-only KbSyncErrorClass / KbPullHeldReason / KbPullWriter, pino's Logger type, the
// token-free local runner (a host-git leaf), the collision precheck (workspace-collision, node:fs/promises), two
// import-free leaves (branch-validation, kb-root), a LAZY `@/server/git-auth` import inside syncWorkspace, and a LAZY
// kb-sync-held import for the recovered-branch prefix at the branch-aside (its logger stays out of module scope). The held-commits merge (#12718, D27) imports its modules LAZILY inside
// that branch: the pull leaves (kb-sync-pull, kb-sync-remote), the isolated-dir creator and dispose leaf, the held-count
// leaf (kb-sync-held-refresh), the service client for system callers (D43), and the connected-repo guarded writer and
// lock (server/connected-repo-git.ts). None of them reaches kb-sync-publish or push-branch at runtime: connected-repo-git
// imports kb-sync-publish for a type only (census row D25(3)).
import {
  mirrorWarnWithDebounce,
  mirrorWithDebounce,
  reportSilentFallback,
  warnSilentFallback,
} from "@/server/observability";
import type { KbSyncErrorClass } from "@/server/session-sync";
import type { KbPullHeldReason, KbPullWriter } from "@/server/kb-sync-pull";
import { runWorkspaceLocalGit, type WorkspaceLocalGitRunner } from "@/server/workspace-local-git";
import type { Logger } from "pino";
import { firstAppFrame } from "@/server/error-frame";
import { validateBranchFormat } from "@/server/branch-validation";
import { hasUntrackedCollision } from "@/server/workspace-collision";
import { KB_ROOT } from "./kb-root";

// Re-declared as local constants typed by the shared union (the union is the
// source of truth; these are the literal members, NOT a new union). Kept local
// so this module stays free of a runtime session-sync import.
const ERROR_CLASS_NON_FAST_FORWARD: KbSyncErrorClass = "non_fast_forward";
const ERROR_CLASS_SYNC_FAILED: KbSyncErrorClass = "sync_failed";

/**
 * The designed holds of the self-heal (#12600, CTO ruling D16): the workspace keeps local state that is not on GitHub
 * yet, so it was deliberately not updated. Set ONLY by the three refusals (`self-heal-aborted-held-commits`,
 * `-dirty-tracked`, `-untracked-collision`); the branch aborts and `self-heal-failed` leave it unset. A KB write route
 * that sees it answers success plus `workspace_sync: "pending"` (the write already landed on GitHub).
 */
export type SyncWorkspaceHeld = "held_commits" | "dirty_tracked" | "untracked_collision";

export type SyncWorkspaceResult =
  | { ok: true; recovered?: boolean }
  | { ok: false; error: unknown; errorClass: KbSyncErrorClass; held?: SyncWorkspaceHeld };

/**
 * Who asked for the sync. A route caller acts for a signed-in user (`userId`, the tenant-scoped repo read). A background
 * job (cron reconcile, webhook reconcile) is `system: true` (CTO ruling D43): no user acts, so the held-commits merge
 * reads `repo_url` through the service client keyed on the job's own `workspaceId` (server-resolved, never user input),
 * and the logs carry `workspaceId` instead of a `userId`.
 */
export type SyncWorkspaceContext = {
  /** The workspace whose repo row names the literal URL of the held-commits merge (#12718, D27). */
  workspaceId: string;
  op: "delete" | "rename" | "upload" | "push" | "manual";
} & ({ userId: string; system?: undefined } | { system: true; userId?: undefined });

/**
 * D38(4): the self-heal's total budget, measured from the self-heal's start. A route caller (KB routes, c4-writer) answers
 * the user's request, so on expiry it answers the existing `pending`; a background caller has the pre-range pull bound.
 */
export const SELF_HEAL_BUDGET_MS = { route: 15_000, background: 60_000 } as const;
/**
 * D38(3): the held-commits merge (and its object hand-over) starts only with at least this much budget left. A started
 * merge is never cut short: it keeps its own child timeout, since killing it is the stranded mid-merge state D36(c) pins.
 */
export const SELF_HEAL_MERGE_START_MIN_MS = { route: 5_000, background: 20_000 } as const;

/**
 * Classify a failed-git error into a {@link KbSyncErrorClass}. Two distinct
 * `git pull --ff-only` aborts (diverged clone, dirty working tree) are
 * self-healable via the same gated `reset --keep refs/remotes/origin/<default>`,
 * so both map to `non_fast_forward`; everything else is `sync_failed`.
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
 * (#12600, CTO ruling D6b: the R18 KB exemption is gone, since a hard reset erases an in-flight KB edit exactly as it
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
 * Resolve the workspace clone's default branch (e.g. `main`) from `git symbolic-ref refs/remotes/origin/HEAD`, a LOCAL
 * read, so it runs token-free through `runLocal` (#12600, CTO ruling D15(d), amending D6(d)). The FULL target refname is
 * parsed, never `--short`: an agent-made `refs/heads/origin/main` makes `origin/main` ambiguous and `--short` then prints
 * `remotes/origin/main`. Falls back to `main` when the symbolic ref is missing or names something else, and (D23) when the
 * name is unresolvable: it starts with `-` (a full refname may, and the agent can write this symref) or fails
 * {@link validateBranchFormat}. That fallback is the existing fail-closed path: a clone not on `main` then aborts at the
 * branch check, and a missing `refs/remotes/origin/main` fails the count read.
 */
async function resolveDefaultBranch(runLocal: WorkspaceLocalGitRunner, workspacePath: string): Promise<string> {
  try {
    const out = await runLocal(["symbolic-ref", "refs/remotes/origin/HEAD"], { cwd: workspacePath, timeout: 30_000 });
    const ref = out.toString().trim(); // e.g. "refs/remotes/origin/main"
    const prefix = "refs/remotes/origin/";
    const name = ref.startsWith(prefix) ? ref.slice(prefix.length) : "";
    if (!name || name.startsWith("-")) return "main";
    validateBranchFormat(name);
    return name;
  } catch {
    return "main";
  }
}

/**
 * Pull the workspace to sync local files with the remote repo after a
 * successful GitHub mutation. On a `non_fast_forward` (diverged clone OR dirty
 * working tree) it attempts a GATED, OBSERVABLE self-heal on the default
 * branch: a `reset --keep refs/remotes/origin/<default>` that runs only when it
 * loses no tracked, committed, untracked or ignored file (a clean tracked tree,
 * local commits whose content is already upstream, which are first branched
 * aside to a durable ref, and nothing on disk in the reset's way). Anything else
 * refuses (see {@link selfHealNonFastForward}). Returns a
 * {@link SyncWorkspaceResult}; the three designed holds set `held` (D16).
 *
 * Reporting is split by recoverability so a self-healed abort does NOT page the
 * operator: the self-healable `non_fast_forward` class logs only an info
 * breadcrumb here and lets the self-heal branches own Sentry escalation
 * (op:self-heal-aborted-dirty / -detached-head / op:self-heal-failed at error,
 * the designed holds op:self-heal-aborted-dirty-tracked / -held-commits /
 * -untracked-collision at warning, op:self-heal-reset warn on recovery); only the non-self-healable `sync_failed`
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
  context: SyncWorkspaceContext,
): Promise<SyncWorkspaceResult> {
  const { gitWithInstallationAuth } = await import("@/server/git-auth");
  const who = actor(context);
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
      // that the gated `reset --keep`
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
      // op:self-heal-aborted-held-commits /
      // op:self-heal-aborted-untracked-collision at warning when recovery does NOT
      // happen, and warns op:self-heal-reset (phantom zero-commit reset) /
      // op:self-heal-recovered-diverged (upstream-equivalent default-branch
      // commits branched aside + reset) on success.
      log.info({ ...who, op: context.op, errorClass }, `kb/${context.op}: ff-only pull blocked — attempting gated self-heal`);
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
    log.error({ err: syncError, ...who, op: context.op, errorClass }, `kb/${context.op}: workspace sync failed`);
    reportSilentFallback(syncError, {
      feature: "kb-route-helpers",
      op: `workspace-sync-${context.op}`,
      // workspacePath omitted — the path embeds raw userId
      // (workspacePath = `<root>/<userId>`) and bypasses the
      // hashExtraUserId top-level rename (Recital 26).
      extra: who,
      message: `kb/${context.op}: workspace sync failed`,
    });
    return { ok: false, error: syncError, errorClass };
  }
}

/** The log and mirror identity of a sync (D43): the user for a route caller, the workspace for a system job. */
function actor(context: SyncWorkspaceContext): { userId: string } | { workspaceId: string } {
  return context.system ? { workspaceId: context.workspaceId } : { userId: context.userId };
}

/** The self-heal's clock (D38(4)): the budget left, and whether the held-commits merge may still start. */
interface SelfHealBudget {
  remaining(): number;
  mayStartMerge(): boolean;
}

function selfHealBudget(context: SyncWorkspaceContext): SelfHealBudget {
  const kind = context.system ? "background" : "route";
  const startedAt = Date.now();
  const remaining = () => SELF_HEAL_BUDGET_MS[kind] - (Date.now() - startedAt);
  return { remaining, mayStartMerge: () => remaining() >= SELF_HEAL_MERGE_START_MIN_MS[kind] };
}

/** Thrown by the budget-gated writer in place of a hand-over or merge child that may no longer start (D38(3)). */
class SelfHealDeadline extends Error {
  constructor() {
    super("self-heal budget left too little time to start the merge");
    this.name = "SelfHealDeadline";
  }
}

/**
 * The guarded writer with D38(3)'s start gate: the hand-over (`unpack`) and the merge child start only while the budget
 * allows; a refused start sets `hit` and throws (the pull maps the throw to `handover_failed` / `merge_refused`, which
 * the caller then reports as `pull_deadline`). Tracking-ref and branch writes pass through untouched.
 */
function budgetGatedWriter(inner: KbPullWriter, budget: SelfHealBudget, hit: { deadline: boolean }): KbPullWriter {
  const gate = (): void => {
    if (!budget.mayStartMerge()) {
      hit.deadline = true;
      throw new SelfHealDeadline();
    }
  };
  return {
    unpack: async (pack) => {
      gate();
      return inner.unpack(pack);
    },
    setTracking: (branch, sha) => inner.setTracking(branch, sha),
    casBranch: (branch, next, prev) => inner.casBranch(branch, next, prev),
    merge: async (target) => {
      gate();
      return inner.merge(target);
    },
  };
}

/** What the held-commits merge reported, beyond its reason: the isolated-dir refusal's own reason (obs F4). */
interface HeldMergeDiag {
  isolatedReason?: string;
}

/** The literal `https://github.com/<owner>/<repo>.git` of the workspace, or null when it cannot be read (`remote_state`). */
async function resolveSelfHealRepoUrl(context: SyncWorkspaceContext): Promise<string | null> {
  const remoteMod = await import("@/server/kb-sync-remote");
  if (!context.system) {
    try {
      return (await remoteMod.resolveRepoUrl(context.userId, context.workspaceId)).url;
    } catch (err) {
      if (err instanceof remoteMod.KbRemoteError) return null;
      throw err;
    }
  }
  // D43: a system job has no user to mint a tenant token for. Service read keyed on the job's own workspace id (from the
  // job's own query, never user input, R3), connected rows only. A failed read is `remote_state`, like the tenant read's.
  try {
    const [{ createServiceClient }, { normalizeRepoUrl }] = await Promise.all([
      import("@/lib/supabase/service"),
      import("@/lib/repo-url"),
    ]);
    const { data, error } = await createServiceClient()
      .from("workspaces")
      .select("repo_url")
      .eq("id", context.workspaceId)
      .eq("repo_status", "ready")
      .maybeSingle();
    const raw = (data as { repo_url?: unknown } | null)?.repo_url;
    if (error || typeof raw !== "string") return null;
    const { owner, repo } = remoteMod.parseOwnerRepo(normalizeRepoUrl(raw));
    return owner && repo ? `https://github.com/${owner}/${repo}.git` : null;
  } catch {
    return null;
  }
}

/**
 * The shared skeleton of the two held-arm git paths: the repo URL, HEAD, one isolated directory disposed in `finally`.
 * `remote_state` / `isolated_refused` when either cannot be had.
 */
async function onIsolatedDir(
  workspacePath: string,
  context: SyncWorkspaceContext,
  diag: HeldMergeDiag,
  body: (a: {
    isolated: import("@/server/git-isolated-push-dir").IsolatedPushDirHandle;
    url: string;
    head: { sha: string; refName: string | null };
  }) => Promise<KbPullHeldReason>,
): Promise<KbPullHeldReason> {
  const [{ readWorkspaceHeadRef }, { createIsolatedPushDir, IsolatedPushDirRefusal }, { disposeIsolated }] = await Promise.all([
    import("@/server/approval/workspace-head"),
    import("@/server/git-isolated-push-dir"),
    import("@/server/git-isolated-dispose"),
  ]);
  const url = await resolveSelfHealRepoUrl(context);
  if (url === null) return "remote_state";
  const head = readWorkspaceHeadRef(workspacePath);
  let isolated: ReturnType<typeof createIsolatedPushDir> | undefined;
  try {
    try {
      isolated = createIsolatedPushDir(workspacePath);
    } catch (err) {
      if (err instanceof IsolatedPushDirRefusal) {
        diag.isolatedReason = err.reason;
        return "isolated_refused";
      }
      throw err;
    }
    return await body({ isolated, url, head });
  } finally {
    disposeIsolated(isolated);
  }
}

/** The four self-heal outcomes that write the held count (D39(a)), with the pull-blocked state each one leaves (D42). */
const HELD_COUNT_WRITES: Partial<Record<KbPullHeldReason, "merge_conflict_precheck" | "untracked_collision" | null>> = {
  merged: null,
  up_to_date: null,
  merge_conflict_precheck: "merge_conflict_precheck",
  untracked_collision: "untracked_collision",
};

/**
 * D27 (amending D6(c)), D37: the held-commits branch merges the verified remote tip instead of refusing, on the hardened
 * arm (server/kb-sync-pull.ts `mergeVerifiedDefault`, with this caller's token-free `merge-tree` pre-check). The writer is
 * the second pinned shape, WITHOUT `--autostash` (D37(2)): the tree was gated clean, so a path dirtied after the gate makes
 * git refuse the merge, and git never stashes and never resets. The writer's entry check (D37(1), server/connected-repo-git.ts)
 * never starts a merge over an unfinished one. A precheck/merge parity break caused by same-uid workspace config is the
 * D26(3) residual. Runs under the same-host workspace lock (D38(6)); the lock wait and every step before the merge count
 * against the self-heal budget, and the hand-over and merge start only while it allows (D38(3)). After `merged`,
 * `up_to_date`, `merge_conflict_precheck` or the writer's `untracked_collision`, the held count is rewritten on this run's
 * isolated dir and `T`, with the pull-blocked state (D39(a), D42). No stamp, no side-tip adoption; the caller reports once.
 */
async function mergeHeldCommits(
  installationId: number,
  workspacePath: string,
  context: SyncWorkspaceContext,
  budget: SelfHealBudget,
  diag: HeldMergeDiag,
): Promise<KbPullHeldReason> {
  const [{ mergeVerifiedDefault }, { kbPullWriter, withWorkspaceGitLock }, { writeHeldFromIsolated }] = await Promise.all([
    import("@/server/kb-sync-pull"),
    import("@/server/connected-repo-git"),
    import("@/server/kb-sync-held-refresh"),
  ]);
  return withWorkspaceGitLock(workspacePath, async () => {
    if (!budget.mayStartMerge()) return "pull_deadline";
    return onIsolatedDir(workspacePath, context, diag, async ({ isolated, url, head }) => {
      const hit = { deadline: false };
      const r = await mergeVerifiedDefault({
        isolated,
        installationId,
        url,
        headSha: head.sha,
        refName: head.refName,
        writer: budgetGatedWriter(kbPullWriter(workspacePath, { autostash: false }), budget, hit),
        precheck: true,
      });
      const reason: KbPullHeldReason = hit.deadline ? "pull_deadline" : r.reason;
      const pullBlocked = HELD_COUNT_WRITES[reason];
      // X5: no count when HEAD is not the remote's default branch (paths that never attempted a count write nothing).
      if (pullBlocked !== undefined && r.remote && head.refName === `refs/heads/${r.remote.defaultBranch}`) {
        const { readWorkspaceHeadRef } = await import("@/server/approval/workspace-head");
        await writeHeldFromIsolated({
          isolated,
          workspacePath,
          workspaceId: context.workspaceId,
          T: r.remote.tip,
          // the merge moved HEAD: count on the HEAD it left
          headSha: reason === "merged" ? readWorkspaceHeadRef(workspacePath).sha : head.sha,
          checkedAt: r.remote.readAt,
          pullBlocked,
        });
      }
      return reason;
    });
  });
}

/**
 * D42: the self-heal's own untracked-collision refusal on the held arm (before any merge) still records the state, so a
 * cc workspace is not frozen silently: one hardened `ls-remote` for `T`, the count on HEAD, `pullBlocked =
 * untracked_collision`. Nothing is merged or handed over. Never throws (the refusal stands whatever happens here).
 */
async function recordCollisionHeld(installationId: number, workspacePath: string, context: SyncWorkspaceContext): Promise<void> {
  try {
    const [{ readRemoteState, KbRemoteError }, { writeHeldFromIsolated }] = await Promise.all([
      import("@/server/kb-sync-remote"),
      import("@/server/kb-sync-held-refresh"),
    ]);
    await onIsolatedDir(workspacePath, context, {}, async ({ isolated, url, head }) => {
      let remote: Awaited<ReturnType<typeof readRemoteState>> = null;
      try {
        remote = await readRemoteState(isolated, installationId, url);
      } catch (err) {
        if (!(err instanceof KbRemoteError)) throw err;
      }
      if (!remote || head.refName !== `refs/heads/${remote.defaultBranch}`) return "remote_state";
      await writeHeldFromIsolated({
        isolated,
        workspacePath,
        workspaceId: context.workspaceId,
        T: remote.tip,
        headSha: head.sha,
        checkedAt: remote.readAt,
        pullBlocked: "untracked_collision",
      });
      return "untracked_collision";
    });
  } catch {
    // display-only state: the refusal itself is already decided and reported by the caller
  }
}

/**
 * Structural 3a#9: what each held-commits merge result means, honestly. `ok` (merged, or the remote is already in HEAD),
 * `collision` (the writer found an untracked or ignored entry in the merge's way: the D15(a) hold), `not_started` (the
 * merge was not started: it would conflict, or exceeds a limit or the budget), `mid_merge` (an unfinished merge is in the
 * workspace, or this merge left one), `failed` (the remote tip could not be read, verified or handed over). The side-tip
 * reasons are never produced by the default-branch merge and fall in `failed`. Every non-`ok` keeps the held-commits hold.
 */
type HeldMergeVerdict = "ok" | "collision" | "not_started" | "mid_merge" | "failed";
const HELD_MERGE_VERDICT: Record<KbPullHeldReason, HeldMergeVerdict> = {
  merged: "ok",
  up_to_date: "ok",
  untracked_collision: "collision",
  merge_conflict_precheck: "not_started",
  walk_cap: "not_started",
  handover_too_large: "not_started",
  pull_deadline: "not_started",
  unresolved_merge: "mid_merge",
  merge_conflict: "mid_merge",
  autostash_conflict: "mid_merge",
  merge_unverified: "mid_merge",
  remote_state: "failed",
  fetch_failed: "failed",
  isolated_refused: "failed",
  tip_mismatch: "failed",
  shallow_changed: "failed",
  handover_failed: "failed",
  merge_refused: "failed",
  non_default_branch: "failed",
  pull_unexpected: "failed",
  side_not_kb_only: "failed",
  side_pr_unknown: "failed",
  side_declined: "failed",
  side_pr_created: "failed",
  side_linked: "failed",
  side_conflict: "failed",
  side_pr_create_failed: "failed",
};

/** The refusal message of a non-`ok`, non-collision verdict (no paths, no shas). */
function heldMergeWhat(verdict: "not_started" | "mid_merge" | "failed", heldKind: string): string {
  switch (verdict) {
    case "not_started":
      return `held ${heldKind} commits; the merge with GitHub was not started`;
    case "mid_merge":
      return `held ${heldKind} commits; the workspace is mid-merge (an unfinished merge)`;
    case "failed":
      return `held ${heldKind} commits; the GitHub tip could not be read or handed over`;
    default: {
      const never: never = verdict;
      return never;
    }
  }
}

/**
 * The full remote-tracking refname of the default branch: never `@{u}` (resolved from the agent-writable
 * `branch.<D>.remote` / `.merge`, CTO ruling D15(b)) and never a bare `origin/<D>` (DWIM resolves `refs/heads/origin/<D>`
 * and tags before `refs/remotes/`, D15(c)). Used in the rev-list, both content diffs, the precheck and the reset.
 */
const remoteTrackingRef = (defaultBranch: string): string => `refs/remotes/origin/${defaultBranch}`;

/**
 * Gated self-heal for a `non_fast_forward` clone (#12600, CTO rulings D6-D8, D15, D16, D20). The `reset --keep` runs only
 * when it loses no tracked, committed, untracked or ignored file. In order:
 *  1. `symbolic-ref` (token-free, D15d), `fetch origin +refs/heads/<D>:refs/remotes/origin/<D>` (token-bearing, X3;
 *     an explicit refspec so D is never a bare argv word, D23), then `rev-parse --abbrev-ref HEAD`
 *     and `status --porcelain -z --untracked-files=no` ONCE, above the zero/non-zero commit split, so both arms are gated.
 *  2. `rev-list --count refs/remotes/origin/<D>..HEAD` (D15b), then the branch check, on both arms (D6f): a detached
 *     HEAD aborts as op:self-heal-aborted-detached-head; a feature branch (tag head=non_default) or an un-countable count
 *     (tag head=uncountable, its own message) as op:self-heal-aborted-dirty. Both at error, debounced per workspace
 *     (D15e). The `-dirty` slug is a MISNOMER kept for continuity (4 test consumers, no alert keys on it): it never means
 *     a dirty tree, which is `-dirty-tracked`.
 *  3. ANY tracked change, `knowledge-base/` included -> refuse (op:self-heal-aborted-dirty-tracked, held dirty_tracked).
 *  4. With local commits whose content is NOT upstream (`diff --quiet refs/remotes/origin/D...HEAD -- .
 *     ':(exclude)knowledge-base/'` exits 1, or the `knowledge-base` trees of HEAD and the remote-tracking ref differ): D27,
 *     the untracked-collision precheck (a hit also records the count with `pullBlocked`, D42), then the hardened merge of
 *     the verified remote tip (`mergeHeldCommits`: token-free `merge-tree` pre-check, no `--autostash`,
 *     `--no-overwrite-ignore`, no stamp, no adoption). `merged` and `up_to_date` return ok with the held commits kept
 *     (D37(3)); the writer's `untracked_collision` is the step-5 refusal (arm diverged); any other reason is
 *     op:self-heal-aborted-held-commits, tags `held_kind` = nonkb | kb, `reason` (the pull reason, e.g.
 *     `merge_conflict_precheck`) and, for a refused isolated dir, `isolated_reason` (obs F4), debounce class
 *     `<op>:<held_kind>:<reason>` (D20, obs F2), held held_commits, the message naming the verdict (structural 3a#9).
 *     Content that IS upstream (the squash-merged side-PR case) goes on to step 5.
 *  5. The untracked-collision precheck ({@link hasUntrackedCollision}) on both arms, BEFORE the branch-aside so a refusal
 *     leaves no recovery branch: op:self-heal-aborted-untracked-collision, tag `arm` = phantom | diverged, no paths in
 *     tags or extra, held untracked_collision.
 *  6. With local commits, the branch-aside to `soleur/recovered-kb-sync-*`; then `reset --keep refs/remotes/origin/<D>`
 *     (op:self-heal-recovered-diverged, or op:self-heal-reset on the phantom arm).
 * Every local verb runs token-free through `runLocal`; only `fetch origin` and the `pull --ff-only` carry the token on the
 * legacy arm (X3), and the held-commits merge's `ls-remote` and fetch on the hardened arm. Every
 * emit passes a null error and carries its details in tags / extra (D8, the #8629 Error-path tag loss); `self-heal-failed`
 * adds `extra.frame` (D20). The three refusals are designed holds the next session-start pull resolves, so they warn,
 * debounced per workspace (D7, D6e). Payloads OMIT workspacePath (raw userId) per the Recital 26 omission above; the
 * debounce key is in-process only. A system caller (D43) logs and mirrors `workspaceId` where a route caller has `userId`.
 * The budget (D38(4)) starts here; on expiry before the merge the result is the held-commits hold (the route's `pending`).
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
  context: SyncWorkspaceContext,
): Promise<SyncWorkspaceResult> {
  const budget = selfHealBudget(context);
  const gitOpts = { cwd: workspacePath, timeout: 30_000 };
  const who = actor(context);
  const extra = who;
  const refuse = (reason: string, held?: SyncWorkspaceHeld): SyncWorkspaceResult => ({
    ok: false,
    error: new Error(reason),
    errorClass: ERROR_CLASS_NON_FAST_FORWARD,
    ...(held ? { held } : {}),
  });
  /** D15(a): an untracked or ignored entry is in the way of the incoming tree: refuse, before any branch-aside or merge. */
  const refuseUntrackedCollision = (arm: "diverged" | "phantom"): SyncWorkspaceResult => {
    const op = "self-heal-aborted-untracked-collision";
    log.warn(
      { ...who, op: context.op, arm },
      `kb/${context.op}: self-heal aborted — an untracked or ignored file is in the reset's way`,
    );
    mirrorWarnWithDebounce(
      null,
      { feature: "kb-route-helpers", op, tags: { arm }, extra, message: `kb/${context.op}: self-heal aborted (an untracked or ignored file is in the reset's way)` },
      workspacePath,
      op,
    );
    return refuse("non-fast-forward with an untracked or ignored file in the reset's way", "untracked_collision");
  };
  try {
    const defaultBranch = await resolveDefaultBranch(runLocal, workspacePath);
    const target = remoteTrackingRef(defaultBranch);

    // D23: an explicit refspec, so the agent-writable D never sits in argv where git parses an option. Forced (`+`) as
    // the clone's configured `+refs/heads/*:refs/remotes/origin/*` is: a non-forced refspec exits 1 (`! [rejected]`)
    // after an upstream force-push (measured, git 2.56), which is the phantom divergence this self-heal resets.
    await gitWithInstallationAuth(
      ["fetch", "origin", `+refs/heads/${defaultBranch}:${target}`],
      installationId,
      gitOpts,
    );

    // D6a: both reads hoisted above the zero/non-zero commit split. `--abbrev-ref HEAD` emits the branch's short name,
    // or the literal "HEAD" when detached. A failing read throws into the catch below (fail closed: no reset).
    const headRef = (await runLocal(["rev-parse", "--abbrev-ref", "HEAD"], gitOpts)).toString().trim();
    const statusOut = await runLocal(["status", "--porcelain", "-z", "--untracked-files=no"], gitOpts);

    // Local-commit count against the remote-tracking ref (D15b). Read before the branch check so an un-countable count
    // (NaN) aborts like a feature branch.
    let localCommits = Number.NaN;
    if (headRef !== "HEAD") {
      localCommits = parseInt((await runLocal(["rev-list", "--count", `${target}..HEAD`], gitOpts)).toString().trim(), 10);
    }

    // D6f: recover ONLY on the default branch, on BOTH arms. A phantom reset on a feature branch would move that branch
    // onto the default branch. A detached HEAD gets a DISTINCT, queryable slug so it is never bucketed into the
    // feature-branch abort; an un-countable count keeps the `-dirty` slug with its own tag and message (D15e).
    if (headRef === "HEAD" || headRef !== defaultBranch || Number.isNaN(localCommits)) {
      const head = headRef === "HEAD" ? "detached" : headRef !== defaultBranch ? "non_default" : "uncountable";
      const abortOp = head === "detached" ? "self-heal-aborted-detached-head" : "self-heal-aborted-dirty";
      const what =
        head === "detached" ? "detached HEAD" : head === "non_default" ? "not on the default branch" : "local-commit count unreadable";
      log.error({ ...who, op: context.op, localCommits, head }, `kb/${context.op}: self-heal aborted — ${what}`);
      mirrorWithDebounce(
        null,
        { feature: "kb-route-helpers", op: abortOp, tags: { head }, extra, message: `kb/${context.op}: self-heal aborted (${what})` },
        workspacePath,
        abortOp,
      );
      return refuse(`non-fast-forward clone ${what}`);
    }

    // D6b: any tracked change refuses, knowledge-base/ included. The stall ends at the next session-start pull (syncPull's
    // hardened merge of the verified remote tip); #5221 keeps the broader recovery-and-lock work.
    if (hasTrackedChange(statusOut)) {
      const op = "self-heal-aborted-dirty-tracked";
      log.warn({ ...who, op: context.op, localCommits }, `kb/${context.op}: self-heal aborted — tracked changes in the working tree`);
      mirrorWarnWithDebounce(
        null,
        { feature: "kb-route-helpers", op, extra, message: `kb/${context.op}: self-heal aborted (tracked changes in the working tree)` },
        workspacePath,
        op,
      );
      return refuse("non-fast-forward with tracked changes in the working tree", "dirty_tracked");
    }

    if (localCommits > 0) {
      // D6c: reset only when the local commits' content is already upstream. Tree-to-tree diffs: no worktree read, no
      // clean/smudge filter; `--no-ext-diff --no-textconv` keep any configured diff helper out. The KB check compares
      // the two `knowledge-base` trees (equal trees <=> no diff under that pathspec, both-absent included).
      const nonKbHeld =
        (await diffQuietExit(
          runLocal,
          ["diff", "--quiet", "--no-ext-diff", "--no-textconv", `${target}...HEAD`, "--", ".", `:(exclude)${KB_ROOT}/`],
          gitOpts,
        )) === 1;
      const kbHeld =
        !nonKbHeld &&
        (await diffQuietExit(
          runLocal,
          ["diff", "--quiet", "--no-ext-diff", "--no-textconv", target, "HEAD", "--", `${KB_ROOT}/`],
          gitOpts,
        )) === 1;
      if (nonKbHeld || kbHeld) {
        // D27: the D15 untracked precheck first (an untracked or ignored entry at an incoming path refuses as below), then
        // the hardened merge. `merged` keeps the held commits and the upstream ones: no reset, no branch-aside.
        if (await hasUntrackedCollision((argv) => runLocal(argv, gitOpts), workspacePath, target)) {
          await recordCollisionHeld(installationId, workspacePath, context);
          return refuseUntrackedCollision("diverged");
        }
        const diag: HeldMergeDiag = {};
        const reason = await mergeHeldCommits(installationId, workspacePath, context, budget, diag);
        const verdict = HELD_MERGE_VERDICT[reason];
        if (verdict === "ok") {
          log.info(
            { ...who, op: context.op, localCommits, reason },
            reason === "merged"
              ? `kb/${context.op}: self-heal merged the default branch`
              : `kb/${context.op}: self-heal found the default branch already in the workspace`,
          );
          return { ok: true };
        }
        if (verdict === "collision") return refuseUntrackedCollision("diverged");
        const op = "self-heal-aborted-held-commits";
        const heldKind = nonKbHeld ? "nonkb" : "kb";
        const what = heldMergeWhat(verdict, heldKind);
        const isolatedTag: Record<string, string> = diag.isolatedReason ? { isolated_reason: diag.isolatedReason } : {};
        log.warn({ ...who, op: context.op, localCommits, heldKind, reason, ...isolatedTag }, `kb/${context.op}: self-heal aborted — ${what}`);
        mirrorWarnWithDebounce(
          null,
          {
            feature: "kb-route-helpers",
            op,
            tags: { held_kind: heldKind, reason, ...isolatedTag },
            extra: { ...extra, localCommits },
            message: `kb/${context.op}: self-heal aborted (${what})`,
          },
          workspacePath,
          `${op}:${heldKind}:${reason}`,
        );
        return refuse("non-fast-forward with held local commits", "held_commits");
      }
    }

    // D15(a): nothing the reset can replace may be an entry HEAD does not track (untracked or ignored). Both arms; before
    // the branch-aside, so a refusal leaves no recovery branch behind.
    if (await hasUntrackedCollision((argv) => runLocal(argv, gitOpts), workspacePath, target)) {
      return refuseUntrackedCollision(localCommits > 0 ? "diverged" : "phantom");
    }

    // `recoveryBranch` is set ONLY when un-pushed commits are branched aside; it distinguishes the recovered-diverged
    // path from the phantom (zero-commit) reset for observability below. The local commits' content is upstream (a
    // squash-merged side PR): keep the commit objects on a durable named ref (recoverable without SSH), then reset. The
    // timestamp avoids clobbering a prior recovery branch.
    let recoveryBranch: string | null = null;
    if (localCommits > 0) {
      // RC-H: the one spelling of the prefix, which the held count reads back (server/kb-sync-held.ts).
      const { RECOVERED_REF_PREFIX } = await import("@/server/kb-sync-held");
      recoveryBranch = `${RECOVERED_REF_PREFIX.slice("refs/heads/".length)}${Date.now()}`;
      await runLocal(["branch", recoveryBranch, "HEAD"], gitOpts);
    }

    // Reached by the phantom (zero-commit) divergence OR after the branch-aside above, on a clean tracked tree with nothing
    // untracked in the way. `--keep` (D15a) is the structural backstop: it refuses rather than overwrite an untracked
    // file at a path it must write, and on a clean tracked tree it changes nothing else versus `--hard`.
    await runLocal(["reset", "--keep", target], gitOpts);

    if (recoveryBranch) {
      log.warn(
        { ...who, op: context.op, defaultBranch, localCommits, recoveryBranch },
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
      { ...who, op: context.op, defaultBranch },
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
    // No `err` key (the pino error mirror would capture it untagged first, #8629) and no message (argv): the name and,
    // when one exists, the first app code frame (D20).
    const errName = healError instanceof Error ? healError.name : typeof healError;
    const frame = firstAppFrame(healError);
    log.error({ ...who, op: context.op, errName, ...(frame ? { frame } : {}) }, `kb/${context.op}: self-heal failed`);
    reportSilentFallback(null, {
      feature: "kb-route-helpers",
      op: "self-heal-failed",
      extra: { ...extra, errName, ...(frame ? { frame } : {}) },
      message: `kb/${context.op}: self-heal failed`,
    });
    return {
      ok: false,
      error: healError,
      errorClass: ERROR_CLASS_NON_FAST_FORWARD,
    };
  }
}
