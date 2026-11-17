// ---------------------------------------------------------------------------
// KB sync pull: the session-start merge of GitHub's default branch, on the hardened arm (#12718, rulings X1, D25-D28).
//
// Git over an injected `KbPullWriter` (D25(2)), plus, in `adoptSideTip` only, the side PR's GitHub REST reads and its one
// create (D28(3): a write to the user's repo; arch F8). `mergeVerifiedDefault` reads the remote state with one hardened
// `ls-remote`, fetches ONE branch into the server-owned isolated directory, checks the fetched tip equals the tip
// `ls-remote` named and hash-verifies, hands over exactly the objects the workspace lacks, and merges that in-memory tip.
// `adoptSideTip` (D28, step 6b) does the same for the side tip `soleur/kb-sync`, behind two KB-only gates (D28(2), D34) and
// the side PR's state. Neither stamps, reports, nor creates or disposes the isolated directory: the callers
// (server/session-sync.ts `syncPull`, server/workspace-sync.ts the self-heal) do. Every function returns a closed reason and
// never throws (D25(7)), so no URL or sha reaches an exception value. One budget bounds a run (D38(2)(3)): each network or
// isolated child gets `min(own cap, remaining)`, a step that cannot start is `pull_deadline`, and a merge starts only with
// `mergeStartMinMs` left; a started merge keeps its own bound.
//
// A leaf of the push: imports neither kb-sync-publish.ts nor push-branch.ts (census row, D25(3)).
// ---------------------------------------------------------------------------

import { HEX40 } from "./approval/workspace-head";
import { firstAppFrame } from "./error-frame";
import { ISOLATED_LOCAL_TIMEOUT_MS, runIsolatedGitLocal } from "./git-isolated-local";
import type { IsolatedPushDirHandle, IsolatedPushDirReason } from "./git-isolated-push-dir";
import { KB_ROOT } from "./kb-root";
import {
  commitTree,
  handOver,
  isAncestor,
  isCommitPresent,
  isKbOnlySide,
  kbOf,
  mergeEffectIsKbOnly,
  readVerified,
  sameKb,
} from "./kb-sync-objects";
import { cappedTimeout, fetchIntoIsolated, KB_SYNC_SIDE_BRANCH, KbRemoteError, readRemoteState, type RemoteState } from "./kb-sync-remote";
import { createKbSyncPr, readSidePrState, type SidePrState } from "./kb-sync-side-pr";

/** The one observability op of a session-start pull (one line per run, D25(6)). */
export const KB_PULL_HELD_OP = "kb-sync.pull-held";

/** The message of the session-start merge commit: the merge argv guard (server/connected-repo-git.ts) pins exactly this value. */
export const AUTO_MERGE_MSG_PULL = "Soleur: merge GitHub before session";
/** The message of the self-heal's merge (D37(2): its own pinned shape, no `--autostash`; arch F7's mislabel settled). */
export const AUTO_MERGE_MSG_SELF_HEAL = "Soleur: merge GitHub into workspace";

/** The message of the link commit `commit-tree(HEAD^{tree}, [HEAD, P])` (D28(4)): no file change, P joins HEAD's history. */
const SIDE_LINK_MSG = "Soleur: merge knowledge-base sync";

/**
 * The hand-over bound (D25(8)): the on-disk size of the objects the workspace lacks. A default branch that moved by more than
 * this in one session gap is `handover_too_large` (held; a re-clone or a smaller gap clears it). The pack buffer is sized
 * from it.
 */
const PULL_HANDOVER_MAX_BYTES = 128 * 1024 * 1024;
/** The object-walk bound, checked BEFORE `pack-objects` runs (D25(8)); its own constant, not `OBJECT_WALK_ENTRY_CAP`. */
const PULL_WALK_ENTRY_CAP = 200_000;

