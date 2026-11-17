// ---------------------------------------------------------------------------
// KB sync publish: the push half of the post-session sync (#12600, CTO ruling R6).
//
// Guard 1 (KB-only publish gate, plan "Guard Contract"): every ref update the post-session sync sends (the default
// branch or `soleur/kb-sync`) names a commit the server built, whose root tree equals the hash-verified remote base's
// root tree in every entry except `knowledge-base`, whose message and identity are Soleur's, and which never drops
// knowledge-base content the remote holds and the workspace never saw. Every sync push call site lives in this module.
// ---------------------------------------------------------------------------

import { mirrorWarnWithDebounce } from "@/server/observability";
import { HEX40 } from "./approval/workspace-head";
import { gitWithInstallationAuth } from "./git-auth";
import { disposeIsolated } from "./git-isolated-dispose";
import { runIsolatedGitLocal } from "./git-isolated-local";
import { createIsolatedPushDir, IsolatedPushDirRefusal, type IsolatedPushDirHandle, type IsolatedPushDirReason } from "./git-isolated-push-dir";
import { KB_ROOT } from "./kb-root";
import {
  commitTree,
  entryKey,
  handOver,
  IDENTITY_PREFIX,
  isAncestor,
  isCommitPresent,
  isKbOnlySide,
  KbObjectsError,
  kbOf,
  mktreeInput,
  readVerified,
  sameKb,
  TREE_MODE,
  type TreeEntry,
  type VerifiedCommit,
} from "./kb-sync-objects";
import { KbRemoteError, readRemoteState, resolveRepoUrl, SIDE_REF, type RemoteState } from "./kb-sync-remote";
import { createKbSyncPr, ensureKbSyncPr, readSidePrState, type SidePrState } from "./kb-sync-side-pr";
import { createChildLogger } from "./logger";

const log = createChildLogger("session-sync");

// #5426 — push-error classification for the protected-branch fallback.
// `protected_branch` routes to the side-branch + PR fallback; `persistent_other`
// is a non-protection reject that must NOT silently retry-loop (notably
// `shallow update not allowed` — these are shallow clones); `other` keeps the
// existing best-effort retry-next-session behaviour (auth/network/transient).
export type PushErrorClass = "protected_branch" | "persistent_other" | "other";

/** git's stderr on a failed child (a Buffer or a string), never `err.message` (which embeds argv). */
const stderrOf = (err: unknown): string => {
  const raw = (err as { stderr?: unknown } | null)?.stderr;
  return Buffer.isBuffer(raw) ? raw.toString("utf8") : typeof raw === "string" ? raw : "";
};

/** GitHub's protected-branch reject, as the first token of a `remote:` line (R2, R16). Tested per line, never multiline. */
const GH006_LINE_RE = /^remote: error: GH006:/;
/**
 * GitHub's require-PR text STARTING a `remote:` line's message, after an optional `error:` and `- ` (#5426; also a GH013 ruleset
 * that requires a PR; CTO rulings D9, D18). `[ \t]`, never `\s`: the text must sit on the `remote:` line itself.
 */
const REQUIRE_PR_LINE_RE = /^remote:(?: error:)?[ \t]*(?:-[ \t]*)?Changes must be made through a pull request/;
/** git's own status line for a shallow reject (D23, the D18 treatment): `<src> -> <dst>` cannot hold a space or tab. */
const SHALLOW_LINE_RE = /^[ \t]*! \[remote rejected\] [^ \t]+ -> [^ \t]+ \(shallow update not allowed\)[ \t]*$/;
/** git's own status line for a rejected ref update (D23): it starts the line, so a `remote:` echo cannot forge it. */
const REJECTED_LINE_RE = /^[ \t]*! \[(?:rejected|remote rejected)\]/;

/** git's stderr lines: CR normalised (`\r\n?` -> `\n`), split on `\n` only, so U+2028 / U+2029 never start a line (D18). */
const stderrLines = (err: unknown): string[] => stderrOf(err).replace(/\r\n?/g, "\n").split("\n");

/**
 * Classify a failed `git push` error from git's STDERR only (#12600, CTO rulings R2, R16, re-ruled by D9 and D18). CR is
 * normalised (`\r\n?` -> `\n`, so CRLF and a lone CR of progress output both end a line), the text is split on `\n`, and
 * each line is tested with NON-multiline regexes: a line-anchored `remote: error: GH006:`, or a `remote:` line whose message
 * starts with GitHub's require-PR text. So neither a ref name in git's own status line (ref names cannot hold spaces), nor a
 * `remote:   path: ...` echo of an agent-authored KB path, nor U+2028 / U+2029 (never a line here), nor `err.message` (argv: the
 * URL and the refspec) can steer it. GH013 without the require-PR text (secret push protection) stays `other`. A shallow
 * reject is `persistent_other` only on git's own ` ! [remote rejected] <src> -> <dst> (shallow update not allowed)` line (D23).
 * Narrow by design: auth/network rejections fall through to `other`.
 */
