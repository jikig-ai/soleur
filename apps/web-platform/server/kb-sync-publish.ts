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
import { validateBranchFormat } from "./branch-validation";
import { gitWithInstallationAuth } from "./git-auth";
import { runIsolatedGitLocal, verifyObject } from "./git-isolated-local";
import { createIsolatedPushDir, type IsolatedPushDirHandle } from "./git-isolated-push-dir";
import { createChildLogger } from "./logger";
import { AGENT_AUTHOR_EMAIL, AGENT_AUTHOR_NAME, disposeIsolated } from "./push-branch";

const log = createChildLogger("session-sync");

// #5426 — push-error classification for the protected-branch fallback.
// `protected_branch` routes to the side-branch + PR fallback; `persistent_other`
// is a non-protection reject that must NOT silently retry-loop (notably
// `shallow update not allowed` — these are shallow clones); `other` keeps the
// existing best-effort retry-next-session behaviour (auth/network/transient).
export type PushErrorClass = "protected_branch" | "persistent_other" | "other";

/** GitHub's protected-branch reject, as the first token of a `remote:` line (R2, R16). */
const GH006_LINE_RE = /^remote: error: GH006:/m;
/** GitHub's require-PR text on a `remote:` line (#5426; also a GH013 ruleset that requires a PR; CTO ruling D9). */
const REQUIRE_PR_LINE_RE = /^remote:[^\n]*Changes must be made through a pull request/m;

/**
 * Classify a failed `git push` error from git's STDERR only (#12600, CTO rulings R2, R16, re-ruled by D9). The fallback keys
 * on a line-anchored `remote: error: GH006:` OR a `remote:` line carrying GitHub's require-PR text, so neither a ref name
 * inside git's own status line (ref names cannot hold spaces) nor `err.message` (which embeds argv: the URL and the pushed
 * refspec) can steer it. CRLF and a lone CR (progress output) both end a line. GH013 without the require-PR text (secret
 * push protection) stays `other`. Narrow by design: auth/network rejections fall through to `other`.
 */
export function classifyPushError(err: unknown): PushErrorClass {
  if (!(err instanceof Error)) return "other";
  const raw = (err as { stderr?: unknown }).stderr;
  const stderr = (Buffer.isBuffer(raw) ? raw.toString("utf8") : typeof raw === "string" ? raw : "").replace(/\r\n?/g, "\n");
  if (GH006_LINE_RE.test(stderr) || REQUIRE_PR_LINE_RE.test(stderr)) return "protected_branch";
  if (stderr.includes("shallow update not allowed")) return "persistent_other";
  return "other";
}

// #5426 — protected-branch fallback. When the user's default branch is
// protected, the post-session KB commit can't be pushed onto it; instead a side
// commit (built on the remote tip like S, #12600 R17) accretes onto a durable
// side branch in the user's OWN repo, with a never-auto-merged PR into the
// default branch.
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

// ---------------------------------------------------------------------------
// The KB-only publish (#12600, CTO ruling R14): the sync pushes only a commit the server built.
// ---------------------------------------------------------------------------

const KB_ENTRY = "knowledge-base";
const TREE_MODE = "40000";
const SIDE_REF = `refs/heads/${KB_SYNC_SIDE_BRANCH}`;
const LS_REMOTE_TIMEOUT_MS = 30_000;
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
  | "side_pending"
  | "side_declined"
  | "kb_absent"
  | "held_foreign"
  | "synthetic_pushed";

export type KbPushOutcome = "pushed" | "side_pushed" | "held";

