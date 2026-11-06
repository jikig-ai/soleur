/**
 * The isolated git directory the approved cc push runs from (ADR-309 flip item 9b, option (ii)).
 *
 * `createIsolatedPushDir(workspacePath)` builds a fresh BARE git directory the server owns, writes its `HEAD`, `config`
 * (and, for a shallow workspace, a validated copy of `shallow`) itself with `fs`, and hands back the one workspace path the
 * push child may read: `<workspace>/.git/objects`, exposed only through `GIT_ALTERNATE_OBJECT_DIRECTORIES`. No `git` is
 * spawned (no `git init`, no templates, no hooks directory), and no workspace config, hook, ref, index, `commondir` or graft
 * file is ever opened. Pushing `<sha>:refs/heads/<branch>` from this directory to a literal URL therefore reads no
 * configuration the agent could have written.
 *
 * Falsifier for "the isolated child reads no workspace config": `git config --list --show-origin` in the exact child
 * environment lists only the server-written file and `command line` (asserted in push-branch-isolated-real-git.test.ts).
 *
 * What it still reads from the workspace: the names and entry types under `.git/objects` (to refuse a symlinked or chained
 * object store) and `.git/shallow` (through `readSmallRegularFile`, validated). What it does not cover, stated exactly: a swap
 * of the object store AFTER these checks (non-atomic) exposes object bytes of another repository for a sha the agent already
 * knows, and the bytes of regular object files are not inspected. A server SIGKILL/OOM skips `dispose()` and leaks a directory
 * holding `HEAD`, `config`, `shallow` and, if the kill came mid-push, the `.askpass-<uuid>.sh` script (token-free: the token
 * lives only in the child's environment).
 *
 * Placement: `$HOME/.soleur-push/run-*` (mode 0700), never `/tmp` and never under `TMPDIR` (`TMPDIR` is forwarded to the
 * sandbox CLI). The agent shares the server's uid, so mode 0700 is not the control; path placement is, and it rests on the
 * sandbox configuration (`allowWrite` is the workspace plus the CLI's own per-session directory), not on a live probe. Whether
 * `HOME` is even visible inside the sandbox is UNVERIFIED.
 *
 * Errors never carry a path or an fs error: every refusal is an `IsolatedPushDirRefusal` with a closed `reason`.
 */

import {
  lstatSync,
  mkdirSync,
  mkdtempSync,
  opendirSync,
  realpathSync,
  rmSync,
  writeFileSync,
  type Dirent,
} from "node:fs";
import { basename, dirname, isAbsolute, join, sep } from "node:path";

import { HEX40, readSmallRegularFile, SmallFileError } from "./approval/workspace-head";
import { AGENT_SESSION_TMP_ROOT } from "./agent-session-tmp";
import { ISOLATED_PUSH_DIR_BRAND, isSafeGitPath, type IsolatedPushDir } from "./git-hardened-env";

export type IsolatedPushDirReason =
  | "git_dir_not_plain"
  | "object_store_redirect"
  | "alternate_path_unsafe"
  | "shallow_invalid"
  | "env_path_unsafe"
  | "object_store_too_large"
  | "setup_failed";

/** The directory could not be created. `reason` is the closed discriminator; the message is static and carries no path. */
export class IsolatedPushDirRefusal extends Error {
  constructor(readonly reason: IsolatedPushDirReason) {
    super("Isolated push directory could not be created");
    this.name = "IsolatedPushDirRefusal";
  }
}

export interface IsolatedPushDirHandle extends IsolatedPushDir {
  /** Removes the directory. Idempotent; an already-missing directory is not an error; any other failure throws. */
  dispose(): void;
}

/**
 * Entry cap of the object-store walk, charged per entry as it is read (a bounded listing, never an unbounded one). It is an
 * availability bound, not a tamper signal: a legitimate workspace that has never been garbage-collected holds one loose file per
 * object (measured: 10 458 loose entries with no auto-gc), and git's own `gc.auto` threshold is on the order of thousands, so the
 * cap sits far above it. Over the cap is `object_store_too_large`, an infrastructure refusal, never `object_store_redirect`.
 */