/** D38(2): one budget for a session-start `syncPull`, measured from its entry (the pre-range bound users already had). */
export const SYNC_PULL_BUDGET_MS = 60_000;
/** D38(3): a merge starts only with this much budget left (syncPull and the background self-heal). */
export const MERGE_START_MIN_MS = 20_000;
/** D38(3): the route-path self-heal's merge start minimum (its own 15 s budget, D38(4)). */
export const ROUTE_MERGE_START_MIN_MS = 5_000;

/**
 * A run's time budget (D38(2)(3)): `remaining()` is what is left (may be <= 0); a merge starts only with at least
 * `mergeStartMinMs` left. The budget gates STARTS and never kills a running writer.
 */
export interface PullBudget {
  remaining(): number;
  readonly mergeStartMinMs: number;
}

/** A budget of `totalMs` measured from `startedAt` (default: now). */
export function pullBudget(totalMs: number, mergeStartMinMs: number, startedAt: number = Date.now()): PullBudget {
  return { remaining: () => totalMs - (Date.now() - startedAt), mergeStartMinMs };
}

/** No budget: every step may start (callers that pass none keep each child's own cap). */
const UNBOUNDED: PullBudget = { remaining: () => Number.POSITIVE_INFINITY, mergeStartMinMs: 0 };

/**
 * Why a session-start pull did not simply merge (D25(6)). Warnings (a `kb-sync-pull-held:<reason>` mirror) carry a static
 * message; info reasons carry `null` (one pino line, no Sentry). `merge_conflict_precheck` is the self-heal's only: no
 * `reportPullHeld` caller reaches it (the self-heal reports on its own op), so its message is self-heal-only (obs F13).
 */
export type KbPullHeldReason =
  | "remote_state"
  | "fetch_failed"
  | "isolated_refused"
  | "tip_mismatch"
  | "shallow_changed"
  | "walk_cap"
  | "handover_failed"
  | "handover_too_large"
  | "unresolved_merge"
  | "merge_conflict"
  | "merge_refused"
  | "autostash_conflict"
  | "merge_conflict_precheck"
  | "side_not_kb_only"
  | "side_pr_unknown"
  | "up_to_date"
  | "merged"
  | "non_default_branch"
  | "side_declined"
  | "side_pr_created"
  | "side_linked"
  | "side_conflict"
  // Review Phase 0 (D35, D36(b), D38(2), D45(h), obs F3): widened ahead of the packages that return them.
  | "untracked_collision"
  | "merge_unverified"
  | "pull_deadline"
  | "side_pr_create_failed"
  | "pull_unexpected";

export const KB_PULL_HELD_MESSAGES: Record<KbPullHeldReason, string | null> = {
  remote_state: "KB sync pull: the remote state could not be read",
  fetch_failed: "KB sync pull: the isolated fetch failed",
  isolated_refused: "KB sync pull: the isolated directory was refused",
  tip_mismatch: "KB sync pull: the fetched tip did not match the remote tip",
  shallow_changed: "KB sync pull: the fetch would move the shallow boundary",
  walk_cap: "KB sync pull: the object walk exceeded its cap",
  handover_failed: "KB sync pull: the object hand-over failed",
  handover_too_large: "KB sync pull: the object hand-over exceeded its size cap",
  unresolved_merge: "KB sync pull: a merge is in progress in the workspace",
  merge_conflict: "KB sync pull: the merge with the default branch conflicted",
  merge_refused: "KB sync pull: the merge with the default branch was refused",
  autostash_conflict: "KB sync pull: the autostash did not re-apply cleanly after the merge",
  // self-heal-only (obs F13): unreachable through `reportPullHeld`; kept so the Record stays total
  merge_conflict_precheck: "KB sync self-heal: the merge pre-check conflicted",
  side_not_kb_only: "KB sync pull: the side branch changes files outside knowledge-base",
  side_pr_unknown: "KB sync pull: the side branch pull request could not be read",
  untracked_collision: "KB sync pull: an untracked or ignored file is in the merge's way",
  merge_unverified: "KB sync pull: the merge result could not be verified",
  pull_deadline: "KB sync pull: the pull ran out of time before a step could start",
  side_pr_create_failed: "KB sync pull: the side branch pull request could not be created",
  pull_unexpected: "KB sync pull: an unexpected error stopped the pull",
  // D44: a warning (D25(6)): the state persists, the push side holds `side_ahead` only on turns that push
  side_conflict: "KB sync pull: the side branch conflicts with the workspace",
  up_to_date: null,
  merged: null,
  non_default_branch: null,
  side_declined: null,
  side_pr_created: null,
  side_linked: null,
};