const HELD_WARN_MESSAGES: Partial<Record<KbPushHeldReason, string>> = {
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
  side_ahead: "KB sync held: soleur/kb-sync holds knowledge-base content the workspace has not seen",
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
  log.info({ op: "kb-sync.push-held", reason, outcome }, "KB sync push outcome");
  const message = HELD_WARN_MESSAGES[reason];
  if (!message) return;
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
  | "fetch_failed"
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

export interface RemoteState {
  readonly defaultBranch: string;
  readonly tip: string;
  readonly sideTip: string | null;
}

/**
 * Parse `ls-remote --symref <url> HEAD refs/heads/soleur/kb-sync` (R2, R17): exactly one `ref: refs/heads/<D>\tHEAD`
 * line, one `<sha>\tHEAD` line, at most one exact `refs/heads/soleur/kb-sync` line. Other refs the tail-matching
 * patterns may return (`refs/x/HEAD`) are ignored; a duplicate or malformed line of the three throws. `null` = the remote
 * has no resolvable HEAD (`remote_branch_absent`).
 */
export function parseRemoteState(out: string): RemoteState | null {
  let defaultBranch: string | null = null;
  let tip: string | null = null;
  let sideTip: string | null = null;
  let seenSide = false;
  for (const line of out.split("\n")) {
    if (line === "") continue;
    const tab = line.indexOf("\t");
    if (tab < 0) throw new KbSyncError("remote_state_invalid");
    const left = line.slice(0, tab);
    const name = line.slice(tab + 1);
    if (left.startsWith("ref: ")) {
      if (name !== "HEAD") continue;
      if (defaultBranch !== null) throw new KbSyncError("remote_state_invalid");
      const target = left.slice("ref: ".length);
      if (!target.startsWith("refs/heads/")) throw new KbSyncError("remote_state_invalid");
      const branch = target.slice("refs/heads/".length);
      try {
        validateBranchFormat(branch);
      } catch {
        throw new KbSyncError("remote_state_invalid");
      }
      defaultBranch = branch;
      continue;
    }
    if (!HEX40.test(left)) throw new KbSyncError("remote_state_invalid");
    if (name === "HEAD") {
      if (tip !== null) throw new KbSyncError("remote_state_invalid");
      tip = left;
    } else if (name === SIDE_REF) {
      if (seenSide) throw new KbSyncError("remote_state_invalid");
      seenSide = true;
      sideTip = left;
    }
  }
  if (defaultBranch === null || tip === null) return null;
  return { defaultBranch, tip, sideTip };
}

/** One hardened `ls-remote --symref` against the literal URL; no agent-chosen name in argv. */
export async function readRemoteState(
  isolated: IsolatedPushDirHandle,
  installationId: number,
  url: string,
): Promise<RemoteState | null> {
  let out: Buffer;
  try {
    out = await gitWithInstallationAuth(["ls-remote", "--symref", url, "HEAD", SIDE_REF], installationId, {
      hardened: isolated,
      timeout: LS_REMOTE_TIMEOUT_MS,
    });
  } catch {
    throw new KbSyncError("ls_remote_failed");
  }
  return parseRemoteState(out.toString("utf8"));
}

interface TreeEntry {
  readonly mode: string;
  /** latin1, so the bytes round-trip exactly into `mktree -z`. */
  readonly name: string;
  readonly id: string;
}

/** Parse raw tree object bytes (`<mode> <name>\0<20-byte id>`, repeated); `null` on any malformed entry. */
function parseTree(bytes: Buffer): TreeEntry[] | null {
  const out: TreeEntry[] = [];
  let i = 0;
  while (i < bytes.length) {
    const sp = bytes.indexOf(0x20, i);
    if (sp < 0) return null;
    const nul = bytes.indexOf(0x00, sp + 1);
    if (nul < 0 || nul + 21 > bytes.length) return null;
    const mode = bytes.toString("latin1", i, sp);
    if (!/^[0-7]{5,6}$/.test(mode)) return null;
    out.push({ mode, name: bytes.toString("latin1", sp + 1, nul), id: bytes.toString("hex", nul + 1, nul + 21) });
    i = nul + 21;
  }
  return out;
}

interface CommitHeader {
  readonly tree: string;
  readonly parents: readonly string[];
  readonly author: string;
  readonly committer: string;
  readonly message: string;
}

function parseCommit(bytes: Buffer): CommitHeader | null {
  const text = bytes.toString("latin1");
  const end = text.indexOf("\n\n");
  if (end < 0) return null;
  let tree = "";
  let author = "";
  let committer = "";
  const parents: string[] = [];
  for (const line of text.slice(0, end).split("\n")) {
    if (line.startsWith("tree ")) tree = line.slice(5);
    else if (line.startsWith("parent ")) parents.push(line.slice(7));
    else if (line.startsWith("author ")) author = line.slice(7);
    else if (line.startsWith("committer ")) committer = line.slice(10);
  }
  if (!HEX40.test(tree) || !parents.every((p) => HEX40.test(p))) return null;
  return { tree, parents, author, committer, message: text.slice(end + 2) };
}

/** A commit with its hash-verified root tree. */
interface VerifiedCommit {
  readonly id: string;
  readonly commit: CommitHeader;
  readonly root: readonly TreeEntry[];
}

/** `verifyObject`'s verified bytes, `null` when unverified; a child that could not run is `local_git_failed` (D13). */
async function verifiedBytes(isolated: IsolatedPushDirHandle, type: "commit" | "tree", id: string): Promise<Buffer | null> {
  const v = await verifyObject(isolated, type, id);
  if (v.kind === "failed") throw new KbSyncError("local_git_failed");
  return v.kind === "verified" ? v.bytes : null;
}

/** Hash-verify a commit and its root tree (R14, R15); the parse reads exactly the verified bytes. */
async function readVerified(isolated: IsolatedPushDirHandle, id: string): Promise<VerifiedCommit | null> {
  const commitBytes = await verifiedBytes(isolated, "commit", id);
  const commit = commitBytes ? parseCommit(commitBytes) : null;
  if (!commit) return null;
  const treeBytes = await verifiedBytes(isolated, "tree", commit.tree);
  const root = treeBytes ? parseTree(treeBytes) : null;
  return root ? { id, commit, root } : null;
}

const kbOf = (root: readonly TreeEntry[]): TreeEntry | undefined => root.find((e) => e.name === KB_ENTRY);
const entryKey = (e: TreeEntry): string => `${e.mode} ${e.id}\t${e.name}`;

/**
 * `cat-file -t` says `commit`: the object is present (its bytes are verified separately). Tri-state (D13): a child that
 * could not run (code -1: spawn failure, timeout, kill) is `local_git_failed`, never "absent".
 */
async function isCommitPresent(isolated: IsolatedPushDirHandle, id: string): Promise<boolean> {
  const r = await runIsolatedGitLocal(isolated, ["cat-file", "-t", id]);
  if (r.code === -1) throw new KbSyncError("local_git_failed");
  return r.code === 0 && r.stdout.toString("utf8").trim() === "commit";
}

/** `merge-base --is-ancestor`: 0 yes, 1 no, anything else a local git failure. */
async function isAncestor(isolated: IsolatedPushDirHandle, ancestor: string, of: string): Promise<boolean> {
  const r = await runIsolatedGitLocal(isolated, ["merge-base", "--is-ancestor", ancestor, of]);
  if (r.code === 0) return true;
  if (r.code === 1) return false;
  throw new KbSyncError("local_git_failed");
}

const IDENTITY_ARGS = ["-c", `user.name=${AGENT_AUTHOR_NAME}`, "-c", `user.email=${AGENT_AUTHOR_EMAIL}`] as const;
const IDENTITY_PREFIX = `${AGENT_AUTHOR_NAME} <${AGENT_AUTHOR_EMAIL}> `;

function mktreeInput(entries: readonly TreeEntry[]): Buffer {
  return Buffer.concat(
    entries.map((e) => {
      const type = e.mode === TREE_MODE ? "tree" : e.mode === "160000" ? "commit" : "blob";
      return Buffer.from(`${e.mode.padStart(6, "0")} ${type} ${e.id}\t${e.name}\0`, "latin1");
    }),
  );
}

async function commitTree(
  isolated: IsolatedPushDirHandle,
  tree: string,
  parents: readonly string[],
  message: string,
): Promise<string> {
  const r = await runIsolatedGitLocal(isolated, [
    ...IDENTITY_ARGS,
    "commit-tree",
    tree,
    ...parents.flatMap((p) => ["-p", p]),
    "-m",
    message,
  ]);
  const sha = r.stdout.toString("utf8").trim();
  if (r.code !== 0 || !HEX40.test(sha)) throw new KbSyncError("local_git_failed");
  return sha;
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
  const entries = [...baseRoot.filter((e) => e.name !== KB_ENTRY), { mode: TREE_MODE, name: KB_ENTRY, id: kb.id }];
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
  const a = root.filter((e) => e.name !== KB_ENTRY).map(entryKey).sort();
  const b = baseRoot.filter((e) => e.name !== KB_ENTRY).map(entryKey).sort();
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
    const raw = (err as { stderr?: unknown } | null)?.stderr;
    const stderr = Buffer.isBuffer(raw) ? raw.toString("utf8") : typeof raw === "string" ? raw : "";
    const rejected = pushClass !== "other" || /^\s*! \[(rejected|remote rejected)\]/m.test(stderr);
    throw new KbSyncError(rejected ? "push_rejected" : "push_transient", pushClass);
  }
}