export function classifyPushError(err: unknown): PushErrorClass {
  if (!(err instanceof Error)) return "other";
  const lines = stderrLines(err);
  if (lines.some((line) => GH006_LINE_RE.test(line) || REQUIRE_PR_LINE_RE.test(line))) return "protected_branch";
  if (lines.some((line) => SHALLOW_LINE_RE.test(line))) return "persistent_other";
  return "other";
}

/**
 * A failed push that the remote answered (git's ` ! [rejected]` / ` ! [remote rejected]` status line), as opposed to one that
 * never reached it (`push_transient`). Per line from stderr only, with the same normalisation as `classifyPushError` (D23).
 */
export function isRejectedPush(err: unknown): boolean {
  return stderrLines(err).some((line) => REJECTED_LINE_RE.test(line));
}

// ---------------------------------------------------------------------------
// The KB-only publish (#12600, CTO ruling R14): the sync pushes only a commit the server built.
// ---------------------------------------------------------------------------

// #5426 — protected-branch fallback: when the user's default branch is protected, a side commit (built on the remote tip
// like S, #12600 R17) accretes onto the durable side branch `soleur/kb-sync` (server/kb-sync-remote.ts) in the user's OWN
// repo, with a never-auto-merged PR into the default branch (server/kb-sync-side-pr.ts).
const KB_SYNC_SIDE_COMMIT_MSG = "Soleur: sync knowledge-base";
const PUSH_TIMEOUT_MS = 60_000;

/** Every reason a turn's KB push is held (R7). Warning-level reasons carry a static Sentry message; the rest log only. */
export type KbPushHeldReason =
  | "merge_in_progress"
  | "detached_head"
  | "non_default_branch"
  | "remote_branch_absent"
  | "remote_unknown_tip"
  | "remote_ahead"
  | "hash_mismatch"
  | "kb_not_tree"
  | "guard_failed"
  | "head_moved"
  | "ref_update_failed"
  | "unpack_failed"
  | "side_ahead"
  | "side_not_kb_only"
  | "side_pending"
  | "side_declined"
  | "side_pr_unknown"
  | "side_pr_created"
  | "pr_failed"
  | "kb_absent"
  | "held_foreign"
  | "synthetic_pushed";

export type KbPushOutcome = "pushed" | "side_pushed" | "held";

/** Every reason, with its static Sentry message or an explicit `null` for an info-only reason (D21: compile-checked). */
const HELD_WARN_MESSAGES: Record<KbPushHeldReason, string | null> = {
  merge_in_progress: "KB sync held: a merge is in progress in the workspace",
  detached_head: "KB sync held: the workspace HEAD is detached",
  non_default_branch: "KB sync held: the workspace is not on the default branch",
  remote_branch_absent: "KB sync held: the remote has no default branch",
  hash_mismatch: "KB sync held: a git object failed its hash check",
  kb_not_tree: "KB sync held: knowledge-base is not a directory",
  kb_absent: "KB sync held: the workspace HEAD has no knowledge-base the remote holds",
  guard_failed: "KB sync held: the built commit failed the KB-only guard",
  head_moved: "KB sync held: the local branch moved during the sync",
  ref_update_failed: "KB sync held: the local branch update failed",
  unpack_failed: "KB sync held: the object hand-over to the workspace failed",
  side_ahead: "KB sync held: the side branch holds knowledge-base content the workspace has not seen",
  side_pr_unknown: "KB sync held: the side branch's pull request could not be checked",
  side_not_kb_only: "KB sync held: the side branch changes files outside knowledge-base",
  remote_unknown_tip: null,
  remote_ahead: null,
  side_pending: null,
  side_declined: null,
  side_pr_created: null,
  // the paging `kb-sync.protected-fallback-failed` op already carries a pr_failed exit (D8); this is its per-turn line
  pr_failed: null,
  held_foreign: null,
  synthetic_pushed: null,
};

export interface KbSyncContext {
  readonly userId: string;
  readonly workspaceId: string;
}

/**
 * The ONE outcome report of a turn's KB push (R7): an unconditional info line (Better Stack, every turn), then, for the
 * anomaly reasons only, a debounced warning per workspace and reason. No path, sha, URL or branch name.
 */
