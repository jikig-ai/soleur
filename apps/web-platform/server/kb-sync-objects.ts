// ---------------------------------------------------------------------------
// KB sync objects: the token-free object reads and builds both halves of the KB sync share (#12718, ruling D25(1)).
//
// Every read here runs in the server-owned isolated directory (`runIsolatedGitLocal`, the workspace object store as the
// only alternate) and parses exactly the bytes whose id it recomputed. A leaf: it imports neither kb-sync-publish.ts nor
// push-branch.ts, so the pull (server/kb-sync-pull.ts) and the self-heal (server/workspace-sync.ts) reach it without the
// push. Errors are a neutral `KbObjectsError` with a closed reason; each caller maps it to its own held reason.
// ---------------------------------------------------------------------------

import { AGENT_AUTHOR_EMAIL, AGENT_AUTHOR_NAME } from "./agent-git-identity";
import { HEX40 } from "./approval/workspace-head";
import { runIsolatedGitLocal, verifyObject } from "./git-isolated-local";
import type { IsolatedPushDirHandle } from "./git-isolated-push-dir";
import { KB_ROOT } from "./kb-root";

/** A local step failed: the child could not run (`local_git_failed`, D13) or the hand-over did not land (`unpack_failed`). */
export type KbObjectsErrorReason = "local_git_failed" | "unpack_failed";

export class KbObjectsError extends Error {
  constructor(readonly reason: KbObjectsErrorReason) {
    super(`KB sync object step failed (${reason})`);
    this.name = "KbObjectsError";
  }
}

export const TREE_MODE = "40000";

export interface TreeEntry {
  readonly mode: string;
  /** latin1, so the bytes round-trip exactly into `mktree -z`. */
  readonly name: string;
  readonly id: string;
}

/** Parse raw tree object bytes (`<mode> <name>\0<20-byte id>`, repeated); `null` on any malformed entry. */
export function parseTree(bytes: Buffer): TreeEntry[] | null {
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

export interface CommitHeader {
  readonly tree: string;
  readonly parents: readonly string[];
  readonly author: string;
  readonly committer: string;
  readonly message: string;
}

export function parseCommit(bytes: Buffer): CommitHeader | null {
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
export interface VerifiedCommit {
  readonly id: string;
  readonly commit: CommitHeader;
  readonly root: readonly TreeEntry[];
}

/** `verifyObject`'s verified bytes, `null` when unverified; a child that could not run is `local_git_failed` (D13). */
async function verifiedBytes(isolated: IsolatedPushDirHandle, type: "commit" | "tree", id: string): Promise<Buffer | null> {
  const v = await verifyObject(isolated, type, id);
  if (v.kind === "failed") throw new KbObjectsError("local_git_failed");
  return v.kind === "verified" ? v.bytes : null;
}

/** Hash-verify a commit and its root tree (R14, R15); the parse reads exactly the verified bytes. */
export async function readVerified(isolated: IsolatedPushDirHandle, id: string): Promise<VerifiedCommit | null> {
  const commitBytes = await verifiedBytes(isolated, "commit", id);
  const commit = commitBytes ? parseCommit(commitBytes) : null;
  if (!commit) return null;
  const treeBytes = await verifiedBytes(isolated, "tree", commit.tree);
  const root = treeBytes ? parseTree(treeBytes) : null;
  return root ? { id, commit, root } : null;
}

export const kbOf = (root: readonly TreeEntry[]): TreeEntry | undefined => root.find((e) => e.name === KB_ROOT);
export const entryKey = (e: TreeEntry): string => `${e.mode} ${e.id}\t${e.name}`;
/** Two roots carry the same `knowledge-base` entry (both absent counts as equal). */
export const sameKb = (a: readonly TreeEntry[], b: readonly TreeEntry[]): boolean => {
  const x = kbOf(a);
  const y = kbOf(b);
  return x === undefined || y === undefined ? x === y : x.mode === y.mode && x.id === y.id;
};

/**
 * `cat-file -t` says `commit`: the object is present (its bytes are verified separately). Tri-state (D13): a child that
 * could not run (code -1: spawn failure, timeout, kill) is `local_git_failed`, never "absent".
 */
export async function isCommitPresent(isolated: IsolatedPushDirHandle, id: string): Promise<boolean> {
  const r = await runIsolatedGitLocal(isolated, ["cat-file", "-t", id]);
  if (r.code === -1) throw new KbObjectsError("local_git_failed");
  return r.code === 0 && r.stdout.toString("utf8").trim() === "commit";
}

/** `merge-base --is-ancestor`: 0 yes, 1 no, anything else a local git failure. */
export async function isAncestor(isolated: IsolatedPushDirHandle, ancestor: string, of: string): Promise<boolean> {
  const r = await runIsolatedGitLocal(isolated, ["merge-base", "--is-ancestor", ancestor, of]);
  if (r.code === 0) return true;
  if (r.code === 1) return false;
  throw new KbObjectsError("local_git_failed");
}

export const IDENTITY_ARGS = ["-c", `user.name=${AGENT_AUTHOR_NAME}`, "-c", `user.email=${AGENT_AUTHOR_EMAIL}`] as const;
export const IDENTITY_PREFIX = `${AGENT_AUTHOR_NAME} <${AGENT_AUTHOR_EMAIL}> `;

export function mktreeInput(entries: readonly TreeEntry[]): Buffer {
  return Buffer.concat(
    entries.map((e) => {
      const type = e.mode === TREE_MODE ? "tree" : e.mode === "160000" ? "commit" : "blob";
      return Buffer.from(`${e.mode.padStart(6, "0")} ${type} ${e.id}\t${e.name}\0`, "latin1");
    }),
  );
}

/** `commit-tree` with the Soleur identity, token-free in the isolated directory. */
export async function commitTree(
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
  if (r.code !== 0 || !HEX40.test(sha)) throw new KbObjectsError("local_git_failed");
  return sha;
}

/** The one workspace write the hand-over needs: `unpack-objects -q` with the pack on stdin (throws on failure). */
export interface KbUnpacker {
  unpack(pack: Buffer): void;
}

/**
 * Hand the named objects to the workspace (CTO ruling D10): `pack-objects --stdout -q` over an EXPLICIT object list (no
 * `--revs`), piped to `unpack-objects -q`. The caller names every object; nothing here walks history.
 */
export async function handOver(
  isolated: IsolatedPushDirHandle,
  writer: KbUnpacker,
  objects: readonly string[],
  opts: { readonly maxBufferBytes?: number } = {},
): Promise<void> {
  if (!objects.every((o) => HEX40.test(o))) throw new KbObjectsError("unpack_failed");
  const pack = await runIsolatedGitLocal(isolated, ["pack-objects", "--stdout", "-q"], {
    input: `${objects.join("\n")}\n`,
    ...(opts.maxBufferBytes === undefined ? {} : { maxBufferBytes: opts.maxBufferBytes }),
  });
  if (pack.code !== 0) throw new KbObjectsError("unpack_failed");
  try {
    writer.unpack(pack.stdout);
  } catch {
    throw new KbObjectsError("unpack_failed");
  }
}
