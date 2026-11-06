/**
 * The approval gate's read of the workspace HEAD (ADR-309 flip item 9b). A leaf: it imports only `node:fs` and `node:path`
 * (a content test pins that), so it joins `server/approval/` without a path to the Owner's decide module.
 *
 * Why not `git rev-parse HEAD`: that runs git in the server process, outside the sandbox, inside a directory the agent can
 * write. It would consult the repository's own config and whatever `GIT_*` variables the server environment holds; measured
 * (git 2.56): an inherited `GIT_DIR` redirected the read to another repository, and a planted `.git/commondir` still
 * redirected it with `GIT_DIR`, `GIT_COMMON_DIR` and `GIT_OBJECT_DIRECTORY` all pinned. This reader executes no git, reads
 * no environment variable and no git config; it opens `HEAD` and one ref (or `packed-refs`) as data.
 *
 * What this does NOT claim: that the displayed sha cannot be falsified. The agent writes HEAD, the refs and the objects
 * anyway. The control that matters is that the sha the Owner approved is the sha the push sends, and the push's own local
 * `cat-file` check. What this removes is git running here under agent-controlled configuration.
 *
 * Every refusal throws `WorkspaceHeadUnreadable` with a closed `reason`; no path or file content leaves in the message.
 */

import { closeSync, constants, fstatSync, openSync, readSync, realpathSync, statSync } from "node:fs";
import { join, sep } from "node:path";

export type WorkspaceHeadReason =
  | "git_dir_not_plain"
  | "head_unreadable"
  | "ref_invalid"
  | "ref_unresolvable"
  | "reftable"
  | "symref_chain"
  | "not_hex40";

/** The workspace HEAD cannot be read safely. The message is static; `reason` is the closed discriminator. */
export class WorkspaceHeadUnreadable extends Error {
  constructor(readonly reason: WorkspaceHeadReason) {
    super("workspace HEAD is not readable");
    this.name = "WorkspaceHeadUnreadable";
  }
}

/** Why `readSmallRegularFile` refused. `ENOENT` / `ENOTDIR` mean "absent"; everything else means "present but unusable". */
export type SmallFileFailure = "ENOENT" | "ENOTDIR" | "NOT_REGULAR" | "TOO_LARGE" | "SHORT_READ" | "IO";

export class SmallFileError extends Error {
  constructor(readonly code: SmallFileFailure) {
    super("small file not readable");
    this.name = "SmallFileError";
  }
}

/**
 * Read a small file the agent may have replaced. The ONLY place this pattern is written (workspace HEAD, loose ref,
 * `packed-refs`, and the creator's `shallow` copy):
 *  - `O_NOFOLLOW`: a symlink as the final component is refused (the kernel, not a pre-open `lstat`, so there is no
 *    check-then-open window);
 *  - `O_NONBLOCK`: opening a FIFO returns at once instead of waiting for a writer;
 *  - `fstat` on the open descriptor: must be a regular file no larger than `maxBytes`;
 *  - the bytes read must equal the size `fstat` reported (a short read or a file that grew refuses).
 */
export function readSmallRegularFile(path: string, maxBytes: number): string {
  let fd: number;
  try {
    fd = openSync(path, constants.O_RDONLY | constants.O_NONBLOCK | constants.O_NOFOLLOW);
  } catch (err) {
    const code = (err as NodeJS.ErrnoException)?.code;
    throw new SmallFileError(code === "ENOENT" || code === "ENOTDIR" ? code : "IO");
  }
  try {
    const st = fstatSync(fd);
    if (!st.isFile()) throw new SmallFileError("NOT_REGULAR");
    if (st.size > maxBytes) throw new SmallFileError("TOO_LARGE");
    const buf = Buffer.alloc(st.size);
    let off = 0;
    while (off < st.size) {
      const n = readSync(fd, buf, off, st.size - off, off);
      if (n === 0) break;
      off += n;
    }
    if (off !== st.size) throw new SmallFileError("SHORT_READ");
    return buf.toString("utf8");
  } catch (err) {
    if (err instanceof SmallFileError) throw err;
    throw new SmallFileError("IO");
  } finally {
    try {
      closeSync(fd);
    } catch {
      /* nothing to do: the descriptor is gone either way */
    }
  }
}

const HEX40 = /^[0-9a-f]{40}$/;
const HEX64 = /^[0-9a-f]{64}$/;
const HEAD_MAX_BYTES = 4 * 1024;
const REF_MAX_BYTES = 4 * 1024;
const PACKED_REFS_MAX_BYTES = 8 * 1024 * 1024;