/** Which fetch a fetch-stage reason came from (the `ref` tag, D25(6)). */
export type KbPullRef = "default" | "side";

/**
 * The workspace merge's result, as the connected-repo writer reads it (D26(4): an autostash conflict is never `clean`):
 * `collision` (D35, nothing written), `unverified` (D36(b): the post-merge status could not be read) and `in_progress`
 * (D37(1): a merge state found before the merge).
 */
export type KbMergeOutcome = "clean" | "autostash_conflict" | "conflict" | "refused" | "collision" | "unverified" | "in_progress";

/**
 * The workspace writes a pull makes, injected by its caller (server/connected-repo-git.ts `kbPullWriter`, the guarded
 * `runConnectedRepoGitAsync`): the hand-over `unpack-objects -q`, the `--no-deref` tracking ref and branch CAS, and the
 * pinned merge of a 40-hex target. Async verbs: each but `merge` rejects on failure; `merge` resolves to its outcome.
 */
export interface KbPullWriter {
  unpack(pack: Buffer): Promise<void>;
  setTracking(branch: string, sha: string): Promise<void>;
  casBranch(branch: string, next: string, prev: string): Promise<void>;
  merge(target: string): Promise<KbMergeOutcome>;
}

/** Test seams (TX1-l). Production callers pass nothing. */
export interface KbPullLimits {
  readonly handoverMaxBytes?: number;
  readonly walkEntryCap?: number;
}

/** Why the remote state could not be read (obs F8, the `remote_cause` tag): closed, no URL. */
export type KbPullRemoteCause = "ls_remote_failed" | "remote_state_invalid" | "remote_head_absent" | "repo_url_unresolved";

export interface KbPullStep {
  readonly reason: KbPullHeldReason;
  readonly ref?: KbPullRef;
  /** `remote_state` only (obs F8). */
  readonly remoteCause?: KbPullRemoteCause;
  /** `isolated_refused` only (obs F4): the refusal's closed reason, never a path. */
  readonly isolatedReason?: IsolatedPushDirReason;
  /** `pull_unexpected` only (obs F3): the error's class name and first app frame (`file:line`), never its message. */
  readonly errName?: string;
  readonly frame?: string;
}

const step = (reason: KbPullHeldReason, ref?: KbPullRef): KbPullStep => (ref ? { reason, ref } : { reason });

/** A catch-all (obs F3): `pull_unexpected` with the class name and first app frame, never the raw error (D25(7)). */
const unexpected = (err: unknown): KbPullStep => {
  const frame = firstAppFrame(err);
  return { reason: "pull_unexpected", errName: err instanceof Error ? err.name : typeof err, ...(frame ? { frame } : {}) };
};

/** Merge outcome -> reason. */
const MERGE_REASON: Record<KbMergeOutcome, KbPullHeldReason> = {
  clean: "merged",
  autostash_conflict: "autostash_conflict",
  conflict: "merge_conflict",
  refused: "merge_refused",
  collision: "untracked_collision",
  unverified: "merge_unverified",
  in_progress: "unresolved_merge",
};

/**
 * The merge, behind the budget's start gate (D38(3)): `pull_deadline` when less than `mergeStartMinMs` is left. Once
 * started, the writer's merge keeps its own bound. A writer that throws (its contract is to resolve) is `pull_unexpected`.
 */
async function mergeSafely(writer: KbPullWriter, target: string, budget: PullBudget, ref?: KbPullRef): Promise<KbPullStep> {
  if (budget.remaining() < budget.mergeStartMinMs) return step("pull_deadline", ref);
  try {
    return step(MERGE_REASON[await writer.merge(target)]);
  } catch (err) {
    return unexpected(err);
  }
}