export const OBJECT_WALK_ENTRY_CAP = 250_000;
/** Test seam: `createIsolatedPushDir(ws, { objectWalkEntryCap })`. Production callers pass nothing. */
export interface IsolatedPushDirLimits {
  readonly objectWalkEntryCap?: number;
}
const SHALLOW_MAX_BYTES = 64 * 1024;
const SOLEUR_PUSH_ROOT = ".soleur-push";
const WORKSPACES_ROOT_DEFAULT = "/workspaces";
const WORKTREE_ROOT_DEFAULT = "/var/lib/soleur/worktrees";
const FAN_OUT = /^[0-9a-f]{2}$/;

/**
 * The server-written `config`: no remotes, no hooks, and the parsers of the acceleration files git would otherwise read from the
 * alternate switched off (commit-graph, multi-pack-index, bitmaps and the pack reverse index). A pack `.idx` and the pack itself
 * are still parsed: they are the object bytes the push exists to read.
 */
const ISOLATED_CONFIG = [
  "[core]",
  "\trepositoryformatversion = 0",
  "\tbare = true",
  "\tcommitGraph = false",
  "\tmultiPackIndex = false",
  "[pack]",
  "\tuseBitmaps = false",
  "\treadReverseIndex = false",
  "\tthreads = 1",
  "[gc]",
  "\tauto = 0",
  "",
].join("\n");

function isUnder(path: string, root: string): boolean {
  return path === root || path.startsWith(root.endsWith(sep) ? root : root + sep);
}

/**
 * Resolve through symlinks: the path itself when it exists, else its deepest existing ancestor plus the missing tail (a missing
 * leaf under a symlinked directory still lands where the link points, and the agent could create it).
 */
function resolveIfExists(p: string): string {
  const tail: string[] = [];
  let probe = p;
  for (;;) {
    try {
      return tail.length === 0 ? realpathSync(probe) : join(realpathSync(probe), ...tail.reverse());
    } catch {
      const parent = dirname(probe);
      if (parent === probe) return p;
      tail.push(basename(probe));
      probe = parent;
    }
  }
}

/**
 * The ONE list of directories the agent can write (or that hold other tenants' trees), used for BOTH the `HOME` placement check
 * and the `PATH` / `SSL_CERT_*` check: the resolved workspace, the forwarded `TMPDIR`, the CLI session tmp root, the workspaces
 * root and the worktree root. The sandbox's own set is `workspaceTenantDenyRoots()` (server/workspace-resolver.ts); importing that
 * module pulls in the error reporter, so this mirrors its two environment variables and defaults and a parity test pins it.
 * Each root is listed as written and, when it exists, resolved.
 */
export function agentWritableRoots(ws: string): string[] {
  const raw = [
    ws,
    AGENT_SESSION_TMP_ROOT,
    process.env.WORKSPACES_ROOT || WORKSPACES_ROOT_DEFAULT,
    process.env.WORKTREE_ROOT || WORKTREE_ROOT_DEFAULT,
  ];
  if (process.env.TMPDIR && isAbsolute(process.env.TMPDIR)) raw.push(process.env.TMPDIR);
  const out = new Set<string>();
  for (const r of raw) {
    const trimmed = r.length > 1 ? r.replace(/\/+$/, "") : r;
    if (trimmed === "" || trimmed === sep) continue; // a root of "/" would put everything under it; it is never a tenant root
    out.add(trimmed);
    out.add(resolveIfExists(trimmed));
  }
  return [...out];
}

/** True when `path`, as written or resolved through symlinks, is at or under any of `roots`. */
function underAny(path: string, roots: readonly string[]): boolean {
  const resolved = resolveIfExists(path);
  return roots.some((root) => isUnder(resolved, root) || isUnder(path, root));
}

/** Step 0 (no write): the child resolves `PATH`, `SSL_CERT_FILE` and `SSL_CERT_DIR` from the environment it is given. */
function assertEnvPathsSafe(roots: readonly string[]): void {
  const candidates: string[] = [];
  for (const entry of (process.env.PATH ?? "").split(":")) if (entry && isAbsolute(entry)) candidates.push(entry);
  for (const v of [process.env.SSL_CERT_FILE, process.env.SSL_CERT_DIR]) if (v && isAbsolute(v)) candidates.push(v);
  for (const c of candidates) {
    if (underAny(c, roots)) throw new IsolatedPushDirRefusal("env_path_unsafe");
  }
}