/** The message of the local merge `M` that keeps held (non-KB) commits on the local branch next to `S` (P7). */
export const KB_SYNC_MERGE_MSG = "Soleur: merge knowledge-base sync";

/**
 * The workspace writes the sync makes, injected by `session-sync.ts` (its guarded `runConnectedRepoGit`, R12, R19, R20):
 * `unpack-objects -q` with the pack on stdin, the `--no-deref` CAS of `refs/heads/<b>` and the tracking ref. Each throws
 * on failure (the error carries git's stderr).
 */
export interface KbWorkspaceWriter {
  unpack(pack: Buffer): void;
  casBranch(branch: string, next: string, prev: string): void;
  setTracking(branch: string, sha: string): void;
}

const stderrOf = (err: unknown): string => {
  const raw = (err as { stderr?: unknown } | null)?.stderr;
  return Buffer.isBuffer(raw) ? raw.toString("utf8") : typeof raw === "string" ? raw : "";
};

/**
 * Hand the server-built objects to the workspace (CTO ruling D10): `pack-objects --stdout -q` over an EXPLICIT object list
 * (no `--revs`), piped to `unpack-objects -q`. Every parent of a server-built commit is already in the workspace (T,
 * headSha, a present side tip P, or a commit this function handed over earlier), and the KB subtree is HEAD's, so the only
 * missing objects are the new commit and its new root tree:
 *   S -> S + S^{tree};  M -> S + S^{tree} + M (M's tree is headSha's);  side -> side + side^{tree};  M' -> side + side^{tree} + M'.
 * A `--revs` walk re-sent the KB change set (`^headSha` is not an edge of S) and hit the stdout cap above 64 MB.
 */
