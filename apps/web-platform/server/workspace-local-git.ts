// Token-free runner for the LOCAL git verbs of the workspace self-heal (#12600, CTO ruling D6d).
//
// `selfHealNonFastForward` (server/workspace-sync.ts) used to run every verb, local ones included, through the legacy
// `gitWithInstallationAuth` arm: each call minted an installation token and handed it, in the child's environment, to a
// git process that reads the agent-writable workspace `.git/config` and `.git/info/attributes`. A planted
// `filter.<x>.clean` ran during `status` and a planted `smudge` during `reset --hard`, both with the token in their
// environment (measured by the security and structural review seats). The local verbs need no token at all.
//
// This runner is the shared host-git invocation with `GIT_ALLOW_PROTOCOL=none` and no auth variable, the pattern of
// `provisionWorkspace` (server/workspace.ts) and `assertNoUrlRewrite` (server/git-data-url-guard.ts). It does NOT stop a
// planted filter from running (host-git's header lists `filter.*` as not closed); it stops the filter from receiving a
// token. `runConnectedRepoGit` is not used: its `FORBIDDEN_GIT_FLAGS` refuses `--hard`, which the reset needs.
//
// A leaf: `node:child_process`, `node:util` and host-git only.
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { ALLOW_PROTOCOL_NONE, hostGitInvocation } from "./host-git";

const execFileAsync = promisify(execFile);

export type WorkspaceLocalGitRunner = (args: string[], opts: { cwd: string; timeout: number }) => Promise<Buffer>;

/**
 * Run one local-only git verb in the workspace, token-free. Rejects with the `execFile` error on a non-zero exit (its
 * numeric `code` is git's exit status), or with a `HostGitRefusedError` when the workspace `.git` shape is refused.
 */
export const runWorkspaceLocalGit: WorkspaceLocalGitRunner = async (args, { cwd, timeout }) => {
  const h = hostGitInvocation(args, { cwd, allowProtocol: ALLOW_PROTOCOL_NONE });
  const { stdout } = await execFileAsync("git", h.args, {
    cwd,
    env: h.env,
    timeout,
    encoding: "buffer",
    maxBuffer: 10 * 1024 * 1024,
  });
  return stdout;
};