/** The budget's per-child timeout for an isolated local child (D38(2)). */
const localOpts = (budget: PullBudget): { timeoutMs: number } => ({ timeoutMs: cappedTimeout(ISOLATED_LOCAL_TIMEOUT_MS, finite(budget)) });
const finite = (budget: PullBudget): number | undefined => (Number.isFinite(budget.remaining()) ? budget.remaining() : undefined);
const spent = (budget: PullBudget): boolean => budget.remaining() <= 0;

/**
 * The objects reachable from `tip` and not from `nots`, bounded (D25(8)): the walk cap is checked on the walk's own output
 * BEFORE `pack-objects`, then the on-disk size, then the hand-over. `null` = handed over.
 */
async function transfer(
  isolated: IsolatedPushDirHandle,
  writer: KbPullWriter,
  tip: string,
  nots: readonly string[],
  limits: KbPullLimits,
  budget: PullBudget,
): Promise<KbPullHeldReason | null> {
  if (spent(budget)) return "pull_deadline";
  const cap = limits.walkEntryCap ?? PULL_WALK_ENTRY_CAP;
  const maxBytes = limits.handoverMaxBytes ?? PULL_HANDOVER_MAX_BYTES;
  const walk = await runIsolatedGitLocal(isolated, ["rev-list", "--objects", tip, "--not", ...nots], localOpts(budget));
  // quality P3-7: a walk that ran out of time or output IS the oversized walk `walk_cap` exists for (unless the budget, not
  // the child's own cap, cut it short).
  if (walk.code === -1 && walk.timedOut) return spent(budget) ? "pull_deadline" : "walk_cap";
  if (walk.code !== 0) return "handover_failed";
  const objects = walk.stdout
    .toString("utf8")
    .split("\n")
    .filter((l) => l !== "")
    .map((l) => l.slice(0, 40));
  if (objects.length > cap) return "walk_cap";
  if (objects.length === 0) return null;
  if (!objects.every((o) => HEX40.test(o))) return "handover_failed";
  if (spent(budget)) return "pull_deadline";
  const sizes = await runIsolatedGitLocal(isolated, ["cat-file", "--batch-check=%(objectsize:disk)"], { input: `${objects.join("\n")}\n`, ...localOpts(budget) });
  if (sizes.code !== 0) return "handover_failed";
  let total = 0;
  for (const line of sizes.stdout.toString("utf8").split("\n")) {
    if (line === "") continue;
    if (!/^\d+$/.test(line)) return "handover_failed";
    total += Number(line);
  }
  if (total > maxBytes) return "handover_too_large";
  if (spent(budget)) return "pull_deadline";
  try {
    // A pack is at most a little over the summed on-disk sizes; the buffer bound is the size cap's double. The pack is an
    // isolated child (budgeted); the workspace `unpack-objects` is a writer and keeps its own bound (D38(3)).
    await handOver(isolated, writer, objects, { maxBufferBytes: Math.max(2 * maxBytes, 1024 * 1024), ...localOpts(budget) });
  } catch {
    return "handover_failed";
  }
  return null;
}

/** A `merge-tree` result: `clean` carries the merged tree id (the D34 effect gate reads it; one child for both). */
type MergeTreeResult = { readonly kind: "clean"; readonly tree: string } | { readonly kind: "conflict" } | { readonly kind: "refused" };

/** `merge-tree --write-tree a b` in the isolated directory (token-free): 0 + a tree id is clean, 1 a conflict, else refused. */
async function mergeTreeCheck(isolated: IsolatedPushDirHandle, a: string, b: string, budget: PullBudget): Promise<MergeTreeResult> {
  const r = await runIsolatedGitLocal(isolated, ["merge-tree", "--write-tree", "--no-messages", a, b], localOpts(budget));
  const first = r.stdout.toString("utf8").split("\n")[0] ?? "";
  // measured (9.1 probe7): exit 1 is a conflict, and also a missing object; only a tree id on stdout is a real conflict.
  if (!HEX40.test(first)) return { kind: "refused" };
  if (r.code === 0) return { kind: "clean", tree: first };
  return r.code === 1 ? { kind: "conflict" } : { kind: "refused" };
}

