// ---------------------------------------------------------------------------
// KB sync pull: the session-start merge of GitHub's default branch, on the hardened arm (#12718, rulings X1, D25-D28).
//
// Pure git over an injected `KbPullWriter` (D25(2)): `mergeVerifiedDefault` reads the remote state with one hardened
// `ls-remote`, fetches ONE branch into the server-owned isolated directory, checks the fetched tip equals the tip
// `ls-remote` named and hash-verifies, hands over exactly the objects the workspace lacks, and merges that in-memory tip.
// `adoptSideTip` (D28, step 6b) does the same for the side tip `soleur/kb-sync`, behind a KB-only gate and the side PR's
// state. Neither stamps, reports, nor creates or disposes the isolated directory: the callers (server/session-sync.ts
// `syncPull`, server/workspace-sync.ts the self-heal) do. Every function returns a closed reason and never throws (D25(7)),
// so no URL or sha reaches an exception value.
//
// A leaf of the push: imports neither kb-sync-publish.ts nor push-branch.ts (census row, D25(3)).
// ---------------------------------------------------------------------------

import { HEX40 } from "./approval/workspace-head";
import { runIsolatedGitLocal } from "./git-isolated-local";
import type { IsolatedPushDirHandle } from "./git-isolated-push-dir";
import { KB_ROOT } from "./kb-root";
import { commitTree, handOver, isAncestor, isCommitPresent, isKbOnlySide, readVerified, sameKb } from "./kb-sync-objects";
import { fetchIntoIsolated, KB_SYNC_SIDE_BRANCH, KbRemoteError, readRemoteState, type RemoteState } from "./kb-sync-remote";
import { createKbSyncPr, readSidePrState } from "./kb-sync-side-pr";

/** The one observability op of a session-start pull (one line per run, D25(6)). */
export const KB_PULL_HELD_OP = "kb-sync.pull-held";

/** The message of the session-start merge commit: the merge argv guard (server/connected-repo-git.ts) pins exactly this value. */
export const AUTO_MERGE_MSG_PULL = "Soleur: merge GitHub before session";

/** The message of the link commit `commit-tree(HEAD^{tree}, [HEAD, P])` (D28(4)): no file change, P joins HEAD's history. */
const SIDE_LINK_MSG = "Soleur: merge knowledge-base sync";

/**
 * The hand-over bound (D25(8)): the on-disk size of the objects the workspace lacks. A default branch that moved by more than
 * this in one session gap is `handover_too_large` (held; a re-clone or a smaller gap clears it). The pack buffer is sized
 * from it.
 */
export const PULL_HANDOVER_MAX_BYTES = 128 * 1024 * 1024;
/** The object-walk bound, checked BEFORE `pack-objects` runs (D25(8)); its own constant, not `OBJECT_WALK_ENTRY_CAP`. */
export const PULL_WALK_ENTRY_CAP = 200_000;

/**
 * Why a session-start pull did not simply merge (D25(6)). Warnings (a `kb-sync-pull-held:<reason>` mirror) carry a static
 * message; info reasons carry `null` (one pino line, no Sentry). `merge_conflict_precheck` is the self-heal's only.
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
  merge_conflict_precheck: "KB sync self-heal: the merge pre-check conflicted",
  side_not_kb_only: "KB sync pull: the side branch changes files outside knowledge-base",
  side_pr_unknown: "KB sync pull: the side branch pull request could not be read",
  untracked_collision: "KB sync pull: an untracked or ignored file is in the merge's way",
  merge_unverified: "KB sync pull: the merge result could not be verified",
  pull_deadline: "KB sync pull: the pull ran out of time before a step could start",
  side_pr_create_failed: "KB sync pull: the side branch pull request could not be created",
  pull_unexpected: "KB sync pull: an unexpected error stopped the pull",
  up_to_date: null,
  merged: null,
  non_default_branch: null,
  side_declined: null,
  side_pr_created: null,
  side_linked: null,
  side_conflict: null,
};

/** Which fetch a fetch-stage reason came from (the `ref` tag, D25(6)). */
export type KbPullRef = "default" | "side";

/**
 * The workspace merge's result, as the connected-repo writer reads it (D26(4): an autostash conflict is never `clean`).
 * `collision` (D35), `unverified` (D36(b)) and `in_progress` (D37(1)) are widened ahead of the writer that returns them.
 */
export type KbMergeOutcome = "clean" | "autostash_conflict" | "conflict" | "refused" | "collision" | "unverified" | "in_progress";

