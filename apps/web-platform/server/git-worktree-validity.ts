// ---------------------------------------------------------------------------
// On-disk git work-tree VALIDITY probes (ADR-044 dispatch-readiness, 2026-06-19).
//
// The Concierge dispatch readiness gate used to test mere `.git` PRESENCE
// (`existsSync(<ws>/.git)`). A directory named `.git` that exists but is not a
// valid git work tree (a partial/interrupted clone, or a leftover from a failed
// atomic-rename) passed that gate, so the self-heal/graft was skipped, the agent
// spawned into a corrupt repo, and `/soleur:go` Step 0.0's
// `git rev-parse --is-inside-work-tree` reported "no git repository" — silently.
//
// This module supplies TWO distinct probes (deepen-plan F1/F2), each with a
// deliberately narrow role:
//
//   1. `isValidGitWorkTree`  — SYNC structural fast-path gate. Replaces the
//      presence check on the hot path. Valid = `.git` is a FILE (a `gitdir:`
//      linked-worktree/submodule pointer — treated valid, never removed) OR a
//      directory containing BOTH `HEAD` and `objects`. A Start-Fresh `git init`
//      tree (HEAD+objects, no origin) is VALID and preserved.
//
//   2. `isEmptyCorruptGitDir` — SYNC POSITIVE fingerprint that ALONE authorizes
//      the destructive re-clone `rm`. True ONLY when `.git` is a DIRECTORY AND
//      `HEAD` is ENOENT AND `objects` is ENOENT. An EACCES/EIO blip on a
//      populated `.git`, or a `.git` FILE, returns false → never rm'd. An empty
//      `.git` has no objects = no commits to lose, so removing it is provably
//      safe.
//
// No installation token is needed — every probe is a local read-only filesystem
// operation.
// ---------------------------------------------------------------------------

import { lstatSync, existsSync, readFileSync } from "node:fs";
import { join, isAbsolute, resolve, sep } from "node:path";

/**
 * SYNC structural validity of `<workspacePath>/.git` — the hot-path gate.
 *
 * Returns true when `.git` is:
 *   - a FILE (a `gitdir:` pointer for a linked worktree/submodule — a real,
 *     non-removable tree we must never classify corrupt), OR
 *   - a DIRECTORY containing both `HEAD` and `objects` (an ordinary repo,
 *     including a Start-Fresh `git init` with no origin).
 *
 * Returns false when `.git` is absent, or is a directory missing `HEAD` or
 * `objects` (a bare `mkdir .git`, or a partial/interrupted clone). A read error
 * (EACCES/EIO) is treated as NOT-valid (the workspace is not usable as-is) — but
 * note that NOT-valid does NOT authorize removal; only `isEmptyCorruptGitDir`
 * does. Cost: 1-3 `lstat`/`existsSync` syscalls; no subprocess, no await.
 */
export function isValidGitWorkTree(workspacePath: string): boolean {
  const gitPath = join(workspacePath, ".git");
  let st;
  try {
    st = lstatSync(gitPath);
  } catch {
    return false; // ENOENT (absent) or unreadable → not a usable work tree
  }
  // A `.git` FILE is a gitdir pointer (linked worktree / submodule). Treat as
  // VALID and never removable — resolving the pointed-to dir is out of scope and
  // such trees are real (F2).
  if (st.isFile()) return true;
  if (!st.isDirectory()) return false;
  // Ordinary repo: require both HEAD and the object store. A bare `mkdir .git`
  // (the residual-fixture / failed-atomic-rename shape) has neither.
  return (
    existsSync(join(gitPath, "HEAD")) && existsSync(join(gitPath, "objects"))
  );
}

