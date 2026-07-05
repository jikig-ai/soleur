// Host-side pre-seed of the git config that in-sandbox worktree creation needs —
// applied BEFORE the agent sandbox bind-mounts /dev/null over `.git/config.lock`.
//
// The Claude Agent SDK's bubblewrap masks git-config write targets (`.git/config.lock`,
// and per live evidence `.git/config.worktree`) with a read-only /dev/null bind mount —
// a per-session in-sandbox guard against git-config RCE via `core.hooksPath`/
// `core.sshCommand`. Inside the sandbox, any `git config` WRITE to the shared config
// fails EEXIST against that masked lock, so `worktree-manager.sh`'s `ensure_bare_config`
// (which sets `core.repositoryformatversion=1` + `extensions.worktreeConfig=true` and
// clears `core.bare`/`core.worktree` before `git worktree add`) wedges (#4826).
//
// Performing that exact transformation HOST-SIDE, before the mask exists, makes the
// in-sandbox `ensure_bare_config` a ZERO-WRITE no-op: `atomic_git_config` read-first-skips
// the two SETs (a read never takes the lock) and skips both UNSETs (keys already absent);
// `git worktree add` then writes only `.git/worktrees/<id>/` (a fresh, unmasked subdir).
//
// This module is standalone (only `child_process` + the logger) so the hot per-session
// boot path (`ensureWorkspaceRepoCloned`) can call it WITHOUT pulling in workspace.ts's
// full provisioning dependency graph.

import { execFileSync } from "child_process";
import { existsSync } from "node:fs";
import { join } from "node:path";
import { createChildLogger } from "./logger";

const log = createChildLogger("worktree-config-seed");

/**
 * Idempotently pre-seed the worktree-config prerequisites into `<workspacePath>/.git`.
 *
 * Best-effort by contract: a failure degrades to the in-sandbox write path (no worse
 * than not calling it), so every step logs and continues rather than throwing. Safe to
 * re-run every session — the values are set-to-target, so repeats are no-ops. A no-op
 * when `<workspacePath>/.git` is absent (nothing to seed, and `git config` would fail).
 *
 * Runs at BOTH:
 *   - provision time (`provisionWorkspace` / `provisionWorkspaceWithRepo`) — new workspaces
 *   - session boot (`ensureWorkspaceRepoCloned`) — EXISTING workspaces provisioned before
 *     this fix shipped, which would otherwise never be seeded and keep wedging (#4826).
 */
export function seedWorktreeConfig(workspacePath: string): void {
  // A `.git` may be a directory (normal repo) or a file (linked-worktree pointer);
  // either is seedable. Absent → nothing to do (a repo-less "Start Fresh" dir mid-init).
  if (!existsSync(join(workspacePath, ".git"))) return;

  // SETs mirror ensure_bare_config exactly. repositoryformatversion=1 MUST precede the
  // extensions.* write for git to honor the extension namespace. Failures are logged
  // (they gate in-sandbox success) but never thrown.
  for (const [key, value] of [
    ["core.repositoryformatversion", "1"],
    ["extensions.worktreeConfig", "true"],
  ] as const) {
    try {
      execFileSync("git", ["config", key, value], { cwd: workspacePath, stdio: "pipe" });
    } catch (err) {
      log.warn({ err, workspacePath, key }, "Failed to pre-seed worktree git config");
    }
  }
  // UNSETs: core.bare / core.worktree belong in per-worktree config, not shared (a normal
  // clone/init carries `core.bare=false`). `--unset` of an absent key exits non-zero;
  // that is expected, so these are silent best-effort.
  for (const key of ["core.bare", "core.worktree"] as const) {
    try {
      execFileSync("git", ["config", "--unset", key], { cwd: workspacePath, stdio: "pipe" });
    } catch {
      // absent key (or already-unset) — nothing to do.
    }
  }
}