/** `refs/...`, no empty/`.`/`..` component, no `.lock` suffix, and none of the characters git forbids in a ref name. */
function isSafeRefName(name: string): boolean {
  if (!name.startsWith("refs/") || name.length > 1024) return false;
  if (name.endsWith(".lock") || name.endsWith("/") || name.includes("..") || name.includes("@{")) return false;
  // eslint-disable-next-line no-control-regex -- control characters are exactly what is being refused
  if (/[\u0000- \u007f~^:?*[\\]/.test(name)) return false;
  return name.split("/").every((c) => c !== "" && c !== "." && c !== "..");
}

/** The body of a ref file or HEAD: one trailing "\n" is the format; anything else (CRLF, uppercase, spaces) is not trimmed away. */
function stripOneNewline(body: string): string {
  return body.endsWith("\n") ? body.slice(0, -1) : body;
}

function classifyBody(body: string, onBad: WorkspaceHeadReason): string {
  if (HEX40.test(body)) return body;
  if (HEX64.test(body)) throw new WorkspaceHeadUnreadable("not_hex40");
  if (body.startsWith("ref:")) throw new WorkspaceHeadUnreadable("symref_chain");
  throw new WorkspaceHeadUnreadable(onBad);
}

/** The first exact `<40-hex> <name>` line of `packed-refs`; header (`#`) and peeled (`^`) lines are skipped. */
function packedRefSha(body: string, name: string): string | undefined {
  for (const line of body.split("\n")) {
    if (line === "" || line.startsWith("#") || line.startsWith("^")) continue;
    const sp = line.indexOf(" ");
    if (sp !== 40) continue;
    if (line.slice(sp + 1) !== name) continue;
    const sha = line.slice(0, sp);
    if (HEX40.test(sha)) return sha;
    if (HEX64.test(sha)) throw new WorkspaceHeadUnreadable("not_hex40");
    throw new WorkspaceHeadUnreadable("ref_invalid");
  }
  return undefined;
}

/**
 * The commit sha the workspace's HEAD resolves to, as a 40-hex string. Spawns nothing, reads no environment variable.
 *
 * `<workspace>/.git` must be a real directory whose real path is exactly `<real workspace>/.git` (a symlinked `.git`
 * would make both sides of the later containment compare resolve into the other repository). HEAD is either detached (a
 * 40-hex body) or `ref: <name>` with exactly one hop: the loose ref file, else `packed-refs` (`git gc --auto` packs
 * `refs/heads/*`, and refusing that would turn routine maintenance into a permanent gate failure). A loose file that is
 * itself a symref, a `reftable` repository, an unborn HEAD or any non-regular file refuses.
 */
export function readWorkspaceHeadSha(workspacePath: string): string {
  let gitDir: string;
  try {
    const ws = realpathSync(workspacePath);
    gitDir = join(ws, ".git");
    if (realpathSync(gitDir) !== gitDir || !statSync(gitDir).isDirectory()) {
      throw new WorkspaceHeadUnreadable("git_dir_not_plain");
    }
  } catch (err) {
    if (err instanceof WorkspaceHeadUnreadable) throw err;
    throw new WorkspaceHeadUnreadable("git_dir_not_plain");
  }

  try {
    statSync(join(gitDir, "reftable"));
    throw new WorkspaceHeadUnreadable("reftable");
  } catch (err) {
    if (err instanceof WorkspaceHeadUnreadable) throw err;
    // Absent (the normal case) or unstatable: the files backend is the only one this reader understands, and the HEAD read below fails closed on anything odd.
  }

  let head: string;
  try {
    head = stripOneNewline(readSmallRegularFile(join(gitDir, "HEAD"), HEAD_MAX_BYTES));
  } catch {
    throw new WorkspaceHeadUnreadable("head_unreadable");
  }

  if (!head.startsWith("ref: ")) return classifyHeadBody(head);
  const name = head.slice("ref: ".length);
  if (!isSafeRefName(name)) throw new WorkspaceHeadUnreadable("ref_invalid");

  const refPath = join(gitDir, name);
  let loose: string | undefined;
  try {
    loose = stripOneNewline(readSmallRegularFile(refPath, REF_MAX_BYTES));
  } catch (err) {
    const code = err instanceof SmallFileError ? err.code : "IO";
    if (code !== "ENOENT" && code !== "ENOTDIR") throw new WorkspaceHeadUnreadable("ref_invalid");
  }

  if (loose !== undefined) {
    // Read-then-verify: the file just read must really live under the real `.git` (a symlinked `refs/heads` leads elsewhere).
    // The value is display-only; the push re-verifies the approved sha by content address.
    let realRef: string;
    try {
      realRef = realpathSync(refPath);
    } catch {
      throw new WorkspaceHeadUnreadable("ref_invalid");
    }
    if (!realRef.startsWith(gitDir + sep)) throw new WorkspaceHeadUnreadable("ref_invalid");
    return classifyBody(loose, "ref_invalid");
  }

  let packed: string;
  try {
    packed = readSmallRegularFile(join(gitDir, "packed-refs"), PACKED_REFS_MAX_BYTES);
  } catch {
    throw new WorkspaceHeadUnreadable("ref_unresolvable");
  }
  const sha = packedRefSha(packed, name);
  if (sha === undefined) throw new WorkspaceHeadUnreadable("ref_unresolvable");
  return sha;
}

/** A detached HEAD body: exactly 40 lowercase hex. */
function classifyHeadBody(head: string): string {
  if (HEX40.test(head)) return head;
  if (HEX64.test(head)) throw new WorkspaceHeadUnreadable("not_hex40");
  throw new WorkspaceHeadUnreadable("head_unreadable");
}