export function reportPushHeld(reason: KbPushHeldReason, outcome: KbPushOutcome, ctx: KbSyncContext): void {
  log.info({ op: "kb-sync.push-held", reason, outcome, workspaceId: ctx.workspaceId }, "KB sync push outcome");
  const message = HELD_WARN_MESSAGES[reason];
  if (message === null) return;
  mirrorWarnWithDebounce(
    null,
    { feature: "session-sync", op: "kb-sync.push-held", message, tags: { reason, outcome }, extra: { userId: ctx.userId } },
    ctx.workspaceId,
    `kb-sync-push-held:${reason}`,
  );
}

/** A failed sync step, with a closed reason and a static message: never the git error, whose argv names the URL and shas. */
export type KbSyncErrorReason =
  | "ls_remote_failed"
  | "push_rejected"
  | "push_transient"
  | "isolated_refused"
  | "remote_state_invalid"
  | "local_git_failed"
  | "head_unreadable";

export class KbSyncError extends Error {
  constructor(
    readonly reason: KbSyncErrorReason,
    readonly pushClass?: PushErrorClass,
    /** `isolated_refused` only: the refusal's closed reason (D21), never a path. */
    readonly isolatedReason?: IsolatedPushDirReason,
  ) {
    super(`KB sync step failed (${reason})`);
    this.name = "KbSyncError";
  }
}

/** Internal control flow: the turn is held for `reason` (reported once, by the orchestrator). */
class KbHeld extends Error {
  constructor(readonly reason: KbPushHeldReason) {
    super(`KB sync held (${reason})`);
    this.name = "KbHeld";
  }
}

/** The leaves' neutral errors (D25(1)) in the push's terms: a failed hand-over is held, the rest keep their closed reason. */
function asKbError(err: unknown): unknown {
  if (err instanceof KbRemoteError) return new KbSyncError(err.reason);
  if (err instanceof KbObjectsError) return err.reason === "unpack_failed" ? new KbHeld("unpack_failed") : new KbSyncError("local_git_failed");
  return err;
}

/**
 * The ONLY builder of a commit the sync pushes (R14): `baseRoot` (a verified root) with the `knowledge-base` entry
 * replaced by `kb`, the fixed message and the Soleur identity, parents as given. Built token-free in the isolated dir.
 * Module-private (D12): `baseRoot` is trusted, so only this module's verified roots may reach it.
 */
async function buildKbOverlay(
  isolated: IsolatedPushDirHandle,
  baseRoot: readonly TreeEntry[],
  kb: TreeEntry,
  parents: readonly string[],
): Promise<{ sha: string; tree: string }> {
  const entries = [...baseRoot.filter((e) => e.name !== KB_ROOT), { mode: TREE_MODE, name: KB_ROOT, id: kb.id }];
  const mk = await runIsolatedGitLocal(isolated, ["mktree", "-z"], { input: mktreeInput(entries) });
  const tree = mk.stdout.toString("utf8").trim();
  if (mk.code !== 0 || !HEX40.test(tree)) throw new KbSyncError("local_git_failed");
  return { sha: await commitTree(isolated, tree, parents, KB_SYNC_SIDE_COMMIT_MSG), tree };
}

/**
 * Guard 1: `sha`'s verified root equals `baseRoot` in every entry except `knowledge-base` (present, a tree), and its
 * message and identity are Soleur's. Compared on the parsed entry lists; no history walk. Module-private (D12).
 */
async function assertRootDiffersOnlyInKb(
  isolated: IsolatedPushDirHandle,
  sha: string,
  baseRoot: readonly TreeEntry[],
): Promise<boolean> {
  const built = await readVerified(isolated, sha);
  if (!built) return false;
  const { commit, root } = built;
  if (!commit.author.startsWith(IDENTITY_PREFIX) || !commit.committer.startsWith(IDENTITY_PREFIX)) return false;
  if (commit.message !== `${KB_SYNC_SIDE_COMMIT_MSG}\n`) return false;
  const kb = kbOf(root);
  if (!kb || kb.mode !== TREE_MODE) return false;
  const a = root.filter((e) => e.name !== KB_ROOT).map(entryKey).sort();
  const b = baseRoot.filter((e) => e.name !== KB_ROOT).map(entryKey).sort();
  return a.length === b.length && a.every((k, i) => k === b[i]);
}

/** A sha that passed Guard 1 in `isolated`: only `guardKbOnly` creates one, so the one push can only send a guarded sha. */
interface GuardedSha {
  readonly isolated: IsolatedPushDirHandle;
  readonly sha: string;
}
const GUARDED = new WeakSet<GuardedSha>();

/** Run Guard 1 ONCE for `sha` (D13): the token it returns is what the push takes, so the push never re-reads the commit. */
async function guardKbOnly(
  isolated: IsolatedPushDirHandle,
  sha: string,
  baseRoot: readonly TreeEntry[],
): Promise<GuardedSha | null> {
  if (!HEX40.test(sha) || !(await assertRootDiffersOnlyInKb(isolated, sha, baseRoot))) return null;
  const guarded: GuardedSha = Object.freeze({ isolated, sha });
  GUARDED.add(guarded);
  return guarded;
}

