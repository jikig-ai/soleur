// Preflight for the git-data transport (Ref #9601). The key-auth arm pins the HOST key, not the repository path on that
// host, and `url.<base>.insteadOf` / `pushInsteadOf` in the workspace's (agent-writable) `.git/config` can rewrite an
// explicit git-data URL to another tenant's repository on the same host (measured: the push landed in the other repo).
// `-c` cannot unset these keys, so refuse when any `url.*` key is effective.
//
// ALSO refused: any `remote.<name>.*` key whose <name> is URL-shaped (contains `/`, `:` or `@`). Git resolves a push or
// fetch argument as a remote NAME first, so an agent-written `[remote "<the explicit URL>"] pushurl = <other repo>` section
// defeats the explicit-URL push (measured in review: the push landed in the other repository and the fetch pulled its refs).
// Ordinary remotes (`upstream`, `origin`) and `remote.pushDefault` are not touched: only a name equal to the argument can matter.
// NOT covered: the implicit remotes (`remote.origin.*`, `branch.<b>.remote`) the legacy arm resolves by name.
//
// A PREFLIGHT, NOT A STRUCTURAL CONTROL: a write between this check and the git call is not covered, and it reads only
// the effective config of the workspace. It is a leaf (no observability, no git-data-client import) so both the push
// side (git-data-replication) and the fetch side (git-data-client) can share it without an import cycle.
import { execFileSync } from "node:child_process";
import { ALLOW_PROTOCOL_NONE, hostGitInvocation } from "./host-git";

/** Thrown when a `url.*` rewrite is effective in the workspace config. Carries a count, never a key or value. */
export class GitDataUrlRewriteError extends Error {
  constructor(readonly keyCount: number) {
    super(`git-data: refused, the workspace config carries ${keyCount} url/remote rewrite key(s)`);
    this.name = "GitDataUrlRewriteError";
  }
}

/** `remote.<name>.<var>` -> <name>; the name may itself contain dots (a URL), so strip the prefix and the last segment. */
function remoteNameOf(key: string): string | undefined {
  if (!key.startsWith("remote.")) return undefined;
  const rest = key.slice("remote.".length);
  const dot = rest.lastIndexOf(".");
  return dot < 0 ? undefined : rest.slice(0, dot);
}

export function assertNoUrlRewrite(workspacePath: string): void {
  const h = hostGitInvocation(["config", "--name-only", "-z", "--get-regexp", "^(url|remote)\\."], { cwd: workspacePath, allowProtocol: ALLOW_PROTOCOL_NONE });
  let out = "";
  try {
    out = String(execFileSync("git", h.args, { cwd: workspacePath, env: h.env, stdio: "pipe", timeout: 5000 }) ?? "");
  } catch (err) {
    // exit 1 = no matching key: the expected, clean case. Anything else is a real failure and propagates.
    if ((err as { status?: number }).status === 1) return;
    throw err;
  }
  // `--name-only -z`: NUL-separated key NAMES (no values, no whitespace parsing)
  const keys = out
    .split("\0")
    .filter((k) => k !== "")
    .filter((k) => {
      if (k.toLowerCase().startsWith("url.")) return true;
      const name = remoteNameOf(k);
      return name !== undefined && /[/:@]/.test(name);
    });
  if (keys.length > 0) throw new GitDataUrlRewriteError(keys.length);
}