type EntryKind = "file" | "dir" | "other";

/**
 * What an entry is. Only a regular file or a directory is acceptable. Anything else (a symlink could name another store, a FIFO
 * at an object path blocks git's open, sockets and devices are not objects) is asked of `lstat`, which never follows a link and
 * also answers for a filesystem whose directory listing carries no entry type.
 */
function kindOf(parent: string, e: Dirent): EntryKind {
  if (e.isFile()) return "file";
  if (e.isDirectory()) return "dir";
  const st = lstatSync(join(parent, e.name));
  return st.isFile() ? "file" : st.isDirectory() ? "dir" : "other";
}

/**
 * Names and entry types only, never a file read: `objects`, `objects/pack`, `objects/info` and every loose fan-out directory.
 * Each directory is streamed (`opendirSync`, closed in a `finally`) and every entry is charged against ONE shared budget as it is
 * read, so a huge directory aborts at the cap instead of being listed first. Anything that is not a regular file or a directory
 * (a symlink could name another store, a FIFO would block git) refuses, as does a chain file under `objects/info`.
 */
function assertObjectStorePlain(objects: string, cap: number): void {
  let budget = cap;
  const scan = (path: string, visit: (e: Dirent, kind: EntryKind) => void): void => {
    const dir = opendirSync(path);
    try {
      for (let e = dir.readSync(); e !== null; e = dir.readSync()) {
        if (--budget < 0) throw new IsolatedPushDirRefusal("object_store_too_large");
        const kind = kindOf(path, e);
        if (kind === "other") throw new IsolatedPushDirRefusal("object_store_redirect");
        visit(e, kind);
      }
    } finally {
      try {
        dir.closeSync();
      } catch {
        /* already closed by an error path */
      }
    }
  };
  const subdirs: string[] = [];
  scan(objects, (e, kind) => {
    if (kind === "dir" && (e.name === "pack" || e.name === "info" || FAN_OUT.test(e.name))) subdirs.push(e.name);
  });
  for (const name of subdirs) {
    scan(join(objects, name), (e) => {
      if (name === "info" && (e.name === "alternates" || e.name === "http-alternates")) {
        throw new IsolatedPushDirRefusal("object_store_redirect");
      }
    });
  }
}

/**
 * The validated lines of `<ws>/.git/shallow`, or `undefined` when the workspace is not shallow. Content the agent could have
 * planted (a symlink, a non-regular file, an oversized file, a file that changed under the read, a non-hex line) is
 * `shallow_invalid`; an operating-system failure that says nothing about the content (`EACCES`, `EMFILE`, `EIO`) is
 * `setup_failed`; a missing file means the workspace is not shallow.
 */
function readShallow(gitDir: string): string | undefined {
  let body: string;
  try {
    body = readSmallRegularFile(join(gitDir, "shallow"), SHALLOW_MAX_BYTES);
  } catch (err) {
    if (err instanceof SmallFileError) {
      if (err.code === "ENOENT") return undefined;
      if (err.code === "IO") throw new IsolatedPushDirRefusal("setup_failed");
    }
    throw new IsolatedPushDirRefusal("shallow_invalid");
  }
  const lines = body.split("\n").filter((l, i, all) => !(l === "" && i === all.length - 1));
  for (const l of lines) if (!HEX40.test(l)) throw new IsolatedPushDirRefusal("shallow_invalid");
  return lines.length === 0 ? undefined : `${lines.join("\n")}\n`;
}

/** Never lets an fs error out: ENOENT/ENOTDIR on a workspace path means "not a plain repository", anything else is infrastructure. */
function wrapFs<T>(fn: () => T, enoent: IsolatedPushDirReason = "git_dir_not_plain"): T {
  try {
    return fn();
  } catch (err) {
    if (err instanceof IsolatedPushDirRefusal) throw err;
    const code = (err as NodeJS.ErrnoException)?.code;
    throw new IsolatedPushDirRefusal(code === "ENOENT" || code === "ENOTDIR" ? enoent : "setup_failed");
  }
}

