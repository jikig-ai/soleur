// Host-side HEAL of a workspace's worktree git config (#4826).
//
// HISTORY (important — this file's behavior was INVERTED). #6064/#6068 shipped a
// `seedWorktreeConfig` that SET `extensions.worktreeConfig=true` on the workspace, to
// pre-empt worktree-manager.sh's `ensure_bare_config` config writes wedging on the
// SDK-masked `.git/config.lock`. That was WRONG for a normal (non-bare) Concierge clone:
// enabling worktreeConfig FORCES git to read `.git/config.worktree` on every command, and
// in the agent sandbox that path is a /dev/null CHAR DEVICE owned by nobody:nogroup that
// the agent user cannot read → `fatal: unable to access '.git/config.worktree': Permission
// denied` → EVERY git command fails (readiness gate → "workspace isn't ready"). The seed
// turned a deep worktree-creation wedge into total git breakage.
//
// CORRECT MODEL: a Concierge workspace is a NORMAL working clone. `git worktree add` works
// on it natively with ZERO shared-config surgery — the bare-repo `ensure_bare_config`
// transformation (now guarded off for non-bare repos in worktree-manager.sh) is neither
// needed nor safe here. So this function's job is the INVERSE of the old seed: HEAL a
// non-bare workspace by UNSETTING the harmful `extensions.worktreeConfig` a prior version
// wrote (and resetting the format version), restoring plain-repo semantics.
//
// Runs HOST-SIDE (provision + every session boot via ensureWorkspaceRepoCloned), where
// `.git/config.worktree` is NOT masked, so these git ops work even for a workspace that is
// currently wedged in-sandbox. Idempotent + best-effort (never throws): a healthy workspace
// has nothing to unset; a bare repo is left untouched.

import { execFileSync } from "child_process";
import { statSync } from "node:fs";
import { join } from "node:path";
import { createChildLogger } from "./logger";

const log = createChildLogger("worktree-config-seed");

/** True iff `<workspacePath>/.git` is a DIRECTORY — i.e. a normal working clone, not a
 *  bare repo (no `.git` subdir) and not a linked-worktree pointer (`.git` is a FILE). */
function isNonBareWorkingClone(workspacePath: string): boolean {
  try {
    return statSync(join(workspacePath, ".git")).isDirectory();
  } catch {
    return false; // absent / unreadable → nothing to heal here
  }
}

/**
 * Heal a normal (non-bare) workspace's worktree config so in-sandbox git works and
 * `git worktree add` runs natively. Removes the `extensions.worktreeConfig` key (whose
 * presence forces git to read the sandbox-masked `.git/config.worktree` and fatal) and
 * resets `core.repositoryformatversion` to 0. No-op on a bare repo or a `.git`-less path.
 *
 * NOTE: retains the export name `seedWorktreeConfig` (its two call sites) though its
 * behavior is now a heal, not a seed — a rename is deferred to avoid churn in this
 * hotfix. Best-effort: every step logs on failure and continues.
 */
export function seedWorktreeConfig(workspacePath: string): void {
  if (!isNonBareWorkingClone(workspacePath)) return;

  // The load-bearing heal: remove extensions.worktreeConfig. Probe presence first so a
  // no-op on a healthy workspace stays silent, and a real failure to clear a PRESENT key
  // is surfaced loudly (that key is what keeps in-sandbox git wedged).
  let hadWorktreeConfig = false;
  try {
    execFileSync("git", ["config", "--get", "extensions.worktreeConfig"], {
      cwd: workspacePath,
      stdio: "pipe",
    });
    hadWorktreeConfig = true;
  } catch {
    // absent → healthy, nothing to unset.
  }
  if (!hadWorktreeConfig) return;

  try {
    execFileSync("git", ["config", "--unset-all", "extensions.worktreeConfig"], {
      cwd: workspacePath,
      stdio: "pipe",
    });
    // Reset the format version bumped alongside the old seed. Harmless if already 0.
    execFileSync("git", ["config", "core.repositoryformatversion", "0"], {
      cwd: workspacePath,
      stdio: "pipe",
    });
    log.warn(
      { workspacePath, sec: true },
      "healed workspace: removed harmful extensions.worktreeConfig (#4826 regression)",
    );
  } catch (err) {
    log.error(
      { err, workspacePath },
      "FAILED to heal extensions.worktreeConfig — in-sandbox git may stay wedged (#4826)",
    );
  }
}