/**
 * The workspace writes a pull makes, injected by its caller (server/connected-repo-git.ts `kbPullWriter`, the guarded
 * `runConnectedRepoGit`): the hand-over `unpack-objects -q`, the `--no-deref` tracking ref and branch CAS, and the pinned
 * merge of a 40-hex target. Async verbs (frozen contract): each but `merge` rejects on failure; `merge` resolves to its
 * outcome.
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

export interface KbPullStep {
  readonly reason: KbPullHeldReason;
  readonly ref?: KbPullRef;
}

const step = (reason: KbPullHeldReason, ref?: KbPullRef): KbPullStep => (ref ? { reason, ref } : { reason });

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

async function mergeSafely(writer: KbPullWriter, target: string): Promise<KbPullHeldReason> {
  try {
    return MERGE_REASON[await writer.merge(target)];
  } catch {
    return "merge_refused";
  }
}

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
): Promise<KbPullHeldReason | null> {
  const cap = limits.walkEntryCap ?? PULL_WALK_ENTRY_CAP;
  const maxBytes = limits.handoverMaxBytes ?? PULL_HANDOVER_MAX_BYTES;
  const walk = await runIsolatedGitLocal(isolated, ["rev-list", "--objects", tip, "--not", ...nots]);
  if (walk.code !== 0) return "handover_failed";
  const objects = walk.stdout
    .toString("utf8")
    .split("\n")
    .filter((l) => l !== "")
    .map((l) => l.slice(0, 40));
  if (objects.length > cap) return "walk_cap";
  if (objects.length === 0) return null;
  if (!objects.every((o) => HEX40.test(o))) return "handover_failed";
  const sizes = await runIsolatedGitLocal(isolated, ["cat-file", "--batch-check=%(objectsize:disk)"], { input: `${objects.join("\n")}\n` });
  if (sizes.code !== 0) return "handover_failed";
  let total = 0;
  for (const line of sizes.stdout.toString("utf8").split("\n")) {
    if (line === "") continue;
    if (!/^\d+$/.test(line)) return "handover_failed";
    total += Number(line);
  }
  if (total > maxBytes) return "handover_too_large";
  try {
    // A pack is at most a little over the summed on-disk sizes; the buffer bound is the size cap's double.
    await handOver(isolated, writer, objects, { maxBufferBytes: Math.max(2 * maxBytes, 1024 * 1024) });
  } catch {
    return "handover_failed";
  }
  return null;
}

/** `merge-tree --write-tree a b` in the isolated directory (token-free): 0 + a tree id is clean, 1 a conflict, else refused. */
async function mergeTreeCheck(isolated: IsolatedPushDirHandle, a: string, b: string): Promise<"clean" | "conflict" | "refused"> {
  const r = await runIsolatedGitLocal(isolated, ["merge-tree", "--write-tree", "--no-messages", a, b]);
  const first = r.stdout.toString("utf8").split("\n")[0] ?? "";
  // measured (9.1 probe7): exit 1 is a conflict, and also a missing object; only a tree id on stdout is a real conflict.
  if (!HEX40.test(first)) return "refused";
  if (r.code === 0) return "clean";
  return r.code === 1 ? "conflict" : "refused";
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
  let remote: RemoteState | null = null;
  const done = (reason: KbPullHeldReason, ref?: KbPullRef): MergeDefaultResult => ({ ...step(reason, ref), remote });
  try {
    try {
      remote = await readRemoteState(isolated, input.installationId, input.url);
    } catch (err) {
      if (err instanceof KbRemoteError) return done("remote_state");
      throw err;
    }
    if (!remote) return done("remote_state");
    const D = remote.defaultBranch;
    if (input.refName !== `refs/heads/${D}`) return done("non_default_branch");
    const T = remote.tip;
    if (T === headSha) return done("up_to_date");
    if (await isCommitPresent(isolated, T)) {
      // A present T is trusted only once its bytes hash to its id (a planted loose object at T's id, TX1-k).
      if (!(await readVerified(isolated, T))) return done("tip_mismatch", "default");
      if (await isAncestor(isolated, T, headSha)) return done("up_to_date");
    }
    const fetched = await fetchIntoIsolated(isolated, input.installationId, input.url, {
      branch: D,
      dest: "fetched",
      expected: T,
      haves: [headSha],
    });
    if (!fetched.ok) return done(fetched.reason, "default");
    if (input.precheck) {
      const pre = await mergeTreeCheck(isolated, headSha, T);
      if (pre === "conflict") return done("merge_conflict_precheck");
      if (pre === "refused") return done("merge_refused");
    }
    const moved = await transfer(isolated, writer, T, [headSha], input.limits ?? {});
    if (moved) return done(moved);
    try {
      await writer.setTracking(D, T);
    } catch {
      return done("handover_failed");
    }
    return done(await mergeSafely(writer, T));
  } catch {
    // A local child that could not run (KbObjectsError) or anything unforeseen: a closed reason, never a raw throw.
    return done("handover_failed");
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
}

/**
 * Commits on HEAD's first-parent chain whose `knowledge-base` tree equals `kbTree` (D24(9)/(12)): the relink dropped `P` from
 * the local lineage, but its KB already is local, so a link commit (no file change) suffices. One walk and one batch read.
 */
const LINK_WALK_DEPTH = 200;
async function kbOnFirstParentChain(isolated: IsolatedPushDirHandle, headSha: string, kbTree: string): Promise<boolean> {
  const chain = await runIsolatedGitLocal(isolated, ["rev-list", "--first-parent", `--max-count=${LINK_WALK_DEPTH}`, headSha]);
  if (chain.code !== 0) return false;
  const commits = chain.stdout.toString("utf8").split("\n").filter((c) => HEX40.test(c));
  if (commits.length === 0) return false;
  const kb = await runIsolatedGitLocal(isolated, ["cat-file", "--batch-check=%(objectname) %(objecttype)"], {
    input: `${commits.map((c) => `${c}:${KB_ROOT}`).join("\n")}\n`,
  });
  if (kb.code !== 0) return false;
  return kb.stdout.toString("utf8").split("\n").some((l) => l === `${kbTree} tree`);
}

/**
 * D28, step 6b: adopt the side tip `P` = `soleur/kb-sync` when it carries KB the workspace lacks. `null` = nothing to adopt
 * (no side branch, `P` already in HEAD's history, or `P`'s KB equals `T`'s). Otherwise:
 *   1. `P` is fetched into the isolated directory when absent (haves `T` and HEAD; refusals tagged `ref=side`), else
 *      hash-verified where it is;
 *   2. the KB-only gate: `diff --quiet --no-renames <merge-base(T,P)> <P> -- . ':(exclude)knowledge-base/'`; anything else
 *      changed is `side_not_kb_only` (no hand-over, no merge): pushing to the side branch never lands code in a workspace;
 *   3. the PR table (server/kb-sync-side-pr.ts): open adopts; none creates the PR, then adopts (`side_pr_created`); closed
 *      unmerged is `side_declined`; a merged PR on `P` adopts nothing; a failed GET is `side_pr_unknown` (no write);
 *   4. `P`'s KB tree on HEAD's first-parent chain: hand over, `commit-tree(HEAD^{tree}, [HEAD, P])`, CAS: `side_linked`;
 *   5. else a token-free `merge-tree` pre-check: a conflict is `side_conflict` (files untouched); clean hands over and merges.
 */
export async function adoptSideTip(input: AdoptSideInput): Promise<KbPullStep | null> {
  const { isolated, writer, headSha, remote } = input;
  const P = remote.sideTip;
  const T = remote.tip;
  const D = remote.defaultBranch;
  if (P === null || P === headSha) return null;
  try {
    const present = await isCommitPresent(isolated, P);
    if (present && (await isAncestor(isolated, P, headSha))) return null;
    if (!present) {
      const fetched = await fetchIntoIsolated(isolated, input.installationId, input.url, {
        branch: KB_SYNC_SIDE_BRANCH,
        dest: "fetched-side",
        expected: P,
        haves: [T, headSha],
      });
      if (!fetched.ok) return step(fetched.reason, "side");
    }
    const pV = await readVerified(isolated, P);
    if (!pV) return step("tip_mismatch", "side");
    const tV = await readVerified(isolated, T);
    if (!tV) return step("tip_mismatch", "default");
    if (sameKb(pV.root, tV.root)) return null;

    // 2. The KB-only gate (D28(2)), token-free.
    if (!(await isKbOnlySide(isolated, T, P))) return step("side_not_kb_only");

    // 3. The PR table (D17, D28(3)).
    const pr = await readSidePrState(input.installationId, input.owner, input.repo, D, P);
    if (pr === "unknown") return step("side_pr_unknown");
    if (pr === "declined") return step("side_declined");
    if (pr === "merged") return null;
    let created = false;
    if (pr === "none") {
      try {
        await createKbSyncPr(input.installationId, input.owner, input.repo, D);
      } catch {
        return step("side_pr_unknown");
      }
      created = true;
    }

    // 4./5. Link or merge; the decision is made in the isolated directory before any workspace write.
    const pKb = pV.root.find((e) => e.name === KB_ROOT);
    const link = pKb !== undefined && (await kbOnFirstParentChain(isolated, headSha, pKb.id));
    if (!link) {
      const pre = await mergeTreeCheck(isolated, headSha, P);
      if (pre === "conflict") return step("side_conflict");
      if (pre === "refused") return step("merge_refused");
    }
    const moved = await transfer(isolated, writer, P, [T, headSha], input.limits ?? {});
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
      const moveLink = await transfer(isolated, writer, M, [headSha, P], input.limits ?? {});
      if (moveLink) return step(moveLink, "side");
      try {
        await writer.casBranch(D, M, headSha);
      } catch {
        return step("handover_failed");
      }
      return step("side_linked");
    }
    const merged = await mergeSafely(writer, P);
    return step(merged === "merged" && created ? "side_pr_created" : merged);
  } catch {
    return step("handover_failed");
  }
}
