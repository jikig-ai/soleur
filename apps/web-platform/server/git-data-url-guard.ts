// Preflight for the git-data transport (Ref #9601). The key-auth arm pins the HOST key, not the repository path on that
// host, and `url.<base>.insteadOf` / `pushInsteadOf` in the workspace's (agent-writable) `.git/config` can rewrite an
// explicit git-data URL to another tenant's repository on the same host (measured: the push landed in the other repo).
// `-c` cannot unset these keys, so refuse when any `url.*` key is effective.
//
// A PREFLIGHT, NOT A STRUCTURAL CONTROL: a write between this check and the git call is not covered, and it reads only
// the effective config of the workspace. It is a leaf (no observability, no git-data-client import) so both the push
// side (git-data-replication) and the fetch side (git-data-client) can share it without an import cycle.
import { execFileSync } from "node:child_process";
import { ALLOW_PROTOCOL_NONE, hostGitInvocation } from "./host-git";

/** Thrown when a `url.*` rewrite is effective in the workspace config. Carries a count, never a key or value. */
export class GitDataUrlRewriteError extends Error {
  constructor(readonly keyCount: number) {
    super(`git-data: refused, the workspace config carries ${keyCount} url rewrite key(s)`);
    this.name = "GitDataUrlRewriteError";
  }
}

export function assertNoUrlRewrite(workspacePath: string): void {
  const h = hostGitInvocation(["config", "--get-regexp", "^url\\."], { cwd: workspacePath, allowProtocol: ALLOW_PROTOCOL_NONE });
  let out = "";
  try {
    out = String(execFileSync("git", h.args, { cwd: workspacePath, env: h.env, stdio: "pipe", timeout: 5000 }) ?? "");
  } catch (err) {
    // exit 1 = no matching key: the expected, clean case. Anything else is a real failure and propagates.
    if ((err as { status?: number }).status === 1) return;
    throw err;
  }
  const keys = out.split("\n").filter((l) => l.trim() !== "");
  if (keys.length > 0) throw new GitDataUrlRewriteError(keys.length);
}