interface VerifiedPush {
  readonly installationId: number;
  readonly url: string;
  readonly guarded: GuardedSha;
  /** `refs/heads/<D>` or `refs/heads/soleur/kb-sync`, nothing else. */
  readonly ref: string;
  readonly defaultBranch: string;
}

/**
 * The ONE push of the post-session sync (R6): `<sha>:<ref>` non-force from the isolated directory through the hardened
 * arm, for a sha Guard 1 passed in this turn (the `GuardedSha` token). Throws `KbHeld("guard_failed")` for anything else, or
 * a `KbSyncError` carrying the stderr class. Module-private (D12).
 */
async function pushVerifiedKbOnly(p: VerifiedPush): Promise<void> {
  if (p.ref !== `refs/heads/${p.defaultBranch}` && p.ref !== SIDE_REF) throw new KbSyncError("remote_state_invalid");
  if (!GUARDED.has(p.guarded)) throw new KbHeld("guard_failed");
  try {
    await gitWithInstallationAuth(["push", p.url, `${p.guarded.sha}:${p.ref}`], p.installationId, {
      hardened: p.guarded.isolated,
      timeout: PUSH_TIMEOUT_MS,
    });
  } catch (err) {
    const pushClass = classifyPushError(err);
    const rejected = pushClass !== "other" || isRejectedPush(err);
    throw new KbSyncError(rejected ? "push_rejected" : "push_transient", pushClass);
  }
}

/** The message of the local merge `M` that keeps held (non-KB) commits on the local branch next to `S` (P7). */
const KB_SYNC_MERGE_MSG = "Soleur: merge knowledge-base sync";

/**
 * The workspace writes the sync makes, injected by `session-sync.ts` (its guarded `runConnectedRepoGitAsync`, R12, R19,
 * R20): `unpack-objects -q` with the pack on stdin, the `--no-deref` CAS of `refs/heads/<b>` and the tracking ref. Each
 * rejects on failure (the error carries git's stderr); async so no workspace child blocks the event loop (D38(1)).
 */
export interface KbWorkspaceWriter {
  unpack(pack: Buffer): Promise<void>;
  casBranch(branch: string, next: string, prev: string): Promise<void>;
  setTracking(branch: string, sha: string): Promise<void>;
}

// The hand-over (CTO ruling D10, server/kb-sync-objects.ts `handOver`): every parent of a server-built commit is already in
// the workspace (T, headSha, a present side tip P, or a commit handed over earlier), and the KB subtree is HEAD's, so the only
// missing objects are the new commit and its new root tree:
//   S -> S + S^{tree};  M -> S + S^{tree} + M (M's tree is headSha's);  side -> side + side^{tree};  M' -> side + side^{tree} + M'.
// A `--revs` walk re-sent the KB change set (`^headSha` is not an edge of S) and hit the stdout cap above 64 MB. A failed
// hand-over is `unpack_failed` (`KbObjectsError`, mapped by `asKbError`).

/** The `--no-deref` CAS of the local branch: a moved branch (`but expected`) is `head_moved`, anything else `ref_update_failed`. */
async function casLocalBranch(writer: KbWorkspaceWriter, branch: string, next: string, prev: string): Promise<void> {
  try {
    await writer.casBranch(branch, next, prev);
  } catch (err) {
    throw new KbHeld(/but expected/.test(stderrOf(err)) ? "head_moved" : "ref_update_failed");
  }
}

/**
 * The advisory tracking ref (R8): best-effort, a failure only means one more token mint next turn. A failure that
 * repeats (a stale `.lock`, a broken ref store) mints a token every turn, so it mirrors to Sentry at warning level,
 * debounced per workspace (cq-silent-fallback-must-mirror-to-sentry; CTO ruling D4). No path, sha or branch name.
 */
async function setTrackingBestEffort(writer: KbWorkspaceWriter, branch: string, sha: string, ctx: KbSyncContext): Promise<void> {
  try {
    await writer.setTracking(branch, sha);
  } catch {
    log.warn({ op: "kb-sync.tracking-ref" }, "KB sync: tracking ref update failed");
    mirrorWarnWithDebounce(
      null,
      {
        feature: "session-sync",
        op: "kb-sync.tracking-ref",
        message: "KB sync: tracking ref update failed",
        extra: { userId: ctx.userId },
      },
      ctx.workspaceId,
      "kb-sync-tracking-ref",
    );
  }
}

/** Why the protected-branch fallback did not deliver (the `fallback_reason` tag, closed). */
export type KbFallbackReason = "side_hash_mismatch" | "side_guard_failed" | "side_push_rejected" | "side_push_transient" | "pr_failed";

