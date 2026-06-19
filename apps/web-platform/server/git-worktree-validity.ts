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
// This module supplies THREE distinct probes (deepen-plan F1/F2/F6), each with a
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
//   3. `revParseInsideWorkTree` — ASYNC subprocess recovery discriminator (OFF
//      the hot path). The authoritative check (same as go.md Step 0.0). Used only
//      to classify a structurally-suspect-but-NOT-empty `.git` (populated-but-
//      broken): such a tree is honest-blocked, NEVER blindly rm'd.
//
// No installation token is needed — every probe is a local read-only filesystem
// / `git rev-parse` operation.
// ---------------------------------------------------------------------------

import { lstatSync, existsSync } from "node:fs";
import { join } from "node:path";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

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

/**
 * ASYNC authoritative recovery discriminator (OFF the hot path, F6). Runs the
 * SAME probe `/soleur:go` Step 0.0 runs: `git -C <workspacePath> rev-parse
 * --is-inside-work-tree`. Returns true only when git confirms a usable work
 * tree. Used to classify a structurally-suspect-but-not-empty `.git`
 * (populated-but-broken) so it can be honest-blocked rather than blindly
 * removed. Never call this on the valid-`.git` fast path. Local read-only — no
 * installation token, no network.
 */
export async function revParseInsideWorkTree(
  workspacePath: string,
): Promise<boolean> {
  try {
    const { stdout } = await execFileAsync(
      "git",
      ["-C", workspacePath, "rev-parse", "--is-inside-work-tree"],
      { timeout: 10_000 },
    );
    return stdout.trim() === "true";
  } catch {
    return false; // exit 128 / not a work tree / git missing → invalid
  }
}