/**
 * Structural shape of `<workspacePath>/.git` (#5733). A SYNC, read-only
 * classification used by the dispatch readiness gate + the agent-readiness
 * observability mirror. The load-bearing case is `"file-pointer"`: a `.git`
 * FILE that `isValidGitWorkTree` passes (line 60) but the agent's IN-BWRAP `git
 * rev-parse --is-inside-work-tree` strands on — especially when the `gitdir:`
 * target resolves OUTSIDE the workspace (e.g. under `/workspaces`, which the
 * agent sandbox `denyRead`s). A personal workspace root is NEVER a legitimate
 * linked-worktree/submodule, so a `.git` FILE there is an anomalous stale
 * pointer. `gitdirEscapesWorkspace` enriches the signal (a target inside the
 * workspace would still be readable in-sandbox).
 *
 * Cost: 1 `lstat` + (for a FILE only) 1 small `readFileSync`. No subprocess.
 */
export interface GitWorktreeShape {
  kind: "absent" | "file-pointer" | "dir-valid" | "dir-invalid" | "other";
  /** The raw `gitdir:` target string, for a file-pointer (best-effort). */
  gitdirTarget?: string;
  /** True when the gitdir target resolves OUTSIDE `workspacePath`. */
  gitdirEscapesWorkspace?: boolean;
}

export function probeGitWorktreeShape(workspacePath: string): GitWorktreeShape {
  const gitPath = join(workspacePath, ".git");
  let st;
  try {
    st = lstatSync(gitPath);
  } catch {
    return { kind: "absent" };
  }
  if (st.isFile()) {
    let gitdirTarget: string | undefined;
    let gitdirEscapesWorkspace: boolean | undefined;
    try {
      const body = readFileSync(gitPath, "utf8");
      const m = body.match(/^gitdir:\s*(.+?)\s*$/m);
      gitdirTarget = m?.[1];
      if (gitdirTarget) {
        const resolved = isAbsolute(gitdirTarget)
          ? resolve(gitdirTarget)
          : resolve(workspacePath, gitdirTarget);
        const root = resolve(workspacePath);
        gitdirEscapesWorkspace =
          resolved !== root && !resolved.startsWith(root + sep);
      }
    } catch {
      // Unreadable pointer body — still a file-pointer (escapes unknown).
    }
    return { kind: "file-pointer", gitdirTarget, gitdirEscapesWorkspace };
  }
  if (st.isDirectory()) {
    return { kind: isValidGitWorkTree(workspacePath) ? "dir-valid" : "dir-invalid" };
  }
  return { kind: "other" }; // symlink / socket / etc. — never the file-pointer path
}

/**
 * SYNC POSITIVE empty-corrupt fingerprint — the ONLY authorization for the
 * destructive re-clone `rm` (deepen-plan F2).
 *
 * True ONLY when `.git` exists AND is a DIRECTORY AND `HEAD` is ENOENT AND
 * `objects` is ENOENT. Deliberately conservative:
 *   - A `.git` FILE (gitdir pointer) → false (never rm a linked-worktree).
 *   - A populated `.git` (HEAD or objects present) → false (may hold un-pushed
 *     commits; honest-block instead).
 *   - An EACCES/EIO on `.git` itself → false (a transient unreadable populated
 *     repo must NOT be destroyed). We distinguish ENOENT (genuinely absent) from
 *     other errno: only an explicit ENOENT on HEAD/objects counts as "empty".
 *
 * Never trigger removal on the NEGATION of `isValidGitWorkTree` — that collapses
 * ENOENT with EACCES and would destroy a populated repo on a blip.
 */
export function isEmptyCorruptGitDir(workspacePath: string): boolean {
  const gitPath = join(workspacePath, ".git");
  let st;
  try {
    st = lstatSync(gitPath);
  } catch {
    return false; // absent or unreadable → not the empty-corrupt fingerprint
  }
  if (!st.isDirectory()) return false; // a `.git` FILE is never the fingerprint

  // Positive ENOENT on BOTH HEAD and objects. `existsSync` is false for both
  // ENOENT and a permission error; to keep this a POSITIVE fingerprint we use
  // lstatSync and require an explicit ENOENT (not EACCES/EIO) on each marker.
  const markerIsEnoent = (name: string): boolean => {
    try {
      lstatSync(join(gitPath, name));
      return false; // marker exists → not empty
    } catch (err) {
      return (err as NodeJS.ErrnoException).code === "ENOENT";
    }
  };
  return markerIsEnoent("HEAD") && markerIsEnoent("objects");
}