export type KbPublishResult =
  | { readonly kind: "pushed" }
  | { readonly kind: "held"; readonly reason: KbPushHeldReason }
  | { readonly kind: "noop" }
  | { readonly kind: "fallback"; readonly prUrl: string; readonly commitCount: number }
  /** `pushErr` is null when no push ran this turn (the `side_pending` PR re-check, D17). */
  | { readonly kind: "fallback_failed"; readonly fallbackReason: KbFallbackReason; readonly pushErr: KbSyncError | null };

/** What `onHeldFiles` receives: the turn's isolated directory (still live), the remote tip and the frozen HEAD. */
export interface KbHeldFilesProbe {
  readonly isolatedDir: IsolatedPushDirHandle;
  readonly T: string;
  readonly headSha: string;
}

export interface KbPublishInput extends KbSyncContext {
  readonly workspacePath: string;
  readonly installationId: number;
  /** Frozen HEAD (`readWorkspaceHeadRef`), read before any git child. */
  readonly headSha: string;
  readonly refName: string;
  readonly writer: KbWorkspaceWriter;
  /**
   * #12714 seam (D29(1)): called once per turn BEFORE the isolated directory is disposed, on every exit that read the remote
   * tip (held exits too). A throw or rejection never changes the turn's result.
   */
  readonly onHeldFiles?: (probe: KbHeldFilesProbe) => void | Promise<void>;
}

/** The fallback's state: the turn's input plus what steps 2-4 established (D25(4): no re-declared turn fields). */
interface SideFallbackInput extends KbPublishInput {
  readonly isolated: IsolatedPushDirHandle;
  readonly url: string;
  readonly owner: string;
  readonly repo: string;
  readonly remote: RemoteState;
  readonly tV: VerifiedCommit;
  /** HEAD's verified root tree (the tree of `M` and `M'`). */
  readonly headTree: string;
  readonly headKb: TreeEntry;
  /** Guard 1's token for `S` (a side commit identical to `S` reuses it: Guard 1 once per sha, D13). */
  readonly guardedS: GuardedSha;
  /** The value step 4 moved the local branch to (`S`, or `M`): the link's CAS old value and the rollback's. */
  readonly localNext: string;
  readonly pushErr: KbSyncError;
}

/**
 * D17: the side branch already carries HEAD's KB (`side_pending`). One GET (`state=all`) re-checks its PR through the shared
 * table (server/kb-sync-side-pr.ts), because the link now precedes the PR (D14(2)) and a single REST failure would otherwise
 * leave the KB on a branch no Owner sees:
 *   - an open PR, or a merged one on `P`: `side_pending` (info, nothing to do);
 *   - a closed, unmerged PR whose head is `P`: the Owner declined this exact content, never reopened: `side_declined` (info);
 *   - no PR on `P`: create it (the `pr_failed` retry): `side_pr_created` (info; nothing was pushed, so no protected-fallback
 *     mirror and no bookkeeping, D23); a create failure is `fallback_failed pr_failed`;
 *   - the GET fails (any cause): `side_pr_unknown`, a debounced warning, nothing created (fail toward no duplicate PR, D23).
 */
async function recheckSidePr(installationId: number, owner: string, repo: string, D: string, P: string, ctx: KbSyncContext): Promise<KbPublishResult> {
  const state: SidePrState = await readSidePrState(installationId, owner, repo, D, P);
  // An exhaustive switch (pattern P3-7): a new state fails the compile, never falls through into the create.
  switch (state) {
    case "unknown":
      throw new KbHeld("side_pr_unknown");
    case "open":
    case "merged":
      throw new KbHeld("side_pending");
    case "declined":
      throw new KbHeld("side_declined");
    case "none":
      break;
    default: {
      const never: never = state;
      void never;
      throw new KbHeld("side_pr_unknown");
    }
  }
  try {
    await createKbSyncPr(installationId, owner, repo, D);
  } catch {
    reportPushHeld("pr_failed", "held", ctx);
    return { kind: "fallback_failed", fallbackReason: "pr_failed", pushErr: null };
  }
  throw new KbHeld("side_pr_created");
}

/**
 * D14(4), the scoped rollback: move the local branch back from `localNext` to `headSha`, best effort. Runs on every exit of the
 * fallback before its link completes; never after a non-protected D push error (the remote state is then unknown, and
 * `localNext` is the crash-safe value). A failed rollback (`head_moved`: the agent committed meanwhile) never changes the
 * turn's result: one debounced warning, no outcome line.
 */
