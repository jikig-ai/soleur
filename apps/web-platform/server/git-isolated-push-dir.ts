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
 * holding only `HEAD`, `config` and `shallow` (no token: the token lives only in the child's environment).
 *
 * Placement: `$HOME/.soleur-push/run-*` (mode 0700), never `/tmp` and never under `TMPDIR` (`TMPDIR` is forwarded to the
 * sandbox CLI). The agent shares the server's uid, so mode 0700 is not the control; path placement is, and it rests on the
 * sandbox configuration (`allowWrite` is the workspace plus the CLI's own per-session directory), not on a live probe. Whether
 * `HOME` is even visible inside the sandbox is UNVERIFIED.
 *
 * Errors never carry a path or an fs error: every refusal is an `IsolatedPushDirRefusal` with a closed `reason`.
 */

import {
  mkdirSync,
  mkdtempSync,
  readdirSync,
  realpathSync,
  rmSync,
  writeFileSync,
  type Dirent,
} from "node:fs";
import { isAbsolute, join, sep } from "node:path";

import { readSmallRegularFile, SmallFileError } from "./approval/workspace-head";
import { AGENT_SESSION_TMP_ROOT } from "./agent-session-tmp";
import { ISOLATED_PUSH_DIR_BRAND, isSafeGitPath, type IsolatedPushDir } from "./git-hardened-env";

export type IsolatedPushDirReason =
  | "git_dir_not_plain"
  | "object_store_redirect"
  | "alternate_path_unsafe"
  | "shallow_invalid"
  | "env_path_unsafe"
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

/** Entry cap of the object-store walk: a bounded listing, never an unbounded one (git auto-gc triggers well below it). */
const OBJECT_WALK_ENTRY_CAP = 10_000;
const SHALLOW_MAX_BYTES = 64 * 1024;
const SOLEUR_PUSH_ROOT = ".soleur-push";
const HEX40 = /^[0-9a-f]{40}$/;
const FAN_OUT = /^[0-9a-f]{2}$/;

/** The server-written `config`: no remotes, no hooks, and the parsers of attacker-influenced acceleration files switched off. */
const ISOLATED_CONFIG = [
  "[core]",
  "\trepositoryformatversion = 0",
  "\tbare = true",
  "\tcommitGraph = false",
  "\tmultiPackIndex = false",
  "[pack]",
  "\tuseBitmaps = false",
  "\tthreads = 1",
  "[gc]",
  "\tauto = 0",
  "",
].join("\n");

function isUnder(path: string, root: string): boolean {
  return path === root || path.startsWith(root.endsWith(sep) ? root : root + sep);
}

/** Resolve through symlinks when the path exists (so a symlinked PATH entry cannot hide under the workspace), else use it as written. */
function resolveIfExists(p: string): string {
  try {
    return realpathSync(p);
  } catch {
    return p;
  }
}

/** Step 0 (no write): the child resolves `PATH`, `SSL_CERT_FILE` and `SSL_CERT_DIR` from the environment it is given. */
function assertEnvPathsSafe(ws: string): void {
  const tmpdirEnv = process.env.TMPDIR;
  const unsafeRoots = [ws];
  if (tmpdirEnv && isAbsolute(tmpdirEnv)) unsafeRoots.push(resolveIfExists(tmpdirEnv));
  const candidates: string[] = [];
  for (const entry of (process.env.PATH ?? "").split(":")) if (entry && isAbsolute(entry)) candidates.push(entry);
  for (const v of [process.env.SSL_CERT_FILE, process.env.SSL_CERT_DIR]) if (v && isAbsolute(v)) candidates.push(v);
  for (const c of candidates) {
    const resolved = resolveIfExists(c);
    if (unsafeRoots.some((root) => isUnder(resolved, root) || isUnder(c, root))) {
      throw new IsolatedPushDirRefusal("env_path_unsafe");
    }
  }
}

function listDir(path: string): Dirent[] {
  return readdirSync(path, { withFileTypes: true });
}

/**
 * Names and entry types only, never a file read: `objects`, `objects/pack`, `objects/info` and every loose fan-out directory.
 * A symlink anywhere refuses (it could name another store), as does a chain file under `objects/info` or an over-cap walk.
 */
function assertObjectStorePlain(objects: string): void {
  let budget = OBJECT_WALK_ENTRY_CAP;
  const take = (entries: Dirent[]): void => {
    budget -= entries.length;
    if (budget < 0) throw new IsolatedPushDirRefusal("object_store_redirect");
    for (const e of entries) if (e.isSymbolicLink()) throw new IsolatedPushDirRefusal("object_store_redirect");
  };
  const top = listDir(objects);
  take(top);
  for (const e of top) {
    if (!e.isDirectory()) continue;
    if (e.name !== "pack" && e.name !== "info" && !FAN_OUT.test(e.name)) continue;
    const children = listDir(join(objects, e.name));
    take(children);
    if (e.name === "info") {
      for (const c of children) {
        if (c.name === "alternates" || c.name === "http-alternates") throw new IsolatedPushDirRefusal("object_store_redirect");
      }
    }
  }
}

/** The validated lines of `<ws>/.git/shallow`, or `undefined` when the workspace is not shallow. */
function readShallow(gitDir: string): string | undefined {
  let body: string;
  try {
    body = readSmallRegularFile(join(gitDir, "shallow"), SHALLOW_MAX_BYTES);
  } catch (err) {
    if (err instanceof SmallFileError && err.code === "ENOENT") return undefined;
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

export function createIsolatedPushDir(workspacePath: string): IsolatedPushDirHandle {
  // Steps 1-4 and the HOME checks resolve BEFORE the first write; the temp directory is created last.
  if (typeof workspacePath !== "string" || !isAbsolute(workspacePath)) throw new IsolatedPushDirRefusal("git_dir_not_plain");
  const ws = wrapFs(() => realpathSync(workspacePath));
  const gitDir = join(ws, ".git");
  const objects = join(gitDir, "objects");

  // 1. `.git` and `objects` must be exactly where they appear to be: no symlinked ancestor, `.git` or `objects`, no `gitdir:` file.
  if (wrapFs(() => realpathSync(gitDir)) !== gitDir) throw new IsolatedPushDirRefusal("git_dir_not_plain");
  if (wrapFs(() => realpathSync(objects)) !== objects) throw new IsolatedPushDirRefusal("object_store_redirect");

  // 2. The alternate path is a `:`-separated list entry.
  if (!isSafeGitPath(objects)) throw new IsolatedPushDirRefusal("alternate_path_unsafe");

  // 0. (after the workspace is resolved, before any write) the environment the child will resolve programs and trust stores from.
  assertEnvPathsSafe(ws);

  // 3. The object store walk, names and types only.
  wrapFs(() => assertObjectStorePlain(objects));

  // 4. `shallow`, validated, carried over.
  const shallow = readShallow(gitDir);

  // 5. Placement: under the server HOME, never `/tmp`, never anywhere the sandbox is configured to write.
  const homeEnv = process.env.HOME;
  if (!homeEnv || !isAbsolute(homeEnv)) throw new IsolatedPushDirRefusal("setup_failed");
  const home = wrapFs(() => realpathSync(homeEnv));
  const forbidden = [ws, AGENT_SESSION_TMP_ROOT, process.env.WORKSPACES_ROOT || "/workspaces"];
  if (process.env.TMPDIR && isAbsolute(process.env.TMPDIR)) forbidden.push(resolveIfExists(process.env.TMPDIR));
  if (forbidden.some((f) => isUnder(home, f))) throw new IsolatedPushDirRefusal("setup_failed");

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