export function createIsolatedPushDir(workspacePath: string, limits: IsolatedPushDirLimits = {}): IsolatedPushDirHandle {
  // Steps 1-4 and the HOME checks resolve BEFORE the first write; the temp directory is created last.
  if (typeof workspacePath !== "string" || !isAbsolute(workspacePath)) throw new IsolatedPushDirRefusal("git_dir_not_plain");
  // A workspace ROOT that does not exist is the server's own state (setup_failed); a missing `.git` below it is `git_dir_not_plain`.
  const ws = wrapFs(() => realpathSync(workspacePath), "setup_failed");
  const roots = agentWritableRoots(ws);
  const gitDir = join(ws, ".git");
  const objects = join(gitDir, "objects");

  // 1. `.git` and `objects` must be exactly where they appear to be: no symlinked ancestor, `.git` or `objects`, no `gitdir:` file.
  if (wrapFs(() => realpathSync(gitDir)) !== gitDir) throw new IsolatedPushDirRefusal("git_dir_not_plain");
  if (wrapFs(() => realpathSync(objects)) !== objects) throw new IsolatedPushDirRefusal("object_store_redirect");

  // 2. The alternate path is a `:`-separated list entry.
  if (!isSafeGitPath(objects)) throw new IsolatedPushDirRefusal("alternate_path_unsafe");

  // 0. (after the workspace is resolved, before any write) the environment the child will resolve programs and trust stores from.
  assertEnvPathsSafe(roots);

  // 3. The object store walk, names and types only.
  wrapFs(() => assertObjectStorePlain(objects, limits.objectWalkEntryCap ?? OBJECT_WALK_ENTRY_CAP));

  // 4. `shallow`, validated, carried over.
  const shallow = readShallow(gitDir);

  // 5. Placement: under the server HOME, never `/tmp`, never anywhere the sandbox is configured to write.
  const homeEnv = process.env.HOME;
  if (!homeEnv || !isAbsolute(homeEnv)) throw new IsolatedPushDirRefusal("setup_failed");
  const home = wrapFs(() => realpathSync(homeEnv), "setup_failed");
  if (underAny(home, roots)) throw new IsolatedPushDirRefusal("setup_failed");

  const pushRoot = join(home, SOLEUR_PUSH_ROOT);
  let dir: string | undefined;
  try {
    try {
      mkdirSync(pushRoot, { mode: 0o700 });
    } catch (err) {
      if ((err as NodeJS.ErrnoException)?.code !== "EEXIST") throw err;
    }
    // A pre-existing root must be a real directory under HOME (not a symlink the agent planted elsewhere).
    if (realpathSync(pushRoot) !== pushRoot) throw new IsolatedPushDirRefusal("setup_failed");
    dir = mkdtempSync(join(pushRoot, "run-"));
    if (!isSafeGitPath(dir)) throw new IsolatedPushDirRefusal("setup_failed");
    mkdirSync(join(dir, "objects", "pack"), { recursive: true });
    mkdirSync(join(dir, "objects", "info"), { recursive: true });
    mkdirSync(join(dir, "refs", "heads"), { recursive: true });
    mkdirSync(join(dir, "refs", "tags"), { recursive: true });
    writeFileSync(join(dir, "HEAD"), "ref: refs/heads/main\n", { mode: 0o600 });
    writeFileSync(join(dir, "config"), ISOLATED_CONFIG, { mode: 0o600 });
    if (shallow !== undefined) writeFileSync(join(dir, "shallow"), shallow, { mode: 0o600 });
  } catch (err) {
    // 6. Any throw after the directory exists removes it and rethrows a path-free refusal.
    if (dir !== undefined) {
      try {
        rmSync(dir, { recursive: true, force: true });
      } catch {
        /* the original failure is what matters; a leak holds no secret */
      }
    }
    if (err instanceof IsolatedPushDirRefusal) throw err;
    throw new IsolatedPushDirRefusal("setup_failed");
  }

  const created = dir;
  let disposed = false;
  return {
    gitDir: created,
    alternateObjectDirectory: objects,
    [ISOLATED_PUSH_DIR_BRAND]: true,
    dispose(): void {
      if (disposed) return;
      rmSync(created, { recursive: true, force: true });
      disposed = true;
    },
  };
}