async function rollbackBestEffort(f: SideFallbackInput): Promise<void> {
  try {
    await casLocalBranch(f.writer, f.remote.defaultBranch, f.headSha, f.localNext);
  } catch (err) {
    const reason = err instanceof KbHeld ? err.reason : "ref_update_failed";
    log.warn({ op: "kb-sync.rollback", reason, workspaceId: f.workspaceId }, "KB sync: the local branch rollback failed");
    mirrorWarnWithDebounce(
      null,
      { feature: "session-sync", op: "kb-sync.rollback", message: "KB sync: the local branch rollback failed", tags: { reason }, extra: { userId: f.userId } },
      f.workspaceId,
      "kb-sync-rollback-failed",
    );
  }
}

/**
 * D22(a): the best-effort CAS of the local branch from the merge `M` to `S` after `S` landed on D. A failure (`head_moved`: the
 * agent committed meanwhile) leaves `M`, which loses nothing: one debounced warning, no outcome line, the turn stays `pushed`.
 */
async function relinkBestEffort(writer: KbWorkspaceWriter, branch: string, S: string, M: string, ctx: KbSyncContext): Promise<void> {
  try {
    await casLocalBranch(writer, branch, S, M);
  } catch (err) {
    const reason = err instanceof KbHeld ? err.reason : "ref_update_failed";
    log.warn({ op: "kb-sync.relink", reason, workspaceId: ctx.workspaceId }, "KB sync: the local branch relink to the pushed commit failed");
    mirrorWarnWithDebounce(
      null,
      { feature: "session-sync", op: "kb-sync.relink", message: "KB sync: the local branch relink to the pushed commit failed", tags: { reason }, extra: { userId: ctx.userId } },
      ctx.workspaceId,
      "kb-sync-relink-failed",
    );
  }
}

/** The side delivery up to and including the local link; `linked` once the local branch names the delivered side commit. */
type SideStep = { readonly kind: "linked" } | Extract<KbPublishResult, { kind: "fallback_failed" }>;

/**
 * Steps 6a-6d of the fallback (rulings F, R3, R4, R15, R17, D5, D11, D14), entirely in the isolated directory: no checkout,
 * no reset, no workspace commit. Side parent `P` = the side tip `ls-remote` returned, hash-verified, and present in the
 * workspace object store; it is never fetched here (D5d: an absent P is absent from the workspace too, so it can never pass
 * the ancestry check this turn) and never a workspace ref. A side branch that already carries HEAD's KB never gets here
 * (`side_pending`, in `publishKbOnly`). Ruling I extended: build only when the side branch is absent, `P` is an ancestor of
 * `headSha`, or `P`'s KB entry equals `T`'s (the PR merged); else `side_ahead`. The side commit's root is `T`'s with HEAD's
 * KB entry; parents `T` (no side branch), `P` (when `P` already descends from `T`, so the non-force side push stays a
 * fast-forward) or `(P, T)`. The link target is built and handed over BEFORE the side push (D14(1), D22(b)), so nothing that
 * can throw a non-held error runs after a delivery, and the link CAS runs right after it (D14(2)): the side commit itself when
 * HEAD's tree is the side's tree (no non-KB content to keep), else `M'` = merge(headSha, side) with HEAD's tree.
 */