async function handOver(isolated: IsolatedPushDirHandle, writer: KbWorkspaceWriter, objects: readonly string[]): Promise<void> {
  if (!objects.every((o) => HEX40.test(o))) throw new KbHeld("unpack_failed");
  const pack = await runIsolatedGitLocal(isolated, ["pack-objects", "--stdout", "-q"], { input: `${objects.join("\n")}\n` });
  if (pack.code !== 0) throw new KbHeld("unpack_failed");
  try {
    writer.unpack(pack.stdout);
  } catch {
    throw new KbHeld("unpack_failed");
  }
}

/** The `--no-deref` CAS of the local branch: a moved branch (`but expected`) is `head_moved`, anything else `ref_update_failed`. */
function casLocalBranch(writer: KbWorkspaceWriter, branch: string, next: string, prev: string): void {
  try {
    writer.casBranch(branch, next, prev);
  } catch (err) {
    throw new KbHeld(/but expected/.test(stderrOf(err)) ? "head_moved" : "ref_update_failed");
  }
}

/**
 * The advisory tracking ref (R8): best-effort, a failure only means one more token mint next turn. A failure that
 * repeats (a stale `.lock`, a broken ref store) mints a token every turn, so it mirrors to Sentry at warning level,
 * debounced per workspace (cq-silent-fallback-must-mirror-to-sentry; CTO ruling D4). No path, sha or branch name.
 */