export interface MergeDefaultInput {
  readonly isolated: IsolatedPushDirHandle;
  readonly installationId: number;
  /** The literal `https://github.com/<owner>/<repo>.git` (server/kb-sync-remote.ts `resolveRepoUrl`). */
  readonly url: string;
  /** Frozen HEAD, read after the auto-commit. */
  readonly headSha: string;
  /** HEAD's ref (`refs/heads/<b>`), or null when detached. */
  readonly refName: string | null;
  readonly writer: KbPullWriter;
  /** The self-heal's token-free `merge-tree` pre-check before any workspace write (D27). */
  readonly precheck?: boolean;
  readonly limits?: KbPullLimits;
  /** D38(2)(3): the run's budget (syncPull: `SYNC_PULL_BUDGET_MS` from its entry). None: each child's own cap. */
  readonly budget?: PullBudget;
}

export interface MergeDefaultResult extends KbPullStep {
  /** The remote state `ls-remote` returned, when it was read (step 6b needs the side tip). */
  readonly remote: RemoteState | null;
}

/**
 * X1: the default-branch merge. Order: hardened `ls-remote` (`remote_state`), X5 (`non_default_branch`: HEAD is not
 * `refs/heads/<D>`, or detached), `up_to_date` (T is HEAD, or a present, hash-verified ancestor of HEAD), the isolated fetch
 * of `refs/heads/<D>` (have: HEAD; the fetch-stage refusals tagged `ref=default`), the optional pre-check, the bounded
 * hand-over, the tracking ref, and the merge of the in-memory `T`: the value given to `setTracking` and nothing re-read
 * (D26(5)).
 */
export async function mergeVerifiedDefault(input: MergeDefaultInput): Promise<MergeDefaultResult> {
  const { isolated, writer, headSha } = input;
  const budget = input.budget ?? UNBOUNDED;
  let remote: RemoteState | null = null;
  const done = (reason: KbPullHeldReason, ref?: KbPullRef): MergeDefaultResult => ({ ...step(reason, ref), remote });
  const withRemote = (s: KbPullStep): MergeDefaultResult => ({ ...s, remote });
  try {
    if (spent(budget)) return done("pull_deadline", "default");
    try {
      remote = await readRemoteState(isolated, input.installationId, input.url, { timeoutMs: finite(budget) });
    } catch (err) {
      if (err instanceof KbRemoteError) return { ...done("remote_state"), remoteCause: err.reason };
      throw err;
    }
    if (!remote) return { ...done("remote_state"), remoteCause: "remote_head_absent" };
    const D = remote.defaultBranch;
    if (input.refName !== `refs/heads/${D}`) return done("non_default_branch");
    const T = remote.tip;
    if (T === headSha) return done("up_to_date");
    if (await isCommitPresent(isolated, T)) {
      // A present T is trusted only once its bytes hash to its id (a planted loose object at T's id, TX1-k).
      if (!(await readVerified(isolated, T))) return done("tip_mismatch", "default");
      if (await isAncestor(isolated, T, headSha)) return done("up_to_date");
    }
    if (spent(budget)) return done("pull_deadline", "default");
    const fetched = await fetchIntoIsolated(
      isolated,
      input.installationId,
      input.url,
      { branch: D, dest: "fetched", expected: T, haves: [headSha] },
      { timeoutMs: finite(budget) },
    );
    if (!fetched.ok) return done(fetched.reason, "default");
    if (input.precheck) {
      const pre = await mergeTreeCheck(isolated, headSha, T, budget);
      if (pre.kind === "conflict") return done("merge_conflict_precheck");
      if (pre.kind === "refused") return done("merge_refused");
    }
    const moved = await transfer(isolated, writer, T, [headSha], input.limits ?? {}, budget);
    if (moved) return done(moved, moved === "pull_deadline" ? "default" : undefined);
    try {
      await writer.setTracking(D, T);
    } catch {
      return done("handover_failed");
    }
    return withRemote(await mergeSafely(writer, T, budget, "default"));
  } catch (err) {
    // A local child that could not run (KbObjectsError) or anything unforeseen: a closed reason with the class name and
    // first app frame (obs F3), never a raw throw.
    return withRemote(unexpected(err));
  }
}