async function deliverAndLinkSide(f: SideFallbackInput): Promise<SideStep> {
  const { isolated, installationId, url, remote, tV, headSha, headKb } = f;
  const fail = (fallbackReason: KbFallbackReason): SideStep => ({ kind: "fallback_failed", fallbackReason, pushErr: f.pushErr });
  const D = remote.defaultBranch;
  const T = remote.tip;
  const P = remote.sideTip;
  let parents: string[] = [T];
  if (P !== null) {
    // D28(6): a side tip absent from the workspace holds the turn (`side_ahead`); the next session-start pull adopts it
    // (server/kb-sync-pull.ts `adoptSideTip`: fetched with server-owned have refs, KB-only gated, handed over, merged).
    if (!(await isCommitPresent(isolated, P))) throw new KbHeld("side_ahead");
    const pV = await readVerified(isolated, P);
    if (!pV) return fail("side_hash_mismatch");
    // D28(2): a present P that changes anything outside knowledge-base/ is never built on.
    if (!(await isKbOnlySide(isolated, T, P))) throw new KbHeld("side_not_kb_only");
    // simplicity F11: the shared KB-entry comparison (both present and equal: the PR merged).
    const prMerged = kbOf(pV.root) !== undefined && sameKb(pV.root, tV.root);
    // D28(6): a P not in HEAD's history (and not merged) also holds `side_ahead`; the next session-start pull adopts it.
    if (!prMerged && !(await isAncestor(isolated, P, headSha))) throw new KbHeld("side_ahead");
    parents = pV.commit.parents.includes(T) || (await isAncestor(isolated, T, P)) ? [P] : [P, T];
  }

  const { sha: side, tree: sideTree } = await buildKbOverlay(isolated, tV.root, headKb, parents);
  const guarded = side === f.guardedS.sha ? f.guardedS : await guardKbOnly(isolated, side, tV.root);
  if (!guarded) return fail("side_guard_failed");
  const linkTo = sideTree === f.headTree ? side : await commitTree(isolated, f.headTree, [headSha, side], KB_SYNC_MERGE_MSG);
  // D22(b), amending D14(2): the hand-over runs BEFORE the side push. The objects are inert until the CAS, so a failed
  // hand-over is a pre-delivery exit (rolled back, nothing on GitHub), and after the push the side tip is always present in
  // the workspace: a crash or a `head_moved` after it leaves a no-edit turn that reaches the D17 re-check (`side_pending`).
  await handOver(isolated, f.writer, linkTo === side ? [side, sideTree] : [side, sideTree, linkTo]);
  try {
    await pushVerifiedKbOnly({ installationId, url, guarded, ref: SIDE_REF, defaultBranch: D });
  } catch (err) {
    if (err instanceof KbHeld) return fail("side_guard_failed");
    // D21: a network failure of the side push is retried next turn (warning, off the paging op); a reject is a failure.
    return fail(err instanceof KbSyncError && err.reason === "push_transient" ? "side_push_transient" : "side_push_rejected");
  }
  // D5c: the next turn finds the side commit local and an ancestor of HEAD, so (with no new edit) it is `side_pending`: no
  // push to D, no new merge commit. A failure here is a held reason, never a fallback failure; the side commit is delivered,
  // so its PR is still ensured, best effort (D22(b)), before the held reason propagates.
  try {
    await casLocalBranch(f.writer, D, linkTo, f.localNext);
  } catch (err) {
    await ensureKbSyncPr(installationId, f.owner, f.repo, D).catch(() => undefined); // a miss is retried by the D17 re-check
    throw err;
  }
  return { kind: "linked" };
}

/**
 * Step 6, the protected-branch fallback: deliver and link the side commit, then the tracking ref (D11: `T`, what GitHub's D
 * is, never the side commit), then the never-auto-merged PR. Every exit before the link completes rolls step 4 back
 * (D14(4)); a PR failure after the link keeps it (`pr_failed`, retried by the `side_pending` re-check, D17). The outcome line
 * `synthetic_pushed` / `side_pushed` is written only after the link AND the PR succeed (D14(5)); a `pr_failed` exit writes
 * `pr_failed` / `side_pushed` instead (D23), so every turn has its one line.
 */
async function runSideFallback(f: SideFallbackInput): Promise<KbPublishResult> {
  let step: SideStep;
  try {
    step = await deliverAndLinkSide(f);
  } catch (err) {
    await rollbackBestEffort(f);
    throw err;
  }
  if (step.kind !== "linked") {
    await rollbackBestEffort(f);
    return step;
  }
  const D = f.remote.defaultBranch;
  await setTrackingBestEffort(f.writer, D, f.remote.tip, f);
  let prUrl: string;
  try {
    prUrl = await ensureKbSyncPr(f.installationId, f.owner, f.repo, D);
  } catch {
    reportPushHeld("pr_failed", "side_pushed", f);
    return { kind: "fallback_failed", fallbackReason: "pr_failed", pushErr: f.pushErr };
  }
  reportPushHeld("synthetic_pushed", "side_pushed", f);
  return { kind: "fallback", prUrl, commitCount: 1 };
}

/**
 * Steps 2-6 of the post-session sync (#12600): authoritative remote state, the refusals, the hash checks, the build of
 * `S`, Guard 1, the local branch update, the push and the protected-branch fallback. One isolated directory per turn,
 * disposed in `finally`.
 */