function setTrackingBestEffort(writer: KbWorkspaceWriter, branch: string, sha: string, ctx: KbSyncContext): void {
  try {
    writer.setTracking(branch, sha);
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

/** The literal `https://github.com/<owner>/<repo>.git` push URL (R2): never `remote.origin.url`. */
async function resolvePushUrl(userId: string, workspaceId: string): Promise<{ url: string; owner: string; repo: string }> {
  const { getCurrentRepoUrl } = await import("./current-repo-url");
  const { owner, repo } = parseOwnerRepo(await getCurrentRepoUrl(userId, workspaceId));
  if (!owner || !repo) throw new KbSyncError("remote_state_invalid");
  return { url: `https://github.com/${owner}/${repo}.git`, owner, repo };
}

/** Why the protected-branch fallback did not deliver (the `fallback_reason` tag, closed). */
export type KbFallbackReason = "side_hash_mismatch" | "side_guard_failed" | "side_push_rejected" | "pr_failed";

export type KbPublishResult =
  | { readonly kind: "pushed" }
  | { readonly kind: "held"; readonly reason: KbPushHeldReason }
  | { readonly kind: "noop" }
  | { readonly kind: "fallback"; readonly prUrl: string; readonly commitCount: number }
  /** `pushErr` is null when no push ran this turn (the `side_pending` PR re-check, D17). */
  | { readonly kind: "fallback_failed"; readonly fallbackReason: KbFallbackReason; readonly pushErr: KbSyncError | null };

export interface KbPublishInput extends KbSyncContext {
  readonly workspacePath: string;
  readonly installationId: number;
  /** Frozen HEAD (`readWorkspaceHeadRef`), read before any git child. */
  readonly headSha: string;
  readonly refName: string;
  readonly writer: KbWorkspaceWriter;
}

interface SideFallbackInput {
  readonly isolated: IsolatedPushDirHandle;
  readonly installationId: number;
  readonly url: string;
  readonly owner: string;
  readonly repo: string;
  readonly writer: KbWorkspaceWriter;
  readonly ctx: KbSyncContext;
  readonly remote: RemoteState;
  readonly tV: VerifiedCommit;
  readonly headSha: string;
  /** HEAD's verified root tree (the tree of `M` and `M'`). */
  readonly headTree: string;
  readonly headKb: TreeEntry;
  /** Guard 1's token for `S` (a side commit identical to `S` reuses it: Guard 1 once per sha, D13). */
  readonly guardedS: GuardedSha;
  /** The value step 4 moved the local branch to (`S`, or `M`): the link's CAS old value and the rollback's. */
  readonly localNext: string;
  readonly pushErr: KbSyncError;
}

/** Find or create the never-auto-merged PR `soleur/kb-sync` -> `D` in the user's own repo. */
async function ensureKbSyncPr(installationId: number, owner: string, repo: string, D: string): Promise<string> {
  // Dynamic import keeps github-app out of the static graph (sibling tests mock git-auth but not github-app).
  const { createPullRequest, findOpenPullRequest } = await import("./github-app");
  const existing = await findOpenPullRequest(installationId, owner, repo, KB_SYNC_SIDE_BRANCH, D);
  if (existing) return existing.htmlUrl;
  const pr = await createPullRequest(installationId, owner, repo, KB_SYNC_SIDE_BRANCH, D, KB_SYNC_PR_TITLE, kbSyncPrBody(D));
  return pr.htmlUrl;
}

/**
 * D17: the side branch already carries HEAD's KB (`side_pending`). One GET (`state=all`) re-checks its PR, because the link
 * now precedes the PR (D14(2)) and a single REST failure would otherwise leave the KB on a branch no Owner sees:
 *   - an open PR, or a merged one on `P`: `side_pending` (info, nothing to do);
 *   - a closed, unmerged PR whose head is `P`: the Owner declined this exact content, never reopened: `side_declined` (info);
 *   - no PR on `P`: create it (the `pr_failed` retry); a create failure is `fallback_failed pr_failed`;
 *   - the GET fails: `side_pending`, nothing created (fail toward no duplicate PR).
 */
async function recheckSidePr(installationId: number, owner: string, repo: string, D: string, P: string, ctx: KbSyncContext): Promise<KbPublishResult> {
  const { createPullRequest, listPullRequestsForHead } = await import("./github-app");
  let prs: Awaited<ReturnType<typeof listPullRequestsForHead>>;
  try {
    prs = await listPullRequestsForHead(installationId, owner, repo, KB_SYNC_SIDE_BRANCH, D);
  } catch {
    throw new KbHeld("side_pending");
  }
  if (prs.some((pr) => pr.state === "open")) throw new KbHeld("side_pending");
  const onP = prs.filter((pr) => pr.headSha === P);
  if (onP.some((pr) => !pr.merged)) throw new KbHeld("side_declined");
  if (onP.length > 0) throw new KbHeld("side_pending");
  let prUrl: string;
  try {
    prUrl = (await createPullRequest(installationId, owner, repo, KB_SYNC_SIDE_BRANCH, D, KB_SYNC_PR_TITLE, kbSyncPrBody(D))).htmlUrl;
  } catch {
    return { kind: "fallback_failed", fallbackReason: "pr_failed", pushErr: null };
  }
  reportPushHeld("side_pending", "held", ctx);
  return { kind: "fallback", prUrl, commitCount: 0 };
}

/**
 * D14(4), the scoped rollback: move the local branch back from `localNext` to `headSha`, best effort. Runs on every exit of the
 * fallback before its link completes; never after a non-protected D push error (the remote state is then unknown, and
 * `localNext` is the crash-safe value). A failed rollback (`head_moved`: the agent committed meanwhile) never changes the
 * turn's result: one debounced warning, no outcome line.
 */
function rollbackBestEffort(f: SideFallbackInput): void {
  try {
    casLocalBranch(f.writer, f.remote.defaultBranch, f.headSha, f.localNext);
  } catch (err) {
    const reason = err instanceof KbHeld ? err.reason : "ref_update_failed";
    log.warn({ op: "kb-sync.rollback", reason, workspaceId: f.ctx.workspaceId }, "KB sync: the local branch rollback failed");
    mirrorWarnWithDebounce(
      null,
      { feature: "session-sync", op: "kb-sync.rollback", message: "KB sync: the local branch rollback failed", tags: { reason }, extra: { userId: f.ctx.userId } },
      f.ctx.workspaceId,
      "kb-sync-rollback-failed",
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
 * fast-forward) or `(P, T)`. The link target is built BEFORE the side push (D14(1)), so nothing that can throw a non-held
 * error runs after a delivery, and the link runs right after it (D14(2)): the side commit itself when HEAD's tree is the side's
 * tree (no non-KB content to keep), else `M'` = merge(headSha, side) with HEAD's tree.
 */
async function deliverAndLinkSide(f: SideFallbackInput): Promise<SideStep> {
  const { isolated, installationId, url, remote, tV, headSha, headKb } = f;
  const fail = (fallbackReason: KbFallbackReason): SideStep => ({ kind: "fallback_failed", fallbackReason, pushErr: f.pushErr });
  const D = remote.defaultBranch;
  const T = remote.tip;
  const P = remote.sideTip;
  let parents: string[] = [T];
  if (P !== null) {
    // Phase 9 (D5e/D6c): a side tip absent from the workspace is adopted on the PULL side (fetched with server-owned have
    // refs, handed over, merged while its PR is open). Until then the push side holds the turn: `side_ahead`.
    if (!(await isCommitPresent(isolated, P))) throw new KbHeld("side_ahead");
    const pV = await readVerified(isolated, P);
    if (!pV) return fail("side_hash_mismatch");
    const pKb = kbOf(pV.root);
    const tKb = kbOf(tV.root);
    const prMerged = pKb !== undefined && tKb !== undefined && pKb.mode === tKb.mode && pKb.id === tKb.id;
    // Phase 9 (D5e/D6c): with no open PR, an abandoned P becomes a parent instead of a hold; here it is the interim refusal.
    if (!prMerged && !(await isAncestor(isolated, P, headSha))) throw new KbHeld("side_ahead");
    parents = pV.commit.parents.includes(T) || (await isAncestor(isolated, T, P)) ? [P] : [P, T];
  }

  const { sha: side, tree: sideTree } = await buildKbOverlay(isolated, tV.root, headKb, parents);
  const guarded = side === f.guardedS.sha ? f.guardedS : await guardKbOnly(isolated, side, tV.root);
  if (!guarded) return fail("side_guard_failed");
  const linkTo = sideTree === f.headTree ? side : await commitTree(isolated, f.headTree, [headSha, side], KB_SYNC_MERGE_MSG);
  try {
    await pushVerifiedKbOnly({ installationId, url, guarded, ref: SIDE_REF, defaultBranch: D });
  } catch (err) {
    return fail(err instanceof KbHeld ? "side_guard_failed" : "side_push_rejected");
  }
  // D5c/D14(2): the next turn finds the side commit local and an ancestor of HEAD, so (with no new edit) it is
  // `side_pending`: no push to D, no new merge commit. A failure here is a held reason, never a fallback failure.
  await handOver(isolated, f.writer, linkTo === side ? [side, sideTree] : [side, sideTree, linkTo]);
  casLocalBranch(f.writer, D, linkTo, f.localNext);
  return { kind: "linked" };
}

/**
 * Step 6, the protected-branch fallback: deliver and link the side commit, then the tracking ref (D11: `T`, what GitHub's D
 * is, never the side commit), then the never-auto-merged PR. Every exit before the link completes rolls step 4 back
 * (D14(4)); a PR failure after the link keeps it (`pr_failed`, retried by the `side_pending` re-check, D17). The outcome line
 * `synthetic_pushed` / `side_pushed` is written only after the link AND the PR succeed (D14(5)).
 */
async function runSideFallback(f: SideFallbackInput): Promise<KbPublishResult> {
  let step: SideStep;
  try {
    step = await deliverAndLinkSide(f);
  } catch (err) {
    rollbackBestEffort(f);
    throw err;
  }
  if (step.kind !== "linked") {
    rollbackBestEffort(f);
    return step;
  }
  const D = f.remote.defaultBranch;
  setTrackingBestEffort(f.writer, D, f.remote.tip, f.ctx);
  let prUrl: string;
  try {
    prUrl = await ensureKbSyncPr(f.installationId, f.owner, f.repo, D);
  } catch {
    return { kind: "fallback_failed", fallbackReason: "pr_failed", pushErr: f.pushErr };
  }
  reportPushHeld("synthetic_pushed", "side_pushed", f.ctx);
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
  try {
    const { url, owner, repo } = await resolvePushUrl(input.userId, input.workspaceId);
    try {
      isolated = createIsolatedPushDir(input.workspacePath);
    } catch {
      throw new KbSyncError("isolated_refused");
    }
    const remote = await readRemoteState(isolated, installationId, url);
    if (!remote) throw new KbHeld("remote_branch_absent");
    const D = remote.defaultBranch;
    if (input.refName !== `refs/heads/${D}`) throw new KbHeld("non_default_branch");
    const T = remote.tip;
    if (T === headSha) {
      // Nothing to push; the tracking ref stops the next turn's token mint (R8).
      setTrackingBestEffort(writer, D, T, input);
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
    casLocalBranch(writer, D, localNext, headSha);

    try {
      await pushVerifiedKbOnly({ installationId, url, guarded: guardedS, ref: `refs/heads/${D}`, defaultBranch: D });
    } catch (err) {
      if (!(err instanceof KbSyncError) || err.pushClass !== "protected_branch") throw err;
      return await runSideFallback({
        isolated, installationId, url, owner, repo, writer, ctx: input, remote, tV, headSha, headTree: hV.commit.tree, headKb,
        guardedS, localNext, pushErr: err,
      });
    }
    setTrackingBestEffort(writer, D, S, input);
    reportPushHeld("synthetic_pushed", "pushed", input);
    return { kind: "pushed" };
  } catch (err) {
    if (err instanceof KbHeld) {
      reportPushHeld(err.reason, "held", input);
      return { kind: "held", reason: err.reason };
    }
    throw err;
  } finally {
    disposeIsolated(isolated);
  }
}