export interface AdoptSideInput {
  readonly isolated: IsolatedPushDirHandle;
  readonly installationId: number;
  readonly url: string;
  readonly owner: string;
  readonly repo: string;
  /** The remote state of THIS run (`mergeVerifiedDefault`'s). */
  readonly remote: RemoteState;
  /** HEAD after the default merge (re-read from the files). */
  readonly headSha: string;
  readonly writer: KbPullWriter;
  readonly limits?: KbPullLimits;
  /** D38(2)(3): the same run's budget as the default merge. */
  readonly budget?: PullBudget;
}

/**
 * Commits on HEAD's first-parent chain whose `knowledge-base` tree equals `kbTree` (D24(9)/(12)): the relink dropped `P` from
 * the local lineage, but its KB already is local, so a link commit (no file change) suffices. One walk and one batch read.
 */
const LINK_WALK_DEPTH = 200;
async function kbOnFirstParentChain(isolated: IsolatedPushDirHandle, headSha: string, kbTree: string, budget: PullBudget): Promise<boolean> {
  const chain = await runIsolatedGitLocal(isolated, ["rev-list", "--first-parent", `--max-count=${LINK_WALK_DEPTH}`, headSha], localOpts(budget));
  if (chain.code !== 0) return false;
  const commits = chain.stdout.toString("utf8").split("\n").filter((c) => HEX40.test(c));
  if (commits.length === 0) return false;
  const kb = await runIsolatedGitLocal(isolated, ["cat-file", "--batch-check=%(objectname) %(objecttype)"], {
    input: `${commits.map((c) => `${c}:${KB_ROOT}`).join("\n")}\n`,
    ...localOpts(budget),
  });
  if (kb.code !== 0) return false;
  return kb.stdout.toString("utf8").split("\n").some((l) => l === `${kbTree} tree`);
}

/**
 * D28, step 6b: adopt the side tip `P` = `soleur/kb-sync` when it carries KB the workspace lacks. `null` = nothing to adopt
 * (no side branch, `P` already in HEAD's history, `P`'s KB equals `T`'s, or a merged PR on `P`). Otherwise:
 *   1. `P` is fetched into the isolated directory when absent (haves `T` and HEAD; refusals tagged `ref=side`), else
 *      hash-verified where it is;
 *   2. the D28(2) KB-only gate, the first and cheap refusal: `diff --quiet --no-renames <merge-base(T,P)> <P> -- .
 *      ':(exclude)knowledge-base/'`; anything else changed is `side_not_kb_only` (no hand-over, no merge);
 *   3. the PR table read (server/kb-sync-side-pr.ts): closed unmerged is `side_declined`; a merged PR on `P` adopts nothing;
 *      a failed GET is `side_pr_unknown` (no write); open or none go on;
 *   4. the decision, in the isolated directory before any workspace or GitHub write: `P`'s KB tree on HEAD's first-parent
 *      chain links (the tree stays HEAD's); else the token-free `merge-tree HEAD P`: a conflict is `side_conflict` (warning,
 *      D44), and a clean result must pass the D34 EFFECT gate: the merged tree differs from HEAD's only inside
 *      `knowledge-base/` (`mergeEffectIsKbOnly`), else `side_not_kb_only` — so a `P` built on the workspace's own commit
 *      that reverts it never reaches the files, whether the merge would fast-forward or 3-way merge;
 *   5. only then (D45(h)) a PR is created when none exists (a failure is `side_pr_create_failed`, warning, no merge), and
 *      the hand-over and the link (`commit-tree(HEAD^{tree}, [HEAD, P])` + CAS) or the merge run. A created PR is reported
 *      as `side_pr_created` on both arms.
 * Pushing to the side branch therefore never lands code in a workspace, by either gate.
 */