export async function publishKbOnly(input: KbPublishInput): Promise<KbPublishResult> {
  const { headSha, installationId, writer } = input;
  let isolated: IsolatedPushDirHandle | undefined;
  let tipRead: string | undefined;
  try {
    const { url, owner, repo } = await resolveRepoUrl(input.userId, input.workspaceId).catch((err: unknown) => {
      throw asKbError(err);
    });
    try {
      isolated = createIsolatedPushDir(input.workspacePath);
    } catch (err) {
      throw new KbSyncError("isolated_refused", undefined, err instanceof IsolatedPushDirRefusal ? err.reason : undefined);
    }
    const remote = await readRemoteState(isolated, installationId, url);
    if (!remote) throw new KbHeld("remote_branch_absent");
    tipRead = remote.tip;
    const D = remote.defaultBranch;
    if (input.refName !== `refs/heads/${D}`) throw new KbHeld("non_default_branch");
    const T = remote.tip;
    if (T === headSha) {
      // Nothing to push; the tracking ref stops the next turn's token mint (R8).
      await setTrackingBestEffort(writer, D, T, input);
      return { kind: "noop" };
    }
    if (!(await isCommitPresent(isolated, T))) throw new KbHeld("remote_unknown_tip");
    if (!(await isAncestor(isolated, T, headSha))) throw new KbHeld("remote_ahead");

    const tV = await readVerified(isolated, T);
    const hV = await readVerified(isolated, headSha);
    if (!tV || !hV) throw new KbHeld("hash_mismatch");
    const headKb = kbOf(hV.root);
    const tKb = kbOf(tV.root);
    if (headKb && headKb.mode !== TREE_MODE) throw new KbHeld("kb_not_tree");
    // No KB in HEAD: nothing a KB-only commit can carry. A remote KB the workspace dropped wholesale is held (an overlay
    // cannot express it); no KB on either side is a code-only change like any other held one.
    if (!headKb && tKb) throw new KbHeld("kb_absent");
    if (!headKb || (tKb && tKb.mode === TREE_MODE && tKb.id === headKb.id)) {
      if (hV.commit.tree !== tV.commit.tree) throw new KbHeld("held_foreign");
      return { kind: "noop" };
    }

    // D5b: the side branch already carries HEAD's KB (nothing new this turn): no push to D, no new local commit, one PR
    // re-check (D17). P must be present (no fetch) and hash-verify; otherwise the turn proceeds.
    let sideLineage = false;
    if (remote.sideTip !== null && (await isCommitPresent(isolated, remote.sideTip))) {
      const pV = await readVerified(isolated, remote.sideTip);
      const pKb = pV ? kbOf(pV.root) : undefined;
      if (pKb && pKb.mode === TREE_MODE && pKb.id === headKb.id) return await recheckSidePr(installationId, owner, repo, D, remote.sideTip, input);
      // D14(3): a present, hash-verified side tip in HEAD's history must stay in the local branch's history before the push.
      sideLineage = pV !== null && (await isAncestor(isolated, remote.sideTip, headSha));
    }

    const { sha: S, tree: sTree } = await buildKbOverlay(isolated, tV.root, headKb, [T]);
    const guardedS = await guardKbOnly(isolated, S, tV.root);
    if (!guardedS) throw new KbHeld("guard_failed");

    // Step 4 (R1, R14; P7): keep the clone fast-forwardable BEFORE the push. KB-only local changes: the branch moves to
    // `S` itself (same tree, linear history). Held non-KB changes, or a side tip in HEAD's history (D14(3): `S` has parent
    // `T` only, so it would drop that lineage): the branch moves to `M` = merge(headSha, S), which keeps them. Either way the
    // next turn's `T` (= `S`) is an ancestor of the local branch, and a crash anywhere after this CAS loses nothing.
    const kbOnly = sTree === hV.commit.tree && !sideLineage;
    const localNext = kbOnly ? S : await commitTree(isolated, hV.commit.tree, [headSha, S], KB_SYNC_MERGE_MSG);
    await handOver(isolated, writer, kbOnly ? [S, sTree] : [S, sTree, localNext]);
    await casLocalBranch(writer, D, localNext, headSha);

    try {
      await pushVerifiedKbOnly({ installationId, url, guarded: guardedS, ref: `refs/heads/${D}`, defaultBranch: D });
    } catch (err) {
      if (!(err instanceof KbSyncError) || err.pushClass !== "protected_branch") throw err;
      return await runSideFallback({
        ...input, isolated, url, owner, repo, remote, tV, headTree: hV.commit.tree, headKb, guardedS, localNext, pushErr: err,
      });
    }
    await setTrackingBestEffort(writer, D, S, input);
    // D22(a): the M arm taken only for side lineage (HEAD's tree is S's tree) is replaced by S once S is on D. Lossless (same
    // tree; S carries HEAD's KB, a superset of the side tip's), so a lifted protection leaves local = S = remote, never an
    // unpushed merge that holds every later KB UI write as `held_commits`.
    if (localNext !== S && sTree === hV.commit.tree) await relinkBestEffort(writer, D, S, localNext, input);
    reportPushHeld("synthetic_pushed", "pushed", input);
    return { kind: "pushed" };
  } catch (caught) {
    const err = asKbError(caught);
    if (err instanceof KbHeld) {
      reportPushHeld(err.reason, "held", input);
      return { kind: "held", reason: err.reason };
    }
    throw err;
  } finally {
    if (isolated && tipRead !== undefined && input.onHeldFiles) {
      try {
        await input.onHeldFiles({ isolatedDir: isolated, T: tipRead, headSha });
      } catch {
        // The hook owns its own reporting (#12714); the turn's result never changes.
      }
    }
    disposeIsolated(isolated, "session-sync");
  }
}