export async function adoptSideTip(input: AdoptSideInput): Promise<KbPullStep | null> {
  const { isolated, writer, headSha, remote } = input;
  const budget = input.budget ?? UNBOUNDED;
  const P = remote.sideTip;
  const T = remote.tip;
  const D = remote.defaultBranch;
  if (P === null || P === headSha) return null;
  try {
    if (spent(budget)) return step("pull_deadline", "side");
    const present = await isCommitPresent(isolated, P);
    if (present && (await isAncestor(isolated, P, headSha))) return null;
    if (!present) {
      const fetched = await fetchIntoIsolated(
        isolated,
        input.installationId,
        input.url,
        { branch: KB_SYNC_SIDE_BRANCH, dest: "fetched-side", expected: P, haves: [T, headSha] },
        { timeoutMs: finite(budget) },
      );
      if (!fetched.ok) return step(fetched.reason, "side");
    }
    const pV = await readVerified(isolated, P);
    if (!pV) return step("tip_mismatch", "side");
    const tV = await readVerified(isolated, T);
    if (!tV) return step("tip_mismatch", "default");
    if (sameKb(pV.root, tV.root)) return null;

    // 2. The D28(2) KB-only gate, token-free.
    if (!(await isKbOnlySide(isolated, T, P))) return step("side_not_kb_only");

    // 3. The PR table (D17, D28(3)); an exhaustive switch (pattern P3-7): a new state fails the compile, not into a write.
    if (spent(budget)) return step("pull_deadline", "side");
    const pr: SidePrState = await readSidePrState(input.installationId, input.owner, input.repo, D, P);
    switch (pr) {
      case "unknown":
        return step("side_pr_unknown");
      case "declined":
        return step("side_declined");
      case "merged":
        return null;
      case "open":
      case "none":
        break;
      default: {
        const never: never = pr;
        void never;
        return step("side_pr_unknown");
      }
    }

    // 4. Link or merge; the decision and the D34 effect gate are made in the isolated directory before any write.
    const pKb = kbOf(pV.root);
    const link = pKb !== undefined && (await kbOnFirstParentChain(isolated, headSha, pKb.id, budget));
    if (!link) {
      const pre = await mergeTreeCheck(isolated, headSha, P, budget);
      if (pre.kind === "conflict") return step("side_conflict", "side");
      if (pre.kind === "refused") return step("merge_refused");
      const hV = await readVerified(isolated, headSha);
      if (!hV) return step("tip_mismatch", "default");
      if (!(await mergeEffectIsKbOnly(isolated, hV.commit.tree, pre.tree, localOpts(budget)))) return step("side_not_kb_only");
    }

    // 5. The PR create, after every refusal that would leave it pointless (D45(h)).
    let created = false;
    if (pr === "none") {
      try {
        await createKbSyncPr(input.installationId, input.owner, input.repo, D);
      } catch {
        return step("side_pr_create_failed");
      }
      created = true;
    }
    const moved = await transfer(isolated, writer, P, [T, headSha], input.limits ?? {}, budget);
    if (moved) return step(moved, "side");
    try {
      await writer.setTracking(KB_SYNC_SIDE_BRANCH, P);
    } catch {
      return step("handover_failed", "side");
    }
    if (link) {
      const hV = await readVerified(isolated, headSha);
      if (!hV) return step("handover_failed");
      const M = await commitTree(isolated, hV.commit.tree, [headSha, P], SIDE_LINK_MSG);
      const moveLink = await transfer(isolated, writer, M, [headSha, P], input.limits ?? {}, budget);
      if (moveLink) return step(moveLink, "side");
      try {
        await writer.casBranch(D, M, headSha);
      } catch {
        return step("handover_failed");
      }
      return step(created ? "side_pr_created" : "side_linked");
    }
    const merged = await mergeSafely(writer, P, budget, "side");
    return merged.reason === "merged" && created ? step("side_pr_created") : merged;
  } catch (err) {
    return unexpected(err);
  }
}
